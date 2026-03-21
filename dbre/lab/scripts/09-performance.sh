#!/bin/bash
# Performance exercises:
#   - EXPLAIN / EXPLAIN ANALYZE
#   - Index usage
#   - Slow queries
#   - InnoDB buffer pool stats

set -euo pipefail

run() {
    echo "--- $1 ---"
    docker exec mysql-primary mysql -prootpass shopdb -e "$2" 2>/dev/null
    echo ""
}

echo "============================================"
echo " EXPLAIN — understand query plans"
echo "============================================"

run "Full table scan (no useful index)" \
    "EXPLAIN SELECT * FROM orders WHERE total > 500\G"

run "Index scan on customer_id" \
    "EXPLAIN SELECT * FROM orders WHERE customer_id = 1\G"

run "Covering index (index only scan)" \
    "EXPLAIN SELECT customer_id, status FROM orders WHERE customer_id = 1\G"

run "JOIN execution plan" \
    "EXPLAIN SELECT c.name, COUNT(o.id), SUM(o.total)
     FROM customers c
     LEFT JOIN orders o ON o.customer_id = c.id
     GROUP BY c.id\G"

echo "============================================"
echo " Slow query — function on indexed column"
echo "============================================"
run "BAD: YEAR() on created_at prevents index use" \
    "EXPLAIN SELECT * FROM orders WHERE YEAR(created_at) = 2024\G"

run "GOOD: range query uses index" \
    "EXPLAIN SELECT * FROM orders
     WHERE created_at BETWEEN '2024-01-01' AND '2024-12-31'\G"

echo "============================================"
echo " Creating and testing indexes"
echo "============================================"

echo "Adding composite index on (status, created_at)..."
docker exec mysql-primary mysql -prootpass shopdb 2>/dev/null \
    -e "CREATE INDEX IF NOT EXISTS idx_status_created ON orders(status, created_at);" || true

run "Query using new composite index" \
    "EXPLAIN SELECT * FROM orders
     WHERE status = 'paid' AND created_at > '2024-01-01'\G"

echo "============================================"
echo " InnoDB buffer pool stats"
echo "============================================"
docker exec mysql-primary mysql -prootpass 2>/dev/null <<'EOF'
    SELECT
        CONCAT(FORMAT(@@innodb_buffer_pool_size / 1024 / 1024, 0), ' MB') AS buffer_pool_size,
        FORMAT(Innodb_buffer_pool_pages_total * 16 / 1024, 0) AS total_pages_mb,
        FORMAT(Innodb_buffer_pool_pages_free * 16 / 1024, 0) AS free_pages_mb,
        FORMAT((1 - Innodb_buffer_pool_pages_free/Innodb_buffer_pool_pages_total) * 100, 1) AS pct_used
    FROM (
        SELECT
            variable_value AS Innodb_buffer_pool_pages_total
        FROM performance_schema.global_status
        WHERE variable_name = 'Innodb_buffer_pool_pages_total'
    ) t1
    CROSS JOIN (
        SELECT variable_value AS Innodb_buffer_pool_pages_free
        FROM performance_schema.global_status
        WHERE variable_name = 'Innodb_buffer_pool_pages_free'
    ) t2\G
EOF

echo ""
echo "============================================"
echo " pg_stat_statements equivalent — performance_schema"
echo "============================================"
docker exec mysql-primary mysql -prootpass 2>/dev/null <<'EOF'
    SELECT
        ROUND(SUM_TIMER_WAIT/1e12, 3)  AS total_seconds,
        COUNT_STAR                      AS executions,
        ROUND(AVG_TIMER_WAIT/1e9, 3)   AS avg_ms,
        LEFT(DIGEST_TEXT, 80)          AS query_pattern
    FROM performance_schema.events_statements_summary_by_digest
    WHERE DIGEST_TEXT IS NOT NULL
    ORDER BY SUM_TIMER_WAIT DESC
    LIMIT 10;
EOF
