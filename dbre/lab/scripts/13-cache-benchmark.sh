#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Cache performance benchmark — timed, multi-worker, saved report
#
# Four access paths for the same data:
#   A  Direct MySQL replica    full SQL round-trip, no cache
#   B  ProxySQL cold           cache flushed before run, every query hits MySQL
#   C  ProxySQL warm           cache populated, ProxySQL serves from RAM
#   D  Valkey GET              pure in-memory KV, no SQL
#
# Why this shows real speedup:
#   The benchmark uses a JOIN query (products × order_items aggregate) that
#   takes 20-100ms on MySQL. Cache saves the full execution — returning the
#   same result in < 1ms. TCP connection overhead (~5-10ms) is still present
#   on all paths but no longer dominates.
#
# Usage:
#   ./13-cache-benchmark.sh                      # defaults: 60s/path, 4 workers
#   DURATION=180 WORKERS=8 ./13-cache-benchmark.sh
#   SKIP_SEED=1 ./13-cache-benchmark.sh          # re-use existing data
#
# Total runtime ≈ 4 × DURATION + ~2min setup (default ≈ 6 min)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DURATION=${DURATION:-60}     # seconds per path
WORKERS=${WORKERS:-4}        # concurrent workers per path
SKIP_SEED=${SKIP_SEED:-0}    # set to 1 to skip data generation
REPORT_DIR="/tmp/bench_$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="${REPORT_DIR}/report.txt"

# MySQL 9.x removed mysql_native_password as a loadable plugin; ProxySQL requires it.
# Detect a client binary that can connect to ProxySQL (ports 6032/6033).
PROXYSQL_MYSQL="mysql"
for _candidate in mysql \
    /opt/homebrew/opt/mysql-client@8.3/bin/mysql \
    /usr/local/opt/mysql-client@8.3/bin/mysql; do
    if command -v "$_candidate" &>/dev/null 2>&1; then
        if MYSQL_PWD=apppass "$_candidate" -h 127.0.0.1 -P 6033 -u app shopdb \
               -sN -e "SELECT 1" &>/dev/null 2>&1; then
            PROXYSQL_MYSQL="$_candidate"
            break
        fi
    fi
done
export PROXYSQL_MYSQL

mkdir -p "$REPORT_DIR"

# Benchmark query — JOIN that scans order_items (20-100ms with large data)
BENCH_QUERY="SELECT p.id, p.sku, p.name, p.price, COUNT(oi.id) AS order_count, COALESCE(ROUND(SUM(oi.quantity * oi.unit_price),2),0) AS revenue FROM products p LEFT JOIN order_items oi ON oi.product_id = p.id GROUP BY p.id, p.sku, p.name, p.price ORDER BY revenue DESC"

# ── Helpers ───────────────────────────────────────────────────────────────────
header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Stats from a latency file (one integer ms value per line)
stats() {
    local file=$1
    [ -s "$file" ] || { echo "count=0"; return; }
    sort -n "$file" | awk '
    BEGIN { n=0; sum=0 }
    { v[n++]=$1; sum+=$1 }
    END {
        avg  = sum/n
        p50  = v[int(n*0.50)]
        p95  = v[int(n*0.95)]
        p99  = v[int(n*0.99)]
        printf "count=%-6d avg=%-6.1f p50=%-5d p95=%-5d p99=%-5d", n, avg, p50, p95, p99
    }'
}

qps() {
    local file=$1 dur=$2
    [ -s "$file" ] || { echo "0"; return; }
    local count
    count=$(wc -l < "$file")
    echo "scale=1; $count / $dur" | bc
}

