# Database Observability

[← DBRE Home](README.md) | [← Main](../README.md)

---

## The Monitoring Stack `[B]`

```
MySQL / PostgreSQL
       │
       ▼
  Exporter (mysqld_exporter / postgres_exporter)
       │  scrapes every 15s
       ▼
  Prometheus  ──────► Alertmanager ──────► PagerDuty / Slack
       │
       ▼
   Grafana
```

For RDS/Aurora replace the exporter with CloudWatch — alert structure is the same.

---

## MySQL: mysqld_exporter `[B]`

```bash
docker run -d \
  -e DATA_SOURCE_NAME="monitoring:password@(localhost:3306)/" \
  -p 9104:9104 \
  prom/mysqld-exporter \
  --collect.info_schema.processlist \
  --collect.info_schema.innodb_metrics \
  --collect.slave_status \
  --collect.binlog_size \
  --no-collect.info_schema.tables   # noisy on large schemas — disable
```

```yaml
# prometheus.yml
scrape_configs:
  - job_name: mysql
    static_configs:
      - targets: ['mysqld-exporter:9104']
        labels:
          cluster: r2d2
          role: primary        # label replicas separately
    scrape_interval: 15s
```

**Monitoring user:**

```sql
CREATE USER 'monitoring'@'%' IDENTIFIED BY 'use-secrets-manager';
GRANT PROCESS, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'monitoring'@'%';
GRANT SELECT ON performance_schema.* TO 'monitoring'@'%';
GRANT SELECT ON sys.* TO 'monitoring'@'%';
FLUSH PRIVILEGES;
```

**Key metrics:**

| Metric | What it measures |
|--------|-----------------|
| `mysql_up` | Is the instance reachable |
| `mysql_global_status_threads_connected` | Current connections |
| `mysql_global_variables_max_connections` | Connection limit |
| `mysql_global_status_threads_running` | Active queries right now |
| `mysql_global_status_slow_queries` | Cumulative slow query count |
| `mysql_global_status_innodb_row_lock_waits` | InnoDB row lock contention |
| `mysql_global_status_innodb_row_lock_time_avg` | Average lock wait time (ms) |
| `mysql_slave_status_seconds_behind_master` | Replication lag (replica only) |
| `mysql_slave_status_slave_io_running` | IO thread running (0 = broken) |
| `mysql_slave_status_slave_sql_running` | SQL thread running (0 = broken) |
| `mysql_global_status_binlog_size` | Binary log disk usage |
| `mysql_global_status_innodb_buffer_pool_read_requests` | Buffer pool reads |
| `mysql_global_status_innodb_buffer_pool_reads` | Disk reads (cache miss) |

---

## MySQL: Alert Hierarchy `[B]`

### Tier 1 — Page Immediately

| Alert | Condition | Why |
|-------|-----------|-----|
| MySQL down | `mysql_up == 0` for > 1 min | Database is down |
| Replication IO thread stopped | `mysql_slave_status_slave_io_running == 0` | Replica not receiving binlog |
| Replication SQL thread stopped | `mysql_slave_status_slave_sql_running == 0` | Replica not applying events |
| Replication lag critical | `mysql_slave_status_seconds_behind_master > 300` | Replica 5+ min behind, unusable for failover |
| Disk > 90% | `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.10` | MySQL will crash when binlog fills disk |
| Connections exhausted | `mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.95` | New connections rejected |
| Backup missing | Last backup timestamp > 25h | RPO breach risk |

### Tier 2 — Investigate Within 1 Hour

| Alert | Condition | Why |
|-------|-----------|-----|
| Replication lag high | `mysql_slave_status_seconds_behind_master > 30` | Replica diverging |
| Replication lag growing | `deriv(mysql_slave_status_seconds_behind_master[10m]) > 0` AND lag > 60s | Replica falling further behind |
| High threads running | `mysql_global_status_threads_running > 20` sustained > 5 min | Query pile-up, possible lock contention |
| Lock wait spike | `rate(mysql_global_status_innodb_row_lock_waits[5m]) > 10` | Competing transactions |
| Long lock wait | `mysql_global_status_innodb_row_lock_time_avg > 5000` (ms) | Queries blocked for > 5s on average |
| Slow query rate rising | `rate(mysql_global_status_slow_queries[5m]) > 1` | New slow queries appearing |
| CPU > 80% sustained | > 10 min | Saturation approaching |
| Disk > 80% | | Trending toward Tier 1 |
| Connection utilization > 80% | | Trending toward Tier 1 |

### Tier 3 — Ticket Within 24 Hours

| Alert | Condition | Why |
|-------|-----------|-----|
| Buffer pool hit ratio degrading | < 95% | Working set no longer fits in memory |
| Binlog disk usage > 50% | | binlog retention eating disk |
| Slow query count week-over-week +20% | | Schema or data distribution change |
| Replica count below expected | | Reduced failover coverage |

