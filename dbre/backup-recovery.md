# Backup & Recovery

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Backup Fundamentals `[B]`

### Key Concepts

| Term | Definition |
|------|-----------|
| **RPO** | Recovery Point Objective — max acceptable data loss (e.g., 1 hour means you can lose up to 1 hour of data) |
| **RTO** | Recovery Time Objective — max acceptable downtime during recovery |
| **PITR** | Point-in-Time Recovery — restore to any specific moment |
| **WAL** | Write-Ahead Log — PostgreSQL transaction log, enables PITR |
| **Full backup** | Complete copy of the database |
| **Incremental backup** | Only changes since last backup |
| **Logical backup** | SQL dump (pg_dump), portable, slow for large DBs |
| **Physical backup** | Binary copy of data files, fast, DB-version specific |

### Backup Strategy by Tier

| Tier | Example | RPO | RTO | Strategy |
|------|---------|-----|-----|---------|
| Critical | Payment DB, user accounts | Near-zero | < 1 hour | Continuous WAL archival + PITR |
| Standard | Product catalog, orders | 1-4 hours | < 4 hours | Hourly snapshots + daily full |
| Low | Analytics, logs | 24 hours | < 24 hours | Daily backup |

---

## PostgreSQL Backup Methods `[I]`

### pg_dump (Logical)

```bash
# Single database dump (compressed)
pg_dump -h localhost -U postgres -d mydb -F c -f mydb_backup.dump

# Plain SQL format (human-readable, larger)
pg_dump -h localhost -U postgres -d mydb -F p -f mydb_backup.sql

# Schema only
pg_dump --schema-only -d mydb -f schema.sql

# Specific table
pg_dump -t orders -d mydb -f orders_backup.dump

# Restore
pg_restore -h localhost -U postgres -d mydb_new -F c mydb_backup.dump

# For plain SQL:
psql -h localhost -U postgres -d mydb_new < mydb_backup.sql
```

**Limitations:**
- `pg_dump` takes a consistent snapshot but is slow for large DBs
- Restore is sequential (slow for TB-scale)
- Use pgBackRest or Barman for production

### pgBackRest (Physical, Production-Grade)

```ini
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-path=/backup/pgbackrest
repo1-retention-full=7
repo1-retention-diff=4

[mydb]
pg1-path=/var/lib/postgresql/14/main
pg1-host=postgres-primary
```

```bash
# Full backup
pgbackrest --stanza=mydb backup --type=full

# Differential backup
pgbackrest --stanza=mydb backup --type=diff

# Incremental backup
pgbackrest --stanza=mydb backup --type=incr

# List backups
pgbackrest --stanza=mydb info

# Restore to specific time (PITR)
pgbackrest --stanza=mydb restore \
  --target="2024-01-15 14:30:00" \
  --target-action=promote

# Verify backup integrity
pgbackrest --stanza=mydb check
```

### Continuous WAL Archival

```ini
# postgresql.conf — enable WAL archiving
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=mydb archive-push %p'
```

This enables PITR to any point in time, not just when backups were taken.

---

## AWS RDS / Aurora Backups `[I]`

### Automated Backups

```hcl
resource "aws_db_instance" "main" {
  # ...
  backup_retention_period   = 30        # days
  backup_window             = "03:00-04:00"
  delete_automated_backups  = false
  deletion_protection       = true      # prevent accidental deletion
}
```

**RDS PITR:** AWS stores transaction logs continuously. Restore to any second within the retention window.

```bash
# Restore to specific time via CLI
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier prod-db \
  --target-db-instance-identifier prod-db-restored \
  --restore-time "2024-01-15T14:30:00Z"
```

### Manual Snapshots

```bash
# Create snapshot before risky operations
aws rds create-db-snapshot \
  --db-instance-identifier prod-db \
  --db-snapshot-identifier pre-migration-20240115

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier prod-db

# Copy snapshot to another region (DR)
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:us-east-1:123:snapshot:pre-migration \
  --target-db-snapshot-identifier pre-migration-dr \
  --region us-west-2
```

---

## Backup Verification `[I]`

**A backup that hasn't been tested is not a backup.**

Verification checklist:
- [ ] Backup completes successfully (alert on failure)
- [ ] Backup size is within expected range (alert on anomaly)
- [ ] Weekly restore test to isolated environment
- [ ] Verify data integrity after restore (row counts, checksums)
- [ ] Document and test the end-to-end recovery procedure

```bash
# pgBackRest integrity check
pgbackrest --stanza=mydb check

# After restore, verify data
psql -d restored_db -c "SELECT COUNT(*) FROM orders;"
psql -d restored_db -c "SELECT MAX(created_at) FROM orders;"

# Compare with production
diff <(psql -d prod_db -c "\dt" | sort) \
     <(psql -d restored_db -c "\dt" | sort)
```

---

## Disaster Recovery Playbook `[A]`

### Scenario 1: Accidental Data Delete / Table Drop

```bash
# Immediately: stop writes to the DB or put app in maintenance mode
# (Prevents more data from being written, making recovery window cleaner)

# Option A: PITR to just before the incident
pgbackrest --stanza=mydb restore \
  --target="2024-01-15 13:58:00" \  # 2 minutes before drop
  --target-action=promote \
  --db-path=/var/lib/postgresql/recovered

# Option B: Selective restore of just the table
# 1. Restore to a separate server
# 2. pg_dump just the affected table
# 3. pg_restore into production

# Option C: Extract from logical backup
pg_restore -t orders -d prod_db orders_backup.dump

# After recovery: run postmortem, add DROP TABLE protection
REVOKE DROP ON TABLE orders FROM app_user;
```

### Scenario 2: Primary DB Failure

```
Primary fails
    ↓
Replica promoted to primary (manual or automatic)
    ↓
Application connection string updated (DNS failover or PgBouncer reconfigure)
    ↓
New replica provisioned to replace old primary
    ↓
Postmortem on root cause
```

With AWS RDS Multi-AZ: automatic failover in 60-120 seconds.
With Aurora: automatic failover in ~30 seconds.

### Scenario 3: Corruption / Bad Migration

```bash
# Take immediate snapshot of current state (even if corrupted — for analysis)
aws rds create-db-snapshot --db-instance-identifier prod-db \
  --db-snapshot-identifier corruption-incident-20240115

# Restore to pre-migration state
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier prod-db \
  --target-db-instance-identifier prod-db-restored \
  --restore-time "2024-01-15T09:00:00Z"  # before migration ran
```

---

## Backup Monitoring `[I]`

```yaml
# Prometheus alert rules
- alert: BackupFailed
  expr: pgbackrest_backup_error == 1
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Database backup failed"
    runbook: "https://wiki/dbre/backup-failure"

- alert: BackupTooOld
  expr: time() - pgbackrest_backup_timestamp_last_full > 86400  # 24 hours
  labels:
    severity: warning
  annotations:
    summary: "No successful full backup in 24 hours"
```

---

## Related Topics

- [Fundamentals](fundamentals.md) — RTO/RPO in context of DB SLOs
- [Migrations & Schema Changes](migrations.md) — always backup before migrations
- [Scaling Databases](scaling.md) — replicas and HA
- [SRE: Incident Management](../sre/incident-management.md) — recovery as incident
- [Platform: Cloud Infrastructure](../platform/cloud-infra.md) — RDS, snapshots, EBS
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-table-checksum for data verification
