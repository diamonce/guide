# Database Observability

[← DBRE Home](README.md) | [← Main](../README.md)

---

## The Monitoring Stack `[B]`

Database observability is not a single tool — it is a pipeline:

```
PostgreSQL / MySQL
       │
       ▼
  Exporter (postgres_exporter / mysqld_exporter)
       │  scrapes metrics every 15s
       ▼
  Prometheus  ──────────────────► Alertmanager
       │                               │
       ▼                               ▼
   Grafana                         PagerDuty / Slack
  (dashboards)
```

This is the standard pattern for self-managed or EC2-hosted databases. For RDS/Aurora, replace the exporter with CloudWatch — but the alert structure is the same.

---

## Exporters `[B]`

### postgres_exporter

```bash
# Run as a sidecar or separate service
docker run -d \
  -e DATA_SOURCE_NAME="postgresql://monitoring:password@localhost:5432/postgres?sslmode=verify-full" \
  -p 9187:9187 \
  prometheuscommunity/postgres-exporter
```

```yaml
# prometheus.yml — scrape config
scrape_configs:
  - job_name: postgres
    static_configs:
      - targets: ['postgres-exporter:9187']
    scrape_interval: 15s
```

**Required database role for postgres_exporter:**

```sql
CREATE USER monitoring WITH PASSWORD 'use-secrets-manager';
GRANT pg_monitor TO monitoring;       -- PostgreSQL 10+
GRANT CONNECT ON DATABASE postgres TO monitoring;

-- For pg_stat_statements metrics
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO monitoring;
```

**Key metrics exposed:**

| Metric | What it measures |
|--------|-----------------|
| `pg_up` | Is the database reachable |
| `pg_stat_activity_count` | Connections by state |
| `pg_stat_bgwriter_*` | Background writer activity |
| `pg_stat_database_*` | Per-database statistics |
| `pg_stat_user_tables_*` | Table-level stats (scans, rows, bloat) |
| `pg_stat_replication_*` | Replication state and lag |
| `pg_locks_count` | Lock counts by mode |
| `pg_stat_statements_*` | Query performance (requires extension) |

**Disable noisy defaults** — not all collector groups are useful. In `postgres_exporter` config:

```yaml
# Only collect what you'll alert on or dashboard
collectors:
  - pg_stat_user_tables
  - pg_stat_activity
  - pg_stat_bgwriter
  - pg_stat_database
  - pg_stat_replication
  - pg_locks
  - pg_stat_statements  # requires pg_stat_statements extension
```

### mysqld_exporter

```bash
docker run -d \
  -e DATA_SOURCE_NAME="monitoring:password@(localhost:3306)/" \
  -p 9104:9104 \
  prom/mysqld-exporter
```

```sql
-- MySQL monitoring user
CREATE USER 'monitoring'@'localhost' IDENTIFIED BY 'use-secrets-manager';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'monitoring'@'localhost';
GRANT SELECT ON performance_schema.* TO 'monitoring'@'localhost';
```

---

## Alert Hierarchy `[B]`

Four tiers — not everything should page someone at 3am:

### Tier 1 — Page Immediately

Something is broken right now and data is at risk or users are impacted.

| Alert | Condition | Why |
|-------|-----------|-----|
| Primary unreachable | `pg_up == 0` for > 1 min | Database is down |
| Backup failed | Last backup > 25 hours ago | RPO breach risk |
| Replication broken | No replicas or all lagging > 10 min | Replica useless for failover |
| Disk > 90% | `node_filesystem_free_bytes < 10%` | DB will crash on full disk |
| Connection pool exhausted | Connections at 95% of `max_connections` | New connections being rejected |

### Tier 2 — Investigate Within 1 Hour

Degraded but not failing. Will become Tier 1 if ignored.

| Alert | Condition | Why |
|-------|-----------|-----|
| Query p99 latency spike | 3× baseline for > 5 min | Likely a slow query or lock |
| Replication lag > 30s | `pg_stat_replication lag > 30s` | Replica diverging from primary |
| Disk > 80% | | Trending toward Tier 1 |
| CPU > 80% sustained | > 10 min | Saturation approaching |
| Lock wait > 30s | `pg_locks_count{mode="ExclusiveLock"} > 0 AND wait > 30s` | Blocked queries piling up |
| Autovacuum not running | Last autovacuum > 24h on high-churn tables | Bloat accumulating |