# ── Worker functions (exported for use in subshells) ──────────────────────────
worker_mysql_direct() {
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

worker_proxysql() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        MYSQL_PWD=apppass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6033 -u app shopdb -sN \
            -e "$BENCH_QUERY" 2>/dev/null > /dev/null
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

worker_valkey() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        redis-cli -h 127.0.0.1 -p 6379 GET "bench:product_revenue" > /dev/null 2>&1
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

export -f worker_mysql_direct worker_proxysql worker_valkey
export BENCH_QUERY REPORT_DIR

# ── run_path: launch WORKERS workers for DURATION seconds, collect results ─────
run_path() {
    local label=$1 fn=$2 outbase=$3
    local end=$(( $(date +%s) + DURATION ))
    local pids=()

    printf "  Running %-30s [%ds × %d workers]  " "$label" "$DURATION" "$WORKERS"

    for ((w=1; w<=WORKERS; w++)); do
        "$fn" "$w" "${outbase}_${w}.txt" "$end" &
        pids+=($!)
    done

    # Progress dots
    local remaining=$DURATION
    while [ "$remaining" -gt 0 ]; do
        sleep 10
        remaining=$(( remaining - 10 ))
        printf "."
    done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    printf " done\n"

    # Merge worker files
    cat "${outbase}"_*.txt 2>/dev/null > "${outbase}_all.txt" || true
}

# ── Preflight ─────────────────────────────────────────────────────────────────
header "Preflight"

for svc in mysql-primary mysql-replica1 proxysql valkey redis-cli; do
    printf "  %-20s " "$svc..."
    case "$svc" in
        mysql-*) docker exec "$svc" mysqladmin ping -u root -prootpass -s 2>/dev/null \
                     && echo "ok" || { echo "FAIL — start the cluster first"; exit 1; } ;;
        proxysql) MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin \
                     -e "SELECT 1" --silent 2>/dev/null | grep -q 1 && echo "ok" || { echo "FAIL"; exit 1; } ;;
        valkey) docker exec valkey valkey-cli ping 2>/dev/null | grep -q PONG && echo "ok" || { echo "FAIL"; exit 1; } ;;
        redis-cli) command -v redis-cli &>/dev/null && echo "ok" \
                     || { echo "FAIL — run: brew install redis"; exit 1; } ;;
    esac
done

echo ""
echo "  Duration : ${DURATION}s per path  (4 paths = ~$(( DURATION * 4 / 60 ))min + setup)"
echo "  Workers  : ${WORKERS} concurrent per path"
echo "  Report   : ${REPORT_FILE}"
echo "  Query    : products LEFT JOIN order_items GROUP BY product (revenue aggregate)"

# ── Data generation phase ─────────────────────────────────────────────────────
PRODUCT_COUNT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT COUNT(*) FROM products;" 2>/dev/null || echo 0)
ORDER_ITEM_COUNT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT COUNT(*) FROM order_items;" 2>/dev/null || echo 0)

if [ "$SKIP_SEED" = "1" ]; then
    header "Data: skipping seed (SKIP_SEED=1)"
    echo "  products: ${PRODUCT_COUNT}  order_items: ${ORDER_ITEM_COUNT}"
elif [ "${PRODUCT_COUNT}" -ge 200 ] && [ "${ORDER_ITEM_COUNT}" -ge 50000 ]; then
    header "Data: sufficient (products=${PRODUCT_COUNT}, order_items=${ORDER_ITEM_COUNT})"
    echo "  Skipping seed — use SKIP_SEED=1 to always skip"
