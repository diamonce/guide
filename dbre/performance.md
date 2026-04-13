# MySQL Performance Tuning

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Performance Workflow `[B]`

```
Measure → Identify bottleneck → Hypothesize → Change → Measure again
```

Never tune blind. Start with data:
1. Enable slow query log or query Performance Schema
2. Find the worst queries by **total time** (calls × avg), not just slowest single query
3. Read the execution plan with `EXPLAIN`
4. Add or fix the index
5. Verify with `EXPLAIN` again and check Performance Schema after a load window

---

## Slow Query Log `[B]`

### Enable

```sql
-- Check current state
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- Enable at runtime (no restart needed)
SET GLOBAL slow_query_log       = 'ON';
SET GLOBAL long_query_time      = 1;          -- seconds; use 0.1 for sub-second
SET GLOBAL log_queries_not_using_indexes = 'ON';   -- catch full scans even if fast
SET GLOBAL min_examined_row_limit = 100;      -- skip trivial 1-row lookups

-- Persist in my.cnf / config file:
-- slow_query_log      = 1
-- slow_query_log_file = /var/log/mysql/slow.log
-- long_query_time     = 1
-- log_queries_not_using_indexes = 1
```

### Analyze with pt-query-digest

```bash
# Top queries by total time — the only view that matters for load
pt-query-digest /var/log/mysql/slow.log

# Filter to one schema
pt-query-digest --filter '$event->{db} eq "shopdb"' /var/log/mysql/slow.log

# Last hour only
pt-query-digest --since 3600 /var/log/mysql/slow.log

# Output to a table for historical tracking
pt-query-digest --review h=127.0.0.1,D=percona,t=query_review \
  --history h=127.0.0.1,D=percona,t=query_history \
  /var/log/mysql/slow.log
```

**Read the pt-query-digest report:**
```
# Query 1: 45% of total, 10234 calls, avg 0.8s, worst 5.2s, p99 2.1s
# Attribute    pct   total     min    max    avg     95%  stddev  median
# ============ === ======= ======= ====== ====== ======= ======= =======
# Exec time     45   2289s   100ms   5.2s  0.8s    2.1s    0.6s   0.7s
# Rows examine  78   84.2G  10.00  1.00M   8.2k  500.0k   99.k   3.0k
# Rows sent      2   45.2k      1    100    4.4      35      9      2
SELECT o.*, c.name FROM orders o JOIN customers c ON...
```

`Rows examined / Rows sent` ratio is the key signal — 8,200 rows examined to return 4 rows means a missing or poor index.

---

## Query the Slow Log in SQL `[I]`

You don't need to parse log files. MySQL's Performance Schema and `sys` schema let you query slow queries directly — works even with slow log disabled.

### Enable Performance Schema (usually on by default in MySQL 8)

```sql
SHOW VARIABLES LIKE 'performance_schema';
-- If OFF, add performance_schema=ON to my.cnf and restart

-- Enable statement instrumentation
UPDATE performance_schema.setup_instruments
SET ENABLED='YES', TIMED='YES'
WHERE NAME LIKE 'statement/%';

UPDATE performance_schema.setup_consumers
SET ENABLED='YES'
WHERE NAME IN ('events_statements_summary_by_digest',
               'events_statements_history_long');
```

### Top queries by total time

```sql
-- Raw Performance Schema
SELECT
    ROUND(SUM_TIMER_WAIT/1e12, 2)           AS total_sec,
    COUNT_STAR                               AS calls,
    ROUND(AVG_TIMER_WAIT/1e9, 1)            AS avg_ms,
    ROUND(MAX_TIMER_WAIT/1e9, 1)            AS max_ms,
    ROUND(SUM_ROWS_EXAMINED/COUNT_STAR)     AS avg_rows_examined,
    ROUND(SUM_ROWS_SENT/COUNT_STAR, 1)      AS avg_rows_sent,
    SCHEMA_NAME                              AS db,
    LEFT(DIGEST_TEXT, 120)                  AS query
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME IS NOT NULL
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;
```

### sys schema views (easier)

