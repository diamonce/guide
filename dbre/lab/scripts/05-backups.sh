#!/bin/bash
# Covers all backup methods:
#   A. mysqldump (logical)
#   B. mysqldump single table
#   C. Binary log backup (for PITR)
#   D. Restore from dump
#   E. PITR — restore to specific GTID

set -euo pipefail

BACKUP_DIR="/backup"
TS=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo " A. Full logical backup with mysqldump"
echo "============================================"
docker exec mysql-primary mysqldump \
    -prootpass \
    --all-databases \
    --single-transaction \      # consistent snapshot without locking
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=ON \      # include GTID info for replication-safe restore
    --master-data=2 \           # comment with binlog position
    > "/tmp/full_backup_${TS}.sql" 2>/dev/null

echo "✅ Full backup: /tmp/full_backup_${TS}.sql ($(du -sh /tmp/full_backup_${TS}.sql | cut -f1))"

echo ""
echo "============================================"
echo " B. Single database backup"
echo "============================================"
docker exec mysql-primary mysqldump \
    -prootpass \
    --single-transaction \
    shopdb \
    > "/tmp/shopdb_${TS}.sql" 2>/dev/null

echo "✅ shopdb backup: /tmp/shopdb_${TS}.sql"

echo ""
echo "============================================"
echo " C. Single table backup"
echo "============================================"
docker exec mysql-primary mysqldump \
    -prootpass \
    --single-transaction \
    shopdb orders \
    > "/tmp/orders_${TS}.sql" 2>/dev/null

echo "✅ orders table backup: /tmp/orders_${TS}.sql"

echo ""
echo "============================================"
echo " D. Restore to a NEW database"
echo "============================================"
echo "Creating shopdb_restored..."
docker exec mysql-primary mysql -prootpass \
    -e "CREATE DATABASE IF NOT EXISTS shopdb_restored;"

docker exec -i mysql-primary mysql -prootpass shopdb_restored \
    < "/tmp/shopdb_${TS}.sql" 2>/dev/null

docker exec mysql-primary mysql -prootpass shopdb_restored \
    -e "SELECT 'Restored tables:'; SHOW TABLES; SELECT COUNT(*) AS orders_count FROM orders;"

echo ""
echo "============================================"
echo " E. Binary log backup (PITR building block)"
echo "============================================"
# Show current binlog position
docker exec mysql-primary mysql -prootpass \
    -e "SHOW MASTER STATUS\G"

# Flush to a new binlog file
docker exec mysql-primary mysql -prootpass \
    -e "FLUSH BINARY LOGS;"

# List available binary logs
docker exec mysql-primary mysql -prootpass \
    -e "SHOW BINARY LOGS;"

echo ""
echo "=== PITR demo: make a change, then 'recover' to before it ==="

echo "Current orders count:"
docker exec mysql-primary mysql -prootpass shopdb \
    -e "SELECT COUNT(*) AS before_delete FROM orders;"

# Get GTID before the "oops"
GTID_BEFORE=$(docker exec mysql-primary mysql -prootpass -sN \
    -e "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tr -d ' ')
echo "GTID before oops: $GTID_BEFORE"

# Simulate accidental delete
docker exec mysql-primary mysql -prootpass shopdb \
    -e "DELETE FROM orders WHERE status='cancelled';"

echo "After accidental delete:"
docker exec mysql-primary mysql -prootpass shopdb \
    -e "SELECT COUNT(*) AS after_delete FROM orders;"

echo ""
echo "--- To recover: restore backup + replay binlogs up to GTID before delete ---"
echo "--- In production: mysqlbinlog --stop-position=<pos> binlog | mysql ---"
echo "--- See runbook.md PITR section for full walkthrough ---"

echo ""
echo "✅ Backup exercises complete."
