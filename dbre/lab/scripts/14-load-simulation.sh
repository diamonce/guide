#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Load simulation — realistic database pressure
#
# Two independent levers:
#
#   1. DATA VOLUME  — generate large dataset so queries do real I/O work
#      Default InnoDB buffer pool = 128 MB. We generate enough rows that
#      the working set exceeds it, forcing disk reads on cache misses.
#
#   2. BACKGROUND RPS — concurrent workers hitting MySQL directly (no cache)
#      Simulates real production traffic alongside our benchmark queries.
#      MySQL CPU/IO saturation makes uncached paths degrade; cached paths hold.
#
# What this proves:
#   Under low load  — cache is nice but headroom exists anyway
#   Under high load — cache is the difference between p99=5ms and p99=2000ms
#
# Usage:
#   ./14-load-simulation.sh                   # defaults (see below)
#   ROWS=500000 BG_WORKERS=16 DURATION=120 ./14-load-simulation.sh
#
# Tunables:
#   ROWS        rows in orders table (default 200000; 1M for serious pressure)
#   BG_WORKERS  background load workers hitting MySQL directly (default 8)
#   DURATION    seconds per benchmark path (default 60)
#   WORKERS     cache benchmark workers (default 4)
#   SKIP_SEED   set to 1 to skip data generation (re-use previous run's data)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ROWS=${ROWS:-200000}
BG_WORKERS=${BG_WORKERS:-8}
DURATION=${DURATION:-60}
WORKERS=${WORKERS:-4}
SKIP_SEED=${SKIP_SEED:-0}
REPORT_DIR="/tmp/loadsim_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$REPORT_DIR"

M8="docker exec -i mysql-primary"
MYSQL_PRIMARY="docker exec mysql-primary mysql -u root -prootpass shopdb"
MYSQL_REPLICA="docker exec mysql-replica1 mysql -u root -prootpass shopdb"

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

stats() {
    local file=$1
    [ -s "$file" ] || { echo "count=0 avg=0 p50=0 p95=0 p99=0"; return; }
    sort -n "$file" | awk '
    BEGIN { n=0; sum=0 }
    { v[n++]=$1; sum+=$1 }
    END {
        printf "count=%-6d avg=%-6.1f p50=%-5d p95=%-5d p99=%-5d",
               n, sum/n, v[int(n*0.50)], v[int(n*0.95)], v[int(n*0.99)]
    }'
}

qps() {
    local file=$1 dur=$2
    [ -s "$file" ] || { echo "0.0"; return; }
    echo "scale=1; $(wc -l < "$file" | tr -d ' ') / $dur" | bc 2>/dev/null || echo "0.0"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
header "Preflight"
for svc in mysql-primary mysql-replica1 proxysql valkey; do
    printf "  %-20s " "$svc..."
    case $svc in
        mysql-*) docker exec $svc mysqladmin ping -u root -prootpass -s 2>/dev/null \
                     && echo "ok" || { echo "FAIL"; exit 1; } ;;
        proxysql) MYSQL_PWD=radminpass mysql -h127.0.0.1 -P6032 -uradmin \
                     -e "SELECT 1" --silent 2>/dev/null | grep -q 1 \
                     && echo "ok" || { echo "FAIL"; exit 1; } ;;
        valkey) docker exec valkey valkey-cli ping 2>/dev/null | grep -q PONG \
                     && echo "ok" || { echo "FAIL"; exit 1; } ;;
    esac
done
echo ""
echo "  ROWS=$ROWS  BG_WORKERS=$BG_WORKERS  DURATION=${DURATION}s  WORKERS=$WORKERS"

