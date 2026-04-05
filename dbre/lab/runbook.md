# DBRE Lab Runbook — MySQL

[← DBRE Home](../README.md)

Everything from the DBRE docs, hands-on. Docker-based, runs locally, no cloud needed.

---

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │             HAProxy                  │
                        │  :3306 → primary  (writes)          │
                        │  :3307 → replicas (reads, RR)       │
                        │  :8404 → stats UI                   │
                        └───────────┬──────────────┬──────────┘
                                    │              │
              ┌─────────────────────▼──┐    ┌──────▼───────────────────┐
              │     mysql-primary      │    │      ProxySQL :6033       │
              │  server-id=1           │    │  auto read/write split    │
              │  GTID replication      │    │  connection pooling        │
              │  binary logging        │    └──────────────────────────┘
              └──────────┬────────────┘
                         │ GTID replication
           ┌─────────────┴─────────────┐
           │                           │
  ┌────────▼────────┐         ┌────────▼────────┐
  │  mysql-replica1 │         │  mysql-replica2  │
  │  server-id=2    │         │  server-id=3     │
  │  read-only      │         │  read-only        │
  └─────────────────┘         └─────────────────┘

  toolkit container — pt-* tools, mysqldump, backups
  adminer          — web UI at localhost:8080

  Monitoring stack
  mysqld_exporter ×3 (:9104 :9105 :9106)
    │  scrape every 15s
    ▼
  Prometheus :9090
    │
    ▼
  Grafana :3000  (admin / admin)
    ├── MySQL Overview       — Prometheus time-series metrics
    └── MySQL Processlist    — live SQL: processlist, top queries, locks
```

---

## Prerequisites

Run the setup script once — installs all tools via Homebrew:

```bash
cd dbre/lab
chmod +x setup-macos.sh && ./setup-macos.sh
```

What it installs:

| Tool | Used for |
|------|----------|
| Docker Desktop | All lab containers |
| `mysql-client` | mysql, mysqldump, mysqlbinlog, mysqlslap |
| `percona-toolkit` | pt-online-schema-change, pt-table-checksum, pt-query-digest, pt-mysql-summary + 30 more |
| `gh-ost` | Online schema changes (section 10) |
| `sysbench` | MySQL load testing (load-testing.md) |
| `fio` | Disk IOPS measurement for innodb_io_capacity tuning |
| `netcat` | gh-ost socket control (pause/resume mid-migration) |
| `pv` | Progress bar for mysqldump restores |
| `jq` | JSON output parsing |

`xtrabackup` — no macOS binary. Runs inside the `toolkit` Docker container: `docker exec toolkit xtrabackup --version`

---

## 0. Start the cluster

```bash
cd dbre/lab

docker compose up -d

# Watch everything come up
docker compose logs -f

# Verify health
docker compose ps
```

Expected: all containers `healthy` or `running` within ~30 seconds.

---

## 1. Set up replication

Run once after first `docker compose up`:

```bash
./scripts/01-setup-replication.sh
```

What it does:
- Waits for all three MySQL nodes to be ready
- Configures replica1 and replica2 to replicate from primary via GTID
- Prints replica status — look for `Replica_IO_Running: Yes` and `Replica_SQL_Running: Yes`

Verify manually:
```bash
# Primary: show binlog status
docker exec mysql-primary mysql -prootpass -e "SHOW MASTER STATUS\G"

# Replica: check replication is running
docker exec mysql-replica1 mysql -prootpass -e "SHOW REPLICA STATUS\G"
```

---

## 2. Test replication

```bash
./scripts/02-test-replication.sh
```

What happens:
- Inserts a row into primary
- Reads it back from replica1 and replica2
- Shows replication lag (Seconds_Behind_Source)
- Compares GTID sets between primary and replicas

Key things to understand:
- `Seconds_Behind_Source = 0` means replica is caught up
- GTID sets should be identical if fully synced
- Replicas have `super-read-only = ON` — writes are rejected

Try writing to a replica directly (should fail):
```bash
docker exec mysql-replica1 mysql -prootpass shopdb \
  -e "INSERT INTO customers (name, email) VALUES ('test', 'test@test.com');"