else
    header "Data: generating benchmark dataset"
    echo "  Need ≥200 products and ≥50k order_items for cache speedup to be visible"
    echo ""

    # Generate products (300 total; INSERT IGNORE skips duplicates)
    if [ "${PRODUCT_COUNT}" -lt 200 ]; then
        echo "  Inserting products up to 300..."
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e "
            SET SESSION cte_max_recursion_depth=300;
            INSERT IGNORE INTO products (sku, name, price, stock)
            WITH RECURSIVE seq(n) AS (
                SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 300
            )
            SELECT CONCAT('BENCH-', LPAD(n,5,'0')),
                   CONCAT('Bench Product ', n),
                   ROUND(5 + RAND()*995, 2),
                   FLOOR(RAND()*500)
            FROM seq;" 2>/dev/null
    fi

    # Generate customers (1000) if needed
    CUST_COUNT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
        -e "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo 0)
    if [ "${CUST_COUNT}" -lt 500 ]; then
        echo "  Inserting customers up to 1000..."
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e "
            SET SESSION cte_max_recursion_depth=1000;
            INSERT IGNORE INTO customers (name, email)
            WITH RECURSIVE seq(n) AS (
                SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 1000
            )
            SELECT CONCAT('BenchUser-', n), CONCAT('bench', n, '@bench.test')
            FROM seq;" 2>/dev/null
    fi

    # Generate orders + order_items in batches until we have 50k order_items
    echo "  Inserting orders + order_items (target: 50k order_items)..."
    INSERTED_OI=0
    BATCH=0
    while [ "$ORDER_ITEM_COUNT" -lt 50000 ]; do
        BATCH=$(( BATCH + 1 ))
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e "
            SET SESSION cte_max_recursion_depth=5001;
            INSERT INTO orders (customer_id, total, status)
            WITH RECURSIVE seq(n) AS (
                SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 5000
            )
            SELECT 1 + MOD(n, (SELECT COUNT(*) FROM customers)),
                   ROUND(10 + RAND()*990, 2),
                   ELT(1 + FLOOR(RAND()*4), 'pending','paid','shipped','cancelled')
            FROM seq;" 2>/dev/null

        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e "
            INSERT INTO order_items (order_id, product_id, quantity, unit_price)
            SELECT o.id,
                   1 + MOD(o.id, (SELECT COUNT(*) FROM products)),
                   1 + FLOOR(RAND()*5),
                   p.price
            FROM orders o
            JOIN products p ON p.id = 1 + MOD(o.id, (SELECT COUNT(*) FROM products))
            WHERE o.id > (SELECT COALESCE(MAX(oi.order_id),0) FROM order_items oi)
            LIMIT 10000;" 2>/dev/null || true

        ORDER_ITEM_COUNT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
            -e "SELECT COUNT(*) FROM order_items;" 2>/dev/null || echo 0)
        printf "    batch %d — order_items: %d\r" $BATCH "$ORDER_ITEM_COUNT"
    done
    echo ""

    echo ""
    echo "  Final counts:"
    MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e "
        SELECT 'products'    AS tbl, COUNT(*) AS rows FROM products
        UNION ALL SELECT 'customers',  COUNT(*) FROM customers
        UNION ALL SELECT 'orders',     COUNT(*) FROM orders
        UNION ALL SELECT 'order_items',COUNT(*) FROM order_items;" 2>/dev/null
fi

echo ""
echo "  Baseline query timing (single run):"
T0=$(date +%s%N)
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null > /dev/null
T1=$(date +%s%N)
BASELINE_MS=$(( (T1 - T0) / 1000000 ))
echo "  Direct MySQL replica: ${BASELINE_MS}ms"
if [ "$BASELINE_MS" -lt 10 ]; then
    echo ""
    echo "  ⚠  Query is very fast (${BASELINE_MS}ms) — cache speedup may not be obvious."
    echo "     Generate more data with: SKIP_SEED=0 ./scripts/13-cache-benchmark.sh"
    echo "     Or run ./scripts/14-load-simulation.sh first, then SKIP_SEED=1 ./scripts/13-cache-benchmark.sh"
fi

# ── Setup: Seed Valkey + warm ProxySQL cache ──────────────────────────────────
header "Setup: seed Valkey + warm ProxySQL cache"

# Store full query result in Valkey as a pre-computed blob (simulates app-level caching)
echo "  Computing product revenue results and storing in Valkey..."
RESULT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null)
redis-cli -h 127.0.0.1 -p 6379 SET "bench:product_revenue" "$RESULT" > /dev/null 2>&1
redis-cli -h 127.0.0.1 -p 6379 PERSIST "bench:product_revenue" > /dev/null 2>&1
echo "  Valkey key size: $(redis-cli -h 127.0.0.1 -p 6379 STRLEN 'bench:product_revenue' 2>/dev/null) bytes"

# Also keep per-product HSET for the HGET pattern
echo "  Loading per-product hash keys into Valkey..."
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb \
    -sN -e "SELECT id, sku, name, price, stock FROM products;" 2>/dev/null \
| while IFS=$'\t' read -r id sku name price stock; do
    redis-cli -h 127.0.0.1 -p 6379 HSET "product:${id}" \
        sku "$sku" name "$name" price "$price" stock "$stock" > /dev/null 2>&1
    redis-cli -h 127.0.0.1 -p 6379 PERSIST "product:${id}" > /dev/null 2>&1
done
echo "  Valkey keys total: $(redis-cli -h 127.0.0.1 -p 6379 DBSIZE 2>/dev/null)"

# Reset ProxySQL stats baseline
MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin \
    -e "SELECT * FROM stats_mysql_query_digest_reset;" 2>/dev/null > /dev/null || true

