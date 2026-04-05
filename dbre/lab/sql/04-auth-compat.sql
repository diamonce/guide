-- ─────────────────────────────────────────────────────────────────────────────
-- Authentication compatibility for MySQL 8.0
--
-- MySQL 8.0 defaults to caching_sha2_password. Two components need
-- mysql_native_password to work without extra TLS/RSA handshake:
--
--   app          — ProxySQL does not negotiate caching_sha2_password
--                  by default on the backend connection
--   haproxy_check — HAProxy TCP health check sends no password;
--                   caching_sha2_password rejects empty-password logins
--
-- This file runs at container init time (docker-entrypoint-initdb.d/),
-- so these users already exist (created by MYSQL_USER env or 02-repl.sql).
-- ─────────────────────────────────────────────────────────────────────────────

-- ProxySQL backend user — switch to native password so ProxySQL
-- can authenticate without the caching_sha2 RSA exchange
ALTER USER 'app'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';

-- HAProxy health check — no password, must use native plugin
CREATE USER IF NOT EXISTS 'haproxy_check'@'%'
    IDENTIFIED WITH mysql_native_password BY ''
    PASSWORD EXPIRE NEVER;

-- ProxySQL monitor user — used for backend health checks (ping/connect)
-- Must be mysql_native_password; caching_sha2 causes "handshake out of context"
CREATE USER IF NOT EXISTS 'monitor'@'%'
    IDENTIFIED WITH mysql_native_password BY 'monitorpass'
    PASSWORD EXPIRE NEVER;

FLUSH PRIVILEGES;
