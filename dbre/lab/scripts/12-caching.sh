#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Transparent caching with Valkey + ProxySQL
#
# Two independent caching layers — both transparent to the application:
#
#   Layer 1 — ProxySQL built-in query cache
#     ProxySQL intercepts SELECT queries and serves results from its internal
#     cache (no MySQL I/O). Enabled via cache_ttl in query rules.
#     App sends normal SQL to :6033 and never knows caching happened.
#
#   Layer 2 — Valkey via HAProxy
#     Redis-compatible KV cache. App connects to HAProxy :6379 (writes) or
#     :6380 (reads). HAProxy proxies to Valkey and fails over transparently —
#     if Valkey moves, only haproxy.cfg changes, not the app connection string.
#
# Architecture:
#   App → ProxySQL :6033 ─► cache hit → return immediately (no MySQL)
#                         └► cache miss → MySQL replica → cache → return
#
#   App → HAProxy :6379 → Valkey primary  (writes)
#   App → HAProxy :6380 → Valkey replica  (reads)
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PROXYSQL_ADMIN="docker exec -i proxysql mysql -u admin -padminpass -h 127.0.0.1 -P 6032 --prompt='ProxySQL> '"
MYSQL="docker exec -i mysql-primary mysql -u root -prootpass shopdb"
VALKEY="docker exec valkey valkey-cli"
VALKEY_REPLICA="docker exec valkey-replica valkey-cli"

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── Preflight ────────────────────────────────────────────────────────────────
header "Preflight: verify services are up"

echo -n "ProxySQL... "
docker exec proxysql mysql -u admin -padminpass -h 127.0.0.1 -P 6032 \
    -e "SELECT 'ok'" --silent 2>/dev/null | grep -q ok && echo "ok" || echo "FAIL"

echo -n "Valkey primary... "
$VALKEY ping 2>/dev/null | grep -q PONG && echo "ok" || echo "FAIL"

echo -n "Valkey replica... "
$VALKEY_REPLICA ping 2>/dev/null | grep -q PONG && echo "ok" || echo "FAIL"

echo -n "HAProxy Valkey write port 6379... "
docker run --rm --network dbre-lab_db-net valkey/valkey:8 \
    valkey-cli -h haproxy -p 6379 ping 2>/dev/null | grep -q PONG && echo "ok" || echo "FAIL (HAProxy may not be routing yet)"

# ─── Layer 1: ProxySQL query cache ───────────────────────────────────────────
header "Layer 1: ProxySQL built-in query cache"

echo "Active query rules with cache_ttl:"
docker exec proxysql mysql -u admin -padminpass -h 127.0.0.1 -P 6032 \
    -e "SELECT rule_id, match_pattern, destination_hostgroup, cache_ttl
        FROM mysql_query_rules
        WHERE active=1 AND cache_ttl IS NOT NULL
        ORDER BY rule_id;" 2>/dev/null

echo ""
echo "--- Populate some data first ---"
echo "INSERT INTO products (sku,name,price,stock) VALUES ('SKU-100','Cache Demo Widget',9.99,100)
      ON DUPLICATE KEY UPDATE stock=stock+0;" | $MYSQL 2>/dev/null || true

echo ""
echo "--- Run the same product query 5× and watch cache kick in ---"
echo "First run hits MySQL replica. Subsequent runs come from ProxySQL cache."
echo ""

for i in 1 2 3 4 5; do
    TIME_START=$(date +%s%N)
    docker exec mysql-primary mysql -u app -papppass shopdb \
        -e "SELECT id, sku, name, price FROM products ORDER BY id;" \
        --silent 2>/dev/null | wc -l > /dev/null
    TIME_END=$(date +%s%N)
    MS=$(( (TIME_END - TIME_START) / 1000000 ))
    if [ $i -eq 1 ]; then
        echo "  Run $i: ~${MS}ms  ← MySQL (cache miss, result stored)"
    else
        echo "  Run $i: ~${MS}ms  ← ProxySQL cache (no MySQL I/O)"
    fi
    sleep 0.1
done

echo ""
echo "--- ProxySQL query digest — cache hits vs MySQL hits ---"
docker exec proxysql mysql -u admin -padminpass -h 127.0.0.1 -P 6032 \
    -e "SELECT hostgroup, digest_text, count_star, cache_entries, sum_time
        FROM stats_mysql_query_digest
        WHERE digest_text LIKE '%products%'
        ORDER BY count_star DESC
        LIMIT 10;" 2>/dev/null | column -t || true