```sql
-- Top queries by total latency (sys wraps the raw P_S tables)
SELECT * FROM sys.statement_analysis LIMIT 20;

-- Queries doing full table scans
SELECT db, query, exec_count, total_latency, rows_examined_avg, rows_sent_avg
FROM sys.statements_with_full_table_scans
ORDER BY total_latency DESC
LIMIT 20;

-- Queries causing temp tables on disk (memory spill)
SELECT db, query, exec_count, total_latency, disk_tmp_tables, memory_tmp_tables
FROM sys.statements_with_temp_tables
WHERE disk_tmp_tables > 0
ORDER BY disk_tmp_tables DESC
LIMIT 20;

-- Queries with filesort (ORDER BY not covered by index)
SELECT db, query, exec_count, total_latency, sort_merge_passes
FROM sys.statements_with_sorting
ORDER BY sort_merge_passes DESC
LIMIT 20;

-- Queries with no good index (rows_examined >> rows_sent)
SELECT db, query, exec_count,
       rows_examined_avg, rows_sent_avg,
       ROUND(rows_examined_avg / NULLIF(rows_sent_avg, 0)) AS examine_to_send_ratio,
       total_latency
FROM sys.statement_analysis
WHERE rows_examined_avg / NULLIF(rows_sent_avg, 0) > 100
ORDER BY total_latency DESC
LIMIT 20;

-- Tables with the most full scans
SELECT object_schema, object_name, count_read,
       count_fetch, count_full_scan
FROM sys.schema_table_statistics
ORDER BY count_full_scan DESC
LIMIT 20;

-- Missing indexes — tables where queries aren't using any index
SELECT * FROM sys.schema_tables_with_full_table_scans
ORDER BY rows_full_scanned DESC
LIMIT 20;
```

### Reset statistics

```sql
-- Flush accumulated P_S stats (do before a new measurement window)
TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;
```

---

## EXPLAIN in MySQL `[I]`

### Basic usage

```sql
-- Show plan (does not execute the query)
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;

-- FORMAT=JSON for more detail
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE customer_id = 42;

-- EXPLAIN ANALYZE — executes and shows actual vs estimated rows (MySQL 8.0.18+)
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;
```

### Reading EXPLAIN output

| Column | What to look for |
|--------|-----------------|
| `type` | Access method — see below |
| `key` | Index used (`NULL` = no index) |
| `key_len` | How many bytes of the index are used |
| `rows` | Estimated rows MySQL will examine |
| `filtered` | % of rows passing WHERE after index |
| `Extra` | `Using filesort`, `Using temporary`, `Using index` |

**`type` column — from best to worst:**

| type | Meaning |
|------|---------|
| `system` | Single row, system table |
| `const` | Primary key or unique key equality |
| `eq_ref` | Unique index join (one row per join row) |
| `ref` | Non-unique index equality |
| `range` | Index range scan (BETWEEN, IN, >, <) |
| `index` | Full index scan — reads every index leaf |
| `ALL` | **Full table scan — fix this** |

**`Extra` red flags:**
- `Using filesort` — ORDER BY not covered by an index; MySQL sorts in memory/disk
- `Using temporary` — GROUP BY or DISTINCT creating a temp table
- `Using join buffer (Block Nested Loop)` — join has no index on the inner table

**`Extra` good signs:**
- `Using index` — covering index; no table row access needed
- `Using index condition` — index condition pushdown, fewer row fetches

### Example: spot the problem and fix it

```sql
-- Bad: type=ALL, key=NULL, rows=500000, Extra: Using filesort
EXPLAIN SELECT id, total FROM orders
WHERE status = 'pending' ORDER BY created_at DESC LIMIT 10;

-- Add composite index (equality first, range/sort last)
ALTER TABLE orders ADD INDEX idx_status_created (status, created_at DESC);

-- Good: type=ref, key=idx_status_created, rows=~200, Extra: Using index
EXPLAIN SELECT id, total FROM orders
WHERE status = 'pending' ORDER BY created_at DESC LIMIT 10;
```

---

## Building Indexes from Slow Query Analysis `[I]`

### The workflow

```
1. Find slow query (P_S / pt-query-digest)
2. EXPLAIN the query
3. Read the WHERE / JOIN / ORDER BY / GROUP BY clauses
4. Design the index: equality cols → range cols → sort cols
5. Verify with EXPLAIN — look for type=ref/range and Using index
6. Create online (ALGORITHM=INPLACE for InnoDB, or pt-osc for large tables)
7. Monitor with P_S after traffic picks up
```

### Step 1 — Find the candidate

```sql
-- From P_S: worst by total time with high examine/send ratio
SELECT DIGEST, LEFT(DIGEST_TEXT, 200) AS query,
       COUNT_STAR AS calls,
       ROUND(SUM_TIMER_WAIT/1e12, 1) AS total_sec,
       ROUND(SUM_ROWS_EXAMINED/COUNT_STAR) AS avg_examined,
       ROUND(SUM_ROWS_SENT/COUNT_STAR, 1) AS avg_sent
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = 'shopdb'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
```

### Step 2 — Understand existing indexes

```sql
-- See all indexes on the table
SHOW INDEX FROM orders;

-- Or more detail via information_schema
SELECT INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME, CARDINALITY, NON_UNIQUE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'shopdb' AND TABLE_NAME = 'orders'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;
```

