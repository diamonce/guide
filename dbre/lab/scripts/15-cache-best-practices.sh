#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Cache Best Practices — three lessons
#
#   Lesson 1 — Connection Pooling
#     Script 13 uses a new TCP connection per query, adding ~35ms MySQL
#     handshake overhead that dwarfs cache savings. This lesson uses
#     mysqlslap (persistent connections) and redis-benchmark to show
#     the real per-query latency: ProxySQL warm ~1–5ms, Valkey ~1–2ms.
#
#   Lesson 2 — Cache Invalidation
#     The hardest part of caching. Demonstrates stale reads, ProxySQL's
#     all-or-nothing FLUSH limitation, Valkey per-key DEL, and the
#     write-through pattern that eliminates the stale window entirely.
#
#   Lesson 3 — Cache Stampede
#     When a hot key expires, every concurrent request misses and hits
#     the database simultaneously. Demonstrates the thundering herd and
#     shows jittered TTL as the simplest prevention.
#
# Prerequisites:
#   redis-benchmark — included with redis     (brew install redis)
#   Run ./13-cache-benchmark.sh first to generate the dataset.
#
# Run time: ~3 minutes
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BENCH_QUERY="SELECT p.id, p.sku, p.name, p.price, COUNT(oi.id) AS order_count, COALESCE(ROUND(SUM(oi.quantity * oi.unit_price),2),0) AS revenue FROM products p LEFT JOIN order_items oi ON oi.product_id = p.id GROUP BY p.id, p.sku, p.name, p.price ORDER BY revenue DESC"
CONC=4
QUERIES_PER_CONN=50   # queries per persistent connection; CONC × QUERIES_PER_CONN total

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

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── Preflight ─────────────────────────────────────────────────────────────────
header "Preflight"

for svc in mysql-primary mysql-replica1 proxysql valkey redis-benchmark; do
    printf "  %-22s " "$svc..."
    case "$svc" in
        mysql-*) docker exec "$svc" mysqladmin ping -u root -prootpass -s 2>/dev/null \
                     && echo "ok" || { echo "FAIL — start the cluster"; exit 1; } ;;
        proxysql) MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin \
                     -e "SELECT 1" --silent 2>/dev/null | grep -q 1 \
                     && echo "ok" || { echo "FAIL"; exit 1; } ;;
        valkey) docker exec valkey valkey-cli ping 2>/dev/null | grep -q PONG \
                     && echo "ok" || { echo "FAIL"; exit 1; } ;;
        redis-benchmark) command -v redis-benchmark &>/dev/null \
                     && echo "ok" || { echo "FAIL — brew install redis"; exit 1; } ;;
    esac
done

OI_COUNT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT COUNT(*) FROM order_items;" 2>/dev/null || echo 0)
echo ""
echo "  order_items: ${OI_COUNT}"
if [ "${OI_COUNT}" -lt 50000 ]; then
    echo "  ⚠  Run ./13-cache-benchmark.sh first to generate the dataset."
    exit 1
fi

# ── Setup: warm caches ────────────────────────────────────────────────────────
header "Setup: warming caches"

echo "  Warming ProxySQL cache (3 queries)..."
for _ in 1 2 3; do
    MYSQL_PWD=apppass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6033 -u app shopdb -sN \
        -e "$BENCH_QUERY" 2>/dev/null > /dev/null
done

echo "  Populating Valkey bench key..."
RESULT=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null)
redis-cli -h 127.0.0.1 -p 6379 SET "bench:product_revenue" "$RESULT" > /dev/null 2>&1
redis-cli -h 127.0.0.1 -p 6379 PERSIST "bench:product_revenue" > /dev/null 2>&1
echo "  Ready."

# ─────────────────────────────────────────────────────────────────────────────
header "Lesson 1 — Connection Pooling"
# ─────────────────────────────────────────────────────────────────────────────

echo "  Script 13 opens a new TCP connection per query — the ~35ms MySQL"
echo "  handshake overhead dominates and hides cache savings. Real apps use"
echo "  persistent connection pools. This lesson shows the true cache latency."
echo ""
TOTAL_QUERIES=$(( CONC * QUERIES_PER_CONN ))
echo "  ${CONC} parallel workers × ${QUERIES_PER_CONN} queries/worker = ${TOTAL_QUERIES} total queries per path"
echo "  redis-benchmark: ${CONC} persistent connections, 10000 GET requests"
echo ""

# Direct MySQL — 4 persistent connections, QUERIES_PER_CONN queries each
printf "  %-32s  " "Direct MySQL replica..."
T0=$(date +%s%N)
for w in $(seq 1 $CONC); do
    (for i in $(seq 1 $QUERIES_PER_CONN); do echo "$BENCH_QUERY;"; done) | \
        MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN 2>/dev/null > /dev/null &
