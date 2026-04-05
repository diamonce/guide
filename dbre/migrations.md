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

| Operation | INSTANT | INPLACE (online) | Needs pt-osc/gh-ost |
|-----------|:-------:|:----------------:|:-------------------:|
| ADD COLUMN (end, any default) | ✓ 8.0.29+ | ✓ | No |
| ADD COLUMN (with GENERATED) | ✗ | ✓ | No |
| DROP COLUMN | ✓ 8.0.29+ | ✓ | No |
| RENAME COLUMN | ✓ | ✓ | No |
| ADD SECONDARY INDEX | ✗ | ✓ (lock=NONE) | No — INPLACE is online |
| DROP INDEX | ✗ | ✓ | No |
| ADD FULLTEXT INDEX (first) | ✗ | ✓ | No |
| CHANGE COLUMN TYPE | ✗ | ✗ (COPY) | **Yes** |
| ADD / DROP PRIMARY KEY | ✗ | ✗ (COPY) | **Yes** |
| CONVERT CHARACTER SET | ✗ | ✗ (COPY) | **Yes** |
| ADD FOREIGN KEY | ✗ | ✓ | No |
| OPTIMIZE TABLE | ✗ | ✓ | No (but slow — consider pt-osc) |

INSTANT = zero-lock, metadata-only. INPLACE (online) = brief MDL at start and end, no table copy. COPY = full table rewrite, reads blocked.

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

## MySQL Schema Changes — Planning & Execution `[I]`

### Step 1: Determine which algorithm MySQL will use

Always test the algorithm before running on production. Add the algorithm hint — if MySQL can't honour it, the statement **errors immediately** rather than running a dangerous operation silently:

```sql
-- Test each tier without executing (ALGORITHM clause makes it a dry-run contract)

-- Tier 1: no lock, no copy, instant metadata change
ALTER TABLE orders ADD COLUMN notes TEXT, ALGORITHM=INSTANT;

-- Tier 2: no table copy, brief MDL at start/end only
ALTER TABLE orders ADD COLUMN notes TEXT, ALGORITHM=INPLACE, LOCK=NONE;

-- If both error → table must be copied. Use pt-osc or gh-ost (not native ALTER).
-- Never run ALGORITHM=COPY on a large table in production.
```

What each error means:

```
ERROR 1845: ALGORITHM=INSTANT is not supported  → try INPLACE
ERROR 1846: LOCK=NONE is not supported          → operation needs COPY → use pt-osc/gh-ost
```

---

### Step 2: Tool selection

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Which tool should I use?                          │
│                                                                     │
│  ALGORITHM=INSTANT works?                                           │
│    YES → run native ALTER (zero risk)                               │
│    NO  ↓                                                            │
│                                                                     │
│  ALGORITHM=INPLACE, LOCK=NONE works?                                │
│    YES → run native ALTER (brief MDL only, typically <1s)           │
│          acceptable for most tables regardless of size              │
│    NO  ↓  (operation requires COPY)                                 │
│                                                                     │
│  Table size < 1 GB AND write rate < 100 writes/sec?                 │
│    YES → pt-online-schema-change (simpler, good enough)             │
│    NO  → gh-ost (better throttling, binlog-based, pauseable)        │
└─────────────────────────────────────────────────────────────────────┘
```

| | pt-osc | gh-ost |
|--|--------|--------|
| Mechanism | Triggers on original table | Reads binlog, no triggers |
| Trigger overhead | ~10% write overhead | None |
| Pause mid-migration | No (must kill) | Yes — `echo throttle > /tmp/gh-ost.sock` |
| Progress visibility | Limited | ETA, rows%, lag display |
| Works with triggers already on table | No (pre-8.0) | Yes |
| Replica lag throttling | Yes (`--max-lag`) | Yes (`--max-lag-millis`) |
| Best for | Simpler ops, smaller tables | Large tables, high-write primaries |

---

### Step 3: Estimate duration before you run

```sql
-- 1. Measure table size and row count
SELECT
  table_name,
  table_rows                                              AS est_rows,
  ROUND(data_length  / 1024 / 1024, 0)                  AS data_mb,
  ROUND(index_length / 1024 / 1024, 0)                  AS index_mb,
  ROUND((data_length + index_length) / 1024 / 1024 / 1024, 2) AS total_gb
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY data_length DESC;
```

```sql
-- 2. Measure current write rate on the target table (run for 60s)
SELECT variable_value INTO @before FROM performance_schema.global_status
  WHERE variable_name = 'Innodb_rows_inserted';
