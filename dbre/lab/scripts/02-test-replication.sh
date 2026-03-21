#!/bin/bash
# Verifies replication is working: write to primary, read from each replica.

set -euo pipefail

echo "=== Writing to PRIMARY ==="
docker exec mysql-primary mysql -prootpass shopdb <<'EOF'
INSERT INTO customers (name, email)
VALUES ('Test Replication', CONCAT('testrep-', UNIX_TIMESTAMP(), '@example.com'));

SELECT 'Written to primary:' AS msg, id, name, email
FROM customers ORDER BY id DESC LIMIT 1;
EOF

echo ""
echo "=== Waiting 2s for replication lag ==="
sleep 2

for REPLICA in mysql-replica1 mysql-replica2; do
    echo ""
    echo "=== Reading from $REPLICA ==="
    docker exec "$REPLICA" mysql -prootpass shopdb -e \
        "SELECT 'Read from replica:' AS msg, id, name, email FROM customers ORDER BY id DESC LIMIT 1;"
done

echo ""
echo "=== Replication lag (Seconds_Behind_Source) ==="
for REPLICA in mysql-replica1 mysql-replica2; do
    echo -n "$REPLICA: "
    docker exec "$REPLICA" mysql -prootpass -e "SHOW REPLICA STATUS\G" 2>/dev/null \
        | grep "Seconds_Behind_Source" || echo "check SHOW REPLICA STATUS"
done

echo ""
echo "=== GTID sets ==="
echo -n "Primary executed: "
docker exec mysql-primary mysql -prootpass -e \
    "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tail -1

for REPLICA in mysql-replica1 mysql-replica2; do
    echo -n "$REPLICA executed: "
    docker exec "$REPLICA" mysql -prootpass -e \
        "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tail -1
done
