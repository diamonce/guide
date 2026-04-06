#!/bin/bash
# Fast backup methods for large databases (TB-scale)
#
# Methods covered:
#   A. Percona XtraBackup — physical hot backup (fastest for InnoDB, no locks)
#   B. XtraBackup incremental — only changed pages since last backup
#   C. mydumper — parallel logical backup (faster than mysqldump)
#   D. Storage snapshot simulation — instant copy-on-write approach
#
# Rule of thumb:
#   < 50 GB   → mysqldump or mydumper
#   50 GB–2TB → XtraBackup (full + incremental)
#   > 2TB     → XtraBackup streaming + storage snapshot for RTO

set -euo pipefail

PT="docker exec toolkit"
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE=/backup

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── Check tools ──────────────────────────────────────────────────────────────
header "Tool availability check"
for tool in xtrabackup mydumper; do
    if $PT which $tool >/dev/null 2>&1; then
        echo "✅ $tool: $($PT $tool --version 2>&1 | head -1)"
    else
        echo "⚠  $tool not installed in toolkit container"
        echo "   Run: docker compose build toolkit && docker compose up -d toolkit"
    fi
done

# ─── A. XtraBackup full backup ────────────────────────────────────────────────
header "A. XtraBackup — full physical backup (hot, no locks)"

echo "Why faster than mysqldump:"
echo "  • Copies raw InnoDB pages, not SQL statements"
echo "  • Parallel I/O — saturates disk bandwidth"
echo "  • No global lock (only brief MDL at end for non-InnoDB tables)"
echo "  • 1TB takes ~20-40 min vs hours for mysqldump"
echo ""

FULL_BACKUP_DIR="${BACKUP_BASE}/full_${TS}"

echo "→ Running XtraBackup full backup..."
$PT xtrabackup \
    --backup \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --target-dir="${FULL_BACKUP_DIR}" \
    --parallel=4 \
    --compress \
    --compress-threads=4 \
    2>&1 | tail -5 && echo "✅ Full backup complete: ${FULL_BACKUP_DIR}" \
    || echo "⚠  XtraBackup not available — see tool check above"

echo ""
echo "For TB-scale: stream directly to S3 instead of disk:"
echo "  xtrabackup --backup --stream=xbstream --compress \\"
echo "    | aws s3 cp - s3://bucket/backup-\$(date +%Y%m%d).xbstream"
echo ""
echo "Or stream to another host:"
echo "  xtrabackup --backup --stream=xbstream \\"
echo "    | ssh backup-host 'xbstream -x -C /backup/'"

# ─── B. XtraBackup incremental ────────────────────────────────────────────────
header "B. XtraBackup — incremental backup (changed pages only)"

echo "Why incrementals matter at TB scale:"
echo "  • Full backup: copy ALL pages (slow, expensive)"
echo "  • Incremental: copy only pages changed since last backup (fast, cheap)"
echo "  • InnoDB tracks changes via LSN (Log Sequence Number)"
echo ""

INCR_BACKUP_DIR="${BACKUP_BASE}/incr_${TS}"

if $PT test -d "${FULL_BACKUP_DIR}" 2>/dev/null; then
    LSN=$($PT cat "${FULL_BACKUP_DIR}/xtrabackup_checkpoints" 2>/dev/null \
        | grep to_lsn | awk '{print $3}') || LSN="unknown"
    echo "Base LSN from full backup: $LSN"
    echo "→ Running incremental backup (changes since full)..."
    $PT xtrabackup \
        --backup \
        --host=mysql-primary \
        --user=root \
        --password=rootpass \
        --target-dir="${INCR_BACKUP_DIR}" \
        --incremental-basedir="${FULL_BACKUP_DIR}" \
        --parallel=4 \
        --compress \
        2>&1 | tail -5 && echo "✅ Incremental backup complete: ${INCR_BACKUP_DIR}" \
        || echo "⚠  Incremental backup failed"
else
    echo "(skipping — full backup not available)"
fi

