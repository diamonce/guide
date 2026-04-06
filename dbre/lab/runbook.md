# DBRE Lab Runbook — MySQL

[← DBRE Home](../README.md)

Everything from the DBRE docs, hands-on. Docker-based, runs locally, no cloud needed.

---

## Architecture

```
  App / scripts
      │
      ├── HAProxy :3306 ──────────────► mysql-primary   (writes, server_id=1)
      │           :3307 ──► replica1                    (reads, round-robin)
      │                └──► replica2
      │
      └── ProxySQL :6033 ──► auto read/write split
                  :6032    admin interface (MySQL protocol)
                  :6080    web UI (HTTPS, Digest auth)

  mysql-primary (server_id=1)
      │  GTID replication
      ├── mysql-replica1 (server_id=2, read-only)
      └── mysql-replica2 (server_id=3, read-only)

  toolkit  ── pt-* tools + gh-ost + xtrabackup + mydumper
  mysql-tools  ── mysql:8.0.23 client suite (mysqlbinlog, etc.)
  mysql57      ── MySQL 5.7 source for migration lab (script 11)
  adminer      ── web UI :8080

  Monitoring
  mysqld-exporter-{primary,replica1,replica2} :9104–9106
      │  scrape every 15s
      ▼
  Prometheus :9090
      │
      ▼
  Grafana :3000  (admin / admin)
      ├── MySQL Overview       — time-series: QPS, lag, connections, buffer pool
      └── MySQL Processlist    — live SQL: processlist, top queries, locks, transactions
```

---

## Ports quick-reference

| Port | Service | Notes |
|------|---------|-------|
| 3306 | HAProxy → writes | Always hits primary |
| 3307 | HAProxy → reads | Round-robin replicas |
| 3310 | mysql-primary | Direct access |
| 3311 | mysql-replica1 | Direct access |
| 3312 | mysql-replica2 | Direct access |
| 3315 | mysql57 | MySQL 5.7 migration source |
| 6032 | ProxySQL admin | MySQL protocol — `mysql -P 6032 -uradmin` |
| 6033 | ProxySQL proxy | App connection point |
| 6080 | ProxySQL web UI | HTTPS, Digest auth — `stats / statspass` |
| 8080 | Adminer | Web DB client |
| 8404 | HAProxy stats | HTTP |
| 9090 | Prometheus | |
| 3000 | Grafana | admin / admin |
| 9104–9106 | mysqld_exporter | One per MySQL node |

---

## Prerequisites

Run the setup script once — installs all tools via Homebrew:

```bash
cd dbre/lab
chmod +x setup-macos.sh && ./setup-macos.sh
```

| Tool | Used for |
|------|----------|
| Docker Desktop | All lab containers |
| `mysql-client` | mysql, mysqldump |
| `percona-toolkit` | pt-osc, pt-table-checksum, pt-query-digest, pt-mysql-summary |
| `gh-ost` | Online schema changes (also built into toolkit container) |
| `sysbench` | MySQL load testing |
| `fio` | Disk IOPS measurement for innodb_io_capacity tuning |
| `netcat` | gh-ost socket control (pause/resume) |
| `pv` | Progress bar for large restores |
| `jq` | JSON parsing |

`mysqlbinlog` — not in the official `mysql:8.0` image. Available in the `mysql-tools` container:
```bash
docker exec mysql-tools mysqlbinlog --version
```

`xtrabackup` / `mydumper` — no macOS binary. Built into the `toolkit` container:
```bash
docker exec toolkit xtrabackup --version
docker exec toolkit mydumper --version
```

---

## 0. Start the cluster

```bash
cd dbre/lab

# First run: build toolkit image (includes gh-ost + xtrabackup)
docker compose build toolkit

docker compose up -d

# Watch containers come up
docker compose ps
```

Expected: all containers `healthy` or `running` within ~60 seconds.

---

## 1. Set up replication

Run once after first `docker compose up`:

```bash
./scripts/01-setup-replication.sh
```

What it does:
- Waits for all three MySQL nodes
- Applies `sql/04-auth-compat.sql` on every node — ensures `app`, `haproxy_check`, and `monitor` users have `mysql_native_password` (required by ProxySQL and HAProxy)
- Configures GTID replication on both replicas
- Reloads ProxySQL user list

Verify:
```bash
docker exec mysql-primary mysql -u root -prootpass -e "SHOW MASTER STATUS\G"
docker exec mysql-replica1 mysql -u root -prootpass -e "SHOW REPLICA STATUS\G"
```

