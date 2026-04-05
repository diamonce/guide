# Migrations & Schema Changes

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Why Migrations Are Risky `[B]`

Schema changes on live databases can:
- Lock tables for seconds or minutes (blocking all reads/writes)
- Cause application errors if new/old code expects different schema
- Fill up disk during table rewrites
- Cause replication lag on replicas

**The goal:** zero-downtime, backward-compatible schema changes.

---

## Safe vs Unsafe Operations `[B]`

### PostgreSQL

| Operation | Risk | Notes |
|-----------|------|-------|
| `ADD COLUMN` (nullable, no default) | Safe | Instant metadata change |
| `ADD COLUMN` with DEFAULT (Postgres 11+) | Safe | Stored as default, instant |
| `ADD COLUMN` with DEFAULT (Postgres < 11) | Unsafe | Rewrites entire table |
| `DROP COLUMN` | Safe (after code deploy) | Hides column, no rewrite |
| `CREATE INDEX CONCURRENTLY` | Safe | Non-blocking |
| `CREATE INDEX` | Unsafe | Locks table writes |
| `ADD NOT NULL` | Unsafe | Scans entire table |
| `ALTER COLUMN TYPE` | Unsafe | Rewrites table |
| `DROP TABLE` | Unsafe | Permanent data loss |
| `RENAME TABLE/COLUMN` | Unsafe | Breaks existing code |
| `ADD CONSTRAINT` | Unsafe | Validates entire table |

### MySQL / Aurora

| Operation | Risk | Notes |
| `ADD COLUMN` | Depends | InnoDB instant DDL in MySQL 8+ |
| `ADD INDEX` | Unsafe | Use `pt-online-schema-change` or `gh-ost` |
| `DROP COLUMN` | Depends | MySQL 8 instant DDL |
| `CHANGE COLUMN TYPE` | Unsafe | Rebuilds table |

---

## Expand/Contract Pattern `[I]`

The safest way to make breaking schema changes:

```
Phase 1: EXPAND  — add new structure alongside old
Phase 2: MIGRATE — backfill data to new structure
Phase 3: SWITCH  — update code to use new structure
Phase 4: CONTRACT — remove old structure
```

### Example: Renaming a Column

```
❌ Wrong: RENAME COLUMN user_name TO username
         → breaks running apps instantly

✓ Correct:
Phase 1: ADD COLUMN username VARCHAR(255)
         + write to BOTH columns in application code

Phase 2: UPDATE users SET username = user_name WHERE username IS NULL
         (run in batches, see batching below)

Phase 3: Deploy code that reads from username only
         + verify no reads of user_name in production

Phase 4: DROP COLUMN user_name
```

### Example: Adding NOT NULL Constraint

```sql
-- Phase 1: Add column as nullable
ALTER TABLE orders ADD COLUMN customer_email VARCHAR(255);

-- Phase 2: Backfill (in batches)
UPDATE orders SET customer_email = (
    SELECT email FROM customers WHERE customers.id = orders.customer_id
)
WHERE customer_email IS NULL AND id BETWEEN :start AND :end;

-- Phase 3: Add NOT NULL (after 100% backfill verified)
-- PostgreSQL: avoid full scan with NOT VALID + VALIDATE
ALTER TABLE orders
  ADD CONSTRAINT orders_customer_email_not_null
  CHECK (customer_email IS NOT NULL) NOT VALID;

ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_email_not_null;
-- VALIDATE acquires ShareUpdateExclusiveLock (allows reads/writes)
```

---

## Batching Large Updates `[I]`

Never run `UPDATE ... WHERE` that touches millions of rows in a single transaction:
- Holds locks for minutes
- Generates huge WAL / binlog
- Can cause replication lag

```python
# Python batching example
def backfill_in_batches(batch_size=1000, sleep_seconds=0.1):
    last_id = 0
    while True:
        result = db.execute("""
            UPDATE orders
            SET customer_email = (
                SELECT email FROM customers WHERE customers.id = orders.customer_id
            )
            WHERE id > :last_id
              AND customer_email IS NULL
            LIMIT :batch_size
            RETURNING id
        """, last_id=last_id, batch_size=batch_size)

        if not result:
            break

        last_id = max(row['id'] for row in result)
        time.sleep(sleep_seconds)  # Be gentle on the DB
        print(f"Processed up to id={last_id}")
```