### Tier 4 — Weekly Review

| Signal | Why |
|--------|-----|
| Backup size growth rate | Growing faster than data? |
| `Aborted_connects` rising | Connection errors, auth failures |
| `Table_locks_waited` increasing | MyISAM table lock contention (should be near zero on InnoDB) |

---

## MySQL: PromQL Reference `[I]`

### Availability and Connections

```promql
# Is MySQL up?
mysql_up

# Connection utilization %
mysql_global_status_threads_connected
  / mysql_global_variables_max_connections * 100

# Active queries right now (threads_running spikes = pile-up)
mysql_global_status_threads_running

# Connections per second (connection churn)
rate(mysql_global_status_connections[5m])
```

### Replication

```promql
# Replication lag in seconds (run on replica)
mysql_slave_status_seconds_behind_master

# Alert: lag > 30s
mysql_slave_status_seconds_behind_master > 30

# Alert: lag growing monotonically (replica stuck)
deriv(mysql_slave_status_seconds_behind_master[10m]) > 0
  AND mysql_slave_status_seconds_behind_master > 60

# Both threads must be running (0 = problem)
mysql_slave_status_slave_io_running == 0   # IO thread broken
mysql_slave_status_slave_sql_running == 0  # SQL thread broken

# Compare primary and replica positions (bytes behind)
mysql_slave_status_master_log_pos - mysql_slave_status_read_master_log_pos
```

### Query Performance

```promql
# Queries per second
rate(mysql_global_status_queries[5m])

# Slow queries per second
rate(mysql_global_status_slow_queries[5m])

# Slow query ratio
rate(mysql_global_status_slow_queries[5m])
  / rate(mysql_global_status_queries[5m])

# Transaction commits/rollbacks per second
rate(mysql_global_status_handlers_total{handler="commit"}[5m])
rate(mysql_global_status_handlers_total{handler="rollback"}[5m])
```

### InnoDB and Locks

```promql
# Buffer pool hit ratio (target > 99%)
1 - (
  rate(mysql_global_status_innodb_buffer_pool_reads[5m])
  / rate(mysql_global_status_innodb_buffer_pool_read_requests[5m])
)

# Row lock waits per second
rate(mysql_global_status_innodb_row_lock_waits[5m])

# Average row lock wait time (ms) — alert if > 1000ms
mysql_global_status_innodb_row_lock_time_avg

# InnoDB dirty pages ratio
mysql_global_status_innodb_buffer_pool_pages_dirty
  / mysql_global_status_innodb_buffer_pool_pages_total
```

### Disk

```promql
# Disk usage % on /var/lib/mysql
1 - (
  node_filesystem_avail_bytes{mountpoint="/var/lib/mysql"}
  / node_filesystem_size_bytes{mountpoint="/var/lib/mysql"}
)

# Binlog size (bytes)
mysql_global_status_binlog_size
```

---

## MySQL: Alerting Rules `[I]`

```yaml
# prometheus/alerts/mysql.yml
groups:
  - name: mysql_availability
    rules:
      - alert: MySQLDown
        expr: mysql_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MySQL down on {{ $labels.instance }}"
          runbook: "wiki.internal/dbre/runbooks/mysql-down"

      - alert: MySQLConnectionsExhausted
        expr: >
          mysql_global_status_threads_connected
          / mysql_global_variables_max_connections > 0.90
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "MySQL connections at {{ $value | humanizePercentage }} on {{ $labels.instance }}"

  - name: mysql_replication
    rules:
      - alert: MySQLReplicationIOThreadDown
        expr: mysql_slave_status_slave_io_running == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication IO thread stopped on {{ $labels.instance }}"
          runbook: "wiki.internal/dbre/runbooks/replication-broken"

      - alert: MySQLReplicationSQLThreadDown
        expr: mysql_slave_status_slave_sql_running == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication SQL thread stopped on {{ $labels.instance }}"

      - alert: MySQLReplicationLagHigh
        expr: mysql_slave_status_seconds_behind_master > 30
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag {{ $value }}s on {{ $labels.instance }}"

      - alert: MySQLReplicationLagCritical
        expr: mysql_slave_status_seconds_behind_master > 300
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag CRITICAL {{ $value }}s — replica unusable for failover"

      - alert: MySQLReplicaStuck
        expr: >
          deriv(mysql_slave_status_seconds_behind_master[10m]) > 0
          AND mysql_slave_status_seconds_behind_master > 120
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Replica falling further behind — may be stuck"
```

---

## MySQL: Diagnosing Alerts `[I]`

### MySQL down

```bash
systemctl status mysql
journalctl -u mysql -n 50

# Check mount — common cause after instance reset
lsblk
cat /var/lib/mysql/mysql-bin.index   # paths must show /var/lib/mysql/
```

