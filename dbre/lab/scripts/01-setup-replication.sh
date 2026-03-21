#!/bin/bash
# Sets up GTID-based replication on both replicas.
# Run this ONCE after docker compose up.

set -euo pipefail

PRIMARY="mysql-primary"
REPLICAS=("mysql-replica1" "mysql-replica2")
ROOT_PASS="rootpass"

wait_for_mysql() {
    local host=$1
    echo "⏳ waiting for $host..."
    until docker exec "$host" mysqladmin ping -prootpass -s 2>/dev/null; do
        sleep 2
    done
    echo "✅ $host is up"
}

wait_for_mysql "$PRIMARY"
for r in "${REPLICAS[@]}"; do wait_for_mysql "$r"; done

echo ""
echo "=== Primary status ==="
docker exec "$PRIMARY" mysql -prootpass -e "SHOW MASTER STATUS\G"

for REPLICA in "${REPLICAS[@]}"; do
    echo ""
    echo "=== Configuring $REPLICA ==="

    docker exec "$REPLICA" mysql -prootpass <<-EOF
        STOP REPLICA;

        CHANGE REPLICATION SOURCE TO
            SOURCE_HOST='mysql-primary',
            SOURCE_PORT=3306,
            SOURCE_USER='replicator',
            SOURCE_PASSWORD='replpass',
            SOURCE_AUTO_POSITION=1;   -- GTID: no need to specify binlog file/pos

        START REPLICA;
EOF

    echo "--- Replica status for $REPLICA ---"
    docker exec "$REPLICA" mysql -prootpass -e "SHOW REPLICA STATUS\G" \
        | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind|Last_Error|Executed_Gtid_Set"
done

echo ""
echo "✅ Replication setup complete."
echo "   Watch lag: docker exec mysql-replica1 mysql -prootpass -e \"SHOW REPLICA STATUS\G\" | grep Seconds_Behind"
