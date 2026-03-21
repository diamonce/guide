-- Replication user — used by replicas to connect to primary
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

-- HAProxy health check user (no password, no privileges needed)
CREATE USER IF NOT EXISTS 'haproxy_check'@'%';

-- ProxySQL monitor user
CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitorpass';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';

FLUSH PRIVILEGES;