### Replication broken

```sql
-- Check both thread states and last error
SHOW SLAVE STATUS\G

-- Key fields to check:
-- Slave_IO_Running: Yes
-- Slave_SQL_Running: Yes
-- Seconds_Behind_Master: <number>
-- Last_IO_Error: (empty = good)
-- Last_SQL_Error: (empty = good)

-- If SQL thread stopped due to error, skip one event (use carefully):
STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1; START SLAVE;
```

### High threads_running / lock waits

```sql
-- What is running right now?
SELECT id, user, host, db, time, state, LEFT(info, 100) AS query
FROM information_schema.processlist
WHERE command != 'Sleep'
ORDER BY time DESC;

-- Who is blocking who?
SELECT
  r.trx_id AS waiting_trx,
  r.trx_mysql_thread_id AS waiting_thread,
  b.trx_id AS blocking_trx,
  b.trx_mysql_thread_id AS blocking_thread,
  b.trx_query AS blocking_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;

-- Kill a blocking query
KILL <blocking_thread_id>;
```

### Slow queries

```sql
-- Top slow queries (requires slow_query_log = ON or performance_schema)
SELECT
  digest_text,
  count_star AS calls,
  round(avg_timer_wait / 1e9, 2) AS avg_ms,
  round(sum_timer_wait / 1e9, 2) AS total_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC
LIMIT 10;
```

---

## Grafana Dashboard Structure `[I]`

### Dashboard 1: MySQL Overview

```
Row 1 — Health
  [Stat] mysql_up    [Stat] Replica lag (max)    [Stat] Threads running

Row 2 — Connections
  [Graph] threads_connected over time
  [Gauge] Connection utilization %

Row 3 — Throughput
  [Graph] Queries/sec    [Graph] Slow queries/sec
  [Graph] Commits/sec    [Graph] Rollbacks/sec

Row 4 — InnoDB
  [Graph] Buffer pool hit ratio (target > 99%)
  [Graph] Row lock waits/sec    [Stat] Avg lock wait ms

Row 5 — Replication
  [Graph] Seconds_behind_master per replica
  [Stat] IO thread    [Stat] SQL thread

Row 6 — Disk
  [Graph] /var/lib/mysql disk usage %
  [Graph] Binlog size
```

### Dashboard 2: Replication Health

```
Row 1 — [Graph] Per-replica lag (one line per replica)
Row 2 — [Stat] IO thread running per replica
Row 3 — [Stat] SQL thread running per replica
Row 4 — [Graph] Replica queries/sec (read load distribution)
```

---

## PostgreSQL: Key Differences `[B]`

For PostgreSQL, use `postgres_exporter` instead. Core differences from MySQL monitoring:

| Concern | MySQL metric | PostgreSQL metric |
|---------|-------------|------------------|
| DB up | `mysql_up` | `pg_up` |
| Connections | `mysql_global_status_threads_connected` | `pg_stat_activity_count` |
| Replication lag | `mysql_slave_status_seconds_behind_master` | `pg_replication_lag` |
| Lock waits | `mysql_global_status_innodb_row_lock_waits` | `pg_locks_count{granted="false"}` |
| Cache hit | InnoDB buffer pool hit ratio | `pg_stat_database_blks_hit / (blks_hit + blks_read)` |
| Slow queries | `performance_schema` | `pg_stat_statements` (extension) |

PostgreSQL-specific: watch `n_dead_tup` (bloat) and autovacuum lag — no MySQL equivalent.

---

## Tool Comparison `[B]`

| Tool | Best for | Limitations |
|------|----------|-------------|
| Prometheus + Grafana | Self-managed, EC2-hosted, full control | Setup overhead |
| CloudWatch | RDS / Aurora, zero setup | Limited granularity, cost at scale |
| Datadog | Unified app + DB + infra | Cost, vendor lock-in |
| RDS Performance Insights | Deep query analysis on RDS/Aurora | RDS-only |
| PMM (Percona Monitoring) | MySQL/PostgreSQL, open-source, rich DB UI | Self-hosted overhead |
| `pt-query-digest` | Offline slow log analysis | Not real-time |
| `mytop` / `innotop` | Live MySQL process monitor (like `top`) | Terminal only, no history |

**PMM (Percona Monitoring and Management)** is worth considering for MySQL-heavy environments —
it wraps mysqld_exporter + Grafana dashboards + query analytics in one self-hosted package.

---

## Related Topics

- [Fundamentals](fundamentals.md#key-metrics-to-monitor) — raw monitoring SQL
- [HA & Failover](ha-failover.md) — replication topology and failover monitoring
- [Backup & Recovery](backup-recovery.md) — backup success alerting
- [SRE: Observability](../sre/observability.md) — application-level observability
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-query-digest, pt-slave-delay
