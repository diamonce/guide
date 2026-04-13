# ProxySQL Commands Cheat Sheet

[← DBRE Home](README.md)

---

## Connect to Admin Interface

ProxySQL has two interfaces: **admin** (6032) for configuration and **data** (6033) for application traffic.

```bash
# Admin interface — use mysql 8.3 or earlier; 8.4+/9.x send SET sql_mode which admin rejects
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass

# In the lab (two nodes)
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass   # node-1
mysql -h 127.0.0.1 -P 6034 -uradmin -pradminpass   # node-2

# Data interface — normal app connection
mysql -h 127.0.0.1 -P 6033 -uapp -papppass shopdb

# Web UI
open http://localhost:6080   # node-1 (stats:statspass)
open http://localhost:6081   # node-2
```

> **Note:** MySQL 8.4+ / 9.x clients send `SET @@SESSION.sql_mode` and `SELECT @@version_comment`
> during handshake — ProxySQL admin doesn't implement these. Use `mysql-client@8.3`:
> `/opt/homebrew/opt/mysql-client@8.3/bin/mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass`

---

## Backends (mysql_servers)

```sql
-- View all backend servers
SELECT hostgroup_id, hostname, port, status, weight, max_connections
FROM mysql_servers;

-- Runtime view (what's actually active)
SELECT hostgroup, srv_host, srv_port, status,
       ConnUsed, ConnFree, ConnOK, ConnERR, Queries, Latency_us
FROM stats_mysql_connection_pool;

-- Add a backend
INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections)
VALUES (1, 'mysql-replica3', 3306, 100);

-- Take a backend offline gracefully (drains existing connections)
UPDATE mysql_servers SET status = 'OFFLINE_SOFT'
WHERE hostname = 'mysql-replica1';

-- Hard offline (drops connections immediately)
UPDATE mysql_servers SET status = 'OFFLINE_HARD'
WHERE hostname = 'mysql-replica1';

-- Bring back online
UPDATE mysql_servers SET status = 'ONLINE'
WHERE hostname = 'mysql-replica1';

-- Remove a backend
DELETE FROM mysql_servers WHERE hostname = 'mysql-replica1';

-- Apply runtime → save to disk
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
```

---

## Query Rules (mysql_query_rules)

```sql
-- View all rules (ordered by rule_id — first match wins)
SELECT rule_id, active, match_pattern, destination_hostgroup, cache_ttl, apply
FROM mysql_query_rules
ORDER BY rule_id;

-- Add a rule: route product SELECTs to replicas with 30s cache
INSERT INTO mysql_query_rules
  (rule_id, active, match_pattern, destination_hostgroup, cache_ttl, apply)
VALUES
  (10, 1, '^SELECT .* FROM products', 1, 30000, 1);

-- Add a rule: send writes to primary
INSERT INTO mysql_query_rules
  (rule_id, active, match_pattern, destination_hostgroup, apply)
VALUES
  (20, 1, '^(INSERT|UPDATE|DELETE|REPLACE)', 0, 1);

-- Disable a rule without deleting it
UPDATE mysql_query_rules SET active = 0 WHERE rule_id = 10;

-- Delete a rule
DELETE FROM mysql_query_rules WHERE rule_id = 10;

-- Apply
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
```

---

## Users (mysql_users)

```sql
-- View users
SELECT username, password, default_hostgroup, active, max_connections
FROM mysql_users;

-- Add a user
INSERT INTO mysql_users (username, password, default_hostgroup)
VALUES ('reporting', 'reportpass', 1);   -- hostgroup 1 = replicas

-- Change default hostgroup
UPDATE mysql_users SET default_hostgroup = 0
WHERE username = 'app';

-- Apply
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
```

---

## Query Cache

```sql
-- Cache hit/miss stats per query digest
SELECT hostgroup, schemaname, username, digest_text,
       count_star, cache_count_get, cache_count_set, cache_count_delete
FROM stats_mysql_query_digest
WHERE cache_count_get > 0
ORDER BY cache_count_get DESC
LIMIT 20;

-- Overall cache stats
SELECT variable_name, variable_value
FROM stats_mysql_global
WHERE variable_name LIKE 'Query_Cache%';

-- Flush the entire query cache (no per-key invalidation in ProxySQL)
PROXYSQL FLUSH QUERY CACHE;

-- Disable caching on a rule (set cache_ttl to NULL)
UPDATE mysql_query_rules SET cache_ttl = NULL WHERE rule_id = 3;
LOAD MYSQL QUERY RULES TO RUNTIME;
```

---

## Connection Pool

```sql
-- Live pool state per hostgroup + backend
SELECT hostgroup, srv_host, srv_port, status,
       ConnUsed, ConnFree, ConnOK, ConnERR, Queries, Bytes_data_sent, Latency_us
FROM stats_mysql_connection_pool
ORDER BY hostgroup, srv_host;

-- Aggregate pool stats
SELECT variable_name, variable_value
FROM stats_mysql_global
WHERE variable_name IN (
  'Client_Connections_connected',
  'Client_Connections_created',
  'Server_Connections_connected',
  'Server_Connections_created',
  'Active_Transactions'
);

-- Per-user connection counts
SELECT username, frontend_connections, frontend_max_connections
FROM stats_mysql_users;
```