SELECT SLEEP(60);
SELECT variable_value - @before AS inserts_per_min FROM performance_schema.global_status
  WHERE variable_name = 'Innodb_rows_inserted';
```

**Duration estimates** (rough; varies by disk I/O, row size, write load):

| Tool | Typical speed | 10M rows | 100M rows | 500M rows |
|------|--------------|----------|-----------|-----------|
| pt-osc (default chunk 1000) | 200k–1M rows/min | 10–50 min | 1–8 h | 8–40 h |
| gh-ost (chunk 1000, auto-tune) | 300k–2M rows/min | 5–30 min | 1–6 h | 5–30 h |
| INPLACE online DDL | 5–50 GB/h | minutes | 1–3 h | 3–15 h |

**Rule:** always measure on a production-sized replica before running on primary. 1 hour on a 64GB RAM replica ≠ 1 hour on a loaded primary.

```bash
# Dry-run on replica to measure actual throughput (no writes to production)
gh-ost \
  --host=replica1 --user=root --password=rootpass \
  --database=shopdb --table=orders \
  --alter="ADD COLUMN notes TEXT" \
  --test-on-replica \           # runs against replica, stops at cutover
  --exact-rowcount \            # COUNT(*) for accurate ETA
  --chunk-size=1000 \
  --execute
# Watch output: "ETA: 2h14m  rows: 3,821,000/45,000,000 (8.5%)"
```

---

### Step 4: Run pt-online-schema-change

```bash
# Dry run first — prints what it would do, touches nothing
pt-online-schema-change \
  --host=mysql-primary --user=root --password=rootpass \
  --database=shopdb \
  --table=orders \
  --alter="ADD COLUMN notes TEXT" \
  --dry-run

# Actual run with safety flags
pt-online-schema-change \
  --host=mysql-primary --user=root --password=rootpass \
  --database=shopdb \
  --table=orders \
  --alter="ADD COLUMN notes TEXT" \
  --chunk-size=1000 \           # rows per chunk (start conservative)
  --chunk-time=0.5 \            # target 0.5s per chunk (auto-adjusts chunk-size)
  --max-lag=5 \                 # pause if any replica is >5s behind
  --check-interval=5 \          # check replica lag every 5s
  --critical-load="Threads_running=50" \   # abort if load too high
  --max-load="Threads_running=25" \         # pause if load too high
  --set-vars="lock_wait_timeout=5" \        # don't wait >5s for MDL on cutover
  --no-drop-old-table \         # keep _orders_old for manual verification
  --execute

# Progress output:
# Copied rows: 50000/458000 (10.9%), 8000 rows/s, ETA 51s
# Copying rows...  100% 00:00 remain
# Swapping tables...
# Dropped triggers...
```

**pt-osc what happens under the hood:**

```
1. Creates _orders_new (copy of schema + your ALTER applied)
2. Adds 3 triggers on orders: AFTER INSERT/UPDATE/DELETE → replicate to _orders_new
3. Copies existing rows in chunks: INSERT INTO _orders_new SELECT ... FROM orders LIMIT chunk-size
4. When copy is 100%, atomically renames: orders → _orders_old, _orders_new → orders
5. Drops triggers. Optionally drops _orders_old.
```

**Abort pt-osc** mid-run: `Ctrl+C` — it cleans up triggers and temp table automatically.

---

### Step 5: Run gh-ost

```bash
# Full production run
gh-ost \
  --host=mysql-primary --user=root --password=rootpass \
  --database=shopdb \
  --table=orders \
  --alter="ADD COLUMN notes TEXT" \
  --chunk-size=1000 \
  --max-lag-millis=1500 \         # pause if any replica lag > 1.5s
  --throttle-control-replicas="replica1,replica2" \  # watch these replicas
  --max-load="Threads_running=30" \
  --critical-load="Threads_running=80" \
  --serve-socket-file=/tmp/gh-ost.sock \   # control socket
  --postpone-cut-over-flag-file=/tmp/gh-ost.postpone \  # delay final cutover
  --ok-to-drop-table \
  --exact-rowcount \
  --verbose \
  --execute

