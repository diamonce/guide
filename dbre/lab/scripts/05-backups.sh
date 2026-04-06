#!/bin/bash
# Covers all backup methods:
#   A. mysqldump full logical backup
#   B. mysqldump single database
#   C. mysqldump single table
#   D. Restore from dump into a new database
#   E. Binary log inspection + PITR demo

set -euo pipefail

TS=$(date +%Y%m%d_%H%M%S)

# Helper: run SQL on primary, suppress password warning
mysql_primary() {
    docker exec mysql-primary mysql -u root -prootpass "$@" 2>/dev/null
}

echo "============================================"
echo " A. Full logical backup with mysqldump"
echo "============================================"
# --single-transaction : consistent InnoDB snapshot, no table locks
# --set-gtid-purged=ON : embeds GTID info for replication-safe restore
# --source-data=2      : adds binlog position as a SQL comment (non-blocking)
docker exec mysql-primary mysqldump \
    -u root -prootpass \
    --all-databases \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=ON \
    --source-data=2 \
    2>/dev/null \
    > "/tmp/full_backup_${TS}.sql"

echo "✅ Full backup: /tmp/full_backup_${TS}.sql ($(du -sh "/tmp/full_backup_${TS}.sql" | cut -f1))"

echo ""
echo "============================================"
echo " B. Single database backup"
echo "============================================"
docker exec mysql-primary mysqldump \
    -u root -prootpass \
    --single-transaction \
    --set-gtid-purged=OFF \
    shopdb \
    2>/dev/null \
    > "/tmp/shopdb_${TS}.sql"

echo "✅ shopdb backup: /tmp/shopdb_${TS}.sql ($(du -sh "/tmp/shopdb_${TS}.sql" | cut -f1))"

echo ""
echo "============================================"
echo " C. Single table backup"
echo "============================================"
docker exec mysql-primary mysqldump \
    -u root -prootpass \
    --single-transaction \
    --set-gtid-purged=OFF \
    shopdb orders \
    2>/dev/null \
    > "/tmp/orders_${TS}.sql"

echo "✅ orders table backup: /tmp/orders_${TS}.sql ($(du -sh "/tmp/orders_${TS}.sql" | cut -f1))"

echo ""
echo "============================================"
echo " D. Restore to a new database"
echo "============================================"
echo "Creating shopdb_restored..."
mysql_primary -e "DROP DATABASE IF EXISTS shopdb_restored; CREATE DATABASE shopdb_restored;"

echo "Copying dump into container..."
docker cp "/tmp/shopdb_${TS}.sql" mysql-primary:/tmp/shopdb_restore.sql

echo "Restoring..."
docker exec mysql-primary bash -c \
    "mysql -u root -prootpass shopdb_restored < /tmp/shopdb_restore.sql"

echo "Verifying restore:"
mysql_primary shopdb_restored -e "SHOW TABLES; SELECT COUNT(*) AS rows_restored FROM orders;"

echo "✅ Restore complete"

echo ""
echo "============================================"
echo " E. PITR — point-in-time recovery walkthrough"
echo "============================================"

echo "--- Reset: restoring shopdb to known seed state ---"
mysql_primary shopdb -e "
    SET foreign_key_checks=0;
    TRUNCATE TABLE order_items;
    TRUNCATE TABLE orders;
    TRUNCATE TABLE products;
    TRUNCATE TABLE customers;
    SET foreign_key_checks=1;

    INSERT INTO customers (name, email) VALUES
        ('Alice Smith',  'alice@example.com'),
        ('Bob Jones',    'bob@example.com'),
        ('Carol White',  'carol@example.com'),
        ('Dave Brown',   'dave@example.com'),
        ('Eve Davis',    'eve@example.com');

    INSERT INTO products (sku, name, price, stock) VALUES
        ('SKU-001', 'Laptop Pro 15',       1299.99, 50),
        ('SKU-002', 'Wireless Mouse',        29.99, 200),
        ('SKU-003', 'USB-C Hub',             49.99, 150),
        ('SKU-004', 'Mechanical Keyboard',   89.99,  75),
        ('SKU-005', 'Monitor 27\"',         399.99,  30);

    INSERT INTO orders (customer_id, total, status) VALUES
        (1, 1329.98, 'paid'),
        (2,   49.99, 'shipped'),
        (3,  489.98, 'pending'),
        (1,   89.99, 'paid'),
        (4, 1299.99, 'cancelled');

    INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
        (1, 1, 1, 1299.99),
        (1, 2, 1,   29.99),
        (2, 3, 1,   49.99),
        (3, 4, 1,   89.99),
        (3, 5, 1,  399.99),
        (4, 4, 1,   89.99),
        (5, 1, 1, 1299.99);"
