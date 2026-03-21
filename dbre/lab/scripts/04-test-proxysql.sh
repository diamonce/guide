#!/bin/bash
# Tests ProxySQL automatic read/write split.
# SELECTs → replicas, writes → primary.

set -euo pipefail

echo "=== ProxySQL query routing (port 6033) ==="
echo "--- Write (INSERT) → primary ---"
mysql -h 127.0.0.1 -P 6033 -uapp -papppass shopdb \
    -e "INSERT INTO customers (name, email) VALUES ('ProxySQL Test', CONCAT('proxysql-', UNIX_TIMESTAMP(), '@test.com'));" 2>/dev/null
echo "Insert done"

echo ""
echo "--- SELECT → replica (should show server_id 2 or 3) ---"
for i in 1 2 3 4; do
    mysql -h 127.0.0.1 -P 6033 -uapp -papppass shopdb \
        -e "SELECT @@server_id, COUNT(*) AS total_customers FROM customers;" 2>/dev/null
done

echo ""
echo "--- SELECT FOR UPDATE → primary (server_id 1) ---"
mysql -h 127.0.0.1 -P 6033 -uapp -papppass shopdb \
    -e "SELECT @@server_id, id FROM customers WHERE id=1 FOR UPDATE;" 2>/dev/null

echo ""
echo "=== ProxySQL stats (admin interface) ==="
mysql -h 127.0.0.1 -P 6032 -uadmin -padminpass \
    -e "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool;" 2>/dev/null

echo ""
echo "=== Query routing breakdown ==="
mysql -h 127.0.0.1 -P 6032 -uadmin -padminpass \
    -e "SELECT rule_id, hits, destination_hostgroup, match_pattern FROM stats_mysql_query_rules;" 2>/dev/null