```sql
-- Pure SQL batching (PostgreSQL)
DO $$
DECLARE
  batch_id BIGINT := 0;
  max_id BIGINT;
BEGIN
  SELECT MAX(id) INTO max_id FROM orders;

  WHILE batch_id < max_id LOOP
    UPDATE orders
    SET processed = TRUE
    WHERE id > batch_id AND id <= batch_id + 1000
      AND processed IS FALSE;

    batch_id := batch_id + 1000;
    PERFORM pg_sleep(0.1);  -- small delay between batches
  END LOOP;
END $$;
```

---

## Non-Blocking Index Creation `[I]`

```sql
-- Always use CONCURRENTLY in production
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);

-- If CONCURRENTLY fails, it leaves an INVALID index:
-- Check for invalid indexes
SELECT indexname, indisvalid
FROM pg_indexes
JOIN pg_index ON pg_index.indexrelid = pg_class.oid
JOIN pg_class ON pg_class.relname = pg_indexes.indexname
WHERE NOT indisvalid;

-- Drop and retry
DROP INDEX CONCURRENTLY idx_orders_customer_id;
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
```

---

## Migration Tools `[I]`

### Flyway

```sql
-- V1__create_orders.sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- V2__add_status_to_orders.sql
ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);
```

```bash
flyway -url=jdbc:postgresql://localhost/mydb migrate
flyway info   # show migration status
```

### Alembic (Python/SQLAlchemy)

```python
# alembic/versions/abc123_add_customer_email.py
def upgrade():
    op.add_column('orders',
        sa.Column('customer_email', sa.String(255), nullable=True)
    )
    # Note: create index CONCURRENTLY separately or use op.execute()
    op.execute("""
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_customer_email
        ON orders(customer_email)
    """)

def downgrade():
    op.drop_index('idx_orders_customer_email', table_name='orders')
    op.drop_column('orders', 'customer_email')
```

### gh-ost (GitHub Online Schema Change — MySQL)

```bash
gh-ost \
  --user="dbre" \
  --password="..." \
  --host=primary.db.example.com \
  --database="myapp" \
  --table="orders" \
  --alter="ADD COLUMN customer_email VARCHAR(255)" \
  --execute
```

Uses binary log to apply changes incrementally, no long table locks.

---

## Rollback Strategies `[I]`

Not all migrations are reversible in the same way. Know your rollback before you run.

| Migration type | Rollback procedure | Reversible? |
|---------------|-------------------|-------------|
| `ADD COLUMN` (nullable) | `DROP COLUMN` | Yes — instant |
| `ADD COLUMN` with DEFAULT | `DROP COLUMN` | Yes — instant (Postgres 11+) |
| `CREATE INDEX CONCURRENTLY` | `DROP INDEX CONCURRENTLY` | Yes |
| Backfill (UPDATE in batches) | Reverse backfill (run opposite UPDATE) | Yes — but slow |
| `DROP COLUMN` | Restore from snapshot | No — must snapshot before |
| `DROP TABLE` | Restore from snapshot | No — must snapshot before |
| `RENAME COLUMN` (via expand/contract) | Remove new column, restore old writes | Yes — if expand phase only |
| `ALTER COLUMN TYPE` | Restore from snapshot | No |
| Constraint (`NOT VALID` + `VALIDATE`) | `DROP CONSTRAINT` | Yes |

**Rule:** any migration that touches existing data or removes structure needs a pre-migration snapshot.

```bash
# AWS RDS: snapshot before every risky migration
aws rds create-db-snapshot \
  --db-instance-identifier prod-db \
  --db-snapshot-identifier "pre-migration-$(date +%Y%m%d-%H%M)"

# Verify snapshot is available before proceeding
aws rds describe-db-snapshots \
  --db-snapshot-identifier "pre-migration-$(date +%Y%m%d-%H%M)" \
  --query 'DBSnapshots[0].Status'
```

