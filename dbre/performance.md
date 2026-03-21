# Database Performance Tuning

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Performance Workflow `[B]`

```
Measure → Identify bottleneck → Hypothesize → Change → Measure again
```

Never tune blind. Start with data:
1. Enable slow query log
2. Identify the worst queries by total time (not just longest individual)
3. Understand the execution plan
4. Apply targeted fix
5. Verify improvement

---

## Slow Query Log `[B]`

### PostgreSQL

```sql
-- Show current setting
SHOW log_min_duration_statement;

-- Set in postgresql.conf or at runtime
ALTER SYSTEM SET log_min_duration_statement = '1000';  -- log queries > 1 second
SELECT pg_reload_conf();

-- Or use pg_stat_statements extension (better for production)
CREATE EXTENSION pg_stat_statements;

-- Top 10 queries by total time
SELECT
    round(total_exec_time::numeric, 2) AS total_ms,
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS pct,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### MySQL

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;

-- Analyze with Percona's pt-query-digest
-- pt-query-digest /var/log/mysql/slow.log
```

→ [percona-toolkit](../resources/percona-toolkit/README.md)

---

## EXPLAIN / EXPLAIN ANALYZE `[I]`

Read the execution plan to understand what the database is doing.

```sql
-- Show plan without executing
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;

-- Execute and show actual timings
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders WHERE customer_id = 42;
```

### Reading EXPLAIN Output

```
Seq Scan on orders  (cost=0.00..4500.00 rows=1 width=64) (actual time=0.05..85.3 rows=1 loops=1)
  Filter: (customer_id = 42)
  Rows Removed by Filter: 89999
```

**Red flags:**
- `Seq Scan` on large tables (should be Index Scan)
- High `Rows Removed by Filter` (index missing or not selective)
- `Hash Join` on huge datasets (check join conditions and indexes)
- `Sort` without index support (for ORDER BY or GROUP BY)
- High `loops` count in nested loops

**Good signs:**
- `Index Scan` or `Index Only Scan`
- Low `rows` estimates matching actual rows
- `Bitmap Index Scan` for range queries with many results

### Online EXPLAIN Visualizer

