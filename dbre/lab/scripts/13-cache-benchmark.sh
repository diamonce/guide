#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Cache performance benchmark — timed, multi-worker, saved report
#
# Four access paths for the same data:
#   A  Direct MySQL replica    full SQL round-trip, no cache
#   B  ProxySQL cold           cache flushed before run, every query hits MySQL
#   C  ProxySQL warm           cache populated, ProxySQL serves from RAM
#   D  Valkey HGET             pure in-memory KV, no SQL
#
# Usage:
#   ./13-cache-benchmark.sh                      # defaults: 180s/path, 4 workers
#   DURATION=60 WORKERS=8 ./13-cache-benchmark.sh
#
# Total runtime ≈ 4 × DURATION + ~60s setup (default ≈ 15 min)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DURATION=${DURATION:-180}    # seconds per path
WORKERS=${WORKERS:-4}        # concurrent workers per path
REPORT_DIR="/tmp/bench_$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="${REPORT_DIR}/report.txt"

mkdir -p "$REPORT_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

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
            -e "SELECT id, sku, name, price FROM products ORDER BY id;" \
            2>/dev/null > /dev/null
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

worker_proxysql() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        MYSQL_PWD=apppass mysql -h 127.0.0.1 -P 6033 -u app shopdb -sN \
            -e "SELECT id, sku, name, price FROM products ORDER BY id;" \
            2>/dev/null > /dev/null
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

worker_valkey() {
    local id=$1 outfile=$2 end=$3
    while [ "$(date +%s)" -lt "$end" ]; do
        local t0 t1
        t0=$(date +%s%N)
        redis-cli -h 127.0.0.1 -p 6379 HGET "product:1" name > /dev/null 2>&1
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$outfile"
    done
}

export -f worker_mysql_direct worker_proxysql worker_valkey
export REPORT_DIR

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

for svc in mysql-primary mysql-replica1 proxysql valkey; do
    printf "  %-20s " "$svc..."
    case "$svc" in
        mysql-*) docker exec "$svc" mysqladmin ping -u root -prootpass -s 2>/dev/null \
                     && echo "ok" || { echo "FAIL — start the cluster first"; exit 1; } ;;
        proxysql) MYSQL_PWD=radminpass mysql -h 127.0.0.1 -P 6032 -uradmin \
                     -e "SELECT 1" --silent 2>/dev/null | grep -q 1 && echo "ok" || { echo "FAIL"; exit 1; } ;;
        valkey) docker exec valkey valkey-cli ping 2>/dev/null | grep -q PONG && echo "ok" || { echo "FAIL"; exit 1; } ;;
    esac
done

echo ""
echo "  Duration : ${DURATION}s per path  (4 paths = ~$(( DURATION * 4 / 60 ))min + setup)"
echo "  Workers  : ${WORKERS} concurrent per path"
echo "  Report   : ${REPORT_FILE}"
echo "  Query    : SELECT id, sku, name, price FROM products ORDER BY id"

# ── Seed Valkey ───────────────────────────────────────────────────────────────
header "Setup: seed Valkey + warm ProxySQL cache"

echo "  Loading product catalog into Valkey..."
docker exec mysql-primary mysql -u root -prootpass shopdb \
    -sN -e "SELECT id, sku, name, price, stock FROM products;" 2>/dev/null \
| while IFS=$'\t' read -r id sku name price stock; do
    docker exec valkey valkey-cli HSET "product:${id}" \
        sku "$sku" name "$name" price "$price" stock "$stock" > /dev/null 2>&1
    docker exec valkey valkey-cli PERSIST "product:${id}" > /dev/null 2>&1   # no TTL during benchmark
done
echo "  Valkey keys: $(docker exec valkey valkey-cli DBSIZE 2>/dev/null)"

# Reset ProxySQL stats baseline
MYSQL_PWD=radminpass mysql -h 127.0.0.1 -P 6032 -uradmin \
    -e "SELECT * FROM stats_mysql_query_digest_reset;" 2>/dev/null > /dev/null || true

# ── Path A: Direct MySQL (no cache) ───────────────────────────────────────────
header "Path A — Direct MySQL replica (no cache, ${DURATION}s)"
run_path "Direct MySQL" worker_mysql_direct "${REPORT_DIR}/A"
A_QPS=$(qps "${REPORT_DIR}/A_all.txt" "$DURATION")
A_STATS=$(stats "${REPORT_DIR}/A_all.txt")