# ERROR 1290 (HY000): read-only mode
```

---

## 3. HAProxy — split read/write traffic

```bash
./scripts/03-test-haproxy.sh
```

What to look for:
- Port `3306` always returns `server_id=1` (primary)
- Port `3307` alternates between `server_id=2` and `server_id=3` (round-robin)

Stats UI: open [http://localhost:8404/stats](http://localhost:8404/stats)

Manual test:
```bash
# Write port → always primary
mysql -h 127.0.0.1 -P 3306 -uapp -papppass shopdb \
  -e "SELECT @@server_id, 'write port';"

# Read port → replicas (run several times, watch server_id change)
mysql -h 127.0.0.1 -P 3307 -uapp -papppass shopdb \
  -e "SELECT @@server_id, 'read port';"
```

Kill a replica, watch HAProxy route around it:
```bash
docker pause mysql-replica2

# This should only return server_id=2 now
for i in 1 2 3 4; do
  mysql -h 127.0.0.1 -P 3307 -uapp -papppass shopdb -e "SELECT @@server_id;" 2>/dev/null
done

docker unpause mysql-replica2
```

---

## 4. ProxySQL — automatic read/write split

```bash
./scripts/04-test-proxysql.sh
```

ProxySQL parses each query and routes it:
- `INSERT / UPDATE / DELETE` → hostgroup 0 (primary)
- `SELECT` → hostgroup 1 (replicas)
- `SELECT ... FOR UPDATE` → hostgroup 0 (primary, needs lock)

App connects to port `6033` — no awareness of primary/replica topology.

ProxySQL admin interface:
```bash
mysql -h 127.0.0.1 -P 6032 -uadmin -padminpass

# Check routing stats
SELECT rule_id, hits, destination_hostgroup, match_pattern
FROM stats_mysql_query_rules;

# Connection pool
SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries
FROM stats_mysql_connection_pool;

# See all queries that went through
SELECT hostgroup, digest_text, count_star, sum_time/count_star AS avg_us
FROM stats_mysql_query_digest
ORDER BY sum_time DESC LIMIT 10;
```

---

## 5. Backups

```bash
./scripts/05-backups.sh
```

Covers:
- Full database dump (`mysqldump --all-databases --single-transaction`)
- Single database dump
- Single table dump
- Restore to a new database
- Binary log inspection (PITR foundation)

### Manual backup commands

```bash
# Full backup (consistent, non-blocking)
docker exec mysql-primary mysqldump \
  -prootpass \
  --all-databases \
  --single-transaction \
  --routines --triggers --events \
  --set-gtid-purged=ON \
  > /tmp/full_$(date +%Y%m%d).sql

# Verify the dump is valid
head -50 /tmp/full_$(date +%Y%m%d).sql

# Restore
docker exec -i mysql-primary mysql -prootpass < /tmp/full_$(date +%Y%m%d).sql
```

### PITR (Point-in-Time Recovery)

```bash
# 1. Find the GTID / binlog position before the bad event
docker exec mysql-primary mysql -prootpass \
  -e "SHOW BINARY LOGS;"

# 2. Decode a binlog file
docker exec mysql-primary mysqlbinlog \
  --no-defaults \
  /var/lib/mysql/mysql-bin.000001 | head -100

# 3. Restore to specific position
docker exec mysql-primary mysqlbinlog \
  --no-defaults \
  --stop-datetime="2024-01-15 14:30:00" \
  /var/lib/mysql/mysql-bin.000001 | \
  mysql -h 127.0.0.1 -P 3306 -uapp -papppass

# 4. Or stop at a specific GTID
docker exec mysql-primary mysqlbinlog \
  --no-defaults \
  --exclude-gtids="<gtid-of-bad-event>" \
  /var/lib/mysql/mysql-bin.000001 | \
  mysql -h 127.0.0.1 -P 3306 -uapp -papppass