echo "✅ shopdb reset to seed state"

echo ""
echo "--- Step 1: Check current binlog position and GTID state ---"
mysql_primary -e "SHOW MASTER STATUS\G"
mysql_primary -e "
    SELECT @@GLOBAL.gtid_mode       AS gtid_mode,
           @@GLOBAL.gtid_executed   AS gtid_executed,
           @@GLOBAL.binlog_format   AS binlog_format;"

echo ""
echo "--- Step 2: List all binary log files ---"
mysql_primary -e "SHOW BINARY LOGS;"

echo ""
echo "--- Step 3: Flush to a clean binlog file (seals current transactions) ---"
mysql_primary -e "FLUSH BINARY LOGS;"
mysql_primary -e "SHOW MASTER STATUS\G"

echo ""
echo "--- Step 4: Take a backup snapshot (this is our restore point) ---"
PITR_TS=$(date +%Y%m%d_%H%M%S)
docker exec mysql-primary mysqldump \
    -u root -prootpass \
    --single-transaction \
    --set-gtid-purged=OFF \
    shopdb \
    2>/dev/null \
    > "/tmp/pitr_snapshot_${PITR_TS}.sql"

BINLOG_FILE=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SHOW MASTER STATUS;" 2>/dev/null | awk '{print $1}') || true
BINLOG_POS=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SHOW MASTER STATUS;" 2>/dev/null | awk '{print $2}') || true
GTID_SNAPSHOT=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tr -d ' \n') || true

echo "✅ Snapshot taken — binlog: $BINLOG_FILE pos: $BINLOG_POS"
echo "   GTID set at snapshot: $GTID_SNAPSHOT"

echo ""
echo "--- Step 5: Simulate work after the backup ---"
mysql_primary shopdb -e "
    INSERT INTO orders (customer_id, total, status)
    VALUES (1, 99.99, 'pending'), (2, 149.00, 'paid');"

echo "Orders after new inserts:"
mysql_primary shopdb -e "SELECT COUNT(*) AS total, status FROM orders GROUP BY status;"

echo ""
echo "--- Step 6: Accidental DELETE (the 'oops') ---"
GTID_BEFORE_DELETE=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tr -d ' \n') || true

mysql_primary shopdb -e "
    SET foreign_key_checks=0;
    DELETE FROM orders WHERE status='cancelled';
    SET foreign_key_checks=1;"

GTID_AFTER_DELETE=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tr -d ' \n') || true

echo "Orders after accidental delete:"
mysql_primary shopdb -e "SELECT COUNT(*) AS total, status FROM orders GROUP BY status;"

echo ""
echo "GTID before delete : $GTID_BEFORE_DELETE"
echo "GTID after delete  : $GTID_AFTER_DELETE"

echo ""
echo "--- Step 7: Inspect binlog — find the DELETE event ---"
CURRENT_BINLOG=$(docker exec mysql-primary mysql -u root -prootpass -sN \
    -e "SHOW MASTER STATUS;" 2>/dev/null | awk '{print $1}') || true
echo "Current binlog: $CURRENT_BINLOG"

echo ""
echo "All events in current binlog:"
mysql_primary -e "SHOW BINLOG EVENTS IN '${CURRENT_BINLOG}' LIMIT 200;" | \
    grep -i "delete\|Query\|GTID" | head -30 || echo "(no matching events)"

echo ""
echo "Full binlog decode via mysqlbinlog (mysql-tools container):"
docker exec mysql-tools mysqlbinlog \
    --no-defaults \
    --read-from-remote-server \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --base64-output=DECODE-ROWS \
    --verbose \
    "${CURRENT_BINLOG}" 2>/dev/null | grep -A5 "DELETE FROM" | head -40 \
    || echo "(no DELETE statements found in decoded binlog)"

