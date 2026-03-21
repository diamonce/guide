#!/bin/bash
# Runs Percona Toolkit tools against the lab cluster.
# All tools run inside the 'toolkit' container which has pt-* installed.

set -euo pipefail

PT="docker exec toolkit"

echo "============================================"
echo " pt-summary — system summary"
echo "============================================"
$PT pt-mysql-summary --host=mysql-primary --user=root --password=rootpass 2>/dev/null | head -60

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
    --host=mysql-replica1 \
    --user=root \
    --password=rootpass \
    --databases=shopdb 2>/dev/null || true

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
    --execute \
    D=shopdb,t=orders 2>/dev/null && \
    echo "✅ Index added online" || echo "Index may already exist"

echo ""
echo "=== Verify index was added ==="
docker exec mysql-primary mysql -prootpass shopdb \
    -e "SHOW INDEX FROM orders;"

echo ""
echo "============================================"
echo " pt-query-digest — analyze slow queries"
echo "============================================"
echo "First, generate some slow queries..."
docker exec mysql-primary mysql -prootpass shopdb 2>/dev/null <<'EOF'
    -- This will hit slow log (joins without optimal index)
    SELECT c.name, COUNT(o.id) AS order_count, SUM(o.total) AS ltv
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.id
    LEFT JOIN order_items oi ON oi.order_id = o.id
    GROUP BY c.id
    ORDER BY ltv DESC;
EOF

echo "Flushing slow log..."
docker exec mysql-primary mysql -prootpass \
    -e "FLUSH SLOW LOGS;" 2>/dev/null

echo ""
echo "pt-query-digest output (from general log simulation):"
docker exec mysql-primary mysql -prootpass -e "SHOW VARIABLES LIKE 'slow_query_log_file';" 2>/dev/null

echo ""
echo "✅ Percona Toolkit demo complete."