---

## What to Do When a Migration Goes Wrong `[I]`

### Step 1: Assess the situation

```sql
-- Is the migration still running?
SELECT pid, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC;

-- How many rows remain? (estimate from last_id progress in backfill)
SELECT COUNT(*) FROM orders WHERE customer_email IS NULL;

-- Is anything blocked behind it?
SELECT
  blocking.pid AS blocking_pid,
  blocked.pid  AS blocked_pid,
  blocking.query AS blocker,
  blocked.query  AS blocked,
  now() - blocked.query_start AS blocked_duration
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));
```

### Step 2: Decision — wait or cancel?

```
Duration estimate acceptable AND no critical queries blocked?
  → Wait. Monitor.

Duration unacceptable OR critical queries blocked?
  → Cancel the migration.
```

### Step 3: Cancel safely

```sql
-- Soft cancel (preferred — waits for safe point)
SELECT pg_cancel_backend(:migration_pid);

-- Hard terminate (use if soft cancel doesn't work after 30s)
SELECT pg_terminate_backend(:migration_pid);
```

### Step 4: Clean up after a failed `CREATE INDEX CONCURRENTLY`

A failed `CREATE INDEX CONCURRENTLY` leaves an `INVALID` index that continues to consume space and slow writes without helping reads:

```sql
-- Find invalid indexes
SELECT indexname, tablename
FROM pg_indexes
JOIN pg_class ON pg_class.relname = pg_indexes.indexname
JOIN pg_index ON pg_index.indexrelid = pg_class.oid
WHERE NOT pg_index.indisvalid;

-- Drop the invalid index, then retry
DROP INDEX CONCURRENTLY idx_orders_customer_email;
CREATE INDEX CONCURRENTLY idx_orders_customer_email ON orders(customer_email);
```

### Step 5: If rollback is needed

```bash
# Restore from pre-migration snapshot (RDS)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier prod-db-restored \
  --db-snapshot-identifier "pre-migration-20240315-1400"

# Point application at restored instance, verify data
# Then cut back DNS / connection string
```

---

## What to Watch During a Migration `[I]`

Open these dashboards before starting any migration with risk > Low:

```sql
-- Terminal 1: watch lock waits in real time
SELECT
  now() - query_start AS wait_duration,
  pid,
  wait_event_type,
  wait_event,
  LEFT(query, 80) AS query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
ORDER BY wait_duration DESC;

-- Terminal 2: watch replication lag
SELECT
  client_addr,
  state,
  sent_lsn - replay_lsn AS lag_bytes,
  replay_lag
FROM pg_stat_replication;

-- Terminal 3: disk usage (table rewrites can temporarily double disk)
SELECT
  pg_size_pretty(pg_total_relation_size('orders')) AS table_size,
  pg_size_pretty(pg_relation_size('orders')) AS heap_size;
```

**Alert thresholds during migration:**
- Replication lag > 60s → pause batching, let replica catch up
- Lock wait > 30s → assess if migration is blocking critical app queries
- Disk usage growth > 20% during migration → check for unexpected table rewrite

---

## Migration Checklist `[A]`

Before running a migration in production:

- [ ] Migration tested on a production-sized copy of data
- [ ] Estimated duration known (tested in staging)
- [ ] **Pre-migration snapshot taken** (`aws rds create-db-snapshot`)
- [ ] Rollback procedure documented (see table above)
- [ ] Application code is backward-compatible with both old and new schema
- [ ] Batching used for large data updates
- [ ] `CONCURRENTLY` used for index creation
- [ ] `NOT VALID` + `VALIDATE CONSTRAINT` for PostgreSQL constraints
- [ ] Monitoring terminals open (locks, replication lag, disk)
- [ ] DBA / DBRE aware (for SEV1-risk changes)
- [ ] Runbook updated

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Performance Tuning](performance.md) — index creation
- [Backup & Recovery](backup-recovery.md) — always backup before major migrations
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-online-schema-change
- [Platform: CI/CD](../platform/cicd.md) — migrations in deployment pipelines