```

---

## 6. Failover

```bash
./scripts/06-failover.sh
```

Simulates:
1. Primary container crash (`docker pause`)
2. Verifying reads still work via replicas
3. Promoting replica1 to new primary
4. Re-pointing replica2 at the new primary
5. Bringing old primary back as a replica

After the script, the topology is:
```
mysql-replica1 (server_id=2) → new primary
mysql-primary  (server_id=1) → now a replica
mysql-replica2 (server_id=3) → replica of new primary
```

Reset to original topology:
```bash
docker compose down -v && docker compose up -d
./scripts/01-setup-replication.sh
```

---

## 7. Parallel writes + locking

```bash
./scripts/07-parallel-writes.sh
```

Covers:
- 5 concurrent connections writing simultaneously
- Row-level lock contention observation
- Deadlock — two transactions updating rows in opposite order
- Reading `SHOW ENGINE INNODB STATUS` for deadlock info

Monitor locks in real time:
```bash
# Watch active transactions and locks
watch -n1 'docker exec mysql-primary mysql -prootpass 2>/dev/null -e "
SELECT trx_id, trx_state, trx_started, trx_rows_locked, trx_query
FROM information_schema.innodb_trx;"'
```

Kill a blocking query:
```bash
# Find blocking thread ID
docker exec mysql-primary mysql -prootpass -e "SHOW FULL PROCESSLIST;"

# Kill it
docker exec mysql-primary mysql -prootpass -e "KILL QUERY <thread_id>;"
```

---

## 8. Percona Toolkit

```bash
./scripts/08-percona-toolkit.sh
```

Tools demonstrated:
- `pt-mysql-summary` — full cluster summary
- `pt-duplicate-key-checker` — finds redundant indexes
- `pt-table-checksum` — verifies replica data matches primary
- `pt-table-sync` — fixes data drift between primary and replica
- `pt-online-schema-change` — ALTER TABLE without downtime

Run any pt-* tool manually:
```bash
docker exec toolkit pt-duplicate-key-checker \
  --host=mysql-primary --user=root --password=rootpass

docker exec toolkit pt-online-schema-change \
  --host=mysql-primary --user=root --password=rootpass \
  --alter "ADD COLUMN notes TEXT" \
  --execute D=shopdb,t=orders
```

---

## 9. Performance & EXPLAIN

```bash
./scripts/09-performance.sh
```

Covers:
- `EXPLAIN` output for different query patterns
- Full scan vs index scan vs covering index
- Slow queries from function on indexed column
- Creating indexes and observing plan change
- `performance_schema.events_statements_summary_by_digest` (MySQL equivalent of pg_stat_statements)

Manual EXPLAIN:
```bash
docker exec mysql-primary mysql -prootpass shopdb -e "
EXPLAIN FORMAT=JSON
SELECT c.name, SUM(o.total)
FROM customers c
JOIN orders o ON o.customer_id = c.id
GROUP BY c.id\G"
```

---

## 10. Schema Changes — pt-osc, gh-ost, Online DDL

```bash
./scripts/10-schema-changes.sh
```

Covers:
- `ALGORITHM=INSTANT` / `INPLACE` dry runs — use these before anything else
- Table size and write rate measurement for duration estimation
- `pt-online-schema-change` with safety flags (`--max-lag`, `--chunk-time`, `--critical-load`)
- `gh-ost` with postponed cutover, control socket (pause/resume/abort mid-run)
- Replication lag check after the change

**Decision flow:**

```
Try ALGORITHM=INSTANT first (zero lock)
  → fails? Try ALGORITHM=INPLACE, LOCK=NONE (brief MDL only)
    → fails? COPY required → use pt-osc or gh-ost
                → table < 1GB, low writes: pt-osc
                → large table or high write rate: gh-ost
```

Manual ALGORITHM dry run (errors immediately if not supported — safe to run):

```bash
# Test INSTANT — will error if not supported, zero risk
docker exec mysql-primary mysql -prootpass shopdb \
  -e "ALTER TABLE orders ADD COLUMN notes TEXT, ALGORITHM=INSTANT;"