---

## Traffic Stats

```sql
-- Top queries by count
SELECT hostgroup, digest_text, count_star,
       ROUND(sum_time/count_star/1000) AS avg_ms,
       ROUND(min_time/1000) AS min_ms,
       ROUND(max_time/1000) AS max_ms
FROM stats_mysql_query_digest
ORDER BY count_star DESC
LIMIT 20;

-- Top queries by total time (find slow hogs)
SELECT hostgroup, digest_text, count_star,
       ROUND(sum_time/1000000) AS total_sec,
       ROUND(sum_time/count_star/1000) AS avg_ms
FROM stats_mysql_query_digest
ORDER BY sum_time DESC
LIMIT 10;

-- Reset stats
SELECT * FROM stats_mysql_query_digest_reset LIMIT 1;

-- Hostgroup traffic summary
SELECT hostgroup, SUM(count_star) AS queries, SUM(sum_time)/1e9 AS total_sec
FROM stats_mysql_query_digest
GROUP BY hostgroup;
```

---

## Global Variables

```sql
-- View mysql variables
SELECT variable_name, variable_value
FROM global_variables
WHERE variable_name LIKE 'mysql-%'
ORDER BY variable_name;

-- Common tuning knobs
SET mysql-max_connections = 4096;
SET mysql-default_query_timeout = 10000;       -- ms
SET mysql-connect_timeout_server = 3000;       -- ms
SET mysql-monitor_ping_interval = 5000;        -- ms

-- Apply variables
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
```

---

## Cluster (ProxySQL Cluster)

```sql
-- View cluster peers
SELECT hostname, port, weight, comment FROM proxysql_servers;

-- Sync status per config table (checksum, last_changed, last_checked live here)
SELECT * FROM stats_proxysql_servers_checksums;

-- Cluster sync status (per config table)
SELECT * FROM stats_proxysql_servers_checksums;

-- Add a peer
INSERT INTO proxysql_servers (hostname, port, weight, comment)
VALUES ('proxysql3', 6032, 1, 'node-3');

LOAD PROXYSQL SERVERS TO RUNTIME;
SAVE PROXYSQL SERVERS TO DISK;
```

---

## Save / Load Reference

Changes are made to the **in-memory** config. You must explicitly push to runtime and save to disk.

```sql
-- Servers
LOAD MYSQL SERVERS TO RUNTIME;    SAVE MYSQL SERVERS TO DISK;
-- Query rules
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;
-- Users
LOAD MYSQL USERS TO RUNTIME;      SAVE MYSQL USERS TO DISK;
-- Variables
LOAD MYSQL VARIABLES TO RUNTIME;  SAVE MYSQL VARIABLES TO DISK;
-- Admin variables
LOAD ADMIN VARIABLES TO RUNTIME;  SAVE ADMIN VARIABLES TO DISK;
-- ProxySQL cluster peers
LOAD PROXYSQL SERVERS TO RUNTIME; SAVE PROXYSQL SERVERS TO DISK;

-- Load everything from disk into runtime (emergency rollback to last saved state)
LOAD MYSQL SERVERS FROM DISK;
LOAD MYSQL QUERY RULES FROM DISK;
```

---

## Health Check Queries

```sql
-- Backend health (is monitor seeing them as UP?)
SELECT hostgroup_id, hostname, port, status, last_check_ms
FROM monitor.mysql_server_ping_log
ORDER BY time_start_us DESC
LIMIT 20;

SELECT hostname, port, status, time_start_us, ping_success_time_us, error
FROM monitor.mysql_server_connect_log
ORDER BY time_start_us DESC
LIMIT 20;

-- Replication lag as seen by monitor
SELECT hostname, port, time_start_us, repl_lag, error
FROM monitor.mysql_server_replication_lag_log
ORDER BY time_start_us DESC
LIMIT 20;
```

---

## Lab Quick Reference

```bash
# Credentials (lab)
# Admin:  -h 127.0.0.1 -P 6032 -uradmin  -pradminpass
# Stats:  -h 127.0.0.1 -P 6032 -ustats   -pstatspass
# App:    -h 127.0.0.1 -P 6033 -uapp     -papppass

# Hostgroups
# 0 = primary  (writes)
# 1 = replicas (reads)

# Flush cache one-liner from shell
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass \
  -e "PROXYSQL FLUSH QUERY CACHE"

# Watch query cache hit rate live (refresh every 2s)
watch -n2 "mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass --silent \
  -e \"SELECT variable_name, variable_value FROM stats_mysql_global \
       WHERE variable_name LIKE 'Query_Cache%'\""

# Tail the monitor log for a specific host
mysql -h 127.0.0.1 -P 6032 -uradmin -pradminpass \
  -e "SELECT * FROM monitor.mysql_server_ping_log \
      WHERE hostname='mysql-replica1' ORDER BY time_start_us DESC LIMIT 10"
```

---

[← DBRE Home](README.md)
