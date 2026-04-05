#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Script 10: MySQL Schema Changes — pt-osc, gh-ost, Online DDL
#
# Demonstrates:
#   - ALGORITHM=INSTANT / INPLACE dry runs
#   - Duration estimation
#   - pt-online-schema-change (via toolkit container)
#   - gh-ost (docker run, against lab primary)
#   - Monitoring replication lag during the change
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
PRIMARY=127.0.0.1
PORT=3310            # mysql-primary exposed port
USER=root
PASS=rootpass
DB=shopdb
TABLE=orders

mysql_cmd() { mysql -h $PRIMARY -P $PORT -u$USER -p$PASS --connect-timeout=5 2>/dev/null "$@"; }

header() { echo; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $1"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# ─── Seed extra rows so migrations take a measurable amount of time ───────────
header "0. Seeding extra rows into orders (5000 rows)"
mysql_cmd $DB <<'SQL'
DROP PROCEDURE IF EXISTS seed_orders;
DELIMITER //
CREATE PROCEDURE seed_orders()
BEGIN
  DECLARE i INT DEFAULT 0;
  WHILE i < 5000 DO
    INSERT INTO orders (customer_id, total, status)
    VALUES (
      FLOOR(1 + RAND() * 5),
      ROUND(RAND() * 500, 2),
      ELT(FLOOR(1 + RAND() * 4), 'pending','paid','shipped','cancelled')
    );
    SET i = i + 1;
  END WHILE;
END//
DELIMITER ;
CALL seed_orders();
DROP PROCEDURE seed_orders;
SQL
mysql_cmd $DB -e "SELECT COUNT(*) AS total_orders FROM orders;"

# ─── Step 1: Measure table ────────────────────────────────────────────────────
header "1. Table size and row count"
mysql_cmd -e "
SELECT
  table_name,
  table_rows                                              AS est_rows,
  ROUND(data_length  / 1024, 0)                          AS data_kb,
  ROUND(index_length / 1024, 0)                          AS index_kb,
  ROUND((data_length + index_length) / 1024, 0)          AS total_kb
FROM information_schema.tables
WHERE table_schema = '$DB'
ORDER BY data_length DESC;"

# ─── Step 2: Algorithm dry runs ──────────────────────────────────────────────
header "2. Test ALGORITHM=INSTANT (ADD COLUMN at end)"
echo "→ Testing: ALTER TABLE $TABLE ADD COLUMN notes TEXT, ALGORITHM=INSTANT"
mysql_cmd $DB -e "ALTER TABLE $TABLE ADD COLUMN notes TEXT, ALGORITHM=INSTANT;" \
  && echo "✓ INSTANT supported — zero lock, no copy" \
  || echo "✗ INSTANT not supported — try INPLACE"

# Remove the column we just added so we can test it properly
mysql_cmd $DB -e "ALTER TABLE $TABLE DROP COLUMN notes, ALGORITHM=INSTANT;" 2>/dev/null || true

echo
echo "→ Testing: ADD INDEX ALGORITHM=INPLACE, LOCK=NONE"
mysql_cmd $DB -e "ALTER TABLE $TABLE ADD INDEX idx_test_status (status), ALGORITHM=INPLACE, LOCK=NONE;" \
  && echo "✓ INPLACE/LOCK=NONE supported" \
  || echo "✗ Need COPY → use pt-osc or gh-ost"
mysql_cmd $DB -e "ALTER TABLE $TABLE DROP INDEX idx_test_status;" 2>/dev/null || true

echo
echo "→ Testing a TYPE CHANGE (should fail INPLACE — needs COPY)"
mysql_cmd $DB -e "ALTER TABLE $TABLE MODIFY COLUMN status VARCHAR(30), ALGORITHM=INPLACE, LOCK=NONE;" \
  && echo "✓ INPLACE OK" \
  || echo "✗ Needs COPY — use pt-osc or gh-ost for large tables"

# ─── Step 3: Duration estimation ─────────────────────────────────────────────
header "3. Write rate measurement (10-second window)"
mysql_cmd -e "
  SELECT variable_value INTO @before FROM performance_schema.global_status
  WHERE variable_name = 'Innodb_rows_inserted';"
echo "Measuring inserts for 10 seconds..."
sleep 10
mysql_cmd -e "
  SELECT (variable_value - @before) AS inserts_in_10s,
         ROUND((variable_value - @before) * 6, 0) AS est_inserts_per_min
  FROM performance_schema.global_status
  WHERE variable_name = 'Innodb_rows_inserted';"

# ─── Step 4: pt-online-schema-change ─────────────────────────────────────────
header "4. pt-online-schema-change — ADD COLUMN via toolkit container"

echo "→ Dry run first (no changes)"
docker exec toolkit pt-online-schema-change \
  --host=mysql-primary \
  --user=$USER --password=$PASS \
  --database=$DB \
  --table=$TABLE \
  --alter="ADD COLUMN notes TEXT" \
  --chunk-size=500 \
  --max-lag=3 \
  --dry-run \
  2>&1 | grep -E "Dry run|Would|chunk|table|trigger|error" || true

echo
echo "→ Actual run (small table — will be fast)"
docker exec toolkit pt-online-schema-change \
  --host=mysql-primary \
  --user=$USER --password=$PASS \
  --database=$DB \
  --table=$TABLE \
  --alter="ADD COLUMN notes TEXT" \
  --chunk-size=500 \
  --chunk-time=0.5 \
  --max-lag=5 \
  --check-interval=2 \
  --max-load="Threads_running=20" \
  --critical-load="Threads_running=50" \
  --set-vars="lock_wait_timeout=5" \
  --no-drop-old-table \
  --execute 2>&1 | tail -20

echo
echo "→ Verify column was added"
mysql_cmd $DB -e "SHOW COLUMNS FROM $TABLE LIKE 'notes';"

echo
echo "→ Old table is preserved as _${TABLE}_old (for manual verification)"
mysql_cmd $DB -e "SHOW TABLES LIKE '%${TABLE}%';"

echo
echo "→ Drop old table when satisfied"
mysql_cmd $DB -e "DROP TABLE IF EXISTS _${TABLE}_old;" 2>/dev/null || true

# ─── Step 5: gh-ost ──────────────────────────────────────────────────────────
header "5. gh-ost — ADD INDEX via ghost table (binlog-based, no triggers)"

echo "gh-ost requires network access from the host machine to the primary."
echo "Using: docker run --network dbre-lab_db-net"

# Create a postpone flag file to control cutover manually
POSTPONE_FILE=/tmp/gh-ost-lab.postpone

echo
echo "→ Running gh-ost with postponed cutover (touch $POSTPONE_FILE to delay swap)"
touch $POSTPONE_FILE

docker run --rm --network dbre-lab_db-net \
  -v /tmp:/tmp \
  skeema/gh-ost:latest \
    --host=mysql-primary \
    --port=3306 \
    --user=$USER \
    --password=$PASS \
    --database=$DB \
    --table=$TABLE \
    --alter="ADD INDEX idx_gh_total (total)" \
    --chunk-size=500 \
    --max-lag-millis=2000 \
    --max-load="Threads_running=20" \
    --critical-load="Threads_running=50" \
    --serve-socket-file=/tmp/gh-ost-lab.sock \
    --postpone-cut-over-flag-file=$POSTPONE_FILE \
    --ok-to-drop-table \
    --initially-drop-ghost-table \
    --initially-drop-socket-file \
    --verbose \
    --execute &

GH_OST_PID=$!

echo "gh-ost running (PID $GH_OST_PID)"
echo "Control commands while running:"
echo "  Pause:   echo throttle | nc -U /tmp/gh-ost-lab.sock"
echo "  Resume:  echo no-throttle | nc -U /tmp/gh-ost-lab.sock"
echo "  Status:  echo status | nc -U /tmp/gh-ost-lab.sock"
echo "  Abort:   echo panic | nc -U /tmp/gh-ost-lab.sock"
echo
echo "Waiting for copy to complete..."
sleep 5

# Check status
if [ -S /tmp/gh-ost-lab.sock ]; then
  echo status | nc -U /tmp/gh-ost-lab.sock 2>/dev/null || true
fi

# Allow cutover
echo "Releasing postpone flag → cutover will proceed"
rm -f $POSTPONE_FILE

wait $GH_OST_PID || true

echo
echo "→ Verify index was added"
mysql_cmd $DB -e "SHOW INDEX FROM $TABLE WHERE Key_name = 'idx_gh_total';"

# ─── Step 6: Monitor replication lag during a migration ──────────────────────
header "6. What to watch — replication lag during change"

echo "Replication lag after all changes:"
for replica in mysql-replica1 mysql-replica2; do
  echo -n "  $replica: "
  docker exec $replica mysql -p$PASS -sN \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep Seconds_Behind_Source || echo "N/A"
done

echo
echo "Performance schema — top queries generated by migration tools:"
mysql_cmd -e "
SELECT
  SUBSTRING(DIGEST_TEXT, 1, 80) AS query_pattern,
  COUNT_STAR AS calls,
  ROUND(AVG_TIMER_WAIT/1e9, 2) AS avg_ms
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = '$DB'
  AND (DIGEST_TEXT LIKE '%_orders%' OR DIGEST_TEXT LIKE '%pt-osc%' OR DIGEST_TEXT LIKE '%gh-ost%')
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;" 2>/dev/null || true

header "Done. Summary of changes made to $TABLE:"
mysql_cmd $DB -e "SHOW CREATE TABLE $TABLE\G" | grep -E "notes|idx_gh"

echo
echo "Open Grafana http://localhost:3000 → MySQL Processlist → Top Queries"
echo "to see the migration queries in events_statements_summary_by_digest."