# ── Phase 1: Generate large dataset ──────────────────────────────────────────
if [ "$SKIP_SEED" = "0" ]; then
    header "Phase 1: Generate large dataset (${ROWS} orders)"

    # Customers — 10k bulk insert via recursive CTE
    # cte_max_recursion_depth defaults to 1000; raise it per-session
    echo "  Inserting 10,000 customers..."
    $MYSQL_PRIMARY -e "
        SET SESSION cte_max_recursion_depth=10000;
        INSERT IGNORE INTO customers (name, email)
        WITH RECURSIVE seq (n) AS (
            SELECT 1
            UNION ALL SELECT n + 1 FROM seq WHERE n < 10000
        )
        SELECT CONCAT('BenchUser ', n),
               CONCAT('bench', n, '@load.test')
        FROM seq;" 2>/dev/null

    # Products — 500 rows
    echo "  Inserting 500 products..."
    $MYSQL_PRIMARY -e "
        INSERT IGNORE INTO products (sku, name, price, stock)
        WITH RECURSIVE seq (n) AS (
            SELECT 1
            UNION ALL SELECT n + 1 FROM seq WHERE n < 500
        )
        SELECT CONCAT('BENCH-', LPAD(n, 5, '0')),
               CONCAT('Bench Product ', n),
               ROUND(1 + RAND() * 999, 2),
               FLOOR(RAND() * 1000)
        FROM seq;" 2>/dev/null

    # Orders — target ROWS, inserted in batches to avoid single huge transaction
    echo "  Inserting ${ROWS} orders (batches of 10000)..."
    INSERTED=0
    BATCH=10000
    while [ $INSERTED -lt $ROWS ]; do
        REMAINING=$(( ROWS - INSERTED ))
        [ $REMAINING -gt $BATCH ] && THIS_BATCH=$BATCH || THIS_BATCH=$REMAINING
        $MYSQL_PRIMARY -e "
            SET SESSION cte_max_recursion_depth=10001;
            INSERT INTO orders (customer_id, total, status)
            WITH RECURSIVE seq (n) AS (
                SELECT 1
                UNION ALL SELECT n + 1 FROM seq WHERE n < ${THIS_BATCH}
            )
            SELECT 1 + MOD(n, (SELECT COUNT(*) FROM customers)),
                   ROUND(10 + RAND() * 990, 2),
                   ELT(1 + FLOOR(RAND() * 4), 'pending','paid','shipped','cancelled')
            FROM seq;" 2>/dev/null
        INSERTED=$(( INSERTED + THIS_BATCH ))
        printf "    %d / %d\r" $INSERTED $ROWS
    done
    echo ""

    # order_items — 2 items per order (batches)
    echo "  Inserting order_items (2 per order)..."
    $MYSQL_PRIMARY -e "
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        SELECT o.id,
               1 + MOD(o.id, (SELECT COUNT(*) FROM products)),
               1 + FLOOR(RAND() * 5),
               p.price
        FROM orders o
        JOIN products p ON p.id = 1 + MOD(o.id, (SELECT COUNT(*) FROM products))
        WHERE o.id > (SELECT COALESCE(MAX(oi.order_id), 0) FROM order_items oi)
        LIMIT 500000;" 2>/dev/null || true

    echo ""
    echo "  Final row counts:"
    $MYSQL_PRIMARY -e "
        SELECT 'customers'  AS tbl, COUNT(*) AS rows FROM customers
        UNION ALL SELECT 'products',   COUNT(*) FROM products
        UNION ALL SELECT 'orders',     COUNT(*) FROM orders
        UNION ALL SELECT 'order_items',COUNT(*) FROM order_items;" 2>/dev/null

    # Update Valkey with the current (small) product catalog used in benchmark
    echo ""
    echo "  Refreshing Valkey product cache..."
    docker exec mysql-primary mysql -u root -prootpass shopdb \
        -sN -e "SELECT id, sku, name, price, stock FROM products LIMIT 20;" 2>/dev/null \
    | while IFS=$'\t' read -r id sku name price stock; do
        docker exec valkey valkey-cli HSET "product:${id}" \
            sku "$sku" name "$name" price "$price" stock "$stock" > /dev/null 2>&1
        docker exec valkey valkey-cli PERSIST "product:${id}" > /dev/null 2>&1
    done

else
    header "Phase 1: Skipped (SKIP_SEED=1)"
    $MYSQL_PRIMARY -e "
        SELECT 'customers'  AS tbl, COUNT(*) AS rows FROM customers
        UNION ALL SELECT 'products',   COUNT(*) FROM products
        UNION ALL SELECT 'orders',     COUNT(*) FROM orders
        UNION ALL SELECT 'order_items',COUNT(*) FROM order_items;" 2>/dev/null
fi

# Show InnoDB buffer pool pressure
echo ""
echo "  InnoDB buffer pool:"
docker exec mysql-primary mysql -u root -prootpass -e "
    SELECT ROUND(@@innodb_buffer_pool_size / 1024 / 1024) AS pool_MB,
           ROUND(variable_value / 1024 / 1024, 1) AS data_MB,
           ROUND(100 * variable_value / @@innodb_buffer_pool_size, 1) AS pct_full
    FROM information_schema.global_status
    WHERE variable_name = 'Innodb_buffer_pool_bytes_data';" 2>/dev/null
