-- ─────────────────────────────────────────────────────────────────────────────
-- Authentication compatibility for MySQL 8.0
--
-- MySQL 8.0 defaults to caching_sha2_password. Two components need
-- mysql_native_password to work without extra TLS/RSA handshake:
--
--   app           — ProxySQL cannot negotiate caching_sha2_password on backends
--   haproxy_check — HAProxy TCP health check sends no password;
--                   caching_sha2_password rejects empty-password logins
--   monitor       — ProxySQL backend health-check user; same constraint as app
--
-- Pattern: CREATE IF NOT EXISTS (no-op if exists) + ALTER USER (always applies).
-- This makes the file safe to re-run against a live instance.
-- ─────────────────────────────────────────────────────────────────────────────

-- app — created by MYSQL_USER env var, may have caching_sha2_password
ALTER USER 'app'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';

-- haproxy_check — not created by any env var, must be created here
CREATE USER IF NOT EXISTS 'haproxy_check'@'%';
ALTER USER 'haproxy_check'@'%'
    IDENTIFIED WITH mysql_native_password BY ''
    PASSWORD EXPIRE NEVER;

-- monitor — ProxySQL backend health-check user
CREATE USER IF NOT EXISTS 'monitor'@'%';
ALTER USER 'monitor'@'%'
    IDENTIFIED WITH mysql_native_password BY 'monitorpass'
    PASSWORD EXPIRE NEVER;

FLUSH PRIVILEGES;