# ── Path B: ProxySQL cold ──────────────────────────────────────────────────────
header "Path B — ProxySQL COLD (cache flushed, every query hits MySQL, ${DURATION}s)"
MYSQL_PWD=radminpass mysql -h 127.0.0.1 -P 6032 -uradmin \
    -e "PROXYSQL FLUSH QUERY CACHE;" 2>/dev/null || true
run_path "ProxySQL cold" worker_proxysql "${REPORT_DIR}/B"
B_QPS=$(qps "${REPORT_DIR}/B_all.txt" "$DURATION")
B_STATS=$(stats "${REPORT_DIR}/B_all.txt")

# ── Path C: ProxySQL warm ─────────────────────────────────────────────────────
header "Path C — ProxySQL WARM (cache populated, served from RAM, ${DURATION}s)"
# Pre-warm: send 3 queries to populate cache before workers start
for _ in 1 2 3; do
    MYSQL_PWD=apppass mysql -h 127.0.0.1 -P 6033 -u app shopdb -sN \
        -e "SELECT id, sku, name, price FROM products ORDER BY id;" \
        2>/dev/null > /dev/null
done
run_path "ProxySQL warm" worker_proxysql "${REPORT_DIR}/C"
C_QPS=$(qps "${REPORT_DIR}/C_all.txt" "$DURATION")
C_STATS=$(stats "${REPORT_DIR}/C_all.txt")

# ── Path D: Valkey HGET ───────────────────────────────────────────────────────
header "Path D — Valkey HGET (pure in-memory KV, ${DURATION}s)"
run_path "Valkey HGET" worker_valkey "${REPORT_DIR}/D"
D_QPS=$(qps "${REPORT_DIR}/D_all.txt" "$DURATION")
D_STATS=$(stats "${REPORT_DIR}/D_all.txt")

# ── Stats gathering — disable set -e; non-fatal if any query fails ────────────
set +e

# ProxySQL cache stats via host mysql client (port 6032 exposed on host)
# Use awk -F'\t' to handle tab-separated mysql output; no grep pipelines that
# can return exit code 1 (empty match) and trip set -e.
CACHE_RAW=$(MYSQL_PWD=radminpass mysql -h 127.0.0.1 -P 6032 -uradmin -sN \
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

# Speedup ratios — extract avg from stats() output
# stats() outputs: "count=N   avg=X.X  p50=..."  — awk is safer than grep -o
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
  Query   : SELECT id,sku,name,price FROM products ORDER BY id
════════════════════════════════════════════════════════════════════════

  NOTE: Each worker opens a new TCP connection per query (no connection pooling).
  Absolute latency is higher than a persistent-connection app client.
  Relative ratios between paths are accurate and show real cache benefit.

────────────────────────────────────────────────────────────────────────
  Path                         QPS      avg ms   p50    p95    p99
────────────────────────────────────────────────────────────────────────
HEADER
printf "  %-28s  %-8s  %s\n" "A: Direct MySQL replica"  "$A_QPS"  "$A_STATS"
printf "  %-28s  %-8s  %s\n" "B: ProxySQL cold (miss)"  "$B_QPS"  "$B_STATS"
printf "  %-28s  %-8s  %s\n" "C: ProxySQL warm (hit)"   "$C_QPS"  "$C_STATS"
printf "  %-28s  %-8s  %s\n" "D: Valkey HGET"           "$D_QPS"  "$D_STATS"
cat <<FOOTER

────────────────────────────────────────────────────────────────────────
  Speedup vs Direct MySQL (avg latency)
    ProxySQL warm : ${C_SPEEDUP}x faster  (${C_QPS_GAIN}x QPS)
    Valkey HGET   : ${D_SPEEDUP}x faster  (${D_QPS_GAIN}x QPS)

  Cache hit rates
    ProxySQL query cache : ${CACHE_HIT_PCT}  (${CACHE_HIT:-0} hits / ${CACHE_GET:-0} lookups)
    Valkey keyspace      : ${VALKEY_HIT_PCT}  (${V_HITS:-0} hits / ${V_TOTAL} lookups)

  Interpretation
    A vs B  — ProxySQL routing overhead vs direct connection
    B vs C  — pure cache effect (same ProxySQL path, cache on vs off)
    A vs D  — Valkey KV vs full SQL round-trip
════════════════════════════════════════════════════════════════════════
FOOTER
} | tee "$REPORT_FILE"

echo ""
echo "  Full report saved: ${REPORT_FILE}"
echo "  Raw latency data : ${REPORT_DIR}/"
echo ""
echo "  Watch live in Grafana → localhost:3000 → Valkey Cache / ProxySQL dashboards"
echo "  Re-run with more load:"
echo "    DURATION=300 WORKERS=8 ./scripts/13-cache-benchmark.sh"