# Progress output:
# [migrating] 2026/04/05 12:00:00 copy iteration 4500/45231; eta: 01:12:33; ETA: 13:12:33;
#   copied rows: 4,500,000; backlog: 0/100; lag: 0.3s
```

**Control gh-ost mid-run via the socket:**

```bash
# Pause migration (e.g. during peak traffic)
echo throttle | nc -U /tmp/gh-ost.sock

# Resume
echo no-throttle | nc -U /tmp/gh-ost.sock

# Change chunk-size on the fly
echo chunk-size=500 | nc -U /tmp/gh-ost.sock

# Delay final table cutover (gives you time to verify)
touch /tmp/gh-ost.postpone          # create flag file before running
# migration copies rows but waits at 100% — verify app still works
rm /tmp/gh-ost.postpone             # remove flag → cutover proceeds

# Abort completely (drops ghost table, no changes to original)
echo panic | nc -U /tmp/gh-ost.sock
```

**gh-ost what happens under the hood:**

```
1. Creates _orders_ghc (changelog table) and _orders_gho (shadow table with ALTER)
2. Connects to binlog stream on primary
3. Copies existing rows in chunks to _orders_gho
4. Simultaneously applies binlog events to _orders_gho (no triggers)
5. When copy is done, waits for binlog to catch up (lag → 0)
6. Atomic cutover: brief MDL (~0.5s), renames orders → _orders_del, _orders_gho → orders
7. Drops _orders_del and _orders_ghc
```

---

### Step 6: Monitor during the change

Open these terminals while any large schema change runs:

```sql
-- Terminal 1: watch MDL (metadata lock) waits — anything waiting on the migrated table?
SELECT
  r.trx_mysql_thread_id                        AS waiting_thread,
  r.trx_query                                  AS waiting_query,
  b.trx_mysql_thread_id                        AS blocked_by,
  b.trx_query                                  AS blocker,
  TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_sec
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id;
```

```sql
-- Terminal 2: replication lag on all replicas (pause pt-osc/gh-ost if > 5s)
SELECT @@hostname, Seconds_Behind_Source FROM performance_schema.replication_applier_status_by_worker\G
-- or simpler:
SHOW REPLICA STATUS\G   -- look for Seconds_Behind_Source
```

```sql
-- Terminal 3: disk usage — schema changes can temporarily double table size
SELECT
  table_name,
  ROUND((data_length + index_length) / 1024 / 1024, 0) AS total_mb,
  ROUND(data_free              / 1024 / 1024, 0) AS free_mb
FROM information_schema.tables
WHERE table_schema = 'shopdb'
ORDER BY data_length DESC;
```

```bash
# Terminal 4: watch disk at OS level
iostat -xm 2   # watch %util and await on MySQL data disk
df -h /var/lib/mysql
```

**Stop thresholds:**
- Replication lag > 10s → pause (gh-ost auto-pauses; pt-osc auto-pauses with `--max-lag`)
- `Threads_running` > 30 sustained → pause
- Disk usage > 85% → stop immediately, free space before continuing

---

### Schema Change Checklist (MySQL) `[A]`

- [ ] Checked `ALGORITHM=INSTANT` — fastest, no risk
- [ ] Checked `ALGORITHM=INPLACE, LOCK=NONE` — brief MDL only
- [ ] If COPY needed: chose pt-osc or gh-ost based on table size/write rate
- [ ] Table row count and size measured (`information_schema.tables`)
- [ ] Duration estimated on staging with production-sized data
- [ ] Pre-migration snapshot taken (`aws rds create-db-snapshot` or `mysqldump`)
- [ ] Application code backward-compatible with both old and new schema
- [ ] gh-ost postpone flag set — do NOT auto-cutover on first attempt
- [ ] Replica lag monitoring terminal open
- [ ] Disk usage terminal open
- [ ] Replication lag thresholds configured (`--max-lag` / `--max-lag-millis`)
- [ ] Runbook documented: what to do if abort is needed

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Performance Tuning](performance.md) — index creation
- [Backup & Recovery](backup-recovery.md) — always backup before major migrations
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-online-schema-change
- [Platform: CI/CD](../platform/cicd.md) — migrations in deployment pipelines
