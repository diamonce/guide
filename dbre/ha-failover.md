# HA & Failover

[← DBRE Home](README.md) | [← Main](../README.md)

---

## HA Architecture Patterns `[B]`

Three tiers — choose based on your RTO requirement:

```
Tier 1: No HA (single node)
  Primary ──► application
  Failure: manual restart, minutes to hours of downtime

Tier 2: Warm standby (replica + manual promotion)
  Primary ──► Replica
  Failure: DBRE promotes replica manually, 5–30 min RTO

Tier 3: Automated failover (Orchestrator / MHA / cloud-managed)
  Primary ──► Replica(s) ──► Orchestrator monitors
  Failure: auto-promotion in 30–120 seconds, app reconnects via ProxySQL/VIP
```

For most production MySQL workloads: **Tier 3 with ProxySQL**.

---

## Connection Routing: ProxySQL `[B]`

Applications should never connect directly to the primary IP. ProxySQL sits between the app and MySQL — it knows the current primary and routes writes/reads automatically.

```
App pods ──► ProxySQL (port 6033) ──► Primary (hostgroup 10)
                                  └──► Replicas (hostgroup 20)
```

```ini
# /etc/proxysql.cnf — minimal config
datadir="/var/lib/proxysql"

mysql_servers =
(
  { address="db-primary", port=3306, hostgroup=10, max_connections=100 },
  { address="db-replica-1", port=3306, hostgroup=20, max_connections=100 },
  { address="db-replica-2", port=3306, hostgroup=20, max_connections=100 }
)

mysql_replication_hostgroups =
(
  { writer_hostgroup=10, reader_hostgroup=20, comment="r2d2" }
)

mysql_query_rules =
(
  { rule_id=1, active=1, match_pattern="^SELECT", destination_hostgroup=20, apply=1 },
  { rule_id=2, active=1, match_pattern=".*",       destination_hostgroup=10, apply=1 }
)

mysql_users =
(
  { username="app", password="...", default_hostgroup=10 }
)
```

ProxySQL monitors `SHOW SLAVE STATUS` on all backends every few seconds. On master change, it automatically shifts writes to the new primary — applications keep the same connection string and do not need to reconnect.

---

## Automated Failover: MySQL Orchestrator `[I]`