echo "  pct_full > 100% means working set exceeds pool — disk reads occur"

# ── Phase 2: Define benchmark query (complex, realistic) ─────────────────────
header "Phase 2: Benchmark query (JOIN + aggregate, realistic)"

BENCH_QUERY="SELECT c.name, COUNT(o.id) AS order_count, ROUND(SUM(o.total),2) AS revenue
             FROM customers c
             JOIN orders o ON o.customer_id = c.id
             WHERE o.status = 'paid'
             GROUP BY c.id
             ORDER BY revenue DESC
             LIMIT 20"

echo "  Query: $BENCH_QUERY"
echo ""
echo "  Baseline timing (single run, no load):"
TIME_START=$(date +%s%N)
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null > /dev/null
TIME_END=$(date +%s%N)
echo "  Direct MySQL: $(( (TIME_END - TIME_START) / 1000000 ))ms"

# Seed ProxySQL cache with the benchmark query
MYSQL_PWD=radminpass mysql -h127.0.0.1 -P6032 -uradmin \
    -e "PROXYSQL FLUSH QUERY CACHE;" 2>/dev/null || true

# Add cache rule for our JOIN query if not already present
MYSQL_PWD=radminpass mysql -h127.0.0.1 -P6032 -uradmin -e "
    INSERT OR IGNORE INTO mysql_query_rules
        (rule_id, active, match_pattern, destination_hostgroup, cache_ttl, apply)
    VALUES (6, 1, '^SELECT c\\.name.*FROM customers', 1, 10000, 1);
    LOAD MYSQL QUERY RULES TO RUNTIME;" 2>/dev/null || true

# Pre-warm ProxySQL cache
MYSQL_PWD=apppass mysql -h 127.0.0.1 -P 6033 -u app shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null > /dev/null

# Seed Valkey with pre-computed result
echo ""
echo "  Seeding Valkey with pre-computed query result (simulating app-level cache)..."
RESULT=$(docker exec mysql-replica1 mysql -u root -prootpass shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null | head -20)
docker exec valkey valkey-cli SET "query:top_customers" "$RESULT" > /dev/null 2>&1
docker exec valkey valkey-cli PERSIST "query:top_customers" > /dev/null 2>&1

# ── Worker functions ──────────────────────────────────────────────────────────
# Background load worker: runs complex queries on MySQL replica directly
# Uses host client for lower overhead → more effective MySQL pressure
bg_load_worker() {
    local id=$1 end=$2
    while [ "$(date +%s)" -lt "$end" ]; do
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN -e "
            SELECT o.status, COUNT(*) AS cnt, ROUND(AVG(o.total),2) AS avg_total
            FROM orders o
            JOIN order_items oi ON oi.order_id = o.id
            GROUP BY o.status;" 2>/dev/null > /dev/null || true
    done
}

# Benchmark workers — host clients only (no docker exec overhead)
bench_mysql() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN \
            -e "$BENCH_QUERY" 2>/dev/null > /dev/null
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

bench_proxysql_warm() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        MYSQL_PWD=apppass mysql -h 127.0.0.1 -P 6033 -u app shopdb -sN \
            -e "$BENCH_QUERY" 2>/dev/null > /dev/null
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

bench_valkey() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        redis-cli -h 127.0.0.1 -p 6379 GET "query:top_customers" > /dev/null 2>&1
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

export -f bg_load_worker bench_mysql bench_proxysql_warm bench_valkey
export BENCH_QUERY REPORT_DIR

# ── Phase 3: Benchmark WITHOUT background load ────────────────────────────────
header "Phase 3: Benchmark — NO background load"

echo "--- Direct MySQL replica ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_mysql "$w" "${REPORT_DIR}/noload_mysql_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/noload_mysql_*.txt > "${REPORT_DIR}/noload_mysql.txt" 2>/dev/null || true
NOLOAD_MYSQL_QPS=$(qps "${REPORT_DIR}/noload_mysql.txt" "$DURATION")
NOLOAD_MYSQL_STATS=$(stats "${REPORT_DIR}/noload_mysql.txt")
printf "  %-28s  QPS=%-8s  %s\n" "Direct MySQL" "$NOLOAD_MYSQL_QPS" "$NOLOAD_MYSQL_STATS"