### Step 3 — Design the index

Rules for composite index column order:

```
1. Equality columns first   (WHERE status = 'active')
2. Range columns next       (WHERE created_at > '2024-01-01')
3. Sort column last         (ORDER BY created_at DESC)
4. Include SELECT columns   (to make it covering — avoid table row fetch)
```

```sql
-- Query to index:
SELECT id, total, customer_id
FROM orders
WHERE status = 'active'
  AND region = 'us-east'
  AND created_at > NOW() - INTERVAL 30 DAY
ORDER BY created_at DESC
LIMIT 20;

-- Index design:
--   status  = equality → first
--   region  = equality → second
--   created_at = range + sort → third
--   id, total, customer_id = SELECT cols → covering via INCLUDE alternative (use composite)
CREATE INDEX idx_orders_status_region_created
ON orders (status, region, created_at);
-- If the SELECT cols fit, add them to make it covering:
-- (status, region, created_at, id, total, customer_id)
```

### Step 4 — Verify with EXPLAIN before creating

```sql
-- Force MySQL to evaluate which index it would pick if it existed
-- (use SELECT in a subquery or hint to test the direction)
EXPLAIN SELECT id, total, customer_id
FROM orders
WHERE status = 'active' AND region = 'us-east'
  AND created_at > NOW() - INTERVAL 30 DAY
ORDER BY created_at DESC
LIMIT 20;
-- Look at type, rows, Extra before adding the index
-- Then create → run EXPLAIN again → compare rows and Extra
```

### Step 5 — Create online (non-blocking)

```sql
-- InnoDB INPLACE: doesn't copy table, brief metadata lock only at start/end
-- Safe for most index additions in MySQL 8
ALTER TABLE orders
  ADD INDEX idx_orders_status_region_created (status, region, created_at),
  ALGORITHM=INPLACE, LOCK=NONE;

-- Large tables (100M+ rows): use pt-online-schema-change to avoid blocking
-- pt-osc builds the index on a shadow copy and hot-swaps with a brief lock
pt-online-schema-change \
  --host=127.0.0.1 --user=root --password=rootpass \
  --alter "ADD INDEX idx_orders_status_region_created (status, region, created_at)" \
  D=shopdb,t=orders --execute
```

### Step 6 — Monitor impact

```sql
-- After a traffic window, check if the index is being used
SELECT INDEX_NAME, COUNT(*) AS times_used
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'shopdb' AND OBJECT_NAME = 'orders'
GROUP BY INDEX_NAME
ORDER BY times_used DESC;

-- Verify the query is now using it
SELECT DIGEST_TEXT, COUNT_STAR,
       ROUND(AVG_TIMER_WAIT/1e9, 1) AS avg_ms_now
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT LIKE '%orders%status%'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 5;
```

### Finding and dropping unused indexes

```sql
-- Indexes with zero reads since last restart (candidates for removal)
SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME,
       COUNT_READ, COUNT_WRITE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE INDEX_NAME IS NOT NULL
  AND COUNT_READ = 0
  AND OBJECT_SCHEMA NOT IN ('mysql', 'sys', 'performance_schema')
ORDER BY OBJECT_SCHEMA, OBJECT_NAME;

-- pt-duplicate-key-checker: finds redundant and duplicate indexes
pt-duplicate-key-checker --host=127.0.0.1 --user=root --password=rootpass

-- Drop an unused index online
ALTER TABLE orders DROP INDEX idx_old_status, ALGORITHM=INPLACE, LOCK=NONE;
```

---

## MySQL Index Types `[I]`

| Type | Syntax | Use case |
|------|--------|---------|
| B-tree (default) | `INDEX (col)` | Equality, range, ORDER BY |
| Composite | `INDEX (a, b, c)` | Multi-column WHERE / ORDER BY |
| Covering | `INDEX (a, b, c)` where c = SELECT col | Avoid table row fetch entirely |
| Prefix | `INDEX (col(20))` | Long VARCHAR/TEXT columns |
| Unique | `UNIQUE INDEX (col)` | Constraint + fast lookup |
| Full-text | `FULLTEXT INDEX (col)` | `MATCH ... AGAINST` text search |
| Spatial | `SPATIAL INDEX (col)` | Geometry types |
| Invisible | `ALTER ... INVISIBLE` | Test dropping an index safely |

```sql
-- Invisible index: hide from optimizer without dropping (test impact safely)
ALTER TABLE orders ALTER INDEX idx_status INVISIBLE;
-- verify query plans still work, then drop if confirmed unused
ALTER TABLE orders DROP INDEX idx_status;

-- Prefix index for long strings (only index first N characters)
ALTER TABLE users ADD INDEX idx_email_prefix (email(40));

-- Full-text search
ALTER TABLE products ADD FULLTEXT INDEX idx_desc_ft (description);
SELECT * FROM products WHERE MATCH(description) AGAINST ('wireless keyboard' IN BOOLEAN MODE);
```

