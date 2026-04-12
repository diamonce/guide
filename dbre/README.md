# DBRE — Database Reliability Engineering

[← Home](../README.md)

DBRE applies SRE principles to databases. Databases are the most critical and least replaceable part of most systems. Your goal: keep them fast, available, correct, and operable.

---

## Topics

| Topic | What you'll learn |
|-------|------------------|
| [Database Landscape](databases.md) | Every major engine — relational, NoSQL, cloud-native; pros/cons, decision framework |
| [Fundamentals](fundamentals.md) | DB reliability concepts, connection pooling, monitoring |
| [SQL Best Practices](sql.md) | Query writing, anti-patterns, optimization |
| [Anti-Patterns](antipatterns.md) | Design and query anti-patterns (sqlcheck reference) |
| [Security](security.md) | Access control, encryption, secrets management, audit logging, PII/compliance |
| [Performance Tuning](performance.md) | Query optimization, indexes, execution plans |
| [Migrations & Schema Changes](migrations.md) | INSTANT/INPLACE/pt-osc/gh-ost selection, duration estimation, zero-downtime execution |
| [Backup & Recovery](backup-recovery.md) | mysqldump, XtraBackup, mydumper, PITR with GTIDs, zero-downtime table swap |
| [Observability](observability.md) | Prometheus + mysqld_exporter, Grafana dashboards, alert hierarchy, replication lag |
| [HA & Failover](ha-failover.md) | HAProxy, ProxySQL routing, replica promotion, failover runbooks |
| [Load Testing & VM Optimization](load-testing.md) | sysbench, mysqlslap, InnoDB tuning, OS settings, GCP VM sizing |
| [Scaling Databases](scaling.md) | Read replicas, ProxySQL connection pooling, sharding |
| [**Lab**](lab/runbook.md) | **Hands-on Docker lab — everything below in a running cluster** |
| [Best Practices](best-practices.md) | Schema design, queries, indexing, tools, naming conventions |
| [External Links](external-links.md) | PostgreSQL docs, Don't Do This wiki, sqlblog bad habits, modern-sql |
| [**Postmortem Template**](postmortem-template.md) | **Operational failures — outage, failover, replication break, backup failure** |
| [**DEA Template**](dea-template.md) | **Defect Escape Analysis — defects that slipped through quality gates to production** |

---

## Lab

The lab is a self-contained Docker environment covering every topic end-to-end. No cloud account needed.

```
mysql-primary ──GTID──► mysql-replica1
              └─GTID──► mysql-replica2

HAProxy    :3306 writes → primary
           :3307 reads  → replicas (round-robin)
           :6379        → Valkey primary   (stable endpoint; app uses Redis client)
           :6380        → Valkey replica

ProxySQL   cluster: node-1 ←──sync──→ node-2 (config changes propagate automatically)
           HAProxy :6033 → node-1 / node-2  (leastconn, failover in ~6s)
           :6032 / :6034  admin interfaces
           :6080 / :6081  web UIs
           Query cache: products 30s TTL, COUNT(*) 5s TTL — zero app changes needed

Valkey     valkey         → primary (allkeys-lru, 256MB cap)
           valkey-replica → read-only replica
           ⚠ NOT transparent — app must use Redis client and implement cache-aside

Monitoring  mysqld_exporter ×3 → Prometheus :9090 → Grafana :3000
            redis-exporter     → Prometheus (hits, misses, evictions, memory)
            MySQL Overview dashboard    — time-series metrics
            MySQL Processlist dashboard — live processlist, top queries, locks
            ProxySQL dashboard          — pool, routing, query cache, latency buckets
            Valkey Cache dashboard      — hit rate, memory, evictions, replication

toolkit container  pt-*, gh-ost, xtrabackup, mydumper
mysql-tools        mysqlbinlog, full MySQL client suite
mysql57            MySQL 5.7 source for migration lab (opt-in: --profile migration)
```

### Caching layers

Two fundamentally different caching mechanisms in the lab:

**ProxySQL built-in query cache — transparent, no app changes**

The app sends SQL to ProxySQL `:6033`. ProxySQL intercepts matching SELECTs and serves results from its internal RAM cache. MySQL is never queried on a cache hit. Configured via `cache_ttl` on query rules.

Limitations:
- Cache lives inside one ProxySQL process — not shared across multiple instances
- No explicit invalidation; TTL-only expiry
- No write-through; stale reads possible within TTL window
- Suitable for a single ProxySQL node or per-app-server sidecar deployment

Scaling ProxySQL query cache: you cannot. Each ProxySQL instance caches independently. If you run multiple ProxySQL instances for HA or per-pod sidecars, each builds its own cache from scratch. The cache does not scale horizontally.