echo ""
echo "--- ProxySQL warm cache ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_proxysql_warm "$w" "${REPORT_DIR}/noload_proxysql_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/noload_proxysql_*.txt > "${REPORT_DIR}/noload_proxysql.txt" 2>/dev/null || true
NOLOAD_PSQL_QPS=$(qps "${REPORT_DIR}/noload_proxysql.txt" "$DURATION")
NOLOAD_PSQL_STATS=$(stats "${REPORT_DIR}/noload_proxysql.txt")
printf "  %-28s  QPS=%-8s  %s\n" "ProxySQL warm" "$NOLOAD_PSQL_QPS" "$NOLOAD_PSQL_STATS"

echo ""
echo "--- Valkey GET ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_valkey "$w" "${REPORT_DIR}/noload_valkey_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/noload_valkey_*.txt > "${REPORT_DIR}/noload_valkey.txt" 2>/dev/null || true
NOLOAD_VK_QPS=$(qps "${REPORT_DIR}/noload_valkey.txt" "$DURATION")
NOLOAD_VK_STATS=$(stats "${REPORT_DIR}/noload_valkey.txt")
printf "  %-28s  QPS=%-8s  %s\n" "Valkey GET" "$NOLOAD_VK_QPS" "$NOLOAD_VK_STATS"

# ── Phase 4: Benchmark WITH background load ───────────────────────────────────
header "Phase 4: Benchmark — WITH ${BG_WORKERS} background load workers"

echo "  Starting ${BG_WORKERS} background workers hammering MySQL directly..."
BG_END=$(( $(date +%s) + DURATION * 3 + 30 ))
BG_PIDS=()
for ((w=1; w<=BG_WORKERS; w++)); do
    bg_load_worker "$w" "$BG_END" &
    BG_PIDS+=($!)
done
echo "  Background load running. Waiting 5s for pressure to build..."
sleep 5

echo ""
echo "  MySQL QPS under load:"
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root -e "
    SHOW GLOBAL STATUS LIKE 'Questions';" 2>/dev/null | tail -1
sleep 5
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root -e "
    SHOW GLOBAL STATUS LIKE 'Questions';" 2>/dev/null | tail -1

echo ""
echo "--- Direct MySQL replica (under load) ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_mysql "$w" "${REPORT_DIR}/load_mysql_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/load_mysql_*.txt > "${REPORT_DIR}/load_mysql.txt" 2>/dev/null || true
LOAD_MYSQL_QPS=$(qps "${REPORT_DIR}/load_mysql.txt" "$DURATION")
LOAD_MYSQL_STATS=$(stats "${REPORT_DIR}/load_mysql.txt")
printf "  %-28s  QPS=%-8s  %s\n" "Direct MySQL" "$LOAD_MYSQL_QPS" "$LOAD_MYSQL_STATS"

echo ""
echo "--- ProxySQL warm cache (under load) ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_proxysql_warm "$w" "${REPORT_DIR}/load_proxysql_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/load_proxysql_*.txt > "${REPORT_DIR}/load_proxysql.txt" 2>/dev/null || true
LOAD_PSQL_QPS=$(qps "${REPORT_DIR}/load_proxysql.txt" "$DURATION")
LOAD_PSQL_STATS=$(stats "${REPORT_DIR}/load_proxysql.txt")
printf "  %-28s  QPS=%-8s  %s\n" "ProxySQL warm" "$LOAD_PSQL_QPS" "$LOAD_PSQL_STATS"

echo ""
echo "--- Valkey GET (under load) ---"
END=$(( $(date +%s) + DURATION ))
PIDS=()
for ((w=1; w<=WORKERS; w++)); do
    bench_valkey "$w" "${REPORT_DIR}/load_valkey_${w}.txt" "$END" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
cat "${REPORT_DIR}"/load_valkey_*.txt > "${REPORT_DIR}/load_valkey.txt" 2>/dev/null || true
LOAD_VK_QPS=$(qps "${REPORT_DIR}/load_valkey.txt" "$DURATION")
LOAD_VK_STATS=$(stats "${REPORT_DIR}/load_valkey.txt")
printf "  %-28s  QPS=%-8s  %s\n" "Valkey GET" "$LOAD_VK_QPS" "$LOAD_VK_STATS"

# Stop background load
for pid in "${BG_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
wait "${BG_PIDS[@]}" 2>/dev/null || true
echo ""
echo "  Background load stopped."

# ── Report ────────────────────────────────────────────────────────────────────
set +e

