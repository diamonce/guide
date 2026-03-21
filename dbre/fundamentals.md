# Database Reliability Fundamentals

[← DBRE Home](README.md) | [← Main](../README.md)

---

## DBRE Core Responsibilities `[B]`

- **Availability** — databases are up and serving queries
- **Performance** — queries run within acceptable latency
- **Durability** — data is not lost
- **Correctness** — data is consistent and trustworthy
- **Operability** — DBs can be managed, monitored, migrated safely

---

## Database SLOs `[B]`

Databases need their own SLOs, separate from application SLOs:

| SLI | Example Target |
|-----|---------------|
| Availability | 99.95% uptime (22 min/month budget) |
| Query latency (p99) | < 100ms for OLTP queries |
| Replication lag | < 5 seconds |
| Backup success rate | 100% (every backup must succeed) |
| Recovery time | RTO < 4 hours |

→ See [SRE: SLOs / SLIs / SLAs](../sre/slo-sla-sli.md)

---

## Key Metrics to Monitor `[B]`

### PostgreSQL

```sql
-- Active connections
SELECT count(*), state FROM pg_stat_activity GROUP BY state;

-- Long-running queries
SELECT pid, now() - query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - query_start) > interval '5 minutes'
ORDER BY duration DESC;

-- Table bloat / dead rows
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric/nullif(n_live_tup,0)*100, 2) AS dead_pct
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Index usage
SELECT schemaname, tablename, indexname,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;

-- Replication lag
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

### MySQL / Aurora

```sql
-- Show running queries
SHOW PROCESSLIST;
SHOW FULL PROCESSLIST;

-- InnoDB status (locks, transactions)
SHOW ENGINE INNODB STATUS\G

-- Slow queries
SELECT * FROM information_schema.processlist
WHERE time > 30 ORDER BY time DESC;
```

### Key Metrics Dashboard

| Metric | Alert threshold | Tool |
|--------|----------------|------|
| Connection count | > 80% of max_connections | Prometheus pg_exporter |
| Query p99 latency | > 500ms | APM / slow query log |
| Replication lag | > 30s | pg_exporter, CloudWatch |
| CPU utilization | > 80% sustained | CloudWatch, Datadog |
| Disk usage | > 75% | Node exporter |
| Vacuum last run | > 24 hours on busy tables | pg_stat_user_tables |
| Lock waits | Any > 30 seconds | pg_locks |

---

## Connection Pooling `[B]`

**Problem:** Each DB connection costs memory (~5-10MB for PostgreSQL). Applications often create hundreds of connections.

**Solution:** Connection pool — a small set of persistent connections shared across many app instances.

### PgBouncer (PostgreSQL)

```ini
# pgbouncer.ini
[databases]
mydb = host=postgres-primary port=5432 dbname=mydb

[pgbouncer]
pool_mode = transaction    # or session, statement
max_client_conn = 1000
default_pool_size = 20
max_db_connections = 100
```

**Pool modes:**
- `transaction` — connection returned to pool after each transaction (most efficient)
- `session` — connection held for entire session (safer, less efficient)
- `statement` — connection returned after each statement (breaks transactions)

Use `transaction` mode unless you use session-level features (temp tables, advisory locks, `SET` commands).

### ProxySQL (MySQL)

- Connection multiplexing
- Query routing (read/write split)
- Query rules and caching
- Health checks and failover

---

## Locks & Deadlocks `[I]`

### Detecting Locks (PostgreSQL)

```sql
-- Who is waiting for locks?
SELECT
  blocking.pid AS blocking_pid,
  blocked.pid AS blocked_pid,
  blocking.query AS blocking_query,
  blocked.query AS blocked_query,
  blocked.wait_event_type,
  blocked.wait_event
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type = 'Lock';
```

### Killing a Blocking Query

```sql
-- Soft cancel (waits for safe point)
SELECT pg_cancel_backend(pid);

-- Hard terminate (use carefully)
SELECT pg_terminate_backend(pid);
```

### Deadlock Prevention

- Acquire locks in consistent order (always lock table A before table B)
- Keep transactions short
- Use `NOWAIT` or `SKIP LOCKED` for queue processing
- Avoid long transactions that hold locks

---

## ACID Properties `[B]`

| Property | Meaning |
|----------|---------|
| **Atomicity** | Transaction is all-or-nothing |
| **Consistency** | DB moves from one valid state to another |
| **Isolation** | Concurrent transactions don't see each other's partial work |
| **Durability** | Committed data persists even after crash |

### Isolation Levels

| Level | Prevents | Allows |
|-------|---------|--------|
| Read Uncommitted | — | Dirty reads, non-repeatable reads, phantoms |
| Read Committed | Dirty reads | Non-repeatable reads, phantoms |
| Repeatable Read | Dirty + non-repeatable reads | Phantoms |
| Serializable | All anomalies | — (lowest throughput) |

PostgreSQL default: **Read Committed**. Use **Repeatable Read** or **Serializable** for financial/critical data.

---

## Percona Toolkit `[I]`

Percona Toolkit provides battle-tested tools for MySQL/PostgreSQL operations.

→ [percona-toolkit](../resources/percona-toolkit/README.md)

```bash
# Check for duplicate indexes
pt-duplicate-key-checker --host=db.example.com

# Analyze slow query log
pt-query-digest /var/log/mysql/slow.log

# Online schema change (zero-downtime ALTER TABLE for MySQL)
pt-online-schema-change \
  --alter "ADD INDEX idx_created_at (created_at)" \
  D=mydb,t=orders

# Table checksum (verify replica data matches primary)
pt-table-checksum --host=primary.db.example.com
```

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Performance Tuning](performance.md)
- [Backup & Recovery](backup-recovery.md)
- [Scaling Databases](scaling.md)
- [SRE: Observability](../sre/observability.md)
- [SRE: Incident Management](../sre/incident-management.md)
