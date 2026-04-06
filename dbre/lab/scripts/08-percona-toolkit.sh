#!/bin/bash
# Runs Percona Toolkit tools against the lab cluster.
# All tools run inside the 'toolkit' container which has pt-* installed.

set -euo pipefail

PT="docker exec toolkit"

echo "============================================"
echo " pt-summary — system summary"
echo "============================================"
$PT pt-mysql-summary --host=mysql-primary --user=root --password=rootpass 2>/dev/null | head -60 || true

echo ""
echo "============================================"
echo " pt-duplicate-key-checker"
echo "============================================"
$PT pt-duplicate-key-checker \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --databases=shopdb 2>/dev/null

echo ""
echo "============================================"
echo " pt-table-checksum — verify replicas match primary"
echo "============================================"
# Runs on primary, connects to replicas via replication
$PT pt-table-checksum \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --databases=shopdb \
    --replicate=shopdb.checksums \
    --create-replicate-table 2>/dev/null || true

echo ""
echo "============================================"
echo " pt-table-sync — fix replica drift"
echo "============================================"
echo "(dry run — shows what would be fixed)"
$PT pt-table-sync \
    --dry-run \
    --sync-to-master \
    --databases=shopdb \
    h=mysql-replica1,u=root,p=rootpass 2>/dev/null || true

echo ""
echo "============================================"
echo " pt-online-schema-change — add index online"
echo "============================================"
echo "Adding index on orders(customer_id, status) without blocking writes..."
$PT pt-online-schema-change \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --alter "ADD INDEX idx_customer_status (customer_id, status)" \
    --alter-foreign-keys-method=auto \
    --recursion-method=none \
    --execute \
    D=shopdb,t=orders 2>/dev/null && \
    echo "✅ Index added online" || echo "Index may already exist — skipping"

echo ""
echo "=== Verify index was added ==="
docker exec mysql-primary mysql -u root -prootpass shopdb 2>/dev/null \
    -e "SHOW INDEX FROM orders;"

echo ""
echo "============================================"
echo " pt-query-digest — analyze slow queries"
echo "============================================"

echo "Enabling slow query log and lowering threshold to catch all queries..."
docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "
    SET GLOBAL slow_query_log        = ON;
    SET GLOBAL long_query_time       = 0;
    SET GLOBAL log_queries_not_using_indexes = ON;"

SLOW_LOG=$(docker exec mysql-primary mysql -u root -prootpass -sN 2>/dev/null \
    -e "SELECT @@slow_query_log_file;")
echo "Slow log: $SLOW_LOG"

echo "Generating queries to analyze..."
docker exec mysql-primary mysql -u root -prootpass shopdb 2>/dev/null -e "
    SELECT c.name, COUNT(o.id) AS order_count, SUM(o.total) AS ltv
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id
    GROUP BY c.id ORDER BY ltv DESC;
    SELECT * FROM orders WHERE total > 100 ORDER BY created_at;
    SELECT * FROM order_items oi JOIN orders o ON o.id = oi.order_id;"

echo "Flushing slow log..."
docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "FLUSH SLOW LOGS;"

echo ""
echo "--- pt-query-digest report ---"
# Slow log lives inside mysql-primary — pipe it to pt-query-digest in toolkit
docker exec mysql-primary cat "$SLOW_LOG" 2>/dev/null \
    | docker exec -i toolkit pt-query-digest --type=slowlog - 2>/dev/null \
    || echo "⚠  slow log empty or not accessible — run more queries and retry"

echo "Resetting slow query threshold..."
docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "
    SET GLOBAL long_query_time = 1;
    SET GLOBAL log_queries_not_using_indexes = OFF;"

echo ""
echo "✅ Percona Toolkit demo complete."