Look for: `Replica_IO_Running: Yes`, `Replica_SQL_Running: Yes`, `Seconds_Behind_Source: 0`

---

## 2. Test replication

```bash
./scripts/02-test-replication.sh
```

- Inserts a row on primary, reads it back from both replicas
- Shows replication lag and GTID sets
- Demonstrates `super-read-only` rejection on replicas

```bash
# Try writing to a replica — should fail
docker exec mysql-replica1 mysql -u root -prootpass shopdb \
  -e "INSERT INTO customers (name, email) VALUES ('test', 'x@x.com');"
# ERROR 1290: read-only mode
```

---

## 3. HAProxy — static read/write split

```bash
./scripts/03-test-haproxy.sh
```

- Port `3306` → always `server_id=1` (primary)
- Port `3307` → alternates `server_id=2 / 3` (round-robin)

Stats: [http://localhost:8404/stats](http://localhost:8404/stats)

Health check uses `haproxy_check` user with `mysql_native_password` + `post-41` protocol flag (required for MySQL 8.0).

Kill a replica and watch HAProxy route around it:
```bash
docker pause mysql-replica2
for i in 1 2 3 4; do
  mysql -h 127.0.0.1 -P 3307 -uapp -papppass shopdb -e "SELECT @@server_id;"
done
docker unpause mysql-replica2
```

---

## 4. ProxySQL — automatic read/write split

```bash
./scripts/04-test-proxysql.sh
```

ProxySQL parses each query and routes by rule:

| Rule | Pattern | Destination |
|------|---------|-------------|
| 1 | `SELECT $$` | intercept (multiplexing probe — never reaches MySQL) |
| 2 | `SELECT ... FOR UPDATE` | primary (hostgroup 0) |
| 3 | `SELECT` | replicas (hostgroup 1) |
| default | everything else | primary |

### Admin interfaces

```bash
# MySQL admin interface (from host — uses radmin user)
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass

# Check routing
SELECT rule_id, hits, destination_hostgroup, match_pattern
FROM stats_mysql_query_rules;

# Connection pool
SELECT hostgroup, srv_host, status, ConnUsed, Queries
FROM stats_mysql_connection_pool;
```

### Web UI

Open **https://localhost:6080** in a browser.

> ProxySQL uses HTTP **Digest** auth — browser handles it automatically.
> Credentials: `stats` / `statspass`

Shows: connection pool, query digest, system stats, processlist.

### Runtime config changes

ProxySQL reads `proxysql.cnf` only on first start (empty datadir).
All runtime changes must be applied via SQL and persisted:

```bash
docker exec proxysql mysql -h127.0.0.1 -P6032 -uadmin -padminpass -e "
    SET admin-web_enabled='true';
    SET admin-stats_credentials='stats:statspass';
    LOAD ADMIN VARIABLES TO RUNTIME;
    SAVE ADMIN VARIABLES TO DISK;"
```

---

## 5. Backups — logical + PITR

```bash
./scripts/05-backups.sh
```

Covers: full dump, single-database dump, single-table dump, restore to new database, full PITR walkthrough with GTID-based recovery and zero-downtime table swap.

### mysqldump commands

```bash
# Full backup
docker exec mysql-primary mysqldump \
  -u root -prootpass \
  --all-databases --single-transaction \
  --routines --triggers --events \
  --set-gtid-purged=ON --source-data=2 \
  2>/dev/null > /tmp/full_$(date +%Y%m%d).sql

# Single database (for restore to same server — use OFF to avoid GTID conflict)
docker exec mysql-primary mysqldump \
  -u root -prootpass \
  --single-transaction --set-gtid-purged=OFF \
  shopdb 2>/dev/null > /tmp/shopdb.sql
```

### PITR

```bash
# 1. Flush binlog, note GTID, take snapshot
docker exec mysql-primary mysql -u root -prootpass \
  -e "FLUSH BINARY LOGS; SELECT @@GLOBAL.gtid_executed;"

# 2. Inspect binlog for the bad event
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass -e \
  "SHOW BINLOG EVENTS IN 'mysql-bin.000005' LIMIT 200;" | grep -i delete

# 3. mysqlbinlog (requires mysql-tools container — not in mysql:8.0 image)
BINLOG=mysql-bin.000005
docker exec mysql-tools mysqlbinlog \
  --read-from-remote-server \
  --host=mysql-primary --user=root --password=rootpass \
  --base64-output=DECODE-ROWS --verbose \
  "$BINLOG" 2>/dev/null | grep -A5 "DELETE FROM"

# 4. Restore snapshot + replay binlogs excluding the bad GTID
docker exec mysql-tools mysqlbinlog \
  --read-from-remote-server \
  --host=mysql-primary --user=root --password=rootpass \
  --exclude-gtids="<gtid-of-bad-transaction>" \
  "$BINLOG" 2>/dev/null \
  | docker exec -i mysql-primary mysql -u root -prootpass shopdb_restored
```

### Zero-downtime table swap after restore

```sql
-- Atomic: no window where the table is missing
-- Both renames happen in a single operation
DROP TABLE IF EXISTS shopdb.orders_broken;
RENAME TABLE
    shopdb.orders          TO shopdb.orders_broken,
    shopdb_restored.orders TO shopdb.orders;
```

Keep `orders_broken` for 24h before dropping — instant rollback path.

---

## 6. Fast backups — XtraBackup, mydumper, snapshots

```bash
./scripts/06-fast-backups.sh
```

| Method | Backup time (1TB) | Lock time | Restore time | Use case |
|--------|------------------|-----------|--------------|---------|
| mysqldump | 3–6 hours | full duration | 4–8 hours | < 50 GB |
| mydumper (8 threads) | 1–2 hours | ~seconds | 1–2 hours | logical, cross-version |
| XtraBackup full | 30–60 min | ~seconds | 30–60 min | InnoDB, same version |
| XtraBackup incremental | 2–10 min | ~seconds | 60–90 min | daily full + hourly incr |
| EBS / LVM snapshot | ~seconds | < 1 sec | 5–15 min | cloud, fastest RTO |

```bash
# XtraBackup — physical hot backup
docker exec toolkit xtrabackup \
  --backup \
  --host=mysql-primary --user=root --password=rootpass \
  --target-dir=/backup/full \
  --parallel=4 --compress

# Stream directly to S3 (TB-scale — skip staging on disk)
docker exec toolkit xtrabackup \
  --backup --stream=xbstream --compress \
  --host=mysql-primary --user=root --password=rootpass \
  | aws s3 cp - s3://bucket/backup-$(date +%Y%m%d).xbstream

# Incremental (only pages changed since full)
docker exec toolkit xtrabackup \
  --backup \
  --host=mysql-primary --user=root --password=rootpass \
  --target-dir=/backup/incr \
  --incremental-basedir=/backup/full

# mydumper — parallel logical backup
docker exec toolkit mydumper \
  --host=mysql-primary --user=root --password=rootpass \
  --database=shopdb \
  --outputdir=/backup/mydumper \
  --threads=8 --chunk-filesize=128 --compress

# Restore with myloader (parallel)
docker exec toolkit myloader \
  --host=mysql-primary --user=root --password=rootpass \
  --directory=/backup/mydumper --threads=8
```

---

## 7. Failover

```bash
./scripts/07-failover.sh
```

Simulates primary crash, replica promotion, re-pointing the remaining replica.

Reset:
```bash
docker compose down -v && docker compose up -d
./scripts/01-setup-replication.sh
```

---

## 8. Parallel writes + locking

```bash
./scripts/08-parallel-writes.sh
```

Covers concurrent writes, row-level lock contention, deadlocks, and reading `SHOW ENGINE INNODB STATUS`.

```bash
# Watch active transactions and locks
watch -n1 'docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "
SELECT trx_id, trx_state, trx_rows_locked, trx_query
FROM information_schema.innodb_trx;"'

# Kill a blocking query
docker exec mysql-primary mysql -u root -prootpass \
  -e "KILL QUERY <thread_id>;"
```

---

## 9. Percona Toolkit

```bash
./scripts/09-percona-toolkit.sh
```

| Tool | What it does |
|------|-------------|
| `pt-mysql-summary` | Full cluster summary including replication, engine config |
| `pt-duplicate-key-checker` | Finds redundant indexes (saves space + write overhead) |
| `pt-table-checksum` | Verifies replica data matches primary byte-for-byte |
| `pt-table-sync` | Fixes data drift between primary and replica |
| `pt-online-schema-change` | ALTER TABLE without blocking reads or writes |
| `pt-query-digest` | Parses slow log → ranked query report with avg/max/p99 |

```bash
# Any pt-* tool runs in the toolkit container
docker exec toolkit pt-duplicate-key-checker \
  --host=mysql-primary --user=root --password=rootpass --databases=shopdb

# pt-osc — always use --recursion-method=none with MySQL 8.0
# (avoids "uninitialized value" bug from old Slave_* column names)
docker exec toolkit pt-online-schema-change \
  --host=mysql-primary --user=root --password=rootpass \
  --alter "ADD COLUMN notes TEXT" \
  --alter-foreign-keys-method=auto \
  --recursion-method=none \
  --execute D=shopdb,t=orders

# pt-query-digest — pipe slow log from primary into toolkit
SLOW_LOG=$(docker exec mysql-primary mysql -u root -prootpass -sN \
  -e "SELECT @@slow_query_log_file;" 2>/dev/null)
docker exec mysql-primary cat "$SLOW_LOG" \
  | docker exec -i toolkit pt-query-digest --type=slowlog -
```

---

## 10. Schema Changes — Online DDL, pt-osc, gh-ost

```bash
./scripts/10-schema-changes.sh
```

Script is idempotent — resets table state and re-seeds 5000 rows on every run.

### Decision flow

```
ALGORITHM=INSTANT  → zero lock, no copy (ADD COLUMN at end, rename column 8.0+)
  ↓ fails?
ALGORITHM=INPLACE, LOCK=NONE  → brief MDL only (ADD INDEX, most changes)
  ↓ fails?
Needs COPY → table < 1 GB, low writes: pt-osc
           → large table or high write rate: gh-ost
```

```bash
# Test INSTANT — fails immediately if not supported, zero risk
docker exec mysql-primary mysql -u root -prootpass shopdb \
  -e "ALTER TABLE orders ADD COLUMN notes TEXT, ALGORITHM=INSTANT;"

# Test INPLACE
docker exec mysql-primary mysql -u root -prootpass shopdb \
  -e "ALTER TABLE orders ADD INDEX idx_test (total), ALGORITHM=INPLACE, LOCK=NONE;"
```

### gh-ost (binlog-based, no triggers)

gh-ost runs inside the toolkit container. Limitations:
- Does not support tables that have **child foreign keys** pointing at them (parent-side FKs)
- Use on leaf tables (`order_items`) or tables with no children

```bash
# Control gh-ost while running (via Unix socket inside toolkit)
docker exec toolkit sh -c 'echo status    | nc -U /tmp/gh-ost-lab.sock'
docker exec toolkit sh -c 'echo throttle  | nc -U /tmp/gh-ost-lab.sock'
docker exec toolkit sh -c 'echo no-throttle | nc -U /tmp/gh-ost-lab.sock'
docker exec toolkit sh -c 'echo panic     | nc -U /tmp/gh-ost-lab.sock'
```

---

## 11. MySQL 5.7 → 8.0 Migration (zero downtime)

```bash
docker compose up -d mysql57
./scripts/11-mysql5-to-8-migration.sh
```

Replication-based cutover — total app downtime: **0ms**.

| Phase | What happens | Downtime |
|-------|-------------|---------|
| 1. Compatibility check | sql_mode, reserved words, utf8, zero dates | 0 |
| 2. Snapshot + restore | mysqldump with `--set-gtid-purged=ON` to MySQL 8 | 0 |
| 3. Cross-version replication | MySQL 5.7 → 8.0 replication (supported) | 0 |
| 4. Replication catch-up | Wait `Seconds_Behind_Source = 0` | 0 |
| 5. Validate | pt-table-checksum + app smoke test | 0 |
| 6. ProxySQL cutover | SHUNNED old, ONLINE new, `LOAD MYSQL SERVERS TO RUNTIME` | 0ms |
| 7. Rollback window | Keep 5.7 as replica for 24–48h | 0 |

Key compatibility issues to check:
- `ONLY_FULL_GROUP_BY` now default in sql_mode
- New reserved words (`RANK`, `GROUPS`, `ROWS`, `LAG`, `LEAD`, `OVER`...)
- `utf8mb3` renamed (functional, but check collations)
- `caching_sha2_password` default — ProxySQL/HAProxy need `mysql_native_password`
- `query_cache` removed — remove from `my.cnf`
- `NO_ZERO_DATE`, `NO_ZERO_IN_DATE` stricter by default

---

## Monitoring

### Access

| UI | URL | Credentials |
|----|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin |
| ProxySQL web UI | https://localhost:6080 | stats / statspass (Digest auth) |
| Prometheus | http://localhost:9090 | — |
| HAProxy stats | http://localhost:8404/stats | — |
| Adminer | http://localhost:8080 | root / rootpass, server: mysql-primary |

### Grafana dashboards

**MySQL Overview** (Prometheus):
- MySQL up/down per node
- Max replication lag (threshold coloring)
- Connection utilization gauge
- Queries/sec + slow queries/sec
- Replication lag per replica over time
- Buffer pool hit ratio (target > 99%)
- Row lock waits/sec, binlog size

**MySQL Processlist** (direct SQL against primary):
- Live active queries — non-Sleep connections
- Top 20 queries by total time — avg ms, no-index flag in red
- Active InnoDB transactions with age — long-running in red
- Lock waits — who blocks who
- Query error rates
- Replica connection status

### Generate load and watch it live

```bash
# Parallel writes → watch QPS climb in Grafana
./scripts/07-parallel-writes.sh

# Force slow queries to surface in top-queries panel
docker exec mysql-primary mysql -u root -prootpass -e "
  SET GLOBAL long_query_time = 0;
  SET GLOBAL slow_query_log = ON;"
docker exec mysql-primary mysql -u root -prootpass shopdb -e "
  SELECT c.name, COUNT(o.id), SUM(o.total)
  FROM customers c
  LEFT JOIN orders o ON o.customer_id = c.id
  GROUP BY c.id ORDER BY SUM(o.total) DESC;"
docker exec mysql-primary mysql -u root -prootpass -e "
  SET GLOBAL long_query_time = 1;"
```

### Simulate lock contention

```bash
# Terminal 1 — hold transaction
docker exec -it mysql-primary mysql -u root -prootpass shopdb -e "
  START TRANSACTION;
  UPDATE customers SET name='locked' WHERE id=1;
  SELECT SLEEP(30);
  COMMIT;" &

# Terminal 2 — will block
docker exec mysql-primary mysql -u root -prootpass shopdb -e "
  UPDATE customers SET name='blocked' WHERE id=1;"
# Grafana Processlist → Lock Waits panel shows blocking_thread in red
```

---

## Useful one-liners

```bash
# Replication lag on all replicas
for r in mysql-replica1 mysql-replica2; do
  echo -n "$r: "
  docker exec $r mysql -u root -prootpass -sN \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep Seconds_Behind_Source
done

# Table sizes
docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "
SELECT table_name,
       ROUND(data_length/1024/1024,2)  AS data_mb,
       ROUND(index_length/1024/1024,2) AS index_mb,
       table_rows
FROM information_schema.tables
WHERE table_schema='shopdb'
ORDER BY data_length DESC;"

# InnoDB lock waits
docker exec mysql-primary mysql -u root -prootpass 2>/dev/null -e "
SELECT waiting_pid, blocking_pid, waiting_query, blocking_query
FROM sys.innodb_lock_waits;"

# Active connections with query
docker exec mysql-primary mysql -u root -prootpass -e "SHOW FULL PROCESSLIST;" 2>/dev/null

# Binary log size
docker exec mysql-primary mysql -u root -prootpass -e "SHOW BINARY LOGS;" 2>/dev/null

# SHOW BINLOG EVENTS (no mysqlbinlog needed)
docker exec mysql-primary mysql -u root -prootpass \
  -e "SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 50;" 2>/dev/null

# mysqlbinlog (needs mysql-tools container)
docker exec mysql-tools mysqlbinlog \
  --read-from-remote-server \
  --host=mysql-primary --user=root --password=rootpass \
  --base64-output=DECODE-ROWS --verbose mysql-bin.000001 2>/dev/null | tail -30

# ProxySQL runtime config
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass \
  -e "SELECT variable_name, variable_value FROM runtime_global_variables
      WHERE variable_name LIKE 'admin-web%';"

# Reset performance_schema counters between test runs
docker exec mysql-primary mysql -u root -prootpass -e "
  TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;
  TRUNCATE TABLE performance_schema.events_statements_history_long;" 2>/dev/null
```

---

## Tear down

```bash
# Stop, keep volumes
docker compose stop

# Stop and delete everything including data
docker compose down -v

# Rebuild toolkit image after Dockerfile changes
docker compose build toolkit && docker compose up -d toolkit
```

---

## Related docs

- [Fundamentals](../fundamentals.md) — connection pooling, locks, monitoring queries
- [Observability](../observability.md) — mysqld_exporter, alert hierarchy, PromQL reference
- [Performance Tuning](../performance.md) — EXPLAIN, indexes, events_statements_summary_by_digest
- [Backup & Recovery](../backup-recovery.md) — PITR, mysqldump, xtrabackup
- [Migrations](../migrations.md) — pt-online-schema-change, expand/contract, 5.7→8.0
- [HA & Failover](../ha-failover.md) — ProxySQL routing, failover runbooks
- [Scaling](../scaling.md) — read replicas, ProxySQL, sharding
- [Load Testing](../load-testing.md) — sysbench, fio, GCP tuning