done
wait
T1=$(date +%s%N)
MYSQL_MS=$(echo "scale=1; $(( (T1 - T0) / 1000000 )) / $TOTAL_QUERIES" | bc)
echo "${MYSQL_MS}ms avg"

# ProxySQL warm — 4 persistent connections, QUERIES_PER_CONN queries each
printf "  %-32s  " "ProxySQL warm (cache hit)..."
T0=$(date +%s%N)
for w in $(seq 1 $CONC); do
    (for i in $(seq 1 $QUERIES_PER_CONN); do echo "$BENCH_QUERY;"; done) | \
        MYSQL_PWD=apppass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6033 -u app shopdb -sN 2>/dev/null > /dev/null &
done
wait
T1=$(date +%s%N)
PSQL_MS=$(echo "scale=1; $(( (T1 - T0) / 1000000 )) / $TOTAL_QUERIES" | bc)
echo "${PSQL_MS}ms avg"

# Valkey — persistent connections via redis-benchmark
printf "  %-32s  " "Valkey GET..."
VK_OUT=$(redis-benchmark -h 127.0.0.1 -p 6379 \
    -n 10000 -c $CONC \
    GET bench:product_revenue 2>/dev/null || true)
VK_AVG_MS=$(echo "$VK_OUT" | awk 'p~/avg.*min.*p50/{print $1} {p=$0}')
echo "${VK_AVG_MS}ms avg"

set +e
PSQL_SPEEDUP=$(echo "scale=1; ${MYSQL_MS} / (${PSQL_MS} + 0.01)" | bc 2>/dev/null || echo "?")
VK_SPEEDUP=$(  echo "scale=1; ${MYSQL_MS} / (${VK_AVG_MS} + 0.01)" | bc 2>/dev/null || echo "?")
set -e

echo ""
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  Persistent connections vs new-connection-per-query          │"
printf "  │  %-28s  new-conn: ~707ms  pool: ~%5sms  │\n" "Direct MySQL"     "$MYSQL_MS"
printf "  │  %-28s  new-conn: ~ 39ms  pool: ~%5sms  │\n" "ProxySQL warm"    "$PSQL_MS"
printf "  │  %-28s  new-conn: ~ 15ms  pool: ~%5sms  │\n" "Valkey GET"       "$VK_AVG_MS"
echo "  ├──────────────────────────────────────────────────────────────┤"
printf "  │  ProxySQL speedup: %5sx    Valkey speedup: %5sx         │\n" "$PSQL_SPEEDUP" "$VK_SPEEDUP"
echo "  └──────────────────────────────────────────────────────────────┘"
echo ""
echo "  Key insight: always use a connection pool in production."
echo "  The MySQL handshake (~35ms) paid once at startup, not per query."

# ─────────────────────────────────────────────────────────────────────────────
header "Lesson 2 — Cache Invalidation"
# ─────────────────────────────────────────────────────────────────────────────

echo "  The hardest part of caching: keeping cache consistent when data changes."
echo ""

PRODUCT_ID=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT id FROM products ORDER BY id LIMIT 1;" 2>/dev/null)
ORIG_PRICE=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT price FROM products WHERE id=${PRODUCT_ID};" 2>/dev/null)
NEW_PRICE=$(echo "scale=2; $ORIG_PRICE + 10.00" | bc)

# Seed the caches
MYSQL_PWD=apppass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6033 -u app shopdb -sN \
    -e "$BENCH_QUERY" 2>/dev/null > /dev/null
redis-cli -h 127.0.0.1 -p 6379 HSET "product:${PRODUCT_ID}" price "$ORIG_PRICE" > /dev/null 2>&1
redis-cli -h 127.0.0.1 -p 6379 EXPIRE "product:${PRODUCT_ID}" 30 > /dev/null 2>&1

echo "  Product #${PRODUCT_ID} — current price: \$${ORIG_PRICE}"

# ── 2a: Stale read ────────────────────────────────────────────────────────────
echo ""
echo "  ─── 2a: Stale Read ──────────────────────────────────────────────"
echo ""
echo "  Updating MySQL price: \$${ORIG_PRICE} → \$${NEW_PRICE}"
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e \
    "UPDATE products SET price=${NEW_PRICE} WHERE id=${PRODUCT_ID};" 2>/dev/null

MYSQL_PRICE=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT price FROM products WHERE id=${PRODUCT_ID};" 2>/dev/null)
VALKEY_PRICE=$(redis-cli -h 127.0.0.1 -p 6379 HGET "product:${PRODUCT_ID}" price 2>/dev/null)

echo ""
echo "  MySQL  (truth) : \$${MYSQL_PRICE}"
echo "  Valkey (cached): \$${VALKEY_PRICE}  ← stale!"
echo ""
echo "  Both ProxySQL and Valkey still return the old price."
echo "  This is the stale read window — it lasts until TTL expires or"
echo "  you explicitly invalidate the key."