NL_M_AVG=$(echo "$NOLOAD_MYSQL_STATS"  | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
NL_P_AVG=$(echo "$NOLOAD_PSQL_STATS"   | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
NL_V_AVG=$(echo "$NOLOAD_VK_STATS"     | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
L_M_AVG=$( echo "$LOAD_MYSQL_STATS"    | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
L_P_AVG=$( echo "$LOAD_PSQL_STATS"     | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
L_V_AVG=$( echo "$LOAD_VK_STATS"       | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')

NL_M_AVG=${NL_M_AVG:-1}; NL_P_AVG=${NL_P_AVG:-1}; NL_V_AVG=${NL_V_AVG:-1}
L_M_AVG=${L_M_AVG:-1};   L_P_AVG=${L_P_AVG:-1};   L_V_AVG=${L_V_AVG:-1}

MYSQL_DEGRADATION=$( echo "scale=1; $L_M_AVG / ($NL_M_AVG + 0.01)" | bc 2>/dev/null || echo "?")
PSQL_DEGRADATION=$(  echo "scale=1; $L_P_AVG / ($NL_P_AVG + 0.01)" | bc 2>/dev/null || echo "?")
VK_DEGRADATION=$(    echo "scale=1; $L_V_AVG / ($NL_V_AVG + 0.01)" | bc 2>/dev/null || echo "?")

REPORT_FILE="${REPORT_DIR}/report.txt"
{
cat <<EOF
════════════════════════════════════════════════════════════════════════
  Load Simulation Report
  Date        : $(date '+%Y-%m-%d %H:%M:%S')
  Rows (orders): ${ROWS}
  BG workers  : ${BG_WORKERS}  Duration: ${DURATION}s  Bench workers: ${WORKERS}
  Query       : customers JOIN orders GROUP BY customer (top-20 revenue)
════════════════════════════════════════════════════════════════════════

  WITHOUT background load
  ─────────────────────────────────────────────────────────────────────
EOF
printf "  %-28s  QPS=%-8s  %s\n" "Direct MySQL"   "$NOLOAD_MYSQL_QPS" "$NOLOAD_MYSQL_STATS"
printf "  %-28s  QPS=%-8s  %s\n" "ProxySQL warm"  "$NOLOAD_PSQL_QPS"  "$NOLOAD_PSQL_STATS"
printf "  %-28s  QPS=%-8s  %s\n" "Valkey GET"     "$NOLOAD_VK_QPS"    "$NOLOAD_VK_STATS"
cat <<EOF

  WITH ${BG_WORKERS} background workers (concurrent MySQL load)
  ─────────────────────────────────────────────────────────────────────
EOF
printf "  %-28s  QPS=%-8s  %s\n" "Direct MySQL"   "$LOAD_MYSQL_QPS" "$LOAD_MYSQL_STATS"
printf "  %-28s  QPS=%-8s  %s\n" "ProxySQL warm"  "$LOAD_PSQL_QPS"  "$LOAD_PSQL_STATS"
printf "  %-28s  QPS=%-8s  %s\n" "Valkey GET"     "$LOAD_VK_QPS"    "$LOAD_VK_STATS"
cat <<EOF

  Impact of load on avg latency (ratio loaded/unloaded — lower = more stable)
  ─────────────────────────────────────────────────────────────────────
  Direct MySQL  : ${MYSQL_DEGRADATION}x  ← degrades with DB load
  ProxySQL warm : ${PSQL_DEGRADATION}x  ← should be near 1.0 (cache shields it)
  Valkey GET    : ${VK_DEGRADATION}x  ← should be near 1.0 (no MySQL involved)

  Key insight
    The ratio for ProxySQL/Valkey should stay near 1.0x even as MySQL
    degrades. If MySQL p99 goes from 20ms to 500ms under load, a cached
    path at 1ms stays at ~1ms. That is the value of caching under pressure.
════════════════════════════════════════════════════════════════════════
EOF
} | tee "$REPORT_FILE"

echo ""
echo "  Report : ${REPORT_FILE}"
echo ""
echo "  Scale up for more pressure:"
echo "    ROWS=1000000 BG_WORKERS=32 DURATION=120 ./scripts/14-load-simulation.sh"
echo ""
echo "  Re-run benchmark only (skip data generation):"
echo "    SKIP_SEED=1 BG_WORKERS=16 ./scripts/14-load-simulation.sh"