# Ensure ProxySQL cache rule covers the JOIN query (rule 3 matches ^SELECT .* FROM products)
# Add rule 6 for the specific JOIN pattern with a longer TTL if rule 3 doesn't fire
MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin -e "
    DELETE FROM mysql_query_rules WHERE rule_id=6;
    INSERT INTO mysql_query_rules
        (rule_id, active, match_pattern, destination_hostgroup, cache_ttl, apply)
    VALUES (6, 1, '^SELECT p\\.id.*FROM products p LEFT JOIN', 1, 30000, 1);
    LOAD MYSQL QUERY RULES TO RUNTIME;" 2>/dev/null || true

# ── Path A: Direct MySQL (no cache) ───────────────────────────────────────────
header "Path A — Direct MySQL replica (no cache, ${DURATION}s)"
run_path "Direct MySQL" worker_mysql_direct "${REPORT_DIR}/A"
A_QPS=$(qps "${REPORT_DIR}/A_all.txt" "$DURATION")
A_STATS=$(stats "${REPORT_DIR}/A_all.txt")

# ── Path B: ProxySQL cold ──────────────────────────────────────────────────────
header "Path B — ProxySQL COLD (cache flushed, every query hits MySQL, ${DURATION}s)"
MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin \
    -e "PROXYSQL FLUSH QUERY CACHE;" 2>/dev/null || true
run_path "ProxySQL cold" worker_proxysql "${REPORT_DIR}/B"
B_QPS=$(qps "${REPORT_DIR}/B_all.txt" "$DURATION")
B_STATS=$(stats "${REPORT_DIR}/B_all.txt")

# ── Path C: ProxySQL warm ─────────────────────────────────────────────────────
header "Path C — ProxySQL WARM (cache populated, served from RAM, ${DURATION}s)"
# Pre-warm: send 3 queries to populate cache before workers start
for _ in 1 2 3; do
    MYSQL_PWD=apppass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6033 -u app shopdb -sN \
        -e "$BENCH_QUERY" 2>/dev/null > /dev/null
done
run_path "ProxySQL warm" worker_proxysql "${REPORT_DIR}/C"
C_QPS=$(qps "${REPORT_DIR}/C_all.txt" "$DURATION")
C_STATS=$(stats "${REPORT_DIR}/C_all.txt")

# ── Path D: Valkey GET ────────────────────────────────────────────────────────
header "Path D — Valkey GET (pre-computed result, pure in-memory, ${DURATION}s)"
run_path "Valkey GET" worker_valkey "${REPORT_DIR}/D"
D_QPS=$(qps "${REPORT_DIR}/D_all.txt" "$DURATION")
D_STATS=$(stats "${REPORT_DIR}/D_all.txt")

# ── Stats gathering — disable set -e; non-fatal if any query fails ────────────
set +e

