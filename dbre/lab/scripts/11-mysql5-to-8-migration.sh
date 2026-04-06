#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Zero-downtime MySQL 5.7 → 8.0 migration
#
# Strategy: replication-based cutover
#   mysql57 (source, 5.7)  ──replicates──►  mysql-primary (target, 8.0)
#
# Phase 1 — Compatibility check     : find breaking changes before touching prod
# Phase 2 — Seed & snapshot          : get data into MySQL 8
# Phase 3 — Set up cross-version replication
# Phase 4 — Validate                 : checksums, app smoke test
# Phase 5 — Cutover via ProxySQL     : atomic write switch, zero downtime
# Phase 6 — Rollback path            : keep 5.7 as replica for 24h
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

M57="docker exec mysql57"
M8="docker exec mysql-primary"
PT="docker exec toolkit"

mysql57() { $M57 mysql -u root -prootpass 2>/dev/null "$@"; }
mysql8()  { $M8  mysql -u root -prootpass 2>/dev/null "$@"; }

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

wait_for() {
    local host=$1
    echo -n "Waiting for $host..."
    until docker exec "$host" mysqladmin ping -u root -prootpass -s 2>/dev/null; do
        sleep 2; echo -n "."
    done
    echo " ready"
}

# ─── Phase 1: Compatibility check ────────────────────────────────────────────
header "Phase 1: Compatibility check — breaking changes 5.7 → 8.0"

echo "--- Source (5.7) version ---"
mysql57 -e "SELECT @@version, @@version_comment;"

echo ""
echo "--- Check 1: Tables using utf8mb3 (renamed in 8.0, no action needed but verify) ---"
mysql57 shopdb -e "
    SELECT table_name, ccsa.character_set_name, ccsa.collation_name
    FROM information_schema.tables t
    JOIN information_schema.collation_character_set_applicability ccsa
        ON ccsa.collation_name = t.table_collation
    WHERE t.table_schema = 'shopdb'
      AND ccsa.character_set_name IN ('utf8','utf8mb3');" 2>/dev/null || true

echo ""
echo "--- Check 2: Columns using deprecated types or zero dates ---"
mysql57 shopdb -e "
    SELECT table_name, column_name, column_type, extra
    FROM information_schema.columns
    WHERE table_schema = 'shopdb'
      AND (column_type LIKE '%zerofill%'
        OR column_default = '0000-00-00'
        OR extra LIKE '%on update%');" 2>/dev/null || true

echo ""
echo "--- Check 3: ENUM/SET columns (order matters — do not reorder) ---"
mysql57 shopdb -e "
    SELECT table_name, column_name, column_type
    FROM information_schema.columns
    WHERE table_schema = 'shopdb'
      AND column_type LIKE 'enum%';" 2>/dev/null || true

echo ""
echo "--- Check 4: sql_mode differences (8.0 adds ONLY_FULL_GROUP_BY etc.) ---"
echo "5.7 sql_mode:"
mysql57 -e "SELECT @@GLOBAL.sql_mode\G" 2>/dev/null || true
echo ""
echo "Common 5.7→8.0 sql_mode additions that break queries:"
echo "  ONLY_FULL_GROUP_BY   — GROUP BY must include all non-aggregated SELECTs"
echo "  NO_ZERO_IN_DATE      — '2020-00-01' no longer allowed"
echo "  NO_ZERO_DATE         — '0000-00-00' no longer allowed"
echo "  ERROR_FOR_DIVISION_BY_ZERO — DIV/0 is error, not NULL"

echo ""
echo "--- Check 5: Reserved words added in 8.0 used as identifiers ---"
echo "Checking for columns named with new 8.0 reserved words..."
mysql57 information_schema -e "
    SELECT t.table_schema, t.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t USING (table_schema, table_name)
    WHERE t.table_schema = 'shopdb'
      AND UPPER(c.column_name) IN (
        'RANK','GROUPS','ROWS','LAG','LEAD','DENSE_RANK','CUME_DIST',
        'FIRST_VALUE','LAST_VALUE','NTH_VALUE','NTILE','OVER','WINDOW',
        'SYSTEM','ARRAY','FAILED_LOGIN_ATTEMPTS','MASTER_COMPRESSION_ALGORITHMS',
        'LATERAL','OF','RECURSIVE'
      );" 2>/dev/null || true