---

## InnoDB Configuration `[A]`

Key variables in `my.cnf` — measure before and after changing.

```ini
# ── Memory ────────────────────────────────────────────────────────────────────
# Buffer pool: cache for data pages and indexes. Most important knob.
# Rule: 70–80% of RAM on a dedicated DB server.
innodb_buffer_pool_size         = 12G

# Multiple instances reduce mutex contention (1 per 1G of buffer pool)
innodb_buffer_pool_instances    = 8

# ── Redo log ─────────────────────────────────────────────────────────────────
# Larger log = less checkpoint pressure = better write throughput
# MySQL 8.0.30+: innodb_redo_log_capacity replaces the old file-size params
innodb_redo_log_capacity        = 4G   # MySQL 8.0.30+
# innodb_log_file_size = 1G           # older MySQL

# ── Flush behavior ───────────────────────────────────────────────────────────
# 1 = full ACID (default, safest). 0 or 2 = faster but risk 1s data loss on crash
innodb_flush_log_at_trx_commit  = 1

# O_DIRECT: bypass OS page cache for data files (avoids double buffering)
innodb_flush_method             = O_DIRECT

# ── I/O ──────────────────────────────────────────────────────────────────────
# SSD: set to 2× vCPUs. HDD: 200 is usually fine.
innodb_io_capacity              = 2000
innodb_io_capacity_max          = 4000

# ── Connections ──────────────────────────────────────────────────────────────
max_connections                 = 500   # Use ProxySQL connection pooling; keep this low
thread_cache_size               = 50

# ── Temp tables ──────────────────────────────────────────────────────────────
# Raise if sys.statements_with_temp_tables shows many disk_tmp_tables
tmp_table_size                  = 64M
max_heap_table_size             = 64M

# ── Query cache (MySQL 5.7 only — removed in 8.0) ───────────────────────────
# Don't enable query_cache in 5.7 — global mutex kills concurrency under load
# query_cache_type = 0
```

### Check buffer pool hit rate

```sql
-- Should be > 99% in steady state; if lower, increase innodb_buffer_pool_size
SELECT
    ROUND(
        (1 - (
            (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_reads') /
            (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_read_requests')
        )) * 100, 2
    ) AS buffer_pool_hit_pct;

-- Or via sys schema
SELECT variable_name, variable_value
FROM sys.metrics
WHERE variable_name IN (
    'innodb_buffer_pool_reads',
    'innodb_buffer_pool_read_requests',
    'innodb_buffer_pool_pages_data',
    'innodb_buffer_pool_pages_free'
);
```

### Key status variables to watch

```sql
SELECT variable_name, variable_value
FROM performance_schema.global_status
WHERE variable_name IN (
    'Threads_connected',
    'Threads_running',
    'Slow_queries',
    'Select_full_join',        -- joins with no index = bad
    'Select_scan',             -- full table scans
    'Sort_merge_passes',       -- filesort spill to disk
    'Created_tmp_disk_tables', -- temp table disk spill
    'Innodb_row_lock_waits',
    'Innodb_row_lock_time_avg',
    'Com_select',
    'Com_insert',
    'Com_update',
    'Com_delete'
);
```

---

## Percona Toolkit for Performance `[I]`

```bash
# Identify top queries by total time (parses slow log)
pt-query-digest /var/log/mysql/slow.log

# Queries from a running server via SHOW PROCESSLIST (no log needed)
pt-query-digest --processlist h=127.0.0.1,u=root,p=rootpass --interval 0.5 --run-time 60

# Find redundant and duplicate indexes
pt-duplicate-key-checker --host=127.0.0.1 --user=root --password=rootpass

# Report which indexes are used vs unused (cross-references slow log)
pt-index-usage --host=127.0.0.1 --user=root --password=rootpass \
  /var/log/mysql/slow.log

# Summarize engine stats, buffer pool, key sizes
pt-mysql-summary --host=127.0.0.1 --user=root --password=rootpass
```

→ [percona-toolkit](../resources/percona-toolkit/README.md)

---

## Related Topics

- [SQL Best Practices](sql.md) — anti-patterns, query writing
- [Migrations & Schema Changes](migrations.md) — online index creation with pt-osc / gh-ost
- [Observability](observability.md) — Prometheus metrics, Grafana dashboards, alert hierarchy
- [Scaling Databases](scaling.md) — read replicas, ProxySQL connection pooling
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-query-digest, pt-index-usage, pt-osc