### Tier 3 — Trend Watch (Ticket Within 24 Hours)

Not urgent today, but needs attention before it becomes urgent.

| Alert | Condition | Why |
|-------|-----------|-----|
| Table bloat > 50% | Dead rows > 50% of live rows | Performance degrading |
| Index bloat > 30% | | Wasted space, slower scans |
| Slow query count growing | 20% week-over-week increase | Schema or data distribution change |
| Connection pool utilization trending up | 70% and rising | Will hit Tier 1 threshold |
| Replica count below desired | Expected N replicas, have N-1 | Reduced read capacity and failover coverage |

### Tier 4 — Informational (Weekly Review)

Background trends. No action needed unless pattern persists.

| Alert | Condition |
|-------|-----------|
| Backup size trend | Growing faster than data growth |
| Query plan regressions | Mean time for known queries increased > 50% |
| Checkpoint warnings | `pg_stat_bgwriter.checkpoint_warning > 0` frequently |
| Connection churn | High `connection_errors_*` rate |

---

## PromQL Reference `[I]`

### Connection Monitoring

```promql
# Total active connections
pg_stat_activity_count{state="active"}

# Connection utilization (% of max_connections)
pg_stat_activity_count / pg_settings_max_connections * 100

# Alert: connections > 85%
(pg_stat_activity_count / pg_settings_max_connections) > 0.85

# Idle in transaction (dangerous — holding locks)
pg_stat_activity_count{state="idle in transaction"}
```

### Query Performance

```promql
# Query p99 latency (requires pg_stat_statements)
histogram_quantile(0.99, rate(pg_stat_statements_mean_exec_time_bucket[5m]))

# Queries per second
rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m])

# Transaction rollback rate (spike indicates errors)
rate(pg_stat_database_xact_rollback[5m])
  / (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
```

### Replication Lag

```promql
# Replication lag in seconds (on primary, watching replica)
pg_stat_replication_pg_wal_lsn_diff / 1024 / 1024  -- in MB behind

# Lag from replica's perspective
pg_replication_lag  # seconds since last replay

# Alert: lag > 30 seconds
pg_replication_lag > 30

# Alert: lag growing monotonically (replica stuck)
deriv(pg_replication_lag[5m]) > 0 AND pg_replication_lag > 60
```

### Disk and Bloat

```promql
# Disk usage percentage
1 - (node_filesystem_free_bytes{mountpoint="/var/lib/postgresql"} 
     / node_filesystem_size_bytes{mountpoint="/var/lib/postgresql"})

# Dead row ratio (bloat indicator)
pg_stat_user_tables_n_dead_tup 
  / (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup)

# Tables with high dead row ratio
topk(10, pg_stat_user_tables_n_dead_tup 
          / on(relname) (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup))
```

### Lock Monitoring

```promql
# Total lock count by mode
pg_locks_count

# Exclusive locks held (potential blockers)
pg_locks_count{mode="ExclusiveLock",granted="true"}

# Lock waits (ungranted locks)
pg_locks_count{granted="false"}
```

---

## Grafana Dashboard Structure `[I]`

### Dashboard 1: DB Overview (Always-Visible)

Panels arranged top-to-bottom by urgency:

```
Row 1 — Health Status
  [Stat] DB Up/Down     [Stat] Replica Count     [Stat] Last Backup Age

Row 2 — Connections
  [Graph] Active connections over time
  [Gauge] Connection utilization %

Row 3 — Performance
  [Graph] Transactions/sec (commits + rollbacks)
  [Graph] Query p99 latency
  [Graph] Cache hit ratio (pg_stat_database_blks_hit / (blks_hit + blks_read))

Row 4 — Replication
  [Graph] Replication lag (all replicas)
  [Stat]  Replica states

Row 5 — Disk
  [Graph] Disk usage %
  [Graph] WAL generation rate
```

### Dashboard 2: Query Performance

For investigating slow queries — open during incidents or when Tier 2 alerts fire:

```
Row 1 — Top Queries by Total Time (table from pg_stat_statements)
  Columns: query (truncated), calls, mean_ms, total_ms, % of total

Row 2 — Query Latency Percentiles
  [Graph] p50 / p95 / p99 over time (per normalized query)

Row 3 — Cache Effectiveness
  [Graph] Buffer cache hit ratio
  [Graph] Index hit ratio

Row 4 — Locks
  [Graph] Lock count by mode
  [Table] Current lock waits (from pg_stat_activity WHERE wait_event_type = 'Lock')
```

### Dashboard 3: Replication Health

For monitoring replica fleet:

```
Row 1 — Overview
  [Stat] Number of replicas     [Stat] Max lag     [Stat] Sync state

Row 2 — Per-Replica Lag
  [Graph] Lag in seconds per replica (separate line per replica)
  [Graph] WAL bytes behind per replica

Row 3 — Replica Activity
  [Graph] Queries per second per replica
  [Graph] Connection count per replica
```

---

## Replication Lag Alerting `[I]`

Replication lag is the most common DBRE alert. Three distinct conditions require different responses:

```yaml
# Prometheus alerting rules — postgres_replication.yml
groups:
  - name: postgres_replication
    rules:

    # Lag crossing 30s — degraded (ticket, investigate)
    - alert: PostgresReplicationLagHigh
      expr: pg_replication_lag > 30
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Replication lag {{ $value }}s on {{ $labels.instance }}"
        runbook: "https://wiki.internal/dbre/runbooks/replication-lag"

    # Lag crossing 5 minutes — SLO breach risk (page)
    - alert: PostgresReplicationLagCritical
      expr: pg_replication_lag > 300
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Replication lag CRITICAL {{ $value }}s — replica unusable for failover"

    # Lag growing monotonically — replica stuck (page)
    - alert: PostgresReplicationStuck
      expr: deriv(pg_replication_lag[10m]) > 0.5 AND pg_replication_lag > 120
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Replica appears stuck — lag growing continuously"

    # All replicas gone
    - alert: PostgresNoReplicas
      expr: count(pg_stat_replication_state) == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "No replicas streaming — primary has no standby"
```

**Diagnosing lag when an alert fires:**

```sql
-- On primary: who is lagging and by how much?
SELECT
    client_addr,
    state,
    sent_lsn - write_lsn AS write_lag_bytes,
    sent_lsn - flush_lsn AS flush_lag_bytes,
    sent_lsn - replay_lsn AS replay_lag_bytes,
    write_lag, flush_lag, replay_lag
FROM pg_stat_replication;

-- On replica: how far behind?
SELECT
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_is_in_recovery() AS is_replica,
    pg_last_wal_receive_lsn() AS received,
    pg_last_wal_replay_lsn() AS replayed;
```

---

## Tool Comparison `[B]`

| Tool | Best for | Limitations |
|------|----------|-------------|
| Prometheus + Grafana | Self-managed, full control, existing infra | Setup overhead, requires exporters |
| CloudWatch | RDS/Aurora, AWS-native, zero setup | Limited metric granularity, expensive at scale |
| Datadog | Unified observability (app + DB + infra), rich UI | Cost, vendor lock-in |
| RDS Performance Insights | Deep query analysis for RDS/Aurora | RDS-only, no self-managed |
| pgBadger | PostgreSQL log analysis, offline/batch | Not real-time, requires log access |
| pg_activity | Live query monitor (like `top` for PostgreSQL) | Terminal-only, no history |

**Typical setups:**
- AWS-native shop with RDS: CloudWatch + Performance Insights + Datadog for unified view
- Self-managed / EC2: postgres_exporter + Prometheus + Grafana
- Both: Prometheus scrapes CloudWatch via `cloudwatch_exporter` for unified Grafana dashboards

---

## Related Topics

- [Fundamentals](fundamentals.md#key-metrics-to-monitor) — raw monitoring SQL queries
- [Backup & Recovery](backup-recovery.md) — backup success alerting
- [HA & Failover](ha-failover.md) — replication and failover monitoring
- [SRE: Observability](../sre/observability.md) — application-level observability
- [SRE: SLOs / SLIs / SLAs](../sre/slo-sla-sli.md) — defining DB SLOs