# ProxySQL cache stats
CACHE_RAW=$(MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin -sN \
    -e "SELECT Variable_Name, Variable_Value FROM stats_mysql_global
        WHERE Variable_Name IN (
            'Query_Cache_count_GET','Query_Cache_count_GET_OK',
            'Query_Cache_count_SET','Query_Cache_Entries'
        );" 2>/dev/null)
CACHE_GET=$(echo "$CACHE_RAW" | awk -F'\t' '/count_GET\t/{print $2}' | head -1 | tr -d '\r ')
CACHE_HIT=$(echo "$CACHE_RAW" | awk -F'\t' '/count_GET_OK/{print $2}'           | tr -d '\r ')
CACHE_HIT_PCT="n/a"
if [ -n "$CACHE_GET" ] && [ "${CACHE_GET:-0}" -gt 0 ]; then
    CACHE_HIT_PCT=$(echo "scale=1; ${CACHE_HIT:-0} * 100 / $CACHE_GET" | bc 2>/dev/null)%
fi

# Valkey hit rate
V_INFO=$(docker exec valkey valkey-cli INFO stats 2>/dev/null)
V_HITS=$(echo "$V_INFO" | awk -F: '/^keyspace_hits:/{gsub(/\r/,""); print $2}')
V_MISS=$(echo "$V_INFO" | awk -F: '/^keyspace_misses:/{gsub(/\r/,""); print $2}')
V_TOTAL=$(( ${V_HITS:-0} + ${V_MISS:-0} ))
VALKEY_HIT_PCT="n/a"
[ "${V_TOTAL:-0}" -gt 0 ] && \
    VALKEY_HIT_PCT=$(echo "scale=1; ${V_HITS:-0} * 100 / $V_TOTAL" | bc 2>/dev/null)%

# Speedup ratios
A_AVG=$(echo "$A_STATS" | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
C_AVG=$(echo "$C_STATS" | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
D_AVG=$(echo "$D_STATS" | awk '{for(i=1;i<=NF;i++) if($i~/^avg=/) {sub("avg=","",$i); print $i+0; exit}}')
A_AVG=${A_AVG:-1}; C_AVG=${C_AVG:-1}; D_AVG=${D_AVG:-1}
A_QPS=${A_QPS:-0}; C_QPS=${C_QPS:-0}; D_QPS=${D_QPS:-0}

C_SPEEDUP=$(echo "scale=1; $A_AVG / ($C_AVG + 0.01)" | bc 2>/dev/null || echo "?")
D_SPEEDUP=$(echo "scale=1; $A_AVG / ($D_AVG + 0.01)" | bc 2>/dev/null || echo "?")
C_QPS_GAIN=$(echo "scale=1; $C_QPS / ($A_QPS + 0.01)" | bc 2>/dev/null || echo "?")
D_QPS_GAIN=$(echo "scale=1; $D_QPS / ($A_QPS + 0.01)" | bc 2>/dev/null || echo "?")

set -e

# ── Build report ──────────────────────────────────────────────────────────────
{
cat <<HEADER
════════════════════════════════════════════════════════════════════════
  Cache Benchmark Report
  Date    : $(date '+%Y-%m-%d %H:%M:%S')
  Duration: ${DURATION}s per path  |  Workers: ${WORKERS}
  Query   : products LEFT JOIN order_items GROUP BY product (revenue aggregate)
  Baseline: ${BASELINE_MS}ms for single uncached query on replica
════════════════════════════════════════════════════════════════════════

  NOTE: Each worker opens a new TCP connection per query (no connection
  pooling). Latency includes ~5-15ms connection setup on each path.
  Speedup ratios reflect real-world cache benefit on top of that overhead.

────────────────────────────────────────────────────────────────────────
  Path                         QPS      avg ms   p50    p95    p99
────────────────────────────────────────────────────────────────────────
HEADER
printf "  %-28s  %-8s  %s\n" "A: Direct MySQL replica"  "$A_QPS"  "$A_STATS"
printf "  %-28s  %-8s  %s\n" "B: ProxySQL cold (miss)"  "$B_QPS"  "$B_STATS"
printf "  %-28s  %-8s  %s\n" "C: ProxySQL warm (hit)"   "$C_QPS"  "$C_STATS"
printf "  %-28s  %-8s  %s\n" "D: Valkey GET"            "$D_QPS"  "$D_STATS"
cat <<FOOTER

────────────────────────────────────────────────────────────────────────
  Speedup vs Direct MySQL (avg latency)
    ProxySQL warm : ${C_SPEEDUP}x faster  (${C_QPS_GAIN}x QPS)
    Valkey GET    : ${D_SPEEDUP}x faster  (${D_QPS_GAIN}x QPS)

  Cache hit rates
    ProxySQL query cache : ${CACHE_HIT_PCT}  (${CACHE_HIT:-0} hits / ${CACHE_GET:-0} lookups)
    Valkey keyspace      : ${VALKEY_HIT_PCT}  (${V_HITS:-0} hits / ${V_TOTAL} lookups)

  Interpretation
    A vs B  — ProxySQL routing overhead vs direct connection (~same, < 5ms diff)
    B vs C  — pure cache effect: same ProxySQL path, cache on vs off
    A vs D  — pre-computed KV result vs full SQL JOIN + aggregate
    Speedup visible when baseline query > 15ms (TCP overhead ~5-15ms per conn)
════════════════════════════════════════════════════════════════════════
FOOTER
} | tee "$REPORT_FILE"

echo ""
echo "  Full report saved: ${REPORT_FILE}"
echo "  Raw latency data : ${REPORT_DIR}/"
echo ""
echo "  Watch live in Grafana → localhost:3000 → Valkey Cache / ProxySQL dashboards"
echo "  Re-run (skip seed, use existing data):"
echo "    SKIP_SEED=1 DURATION=120 WORKERS=8 ./scripts/13-cache-benchmark.sh"
echo "  Run with large dataset from load-simulation:"
echo "    ./scripts/14-load-simulation.sh && SKIP_SEED=1 ./scripts/13-cache-benchmark.sh"