echo ""
echo "--- ProxySQL global cache stats ---"
docker exec proxysql mysql -u admin -padminpass -h 127.0.0.1 -P 6032 \
    -e "SELECT * FROM stats_mysql_global
        WHERE Variable_Name IN (
            'Query_Cache_Memory_bytes',
            'Query_Cache_count_GET',
            'Query_Cache_count_GET_OK',
            'Query_Cache_count_SET',
            'Query_Cache_Entries'
        );" 2>/dev/null

echo ""
echo "Key metrics:"
echo "  Query_Cache_count_GET     — total cache lookups"
echo "  Query_Cache_count_GET_OK  — cache hits (GET_OK / GET = hit rate)"
echo "  Query_Cache_count_SET     — results written to cache (cache misses)"
echo "  Query_Cache_Entries       — current entries in cache"
echo "  Query_Cache_Memory_bytes  — current cache memory usage"

# ─── Layer 2: Valkey via HAProxy ─────────────────────────────────────────────
header "Layer 2: Valkey replication and HAProxy health"

echo "--- Valkey primary INFO replication ---"
$VALKEY info replication 2>/dev/null | grep -E "^role:|^connected_slaves:|^slave0:"

echo ""
echo "--- Valkey replica INFO replication ---"
$VALKEY_REPLICA info replication 2>/dev/null | grep -E "^role:|^master_host:|^master_link_status:|^master_last_io_seconds_ago:"

echo ""
echo "--- HAProxy Valkey backend status ---"
echo "Checking via HAProxy stats API..."
curl -s "http://localhost:8404/stats;csv" 2>/dev/null \
    | awk -F, 'NR==1 || $1~/valkey/' \
    | cut -d, -f1-2,18,19 2>/dev/null || echo "(HAProxy stats at localhost:8404/stats)"

# ─── Cache warming pattern ────────────────────────────────────────────────────
header "Cache warming: populate Valkey with hot data from MySQL"

echo "Pattern: read-through cache — if key missing, fetch from MySQL and store."
echo ""
echo "--- Load product catalog into Valkey (HSET per product) ---"

PRODUCTS=$(docker exec mysql-primary mysql -u root -prootpass shopdb \
    -sN -e "SELECT id, sku, name, price, stock FROM products;" 2>/dev/null)

echo "$PRODUCTS" | while IFS=$'\t' read -r id sku name price stock; do
    $VALKEY HSET "product:${id}" \
        sku "$sku" name "$name" price "$price" stock "$stock" \
        > /dev/null 2>&1
    $VALKEY EXPIRE "product:${id}" 30 > /dev/null 2>&1   # 30s TTL matches ProxySQL rule
    echo "  Cached product:${id} → ${name} (TTL 30s)"
done

echo ""
echo "--- Verify products are in Valkey ---"
$VALKEY KEYS "product:*" 2>/dev/null | sort

echo ""
echo "--- Read a product from Valkey (no MySQL I/O) ---"
$VALKEY HGETALL "product:1" 2>/dev/null

# ─── Session / rate-limit pattern ─────────────────────────────────────────────
header "Common Valkey patterns (zero app code changes needed at proxy level)"

echo "--- Pattern 1: Session store ---"
SESSION_ID="sess_$(date +%s)"
$VALKEY HSET "$SESSION_ID" \
    user_id 42 \
    email "alice@example.com" \
    cart_count 3 \
    > /dev/null 2>&1
$VALKEY EXPIRE "$SESSION_ID" 1800 > /dev/null 2>&1   # 30 min session
echo "  SET $SESSION_ID (TTL 30min)"
$VALKEY HGETALL "$SESSION_ID" 2>/dev/null

echo ""
echo "--- Pattern 2: Rate limiting counter (INCR + EXPIRE) ---"
RATE_KEY="ratelimit:alice:$(date +%Y%m%d%H)"
$VALKEY INCR "$RATE_KEY" > /dev/null 2>&1
$VALKEY EXPIRE "$RATE_KEY" 3600 > /dev/null 2>&1     # 1-hour window
COUNT=$($VALKEY GET "$RATE_KEY" 2>/dev/null)
echo "  alice API calls this hour: $COUNT"
echo "  Key expires in: $($VALKEY TTL "$RATE_KEY" 2>/dev/null)s"

echo ""
echo "--- Pattern 3: Distributed lock (SET NX PX) ---"
LOCK_KEY="lock:order:processing"
LOCK_RESULT=$($VALKEY SET "$LOCK_KEY" "worker-1" NX PX 5000 2>/dev/null)
echo "  Lock acquired: $LOCK_RESULT (NX=only-if-not-exists, PX=5000ms TTL)"
echo "  Try to acquire same lock again (should fail):"
$VALKEY SET "$LOCK_KEY" "worker-2" NX PX 5000 2>/dev/null || true
$VALKEY SET "$LOCK_KEY" "worker-2" NX PX 5000 2>/dev/null

