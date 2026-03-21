#!/bin/bash
# Demonstrates parallel writes to primary and what happens on replicas.
# Also shows lock contention and how to observe it.

set -euo pipefail

echo "============================================"
echo " Parallel writes — 5 concurrent connections"
echo "============================================"

write_worker() {
    local id=$1
    local n=20
    for i in $(seq 1 $n); do
        mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb 2>/dev/null <<EOF
            INSERT INTO orders (customer_id, total, status)
            VALUES (
                FLOOR(1 + RAND() * 5),
                ROUND(10 + RAND() * 990, 2),
                ELT(FLOOR(1 + RAND() * 3), 'pending', 'paid', 'shipped')
            );
EOF
    done
    echo "Worker $id done — inserted $n rows"
}

export -f write_worker

# Run 5 workers in parallel
echo "Spawning 5 parallel write workers (20 rows each = 100 total)..."
for i in 1 2 3 4 5; do
    write_worker $i &
done
wait

echo ""
echo "=== Row count after parallel writes ==="
docker exec mysql-primary mysql -prootpass shopdb \
    -e "SELECT COUNT(*) AS total_orders FROM orders;"

echo ""
echo "=== Replication caught up? ==="
sleep 2
for REPLICA in mysql-replica1 mysql-replica2; do
    echo -n "$REPLICA orders count: "
    docker exec "$REPLICA" mysql -prootpass shopdb -sN \
        -e "SELECT COUNT(*) FROM orders;" 2>/dev/null
done

echo ""
echo "============================================"
echo " Lock contention demo"
echo "============================================"
echo "Starting long transaction on primary (holds row lock for 10s)..."

docker exec mysql-primary mysql -prootpass shopdb 2>/dev/null &
LONG_TX_PID=$!

mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb 2>/dev/null <<'EOF' &
    SET SESSION innodb_lock_wait_timeout = 30;
    START TRANSACTION;
    SELECT id, stock FROM products WHERE id = 1 FOR UPDATE;
    DO SLEEP(10);
    UPDATE products SET stock = stock - 1 WHERE id = 1;
    COMMIT;
EOF
LONG_PID=$!

sleep 2

echo ""
echo "=== Active locks (while long transaction runs) ==="
docker exec mysql-primary mysql -prootpass 2>/dev/null <<'EOF'
    SELECT
        r.trx_id AS waiting_trx,
        r.trx_mysql_thread_id AS waiting_thread,
        b.trx_id AS blocking_trx,
        b.trx_mysql_thread_id AS blocking_thread,
        b.trx_query AS blocking_query
    FROM information_schema.innodb_lock_waits w
    JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
    JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id;
EOF

echo ""
echo "=== Trying to update the same row (will wait for lock) ==="
timeout 5 mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb 2>/dev/null \
    -e "UPDATE products SET stock = stock + 100 WHERE id = 1;" \
    && echo "✅ Updated (lock released)" \
    || echo "⏳ Lock wait timeout (expected if long tx still running)"

wait $LONG_PID 2>/dev/null || true

echo ""
echo "============================================"
echo " Deadlock demo"
echo "============================================"
echo "Two transactions updating rows in opposite order → deadlock"

# TX1: lock row 1 then row 2
mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb 2>/dev/null <<'EOF' &
    START TRANSACTION;
    UPDATE products SET stock = stock - 1 WHERE id = 1;
    DO SLEEP(2);
    UPDATE products SET stock = stock - 1 WHERE id = 2;
    COMMIT;
EOF

# TX2: lock row 2 then row 1 (opposite order → deadlock)
mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb 2>/dev/null <<'EOF' &
    START TRANSACTION;
    UPDATE products SET stock = stock - 1 WHERE id = 2;
    DO SLEEP(2);
    UPDATE products SET stock = stock - 1 WHERE id = 1;
    COMMIT;
EOF

wait

echo "=== InnoDB deadlock info ==="
docker exec mysql-primary mysql -prootpass -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null \
    | awk '/LATEST DETECTED DEADLOCK/,/WE ROLL BACK/'

echo ""
echo "✅ Parallel writes and locking demo complete."