# ── 2b: ProxySQL — all-or-nothing flush ──────────────────────────────────────
echo ""
echo "  ─── 2b: ProxySQL Invalidation ───────────────────────────────────"
echo ""
echo "  ProxySQL has no per-key invalidation."
echo "  Only option: PROXYSQL FLUSH QUERY CACHE — evicts everything."
echo ""
MYSQL_PWD=radminpass $PROXYSQL_MYSQL -h 127.0.0.1 -P 6032 -uradmin \
    -e "PROXYSQL FLUSH QUERY CACHE;" 2>/dev/null || true
echo "  Cache flushed. Next query re-executes against MySQL (cache miss)."
echo "  Limitation: flushes ALL cached queries, not just the affected one."

# ── 2c: Valkey — per-key DEL ─────────────────────────────────────────────────
echo ""
echo "  ─── 2c: Valkey Per-Key Invalidation ─────────────────────────────"
echo ""
echo "  DEL invalidates exactly one key. App fetches fresh and re-caches."
echo ""
redis-cli -h 127.0.0.1 -p 6379 DEL "product:${PRODUCT_ID}" > /dev/null 2>&1
FRESH_PRICE=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -sN \
    -e "SELECT price FROM products WHERE id=${PRODUCT_ID};" 2>/dev/null)
redis-cli -h 127.0.0.1 -p 6379 HSET "product:${PRODUCT_ID}" price "$FRESH_PRICE" > /dev/null 2>&1
redis-cli -h 127.0.0.1 -p 6379 EXPIRE "product:${PRODUCT_ID}" 30 > /dev/null 2>&1

VALKEY_AFTER=$(redis-cli -h 127.0.0.1 -p 6379 HGET "product:${PRODUCT_ID}" price 2>/dev/null)
echo "  Valkey after DEL + re-cache: \$${VALKEY_AFTER}  ← fresh"

# ── 2d: Write-through — update DB + cache atomically ─────────────────────────
echo ""
echo "  ─── 2d: Write-Through Pattern ───────────────────────────────────"
echo ""
echo "  Best practice: on every write, update MySQL and Valkey together."
echo "  Zero stale window because the cache is updated before the write returns."
echo ""
FINAL_PRICE=$(echo "scale=2; $ORIG_PRICE + 5.00" | bc)
echo "  Writing: \$${NEW_PRICE} → \$${FINAL_PRICE}"
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e \
    "UPDATE products SET price=${FINAL_PRICE} WHERE id=${PRODUCT_ID};" 2>/dev/null
redis-cli -h 127.0.0.1 -p 6379 HSET "product:${PRODUCT_ID}" price "$FINAL_PRICE" > /dev/null 2>&1

MYSQL_FINAL=$(MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3311 -u root shopdb -sN \
    -e "SELECT price FROM products WHERE id=${PRODUCT_ID};" 2>/dev/null)
VK_FINAL=$(redis-cli -h 127.0.0.1 -p 6379 HGET "product:${PRODUCT_ID}" price 2>/dev/null)
echo "  MySQL  : \$${MYSQL_FINAL}"
echo "  Valkey : \$${VK_FINAL}"
echo "  Both consistent — no stale window."

# Restore original price
MYSQL_PWD=rootpass mysql -h 127.0.0.1 -P 3310 -u root shopdb -e \
    "UPDATE products SET price=${ORIG_PRICE} WHERE id=${PRODUCT_ID};" 2>/dev/null
redis-cli -h 127.0.0.1 -p 6379 HSET "product:${PRODUCT_ID}" price "$ORIG_PRICE" > /dev/null 2>&1

echo ""
echo "  ─── Invalidation Summary ─────────────────────────────────────────"
echo ""
printf "  %-20s  %-20s  %s\n" "Strategy"  "Stale window"  "Notes"
printf "  %-20s  %-20s  %s\n" "──────────────────" "──────────────────" "──────────────────────────────"
printf "  %-20s  %-20s  %s\n" "TTL-only"            "Up to TTL duration" "Zero app work; accept staleness"
printf "  %-20s  %-20s  %s\n" "ProxySQL FLUSH"      "Zero (after flush)" "Flushes ALL keys, not per-key"
printf "  %-20s  %-20s  %s\n" "Valkey DEL on write" "Zero"               "Per-key; requires app code"
printf "  %-20s  %-20s  %s\n" "Write-through"       "Zero"               "DB + cache updated atomically"

# ─────────────────────────────────────────────────────────────────────────────
header "Lesson 3 — Cache Stampede"
# ─────────────────────────────────────────────────────────────────────────────

