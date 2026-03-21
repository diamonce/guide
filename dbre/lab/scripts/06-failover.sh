#!/bin/bash
# Simulates primary failure and manual failover to replica1.
# Shows what breaks, what HAProxy does, and how to promote.

set -euo pipefail

echo "============================================"
echo " BEFORE FAILOVER — verify everything works"
echo "============================================"
echo "Primary server_id:"
docker exec mysql-primary mysql -prootpass -sN -e "SELECT @@server_id;"

echo "Replica lag:"
docker exec mysql-replica1 mysql -prootpass -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep Seconds_Behind

echo ""
echo "============================================"
echo " STEP 1: Simulate primary failure"
echo "============================================"
echo "Pausing mysql-primary container (simulates crash)..."
docker pause mysql-primary

sleep 3

echo ""
echo "=== HAProxy write port (3306) — should fail now ==="
mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb \
    -e "SELECT 'write works'" 2>&1 || echo "❌ Write port unavailable (expected)"

echo ""
echo "=== HAProxy read port (3307) — replicas still answer ==="
mysql -h 127.0.0.1 -P 3307 -uapp -papppass shopdb \
    -e "SELECT @@server_id, COUNT(*) FROM customers;" 2>/dev/null && \
    echo "✅ Reads still work via replicas" || echo "❌ Reads also failing"

echo ""
echo "============================================"
echo " STEP 2: Promote replica1 to primary"
echo "============================================"
echo "Stopping replication on replica1..."
docker exec mysql-replica1 mysql -prootpass <<'EOF'
    STOP REPLICA;
    RESET REPLICA ALL;         -- remove connection to old primary
    SET GLOBAL read_only = OFF;
    SET GLOBAL super_read_only = OFF;
EOF

echo "✅ replica1 is now writable (promoted)"
echo "New primary server_id:"
docker exec mysql-replica1 mysql -prootpass -sN -e "SELECT @@server_id;"

echo ""
echo "============================================"
echo " STEP 3: Point replica2 at new primary"
echo "============================================"
docker exec mysql-replica2 mysql -prootpass <<'EOF'
    STOP REPLICA;
    CHANGE REPLICATION SOURCE TO
        SOURCE_HOST='mysql-replica1',
        SOURCE_PORT=3306,
        SOURCE_USER='replicator',
        SOURCE_PASSWORD='replpass',
        SOURCE_AUTO_POSITION=1;
    START REPLICA;
EOF

echo "replica2 replication status:"
docker exec mysql-replica2 mysql -prootpass -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null \
    | grep -E "Replica_IO_Running|Replica_SQL_Running|Source_Host"

echo ""
echo "============================================"
echo " STEP 4: Recover — bring old primary back"
echo "============================================"
echo "Unpausing mysql-primary..."
docker unpause mysql-primary
sleep 5

echo "Old primary is back — set it as replica of new primary"
docker exec mysql-primary mysql -prootpass <<'EOF'
    STOP REPLICA;
    SET GLOBAL read_only = ON;
    SET GLOBAL super_read_only = ON;
    CHANGE REPLICATION SOURCE TO
        SOURCE_HOST='mysql-replica1',
        SOURCE_PORT=3306,
        SOURCE_USER='replicator',
        SOURCE_PASSWORD='replpass',
        SOURCE_AUTO_POSITION=1;
    START REPLICA;
EOF

echo ""
echo "=== Final topology ==="
echo "New primary: mysql-replica1 (server_id=2)"
echo "Replica of new primary: mysql-primary (server_id=1), mysql-replica2 (server_id=3)"
echo ""
echo "--- Replication status on old primary (now replica) ---"
docker exec mysql-primary mysql -prootpass -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null \
    | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind"

echo ""
echo "💡 In production: update app connection string or HAProxy config"
echo "   to point writes at mysql-replica1 now."
