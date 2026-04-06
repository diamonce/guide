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

# ─── Reset: undo everything this script creates so it can be re-run ───────────
header "0a. Reset — cleaning up previous run artifacts"
mysql_cmd $DB -e "
    -- Remove columns added by pt-osc / INSTANT demos
    ALTER TABLE \`$TABLE\` DROP COLUMN IF EXISTS notes;

    -- Remove indexes added by gh-ost / INPLACE demos
    DROP INDEX IF EXISTS idx_gh_unit_price ON \`order_items\`;
    DROP INDEX IF EXISTS idx_test_status   ON \`$TABLE\`;

    -- Remove old shadow table left by pt-osc --no-drop-old-table
    DROP TABLE IF EXISTS \`_${TABLE}_old\`;

    -- Remove ghost / old tables left by gh-ost
    DROP TABLE IF EXISTS \`_order_items_ghc\`;
    DROP TABLE IF EXISTS \`_order_items_gho\`;
" 2>/dev/null || true
echo "✅ Reset complete"

# ─── Seed extra rows so migrations take a measurable amount of time ───────────
header "0b. Seeding extra rows into orders (5000 rows)"
mysql_cmd $DB -e "
    SET foreign_key_checks=0;
    TRUNCATE TABLE order_items;
    TRUNCATE TABLE orders;
    SET foreign_key_checks=1;"

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
BEFORE=$(mysql_cmd -sN -e "SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_rows_inserted';")
echo "Measuring inserts for 10 seconds..."
sleep 10
AFTER=$(mysql_cmd -sN -e "SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_rows_inserted';")
DELTA=$(( AFTER - BEFORE ))
echo "inserts_in_10s: $DELTA  |  est_inserts_per_min: $(( DELTA * 6 ))"

# ─── Step 4: pt-online-schema-change ─────────────────────────────────────────
header "4. pt-online-schema-change — ADD COLUMN via toolkit container"

echo "→ Dry run first (no changes)"
docker exec toolkit pt-online-schema-change \
  --host=mysql-primary \
  --user=$USER --password=$PASS \
  --alter="ADD COLUMN notes TEXT" \
  --alter-foreign-keys-method=auto \
  --recursion-method=none \
  --chunk-size=500 \
  --max-lag=3 \
  --dry-run \
  D=$DB,t=$TABLE \
  2>&1 | grep -E "Dry run|Would|chunk|table|trigger|slave|error|warning" || true

echo
echo "→ Actual run (small table — will be fast)"
docker exec toolkit pt-online-schema-change \
  --host=mysql-primary \
  --user=$USER --password=$PASS \
  --alter="ADD COLUMN notes TEXT" \
  --alter-foreign-keys-method=auto \
  --recursion-method=none \
  --chunk-size=500 \
  --chunk-time=0.5 \
  --max-lag=5 \
  --check-interval=2 \
  --max-load="Threads_running=20" \
  --critical-load="Threads_running=50" \
  --set-vars="lock_wait_timeout=5" \
  --no-drop-old-table \
  --execute \
  D=$DB,t=$TABLE \
  2>&1 | tail -20

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

echo "gh-ost runs inside the toolkit container (same Docker network as primary)"

POSTPONE_FILE=/tmp/gh-ost-lab.postpone
SOCK_FILE=/tmp/gh-ost-lab.sock

# Create postpone flag inside toolkit container
docker exec toolkit touch $POSTPONE_FILE

echo
echo "→ Running gh-ost with postponed cutover"
docker exec toolkit gh-ost \
    --host=mysql-primary \
    --port=3306 \
    --user=$USER \
    --password=$PASS \
    --database=$DB \
    --table=order_items \
    --alter="ADD INDEX idx_gh_unit_price (unit_price)" \
    --chunk-size=500 \
    --max-lag-millis=2000 \
    --max-load="Threads_running=20" \
    --critical-load="Threads_running=50" \
    --serve-socket-file=$SOCK_FILE \
    --postpone-cut-over-flag-file=$POSTPONE_FILE \
    --ok-to-drop-table \
    --initially-drop-ghost-table \
    --initially-drop-socket-file \
    --assume-rbr \
    --verbose \
    --execute &

GH_OST_PID=$!
echo "gh-ost running in background (PID $GH_OST_PID)"
echo "Control commands:"
echo "  Status:  docker exec toolkit sh -c 'echo status | nc -U $SOCK_FILE'"
echo "  Pause:   docker exec toolkit sh -c 'echo throttle | nc -U $SOCK_FILE'"
echo "  Resume:  docker exec toolkit sh -c 'echo no-throttle | nc -U $SOCK_FILE'"

echo
echo "Waiting for row copy to start..."
sleep 8

docker exec toolkit sh -c "echo status | nc -U $SOCK_FILE 2>/dev/null" || true

echo
echo "Releasing postpone flag → cutover will proceed"
docker exec toolkit rm -f $POSTPONE_FILE

wait $GH_OST_PID || true

echo
echo "→ Verify index was added"
mysql_cmd $DB -e "SHOW INDEX FROM order_items WHERE Key_name = 'idx_gh_unit_price';"

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

header "Done. Summary of changes made to $TABLE and order_items:"
echo "--- $TABLE columns and indexes ---"
mysql_cmd $DB -e "SHOW COLUMNS FROM $TABLE;" 2>/dev/null
mysql_cmd $DB -e "SHOW INDEX FROM $TABLE;" 2>/dev/null | awk '{print $1, $3, $5}'
echo ""
echo "--- order_items indexes ---"
mysql_cmd $DB -e "SHOW INDEX FROM order_items;" 2>/dev/null | awk '{print $1, $3, $5}'

echo
echo "Open Grafana http://localhost:3000 → MySQL Processlist → Top Queries"
echo "to see the migration queries in events_statements_summary_by_digest."