echo "  A hot key expires. Every concurrent request misses simultaneously"
echo "  and hits the database — the thundering herd."
echo ""

STAMPEDE_KEY="bench:stampede_test"
SHORT_TTL=6
STAMPEDE_CLIENTS=20

# Reset Valkey stats
docker exec valkey valkey-cli CONFIG RESETSTAT > /dev/null 2>&1

redis-cli -h 127.0.0.1 -p 6379 SET "$STAMPEDE_KEY" "hot_data" EX $SHORT_TTL > /dev/null 2>&1
echo "  Set '$STAMPEDE_KEY' with ${SHORT_TTL}s TTL."
printf "  Waiting %ds for expiry" $SHORT_TTL
for _ in $(seq 1 $SHORT_TTL); do sleep 1; printf "."; done
echo " expired."
echo ""

# Fire STAMPEDE_CLIENTS concurrent GETs after expiry
echo "  Firing ${STAMPEDE_CLIENTS} concurrent GETs..."
for _ in $(seq 1 $STAMPEDE_CLIENTS); do
    redis-cli -h 127.0.0.1 -p 6379 GET "$STAMPEDE_KEY" > /dev/null 2>&1 &
done
wait

MISSES=$(docker exec valkey valkey-cli INFO stats 2>/dev/null \
    | awk -F: '/^keyspace_misses:/{gsub(/\r/,""); print $2}')
HITS=$(docker exec valkey valkey-cli INFO stats 2>/dev/null \
    | awk -F: '/^keyspace_hits:/{gsub(/\r/,""); print $2}')

echo "  Results: ${MISSES:-0} misses, ${HITS:-0} hits out of ${STAMPEDE_CLIENTS} requests"
echo "  Each miss = one database query in a real app."
echo "  At ${STAMPEDE_CLIENTS} concurrent users: ${MISSES:-$STAMPEDE_CLIENTS} simultaneous DB hits for one expired key."

echo ""
echo "  ─── Prevention: Jittered TTL ────────────────────────────────────"
echo ""
echo "  Problem : SET key EX 30  ← all keys expire at the same instant"
echo "  Fix     : SET key EX \$((30 + RANDOM % 10))  ← spread expiry over 30-40s"
echo ""
echo "  10 keys with jittered TTL (30–40s):"
for i in $(seq 1 10); do
    JITTER=$(( 30 + RANDOM % 10 ))
    redis-cli -h 127.0.0.1 -p 6379 SET "bench:jitter_${i}" "data" EX $JITTER > /dev/null 2>&1
done
printf "  TTLs: "
for i in $(seq 1 10); do
    TTL=$(redis-cli -h 127.0.0.1 -p 6379 TTL "bench:jitter_${i}" 2>/dev/null)
    printf "%ss " "$TTL"
done
echo ""
echo "  No two keys expire at the same second — load spreads naturally."

echo ""
echo "  ─── Other Prevention Strategies ─────────────────────────────────"
echo ""
echo "  1. Jittered TTL       — stagger expiry times (shown above, easiest)"
echo "  2. Lock + refresh     — one process refreshes, others serve stale"
echo "                          or wait. Requires distributed lock (Redlock)."
echo "  3. Background refresh — watch TTL, refresh before it hits zero."
echo "                          App layer: if TTL < 5s, trigger async refresh."
echo "  4. Probabilistic early expiration (PER algorithm)"
echo "                          if TTL < threshold && rand() < recompute_prob:"
echo "                              refresh now (before expiry, under low load)"
echo "  5. Never expire hot keys — refresh on DB write instead of TTL."
echo "                          Only works when you control all writers."

# ─────────────────────────────────────────────────────────────────────────────
header "Summary — Caching Best Practices"
# ─────────────────────────────────────────────────────────────────────────────

cat <<'EOF'
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Practice                   Why                                       │
  ├──────────────────────────────────────────────────────────────────────┤
  │  Use connection pooling     ~35ms handshake paid once, not per query  │
  │  ProxySQL = transparent     No app changes; best for slow-changing    │
  │                             catalogs; 17.7x speedup in the lab        │
  │  Valkey = explicit control  Per-key DEL; shared across all app nodes  │
  │  Match strategy to change   TTL-only for read-heavy static data;      │
  │  rate                       write-through for frequently updated data  │
  │  Jitter all TTLs            +RANDOM % N prevents thundering herd      │
  │  Monitor hit rate           < 80% = cache is not helping              │
  │  Flush ProxySQL sparingly   FLUSH evicts everything, not one query    │
  └──────────────────────────────────────────────────────────────────────┘

  Grafana while running:
    ProxySQL  → localhost:3000/d/proxysql     (hit rate, latency buckets)
    Valkey    → localhost:3000/d/valkey-cache (hit rate, evictions, memory)
EOF