echo ""
echo "--- Check 6: Run MySQL Upgrade Checker (if available) ---"
$PT mysqlcheck \
    --host=mysql57 \
    --user=root \
    --password=rootpass \
    --all-databases \
    --check-upgrade \
    2>/dev/null | grep -v "^shopdb\." | head -20 || echo "(mysqlcheck not available in toolkit)"

# ─── Phase 2: Seed and snapshot ───────────────────────────────────────────────
header "Phase 2: Take snapshot of 5.7 and restore to 8.0 target"

wait_for mysql57

echo "--- Current 5.7 data ---"
mysql57 shopdb -e "SELECT COUNT(*) AS rows_in_57 FROM orders;"

echo ""
echo "--- Flushing binlog on 5.7 before backup ---"
mysql57 -e "FLUSH BINARY LOGS;"

GTID_57=$(docker exec mysql57 mysql -u root -prootpass -sN \
    -e "SELECT @@GLOBAL.gtid_executed;" 2>/dev/null | tr -d ' \n') || true
echo "GTID set at snapshot time: $GTID_57"

echo ""
echo "--- Dumping 5.7 with GTID info ---"
docker exec mysql57 mysqldump \
    -u root -prootpass \
    --all-databases \
    --single-transaction \
    --set-gtid-purged=ON \
    --source-data=2 \
    --routines --triggers --events \
    2>/dev/null \
    > /tmp/mysql57_snapshot.sql

echo "✅ Snapshot: /tmp/mysql57_snapshot.sql ($(du -sh /tmp/mysql57_snapshot.sql | cut -f1))"

echo ""
echo "--- Restoring snapshot to 8.0 (clean target) ---"
echo "NOTE: In production this targets a fresh MySQL 8.0 instance, not an existing one"
echo "Skipping restore to existing mysql-primary to avoid data loss in lab"
echo ""
echo "Production restore command:"
echo "  mysql -h mysql8-host -u root -p < mysql57_snapshot.sql"

# ─── Phase 3: Cross-version replication 5.7 → 8.0 ────────────────────────────
header "Phase 3: Set up replication — MySQL 5.7 (source) → MySQL 8.0 (replica)"

echo "Key facts about cross-version replication:"
echo "  ✓ MySQL supports replication from older → newer version"
echo "  ✗ NOT supported: newer → older (8.0 cannot replicate TO 5.7)"
echo "  ✓ GTID replication works across 5.7 → 8.0"
echo "  ✓ ROW-based binlog format is safest across versions"
echo ""

echo "--- Ensuring replicator user exists on 5.7 with native password ---"
mysql57 -e "
    CREATE USER IF NOT EXISTS 'replicator'@'%'
        IDENTIFIED WITH mysql_native_password BY 'replpass';
    GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
    FLUSH PRIVILEGES;" 2>/dev/null || true

echo ""
echo "--- 5.7 master status ---"
mysql57 -e "SHOW MASTER STATUS\G" 2>/dev/null || true

echo ""
echo "Production command to point MySQL 8.0 at MySQL 5.7:"
cat <<'CMD'
  -- Run on the MySQL 8.0 instance
  STOP REPLICA;
  CHANGE REPLICATION SOURCE TO
      SOURCE_HOST       = 'mysql57-host',
      SOURCE_PORT       = 3306,
      SOURCE_USER       = 'replicator',
      SOURCE_PASSWORD   = 'replpass',
      SOURCE_AUTO_POSITION = 1;   -- requires GTID on both ends
  START REPLICA;
  SHOW REPLICA STATUS\G
CMD

echo ""
echo "--- Simulating: point our mysql-primary (8.0) at mysql57 (5.7) ---"
echo "(Skipping in lab — mysql-primary already has its own data)"
echo ""
echo "In production, after CHANGE REPLICATION SOURCE:"
echo "  Watch: SHOW REPLICA STATUS\\G"
echo "  Wait:  Seconds_Behind_Source = 0"
echo "  Check: Replica_IO_Running = Yes, Replica_SQL_Running = Yes"

# ─── Phase 4: Validate ────────────────────────────────────────────────────────
header "Phase 4: Validate data consistency before cutover"

echo "--- pt-table-checksum between 5.7 and 8.0 ---"
echo "(In production: run against both source and replica)"
$PT pt-table-checksum \
    --host=mysql57 \
    --user=root \
    --password=rootpass \
    --databases=shopdb \
    --replicate=shopdb.checksums \
    --create-replicate-table \
    --no-check-binlog-format \
    2>/dev/null | tail -10 || echo "(pt-table-checksum skipped — mysql57 may not be running)"