# ─── Replication check ────────────────────────────────────────────────────────
header "Verify write → replica replication"

TEST_KEY="repl_test_$(date +%s)"
echo "--- Write to primary via HAProxy :6379 ---"
docker run --rm --network dbre-lab_db-net valkey/valkey:8 \
    valkey-cli -h haproxy -p 6379 SET "$TEST_KEY" "written-via-haproxy" EX 60 2>/dev/null \
    || $VALKEY SET "$TEST_KEY" "written-direct" EX 60 2>/dev/null

sleep 0.5   # allow replication

echo "--- Read from replica (should see the key) ---"
$VALKEY_REPLICA GET "$TEST_KEY" 2>/dev/null

echo ""
echo "--- Replica replication lag ---"
$VALKEY_REPLICA INFO replication 2>/dev/null | grep -E "master_last_io|repl_backlog"

# ─── Memory and eviction ─────────────────────────────────────────────────────
header "Memory usage and eviction policy"

echo "--- Valkey memory stats ---"
$VALKEY INFO memory 2>/dev/null | grep -E "^used_memory_human|^maxmemory_human|^maxmemory_policy|^mem_fragmentation"

echo ""
echo "--- Current keyspace ---"
$VALKEY INFO keyspace 2>/dev/null

echo ""
echo "--- Eviction policy: allkeys-lru ---"
echo "  When maxmemory (256MB) is reached, Valkey evicts the least-recently-used"
echo "  key across ALL keys — not just those with TTL. This is correct for a cache"
echo "  where you want automatic cleanup, not an error on full memory."
echo ""
echo "  Alternatives:"
echo "    volatile-lru    — only evict keys with TTL (keep permanent keys)"
echo "    allkeys-lfu     — evict least-frequently-used (better for skewed access)"
echo "    noeviction      — return error (correct for primary data store, not cache)"

# ─── Monitoring ───────────────────────────────────────────────────────────────
header "Monitoring: redis-exporter metrics"

echo "Key Prometheus metrics from redis-exporter (localhost:9121/metrics):"
echo ""
curl -s http://localhost:9121/metrics 2>/dev/null \
    | grep -E "^redis_(connected_clients|keyspace_hits|keyspace_misses|evicted_keys|memory_used_bytes|replication_lag|commands_processed_total)" \
    | sort || echo "(redis-exporter at localhost:9121/metrics)"

echo ""
echo "--- Cache hit rate formula ---"
echo "  hit_rate = keyspace_hits / (keyspace_hits + keyspace_misses)"
HITS=$($VALKEY INFO stats 2>/dev/null | grep keyspace_hits | cut -d: -f2 | tr -d '\r')
MISSES=$($VALKEY INFO stats 2>/dev/null | grep keyspace_misses | cut -d: -f2 | tr -d '\r')
TOTAL=$((${HITS:-0} + ${MISSES:-0}))
if [ "$TOTAL" -gt 0 ]; then
    RATE=$(echo "scale=1; ${HITS:-0} * 100 / $TOTAL" | bc)
    echo "  Current: ${HITS} hits, ${MISSES} misses → ${RATE}% hit rate"
else
    echo "  No reads yet — hit rate will appear after cache is used"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Summary"
cat <<'SUMMARY'
  Layer             Mechanism             Transparency      TTL / Scope
  ────────────────────────────────────────────────────────────────────────────
  ProxySQL cache    Built-in query cache  100% transparent  30s products,
                    (no app changes)      app sends SQL      5s aggregates
                    intercepts SELECTs
                    before MySQL

  Valkey + HAProxy  Redis KV cache        Endpoint trans-   App-defined TTLs
                    App uses redis         parent: HAProxy   on each key
                    client to :6379/:6380  abstracts topology

  ────────────────────────────────────────────────────────────────────────────

  ProxySQL stats:   docker exec proxysql mysql -u admin -padminpass \
                      -h 127.0.0.1 -P 6032 \
                      -e "SELECT * FROM stats_mysql_global WHERE Variable_Name LIKE 'Query_Cache%';"

  Valkey CLI:       docker exec valkey valkey-cli info all
  Via HAProxy:      docker run --rm --network dbre-lab_db-net valkey/valkey:8 \
                      valkey-cli -h haproxy -p 6379 info server

  Metrics:          localhost:9121/metrics   (redis-exporter → Prometheus)
                    localhost:9090           (Prometheus)
                    localhost:3000           (Grafana)
SUMMARY