Use [explain.dalibo.com](https://explain.dalibo.com) to visualize complex plans.

---

## Indexing `[I]`

### Index Types

| Type | Use case |
|------|---------|
| B-tree (default) | Equality, range queries, ORDER BY |
| Hash | Equality only (rarely better than B-tree) |
| GIN | Array contains, JSONB, full-text search |
| GiST | Geometric data, ranges, full-text |
| BRIN | Very large tables with sequential data (timestamps) |
| Partial | Index a subset of rows |
| Composite | Multi-column queries |

### When to Add an Index

Add an index when a query:
- Filters by a column in WHERE
- Joins on a column
- Orders by a column (for ORDER BY without sort)
- Groups by a column (GROUP BY)

### Index Creation (Non-Blocking)

```sql
-- BLOCKS table writes (don't use in production without maintenance window)
CREATE INDEX idx_orders_customer ON orders(customer_id);

-- CONCURRENT: doesn't block writes, takes longer
CREATE INDEX CONCURRENTLY idx_orders_customer ON orders(customer_id);
```

### Composite Index Column Order

```sql
-- Query: WHERE status = 'active' AND created_at > '2024-01-01'
-- Index should match the most selective column first
CREATE INDEX CONCURRENTLY idx_orders_status_created
ON orders(status, created_at);

-- Rule: equality conditions before range conditions in composite index
```

### Covering Index (Index Only Scan)

```sql
-- Include all columns needed by the query in the index
-- Avoids table heap access entirely
CREATE INDEX CONCURRENTLY idx_orders_covering
ON orders(customer_id)
INCLUDE (total, status, created_at);

-- Query can be satisfied from index alone:
SELECT total, status, created_at
FROM orders
WHERE customer_id = 42;
```

### Partial Index

```sql
-- Index only active orders (if 90% are completed, this is much smaller)
CREATE INDEX CONCURRENTLY idx_active_orders
ON orders(customer_id)
WHERE status = 'active';
```

### Finding Unused Indexes

```sql
-- Indexes not used since last stats reset
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY schemaname, tablename;
```

Unused indexes waste write performance and disk space. Drop them.

---

## Query Optimization Techniques `[I]`

### Join Order and Type

The database should pick the best join order, but you can hint:

```sql
-- Check if join is using indexes on both sides
EXPLAIN ANALYZE
SELECT o.*, c.name
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.created_at > NOW() - INTERVAL '7 days';
-- Make sure: idx on orders(created_at), idx on customers(id)
```

### JSONB Indexing

```sql
-- GIN index on JSONB column
CREATE INDEX CONCURRENTLY idx_metadata_gin
ON events USING GIN(metadata);

-- For specific key access:
CREATE INDEX CONCURRENTLY idx_metadata_user_id
ON events ((metadata->>'user_id'));

-- Query using the index
SELECT * FROM events WHERE metadata->>'user_id' = '12345';
```

### Materialized Views

```sql
-- Pre-compute expensive aggregations
CREATE MATERIALIZED VIEW daily_revenue AS
SELECT
    created_at::date AS day,
    SUM(total) AS revenue,
    COUNT(*) AS order_count
FROM orders
GROUP BY 1;

-- Refresh (can be scheduled)
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_revenue;
```

---

## Vacuum & Table Bloat `[I]`

PostgreSQL uses MVCC — old row versions are kept until VACUUM reclaims them. Without proper vacuuming, tables bloat.

```sql
-- Check autovacuum status
SELECT relname, last_autovacuum, last_autoanalyze, n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Manual vacuum (doesn't block, but slow)
VACUUM ANALYZE orders;

-- Full vacuum (rewrites table, BLOCKS all access — use carefully)
VACUUM FULL orders;

-- Autovacuum tuning for busy tables in postgresql.conf
ALTER TABLE orders SET (
  autovacuum_vacuum_scale_factor = 0.01,   -- vacuum at 1% dead rows (default 20%)
  autovacuum_analyze_scale_factor = 0.005
);
```

---

## PostgreSQL Configuration Tuning `[A]`

Key parameters in `postgresql.conf`:

```ini
# Memory
shared_buffers = 25% of RAM        # Page cache
effective_cache_size = 75% of RAM  # Planner hint for OS cache
work_mem = 64MB                    # Per sort/hash operation (can multiply by connections)
maintenance_work_mem = 512MB       # VACUUM, CREATE INDEX

# WAL / Checkpoints
wal_buffers = 64MB
checkpoint_completion_target = 0.9
max_wal_size = 4GB

# Connections
max_connections = 200              # Keep low, use PgBouncer

# Planner
random_page_cost = 1.1             # SSD: lower than default 4.0
effective_io_concurrency = 200     # SSD: how many concurrent IO requests
```

Use [PGTune](https://pgtune.leopard.in.ua/) for a starting configuration based on your hardware.

---

## Percona Toolkit for Performance `[I]`

From [percona-toolkit](../resources/percona-toolkit/README.md) — production-grade MySQL/PostgreSQL tools:

```bash
# Identify top queries by total time, calls, avg time
pt-query-digest /var/log/mysql/slow.log

# Find redundant indexes wasting write performance
pt-duplicate-key-checker --host=db.example.com --user=dba

# Check index usage (which indexes are actually being used)
pt-index-usage --host=db.example.com /var/log/mysql/slow.log

# Summarize table sizes, row counts, engine stats
pt-table-usage --host=db.example.com

# Collect system performance metrics during an issue
pt-stalk --function status --variable Threads_running --threshold 20
```

**pt-query-digest output explained:**
```
# Query 1: 45% of total time, called 10,234 times, avg 0.8s
# Worst: 5.2s | p99: 2.1s | p95: 1.4s
SELECT o.*, c.name FROM orders o JOIN customers c ON...
```
Focus on queries with high **total time** (calls × avg), not just slowest individual queries.

---

## Related Topics

- [SQL Best Practices](sql.md) — anti-patterns
- [Fundamentals: Monitoring](fundamentals.md#key-metrics-to-monitor)
- [Scaling Databases](scaling.md)
- [Migrations & Schema Changes](migrations.md) — index creation during migrations
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-query-digest, pt-index-usage