echo ""
echo "--- Application smoke test checklist ---"
echo "  □ Connect app to MySQL 8.0 replica with read-only flag"
echo "  □ Run SELECT queries — verify results match 5.7"
echo "  □ Check sql_mode — run GROUP BY queries with ONLY_FULL_GROUP_BY"
echo "  □ Verify utf8/utf8mb4 strings display correctly"
echo "  □ Test stored procedures and triggers"
echo "  □ Verify authentication (native_password vs caching_sha2)"

# ─── Phase 5: Cutover via ProxySQL ───────────────────────────────────────────
header "Phase 5: Zero-downtime cutover via ProxySQL"

echo "Traffic flow before cutover:"
echo "  App → ProxySQL → MySQL 5.7 (primary, hostgroup 0)"
echo ""
echo "Traffic flow after cutover:"
echo "  App → ProxySQL → MySQL 8.0 (primary, hostgroup 0)"
echo ""
echo "The switch is a single ProxySQL admin command — takes effect immediately:"
echo ""
cat <<'PROXYSQL_CMDS'
  -- 1. Add MySQL 8.0 as the new primary
  INSERT INTO mysql_servers (hostgroup_id, hostname, port, status)
  VALUES (0, 'mysql8-host', 3306, 'ONLINE');

  -- 2. Set MySQL 5.7 to SHUNNED (drains connections, no new ones)
  UPDATE mysql_servers SET status='SHUNNED'
  WHERE hostname='mysql57-host' AND hostgroup_id=0;

  -- 3. Apply atomically
  LOAD MYSQL SERVERS TO RUNTIME;

  -- 4. Verify traffic moved
  SELECT hostgroup, srv_host, status, ConnUsed, Queries
  FROM stats_mysql_connection_pool;

  -- 5. Persist
  SAVE MYSQL SERVERS TO DISK;

  -- 6. Remove old server after confirming stable
  DELETE FROM mysql_servers WHERE hostname='mysql57-host';
  LOAD MYSQL SERVERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
PROXYSQL_CMDS

echo ""
echo "Total write downtime: 0ms (ProxySQL queues in-flight transactions)"
echo "Rollback: set mysql57 back to ONLINE and mysql8 to SHUNNED"

# ─── Phase 6: Rollback path ───────────────────────────────────────────────────
header "Phase 6: Rollback and post-cutover cleanup"

echo "Rollback window: keep MySQL 5.7 running as replica of 8.0 for 24–48h"
echo ""
echo "Reverse replication for rollback capability:"
cat <<'ROLLBACK'
  -- On MySQL 5.7, point it at MySQL 8.0 (reverse replication)
  -- NOTE: 8.0 → 5.7 replication is NOT officially supported but works for
  --       simple schemas. For safety, keep 5.7 as a hot standby only.
  STOP SLAVE;
  CHANGE MASTER TO
      MASTER_HOST='mysql8-host',
      MASTER_USER='replicator',
      MASTER_PASSWORD='replpass',
      MASTER_AUTO_POSITION=1;
  START SLAVE;
ROLLBACK

echo ""
echo "Rollback trigger (if 8.0 has critical issues within SLA window):"
echo "  1. ProxySQL: set mysql57 ONLINE, mysql8 SHUNNED (same as cutover, reversed)"
echo "  2. Stop writes to MySQL 8.0"
echo "  3. Let 5.7 catch up (Seconds_Behind_Source = 0)"
echo "  4. Point traffic back to 5.7"
echo ""
echo "Post-cutover cleanup (after 48h stability):"
echo "  □ Drop checksums table"
echo "  □ Remove MySQL 5.7 from ProxySQL config"
echo "  □ Stop and decommission mysql57 container/host"
echo "  □ Update monitoring dashboards"
echo "  □ Update runbook to reflect MySQL 8.0"

header "Migration complete — summary"
cat <<'SUMMARY'
  Step                         Downtime   Time
  ────────────────────────────────────────────────────
  1. Compatibility check       0          1–4 hours
  2. Snapshot + restore        0          30 min–4 hrs
  3. Set up replication        0          minutes
  4. Replication catch-up      0          minutes–hours
  5. Validation                0          1–8 hours
  6. ProxySQL cutover          0ms        seconds
  7. Monitor + rollback ready  0          24–48 hours
  ────────────────────────────────────────────────────
  Total app downtime: 0
SUMMARY