echo ""
echo "Incremental restore sequence:"
echo "  1. xtrabackup --prepare --apply-log-only --target-dir=full/"
echo "  2. xtrabackup --prepare --apply-log-only --target-dir=full/ --incremental-dir=incr1/"
echo "  3. xtrabackup --prepare --target-dir=full/   # final prepare, no --apply-log-only"
echo "  4. xtrabackup --copy-back --target-dir=full/"
echo "  5. chown -R mysql:mysql /var/lib/mysql && systemctl start mysql"

# ─── C. mydumper — parallel logical backup ────────────────────────────────────
header "C. mydumper — parallel logical backup"

echo "Why faster than mysqldump:"
echo "  • Multiple threads dump tables in parallel"
echo "  • One file per table → parallel restore with myloader"
echo "  • Consistent snapshot via single FTWRL, released quickly"
echo "  • chunk-filesize splits large tables for better parallelism"
echo ""

MYDUMPER_DIR="${BACKUP_BASE}/mydumper_${TS}"

echo "→ Running mydumper (4 threads)..."
$PT mydumper \
    --host=mysql-primary \
    --user=root \
    --password=rootpass \
    --database=shopdb \
    --outputdir="${MYDUMPER_DIR}" \
    --threads=4 \
    --chunk-filesize=128 \
    --compress \
    --build-empty-files \
    --trx-consistency-only \
    2>&1 | tail -5 && \
    echo "✅ mydumper complete: ${MYDUMPER_DIR}" && \
    $PT ls "${MYDUMPER_DIR}" \
    || echo "⚠  mydumper not available"

echo ""
echo "Restore with myloader (parallel):"
echo "  myloader --host=target --user=root --password=pass \\"
echo "    --directory=${MYDUMPER_DIR} --threads=8 --database=shopdb"

# ─── D. Storage snapshot approach ─────────────────────────────────────────────
header "D. Storage snapshot — near-instant backup"

echo "How it works:"
echo "  1. FLUSH TABLES WITH READ LOCK  (< 1 second)"
echo "  2. Take snapshot (LVM/EBS/GCP PD) — metadata operation, instant"
echo "  3. UNLOCK TABLES"
echo "  4. Backup from snapshot async — MySQL keeps running, zero impact"
echo ""
echo "Cloud equivalents:"
echo "  AWS RDS:   aws rds create-db-snapshot --db-instance-identifier mydb"
echo "  GCP:       gcloud sql backups create --instance=mydb"
echo "  EBS:       aws ec2 create-snapshot --volume-id vol-xxx"
echo "             → restore: create volume from snapshot, mount, rsync"
echo ""
echo "LVM snapshot example (bare metal / on-prem):"
echo "  mysql -e 'FLUSH TABLES WITH READ LOCK;'"
echo "  lvcreate -L10G -s -n mysql-snap /dev/vg0/mysql"
echo "  mysql -e 'UNLOCK TABLES;'"
echo "  mount /dev/vg0/mysql-snap /mnt/snap"
echo "  rsync -a /mnt/snap/ /backup/snapshot-\$(date +%Y%m%d)/"
echo "  umount /mnt/snap && lvremove /dev/vg0/mysql-snap"

# ─── Throughput comparison ─────────────────────────────────────────────────────
header "Throughput comparison (1 TB database, 500 MB/s disk)"

cat <<'TABLE'
Method              Backup time   Lock time   Restore time   Use case
──────────────────  ───────────   ─────────   ────────────   ────────────────────────────
mysqldump           3–6 hours     full dur.   4–8 hours      < 50 GB, portability needed
mydumper (8 thr.)   1–2 hours     ~seconds    1–2 hours      logical, cross-version restore
XtraBackup full     30–60 min     ~seconds    30–60 min      InnoDB, same/similar version
XtraBackup incr.    2–10 min      ~seconds    60–90 min      daily fulls + hourly incrementals
EBS/LVM snapshot    ~seconds      < 1 sec     5–15 min       cloud, fastest RTO
TABLE

echo ""
echo "✅ Fast backup demo complete."
echo "   Backups written to: ${BACKUP_BASE}/"
$PT ls -lh "${BACKUP_BASE}/" 2>/dev/null | grep -v "^total 0$" || true
