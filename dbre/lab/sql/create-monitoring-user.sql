-- ─────────────────────────────────────────────────────────────────
-- Monitoring user — used by mysqld_exporter and Grafana MySQL datasource
--
-- Grants needed:
--   PROCESS           → SHOW PROCESSLIST, information_schema.innodb_trx
--   REPLICATION CLIENT → SHOW MASTER STATUS / SHOW REPLICA STATUS
--   REPLICATION SLAVE  → slave status metrics
--   SELECT perf_schema → events_statements_summary_by_digest, data_locks, etc.
--   SELECT sys.*       → sys schema views (pt-mysql-summary uses these)
-- ─────────────────────────────────────────────────────────────────

CREATE USER IF NOT EXISTS 'monitoring'@'%' IDENTIFIED BY 'monitorpass';

GRANT PROCESS, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'monitoring'@'%';
GRANT SELECT ON performance_schema.* TO 'monitoring'@'%';
GRANT SELECT ON sys.* TO 'monitoring'@'%';

FLUSH PRIVILEGES;
