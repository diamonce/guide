#!/bin/bash
# Sets up GTID-based replication on both replicas.
# Run this ONCE after docker compose up.

set -euo pipefail

PRIMARY="mysql-primary"
REPLICAS=("mysql-replica1" "mysql-replica2")
ROOT_PASS="rootpass"

# 1. Wait function now includes a timeout
wait_for_mysql() {
    local host=$1
    local max_retries=30
    local count=0
    
    echo "⏳ Waiting for $host..."
    
    # Passing password via MYSQL_PWD hides the insecure CLI warnings
    until docker exec -e MYSQL_PWD="$ROOT_PASS" "$host" mysqladmin ping -u root -s 2>/dev/null; do
        count=$((count + 1))
        if [ $count -ge $max_retries ]; then
            echo "❌ Error: Timed out waiting for $host after 60 seconds." >&2
            exit 1
        fi
        sleep 2
    done
    echo "✅ $host is up"
}

wait_for_mysql "$PRIMARY"
for r in "${REPLICAS[@]}"; do wait_for_mysql "$r"; done

echo ""
echo "=== Primary status ==="
docker exec -e MYSQL_PWD="$ROOT_PASS" "$PRIMARY" mysql -u root -e "SHOW MASTER STATUS\G"

for REPLICA in "${REPLICAS[@]}"; do
    echo ""
    echo "=== Configuring $REPLICA ==="

    # 2. Added '-i' flag so docker exec actually reads the EOF block
    docker exec -i -e MYSQL_PWD="$ROOT_PASS" "$REPLICA" mysql -u root <<-EOF
        STOP REPLICA;

        CHANGE REPLICATION SOURCE TO
            SOURCE_HOST='mysql-primary',
            SOURCE_PORT=3306,
            SOURCE_USER='replicator',
            SOURCE_PASSWORD='replpass',
            SOURCE_AUTO_POSITION=1;   -- GTID: no need to specify binlog file/pos

        START REPLICA;
EOF

    # 3. Added a brief pause to let IO/SQL threads connect before checking status
    echo "⏳ Waiting for replication threads to start..."
    sleep 2

    echo "--- Replica status for $REPLICA ---"
    
    # 4. Added '|| true' so grep doesn't silently kill the script if it finds nothing
    docker exec -e MYSQL_PWD="$ROOT_PASS" "$REPLICA" mysql -u root -e "SHOW REPLICA STATUS\G" \
        | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind|Last_Error|Executed_Gtid_Set" || true
done

wait_for_mysql "$PRIMARY"
for r in "${REPLICAS[@]}"; do wait_for_mysql "$r"; done

# ---------------------------------------------------------
# Create HAProxy health check user on the Primary
# ---------------------------------------------------------
echo ""
echo "=== Configuring HAProxy Check User ==="
docker exec -e MYSQL_PWD="$ROOT_PASS" "$PRIMARY" mysql -u root -e "
    CREATE USER IF NOT EXISTS 'haproxy_check'@'%';
    ALTER USER 'haproxy_check'@'%' IDENTIFIED WITH mysql_native_password BY '' PASSWORD EXPIRE NEVER;
    FLUSH PRIVILEGES;
"

for REPLICA in "${REPLICAS[@]}"; do
    echo ""
    echo "=== Configuring $REPLICA ==="

docker exec -e MYSQL_PWD="$ROOT_PASS" "$REPLICA" mysql -u root -e "
    CREATE USER IF NOT EXISTS 'haproxy_check'@'%';
    ALTER USER 'haproxy_check'@'%' IDENTIFIED WITH mysql_native_password BY '' PASSWORD EXPIRE NEVER;
    FLUSH PRIVILEGES;
"

done

echo "✅ haproxy_check user created with legacy auth and no expiration."