# Test INPLACE
docker exec mysql-primary mysql -prootpass shopdb \
  -e "ALTER TABLE orders ADD INDEX idx_test (total), ALGORITHM=INPLACE, LOCK=NONE;"

# Never run ALGORITHM=COPY on a large table — use pt-osc or gh-ost instead
```

Control gh-ost while running:

```bash
# Pause (e.g. peak traffic window)
echo throttle | nc -U /tmp/gh-ost-lab.sock

# Resume
echo no-throttle | nc -U /tmp/gh-ost-lab.sock

# Check ETA and row progress
echo status | nc -U /tmp/gh-ost-lab.sock

# Hard abort (drops ghost table, original untouched)
echo panic | nc -U /tmp/gh-ost-lab.sock
```

While any schema change runs, watch Grafana **MySQL Processlist** dashboard:
- **Active Queries** — see pt-osc chunk SELECTs/INSERTs in real time
- **Active Transactions** — see if migration holds a long transaction
- **Lock Waits** — any app queries blocked behind the migration's MDL

---

## 11. Monitoring — Grafana + Prometheus

### Access

| UI | URL | Credentials |
|----|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | — |
| HAProxy stats | http://localhost:8404/stats | — |
| Adminer | http://localhost:8080 | root / rootpass |
| mysqld_exporter (primary) | http://localhost:9104/metrics | — |

### Grafana dashboards (auto-provisioned)

Navigate to **Dashboards → MySQL Lab** after startup.

**MySQL Overview** — Prometheus time-series:
- MySQL Up per node (green/red)
- Max replication lag with threshold coloring
- Connection utilization gauge
- Queries/sec and slow queries/sec
- Replication lag over time per replica
- InnoDB buffer pool hit ratio (target > 99%)
- Row lock waits/sec
- Binlog size

**MySQL Processlist & Performance** — direct SQL against primary:
- Live active queries (`performance_schema.processlist` filtered to non-Sleep)
- Top 20 queries by total time (`events_statements_summary_by_digest`) — avg ms, max ms, rows examined, no-index flag highlighted in red
- Active InnoDB transactions with age (long-running = red)
- Lock waits: who is blocking who (`performance_schema.data_lock_waits`)
- Query error rates
- Replica connection status from replica1

### Verify mysqld_exporter is scraping

```bash
# Check scrape targets in Prometheus
open http://localhost:9090/targets

# Raw metrics from primary exporter
curl -s http://localhost:9104/metrics | grep mysql_up
curl -s http://localhost:9104/metrics | grep seconds_behind_master

# Replication lag should be 0 on both replicas after setup
curl -s http://localhost:9105/metrics | grep slave_status_seconds_behind_master
curl -s http://localhost:9106/metrics | grep slave_status_seconds_behind_master
```

### Run a load test and watch it live

```bash
# Generate traffic — run this while watching Grafana
docker exec mysql-primary mysql -prootpass shopdb -e "
  -- Insert 1000 rows to watch QPS climb
  SET @i = 0;
  REPEAT
    INSERT INTO customers (name, email)
    VALUES (CONCAT('user', @i), CONCAT('user', @i, '@test.com'));
    SET @i = @i + 1;
  UNTIL @i >= 200 END REPEAT;"

# Or run the parallel writes script
./scripts/07-parallel-writes.sh
```

Then switch to the **MySQL Processlist** dashboard — you'll see active queries in the processlist panel and them appear in the top-queries-by-time table after they complete.

### Force a slow query and see it surface

```bash
# Enable slow log and lower threshold to 0 (catch everything)
docker exec mysql-primary mysql -prootpass -e "
  SET GLOBAL long_query_time = 0;
  SET GLOBAL slow_query_log = ON;"

# Run a deliberately slow query
docker exec mysql-primary mysql -prootpass shopdb -e "
  SELECT SQL_NO_CACHE c.name, COUNT(o.id), SUM(o.total)
  FROM customers c
  LEFT JOIN orders o ON o.customer_id = c.id
  GROUP BY c.id
  ORDER BY SUM(o.total) DESC;"