[Orchestrator](https://github.com/openark/orchestrator) is the standard open-source tool for MySQL HA. It monitors replication topology, detects primary failure, and promotes the most up-to-date replica.

```bash
# Install
curl -L https://github.com/openark/orchestrator/releases/latest/download/orchestrator-*.tar.gz | tar xz

# Key config: /etc/orchestrator/orchestrator.conf.json
{
  "MySQLTopologyUser": "orchestrator",
  "MySQLTopologyPassword": "use-secrets-manager",
  "DetectClusterAliasQuery": "SELECT 'r2d2'",
  "FailoverOnPromotionViaSlaveLagSeconds": 30,
  "RecoveryPeriodBlockSeconds": 3600,
  "OnFailureDetectionProcesses": [
    "echo 'Failure detected on {failedHost}' | slack-notify"
  ],
  "PostFailoverProcesses": [
    "echo 'Promoted {successorHost} as new primary' | slack-notify"
  ]
}
```

```sql
-- Orchestrator monitoring user (on each MySQL node)
CREATE USER 'orchestrator'@'%' IDENTIFIED BY 'use-secrets-manager';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO 'orchestrator'@'%';
GRANT SELECT ON mysql.slave_master_info TO 'orchestrator'@'%';
```

**Orchestrator topology discovery:**

```bash
# Discover a cluster
orchestrator-client -c discover -i db-primary:3306

# Show current topology
orchestrator-client -c topology -i r2d2

# Output:
# db-primary:3306 [OK,5.7.38,rw,ROW] 0s lag
#   + db-replica-1:3306 [OK,5.7.38,ro,ROW] 1s lag
#   + db-replica-2:3306 [OK,5.7.38,ro,ROW] 2s lag
```

**Manual failover (when automated failover is disabled or you want control):**

```bash
# Graceful: promote specific replica (primary still alive — maintenance)
orchestrator-client -c graceful-master-takeover-auto -i r2d2 -d db-replica-1:3306

# Forced: primary is dead, promote best replica
orchestrator-client -c recover -i db-primary:3306
```

---

## Cloud-Managed Failover: RDS / Aurora `[B]`

```hcl
# RDS Multi-AZ — automated failover in ~60s
resource "aws_db_instance" "primary" {
  multi_az            = true
  # RDS promotes standby automatically on primary failure
  # DNS endpoint stays the same — apps reconnect to same hostname
}

# Aurora — automated failover in ~30s, up to 15 replicas
resource "aws_rds_cluster" "aurora" {
  engine = "aurora-mysql"
}
resource "aws_rds_cluster_instance" "primary" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.xlarge"
  promotion_tier     = 0   # lowest = highest failover priority
}
resource "aws_rds_cluster_instance" "replica" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.large"
  promotion_tier     = 1
}
```

**Aurora cluster endpoint vs. instance endpoints:**

```
Cluster endpoint (writer):  mydb.cluster-xxx.rds.amazonaws.com  → always points to primary
Reader endpoint:             mydb.cluster-ro-xxx.rds.amazonaws.com → load-balanced replicas
Instance endpoint:           mydb-instance-1.xxx.rds.amazonaws.com → specific instance (avoid in app config)
```

Always use the **cluster endpoint** in your application — it follows failover automatically.

---

## Failover Runbook `[I]`

### Scenario A: Planned failover (maintenance, upgrade)

```bash
# 1. Confirm topology before starting
orchestrator-client -c topology -i r2d2

# 2. Verify replica is caught up (lag = 0)
mysql -h db-replica-1 -e "SHOW SLAVE STATUS\G" | grep Seconds_Behind_Master

# 3. Graceful takeover — Orchestrator handles it
orchestrator-client -c graceful-master-takeover-auto -i r2d2 -d db-replica-1:3306

# 4. Verify promotion
orchestrator-client -c topology -i r2d2
mysql -h db-replica-1 -e "SHOW MASTER STATUS\G"   # should now be primary

# 5. Verify apps reconnected (if using ProxySQL)
mysql -h proxysql -P 6032 -u admin -e "SELECT * FROM runtime_mysql_servers;"
```

### Scenario B: Emergency failover (primary dead)

```bash
# 1. Confirm primary is actually dead (not a network blip)
ping db-primary
mysql -h db-primary -e "SELECT 1" --connect-timeout=5

# 2. Check if Orchestrator already promoted a replica
orchestrator-client -c topology -i r2d2

# 3. If not auto-promoted, force recovery
orchestrator-client -c recover -i db-primary:3306

# 4. Verify new primary is healthy
mysql -h db-replica-1 -e "SHOW MASTER STATUS\G"
mysql -h db-replica-1 -e "SELECT @@read_only;"   # must be 0

# 5. Verify ProxySQL rerouted (or update ProxySQL manually if needed)
mysql -h proxysql -P 6032 -u admin \
  -e "UPDATE mysql_servers SET hostgroup_id=10 WHERE hostname='db-replica-1';
      LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"

# 6. Check all remaining replicas are replicating from new primary
mysql -h db-replica-2 -e "SHOW SLAVE STATUS\G" | grep -E "Master_Host|Running|Behind"

# 7. Provision replacement replica for the failed primary
# (see: provisioning a new replica below)
```

### Scenario C: Workers didn't reconnect after failover

```bash
# Verify new primary is healthy first
mysql -h proxysql -e "SELECT @@hostname, @@read_only;"

# Restart affected namespace (faster than GitOps release)
kubectl rollout restart deployment -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>

# Verify workers reconnected
kubectl logs -n <namespace> -l app=<worker> --since=2m | grep -i "connect"
```

---

## Provisioning a New Replica `[I]`

After a failover, provision a replacement replica to restore redundancy:

```bash
# 1. Take a backup from the new primary (or existing replica — less load)
mysqldump --single-transaction --master-data=2 \
  -h db-replica-1 -u backup mydb > /tmp/backup.sql

# Or faster with xtrabackup:
xtrabackup --backup --target-dir=/tmp/xtrabackup --host=db-replica-1

# 2. Restore on new instance
mysql -h new-replica < /tmp/backup.sql

# 3. Configure replication (binlog position is in the dump header)
# --master-data=2 writes it as a comment: CHANGE MASTER TO MASTER_LOG_FILE='...', MASTER_LOG_POS=...
mysql -h new-replica -e "
  CHANGE MASTER TO
    MASTER_HOST='db-replica-1',
    MASTER_USER='replication',
    MASTER_PASSWORD='use-secrets-manager',
    MASTER_LOG_FILE='mysql-bin.000042',
    MASTER_LOG_POS=12345;
  START SLAVE;"

# 4. Verify replication running and lag closing
mysql -h new-replica -e "SHOW SLAVE STATUS\G" | grep -E "Running|Behind"

# 5. Register with Orchestrator
orchestrator-client -c discover -i new-replica:3306
```

---

## Application Connection Resilience `[B]`

The failover incident from the r2d2 cluster happened because apps held stale connections. Two layers of defense:

**Layer 1: Connection pool validation (detect stale connections before use)**

```python
# SQLAlchemy
engine = create_engine(
    "mysql+pymysql://app:pass@proxysql:6033/mydb",
    pool_pre_ping=True,       # SELECT 1 before each checkout — detects dead connections
    pool_recycle=3600,        # recycle connections every hour regardless
    pool_size=10,
    max_overflow=20,
)
```

```yaml
# Django settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'HOST': 'proxysql',
        'PORT': '6033',
        'CONN_MAX_AGE': 60,        # don't hold connections forever
        'OPTIONS': {
            'connect_timeout': 10,
            'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
        }
    }
}
```

**Layer 2: Retry on transient connection errors**

```python
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
import pymysql

@retry(
    retry=retry_if_exception_type((pymysql.OperationalError, pymysql.InterfaceError)),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    stop=stop_after_attempt(5)
)
def db_query(session, stmt):
    return session.execute(stmt)
```

---

## MySQL Version Upgrades `[I]`

Major version upgrades (5.7 → 8.0) are high-risk operations. Use blue/green to preserve a rollback window.

```bash
# Blue/green upgrade via replication
# 1. Set up a replica running the NEW version
mysqldump --single-transaction --master-data=2 -h primary-5.7 mydb > /tmp/backup.sql
mysql -h new-8.0-instance < /tmp/backup.sql
# Configure replication: new-8.0-instance replicates from primary-5.7

# 2. Let it catch up, verify no replication errors
mysql -h new-8.0-instance -e "SHOW SLAVE STATUS\G"

# 3. Run application against new-8.0-instance in staging — check for:
#    - Deprecated SQL syntax (SHOW WARNINGS)
#    - Authentication plugin changes (caching_sha2_password vs mysql_native_password)
#    - Removed variables (query_cache_* no longer exist in 8.0)

# 4. Cutover: stop writes to old primary, let new-8.0 catch up, promote
SET GLOBAL read_only = ON;   -- on old primary
# Wait for Seconds_Behind_Master = 0 on new-8.0
orchestrator-client -c graceful-master-takeover-auto -i cluster -d new-8.0:3306

# 5. Keep old 5.7 primary as a replica for 24h — easy rollback if needed
```

**MySQL 8.0 common upgrade gotchas:**

| Issue | Check |
|-------|-------|
| `query_cache_*` variables removed | Remove from `my.cnf` before upgrade |
| `utf8mb3` → `utf8mb4` default | Test collation-sensitive queries and indexes |
| `caching_sha2_password` default auth | Update client drivers and connection strings |
| `ONLY_FULL_GROUP_BY` stricter | Audit GROUP BY queries in slow log |
| Reserved words expanded | Check column/table names against new reserved words list |

---

## Related Topics

- [Observability](observability.md) — replication lag alerts and MySQL monitoring
- [Fundamentals](fundamentals.md) — connection pooling, ProxySQL basics
- [Scaling Databases](scaling.md) — read replicas, connection pooling at scale
- [Backup & Recovery](backup-recovery.md) — snapshot before planned failover
- [percona-toolkit](../resources/percona-toolkit/README.md) — pt-heartbeat for replication monitoring