**Valkey via HAProxy — requires app code, scales horizontally**

The app must use a Redis client and implement cache-aside logic (check Valkey → on miss, query MySQL → write to Valkey). HAProxy provides a stable endpoint so the app never hardcodes the Valkey address.

| Property | ProxySQL cache | Valkey |
|----------|---------------|--------|
| App changes needed | None | Redis client + cache-aside logic |
| Shared across app instances | No — per-process | Yes — all apps share one cluster |
| Horizontal scale | No | Yes — Valkey Cluster shards across nodes |
| Explicit invalidation | No (flush entire cache only) | Yes — `DEL key` per entry |
| Write-through | No | App implements it |
| Cache invalidation on DB write | No | App or CDC (e.g. Maxwell + binlog) |
| Suitable for | Single node, read-heavy, low write rate | Shared cache, high traffic, large datasets |

**When to use each:**
- Use ProxySQL cache when you cannot change the app and the data changes slowly (config tables, product catalogs with infrequent updates).
- Use Valkey when you control the app, need shared cache state across multiple servers, need explicit invalidation, or need to cache data beyond what fits in one ProxySQL process.

### Lab scripts

| Script | Topic |
|--------|-------|
| `01-setup-replication.sh` | GTID replication, auth-compat for ProxySQL + HAProxy |
| `02-test-replication.sh` | Verify replication, lag, read-only enforcement |
| `03-test-haproxy.sh` | Static read/write split, health checks, failover |
| `04-test-proxysql.sh` | Query-aware routing, admin interface, web UI |
| `05-backups.sh` | mysqldump, restore, PITR walkthrough, RENAME TABLE swap |
| `06-fast-backups.sh` | XtraBackup (full + incremental), mydumper, snapshot approach |
| `07-failover.sh` | Crash simulation, replica promotion, re-topology |
| `08-parallel-writes.sh` | Lock contention, deadlocks, INNODB STATUS |
| `09-percona-toolkit.sh` | pt-mysql-summary, pt-duplicate-key-checker, pt-table-checksum, pt-table-sync, pt-osc, pt-query-digest |
| `10-schema-changes.sh` | INSTANT/INPLACE dry runs, pt-osc, gh-ost with postponed cutover |
| `11-mysql5-to-8-migration.sh` | Zero-downtime major version upgrade via cross-version replication + ProxySQL cutover |
| `12-caching.sh` | ProxySQL built-in query cache (transparent) + Valkey cache-aside pattern (requires Redis client) |
| `13-cache-benchmark.sh` | Performance comparison: Direct MySQL vs ProxySQL cache (cold/warm) vs Valkey HGET |

**[→ Lab runbook](lab/runbook.md)** — full setup, commands, one-liners, tear down.

---

## Learning Path

```
[B] Database Landscape → Fundamentals → SQL Best Practices → Backup & Recovery → Security
[I] Performance Tuning → Migrations → Observability → HA & Failover → Best Practices
[A] Scaling → Load Testing → Lab (hands-on) → Postmortem practice
```

---

## Key Resources

- [percona-toolkit](../resources/percona-toolkit/README.md) — Battle-tested MySQL/PostgreSQL tools
- [sql-guide](../resources/sql-guide/SQL_interview_questions.txt) — SQL interview Q&A
- [sqlcheck](../resources/sqlcheck/README.md) — SQL anti-pattern detection
- [sql-tips-and-tricks](../resources/sql-tips-and-tricks/README.md) — Practical SQL tips and tricks
- [awesome-mysql](../resources/awesome-mysql/README.md) — MySQL queries, commands and snippets
- [awesome-postgres](../resources/awesome-postgres/README.md) — PostgreSQL resources and tools
- [awesome-mongodb](../resources/awesome-mongodb/README.md) — MongoDB resources and tools
- [awesome-redis](../resources/awesome-redis/README.md) — Redis resources and tools
- [awesome-nosql-guides](../resources/awesome-nosql-guides/README.md) — NoSQL patterns and guides
- [sqlstyle-guide](../resources/sqlstyle-guide/README.md) — SQL style guide for consistent formatting
- [data-engineer-handbook](../resources/data-engineer-handbook/README.md) — Data engineering context
- [awesome-scalability](../resources/awesome-scalability/README.md) — DB scaling patterns
- [atlassian-incident-handbook](../resources/atlassian-incident-handbook/postmortems.md) — Postmortem framework, Five Whys, blameless culture

---

[← SRE](../sre/README.md) | [← Platform](../platform/README.md)