# See it in performance_schema top queries
docker exec mysql-primary mysql -prootpass -e "
  SELECT SUBSTRING(DIGEST_TEXT,1,80) AS query,
         COUNT_STAR AS calls,
         ROUND(AVG_TIMER_WAIT/1e9,2) AS avg_ms
  FROM performance_schema.events_statements_summary_by_digest
  WHERE SCHEMA_NAME='shopdb'
  ORDER BY SUM_TIMER_WAIT DESC LIMIT 5;" 2>/dev/null

# Reset threshold
docker exec mysql-primary mysql -prootpass -e "SET GLOBAL long_query_time = 1;"
```

### Simulate lock contention and see it in Grafana

```bash
# Terminal 1 — hold a transaction open
docker exec -it mysql-primary mysql -prootpass shopdb -e "
  START TRANSACTION;
  UPDATE customers SET name='locked' WHERE id=1;
  SELECT SLEEP(30);
  COMMIT;" &

# Terminal 2 — try to update the same row (will block)
docker exec mysql-primary mysql -prootpass shopdb -e "
  UPDATE customers SET name='blocked' WHERE id=1;"

# While those run — check Grafana Processlist dashboard:
# • Active Queries panel: shows both threads
# • Active Transactions: shows age ticking up
# • Lock Waits: shows blocking_thread highlighted in red
```

### Reset performance_schema counters

```bash
# Clears events_statements_summary_by_digest — useful between test runs
docker exec mysql-primary mysql -prootpass -e "
  TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;
  TRUNCATE TABLE performance_schema.events_statements_history_long;"
```

---

## Useful one-liners

```bash
# Replication lag on all replicas
for r in mysql-replica1 mysql-replica2; do
  echo -n "$r: "
  docker exec $r mysql -prootpass -sN \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep Seconds_Behind_Source
done

# Table sizes
docker exec mysql-primary mysql -prootpass 2>/dev/null -e "
SELECT table_name,
       ROUND(data_length/1024/1024, 2) AS data_mb,
       ROUND(index_length/1024/1024, 2) AS index_mb,
       table_rows
FROM information_schema.tables
WHERE table_schema='shopdb'
ORDER BY data_length DESC;"

# Active connections
docker exec mysql-primary mysql -prootpass -e "SHOW FULL PROCESSLIST;" 2>/dev/null

# InnoDB lock waits
docker exec mysql-primary mysql -prootpass 2>/dev/null -e "
SELECT r.trx_id, b.trx_id AS blocks, b.trx_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id;"

# Binary log size
docker exec mysql-primary mysql -prootpass -e "SHOW BINARY LOGS;" 2>/dev/null

# Flush slow log and show path
docker exec mysql-primary mysql -prootpass -e "
FLUSH SLOW LOGS;
SHOW VARIABLES LIKE 'slow_query_log_file';" 2>/dev/null
```

---

## Tear down

```bash
# Stop all, keep volumes
docker compose stop

# Stop and delete everything (data included)
docker compose down -v
```

---

## Related docs

- [Fundamentals](../fundamentals.md) — connection pooling, locks, monitoring queries
- [Observability](../observability.md) — mysqld_exporter, alert hierarchy, PromQL reference
- [Performance Tuning](../performance.md) — EXPLAIN, indexes, events_statements_summary_by_digest
- [Backup & Recovery](../backup-recovery.md) — PITR, mysqldump, xtrabackup
- [Migrations](../migrations.md) — pt-online-schema-change, expand/contract
- [HA & Failover](../ha-failover.md) — ProxySQL routing, Orchestrator, failover runbooks
- [Scaling](../scaling.md) — read replicas, ProxySQL, sharding
- [Anti-Patterns](../antipatterns.md) — sqlcheck categories
- [percona-toolkit](../../resources/percona-toolkit/README.md) — all pt-* tools