echo ""
echo "--- Step 8: PITR recovery into shopdb_pitr ---"
echo "Creating recovery database..."
mysql_primary -e "DROP DATABASE IF EXISTS shopdb_pitr; CREATE DATABASE shopdb_pitr;"

echo "Restoring snapshot backup..."
docker cp "/tmp/pitr_snapshot_${PITR_TS}.sql" mysql-primary:/tmp/pitr_snapshot.sql
docker exec mysql-primary bash -c \
    "mysql -u root -prootpass shopdb_pitr < /tmp/pitr_snapshot.sql 2>/dev/null"

echo "Replaying binlogs excluding the DELETE transaction (GTID-based)..."
docker exec mysql-tools mysqlbinlog \
    --no-defaults \
    --read-from-remote-server \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --exclude-gtids="${GTID_AFTER_DELETE}" \
    "${CURRENT_BINLOG}" 2>/dev/null \
    | docker exec -i mysql-primary mysql -u root -prootpass shopdb_pitr 2>/dev/null || true

echo ""
echo "--- Step 9: Compare original vs recovered ---"
echo "Current shopdb.orders (has the delete):"
mysql_primary shopdb -e "SELECT COUNT(*) AS total, status FROM orders GROUP BY status;"

echo ""
echo "Recovered shopdb_pitr.orders (delete rolled back):"
mysql_primary shopdb_pitr -e "SELECT COUNT(*) AS total, status FROM orders GROUP BY status;" \
    || echo "(binlog replay not captured — snapshot is the restore point)"

echo ""
echo "--- Step 10: Zero-downtime table swap using RENAME TABLE ---"
echo ""
echo "RENAME TABLE is atomic — no window where the table is missing."
echo "Clients see either the old table or the new one, never nothing."
echo ""
echo "Before swap:"
mysql_primary shopdb -e "
    SELECT 'shopdb.orders'        AS tbl, COUNT(*) AS rows, 'active'    AS role FROM orders
    UNION ALL
    SELECT 'shopdb_pitr.orders'   AS tbl, COUNT(*) AS rows, 'recovered' AS role
    FROM shopdb_pitr.orders;" 2>/dev/null || true

echo ""
echo "Swapping: orders → orders_broken, shopdb_pitr.orders → orders ..."
mysql_primary -e "
    -- Drop stale _broken table if a previous run left it
    DROP TABLE IF EXISTS shopdb.orders_broken;

    -- Atomic swap: one statement, no downtime
    RENAME TABLE
        shopdb.orders       TO shopdb.orders_broken,
        shopdb_pitr.orders  TO shopdb.orders;"

echo ""
echo "After swap:"
mysql_primary shopdb -e "
    SELECT 'orders (now active)'  AS tbl, COUNT(*) AS rows FROM orders
    UNION ALL
    SELECT 'orders_broken (old)'  AS tbl, COUNT(*) AS rows FROM orders_broken;"

echo ""
echo "Verify status distribution in promoted table:"
mysql_primary shopdb -e "SELECT status, COUNT(*) AS rows FROM orders GROUP BY status;"

echo ""
echo "--- Swap best practices ---"
echo "  1. Restore to a shadow DB/table (shopdb_pitr)"
echo "  2. Verify row counts, spot-check data"
echo "  3. RENAME TABLE old → old_broken, shadow → active  (atomic, instant)"
echo "  4. Keep old_broken for 24h before dropping"
echo "  5. For full-DB swap: rename all tables in one RENAME TABLE statement"
echo "     or use ProxySQL to redirect traffic to the shadow DB first"

echo ""
echo "--- Summary: PITR steps ---"
echo "  1. FLUSH BINARY LOGS                        — seal current binlog before backup"
echo "  2. mysqldump --set-gtid-purged=OFF           — consistent snapshot (same-server restore)"
echo "  3. Note GTID_EXECUTED at snapshot time"
echo "  4. Incident happens — identify bad GTID"
echo "  5. Restore snapshot to shadow DB"
echo "  6. mysqlbinlog --exclude-gtids=<bad_gtid>    — replay safe transactions"
echo "  7. Verify shadow DB data"
echo "  8. RENAME TABLE atomic swap — zero downtime promotion"

echo ""
echo "✅ Backup exercises complete."
