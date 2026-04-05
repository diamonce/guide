#!/bin/bash
# Tests ProxySQL automatic read/write split.
# SELECTs → replicas, writes → primary.

set -euo pipefail

echo "=== ProxySQL query routing (port 6033) ==="
echo "--- Write (INSERT) → primary ---"

# Pass password securely to avoid CLI warnings, and REMOVE 2>/dev/null
MYSQL_PWD="apppass" mysql -h 127.0.0.1 -P 6033 -uapp shopdb \
    -e "INSERT INTO customers (name, email) VALUES ('ProxySQL Test', CONCAT('proxysql-', UNIX_TIMESTAMP(), '@test.com'));"

echo "✅ Insert done"

echo ""
echo "--- SELECT → replica (should show server_id 2 or 3) ---"
for i in 1 2 3 4; do
    MYSQL_PWD="apppass" mysql -h 127.0.0.1 -P 6033 -uapp shopdb \
        -e "SELECT @@server_id, COUNT(*) AS total_customers FROM customers;"
done

echo ""
echo "--- SELECT FOR UPDATE → primary (server_id 1) ---"
MYSQL_PWD="apppass" mysql -h 127.0.0.1 -P 6033 -uapp shopdb \
    -e "SELECT @@server_id, id FROM customers WHERE id=1 FOR UPDATE;"

echo ""
echo "=== ProxySQL stats (admin interface) ==="
MYSQL_PWD="adminpass" mysql -h 127.0.0.1 -P 6032 -uadmin \
    -e "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool;"

echo ""
echo "=== Query routing breakdown ==="
MYSQL_PWD="adminpass" mysql -h 127.0.0.1 -P 6032 -uadmin \
    -e "SELECT rule_id, hits, destination_hostgroup, match_pattern FROM stats_mysql_query_rules;"