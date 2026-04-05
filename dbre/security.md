# Database Security

[← DBRE Home](README.md) | [← Main](../README.md)

---

## Why DB Security Is a DBRE Concern `[B]`

Application security is owned by developers. Network security is owned by infra. **Database security sits at the intersection** — and falls through the cracks unless DBRE owns it explicitly.

The database is the most valuable target in any breach:
- Application compromise → attacker gets one user's data
- Database compromise → attacker gets everyone's data

**Scope of this file:** database-layer controls only. Network segmentation, VPCs, and security groups belong in [Platform: Cloud Infrastructure](../platform/cloud-infra.md).

---

## Access Control: Principle of Least Privilege `[B]`

**The antipattern:** applications connecting as a superuser or as the database owner.

**The rule:** every role gets exactly the permissions it needs — nothing more.

### PostgreSQL Role Design

```sql
-- Application role: read/write on app tables only
CREATE ROLE app_rw LOGIN PASSWORD 'use-secrets-manager';
GRANT CONNECT ON DATABASE mydb TO app_rw;
GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;

-- Read-only role: analytics, reporting, read replicas
CREATE ROLE app_ro LOGIN PASSWORD 'use-secrets-manager';
GRANT CONNECT ON DATABASE mydb TO app_ro;
GRANT USAGE ON SCHEMA public TO app_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_ro;

-- Migration role: schema changes only (used by Flyway/Alembic in CI)
CREATE ROLE app_migrate LOGIN PASSWORD 'use-secrets-manager';
GRANT CONNECT ON DATABASE mydb TO app_migrate;
GRANT ALL ON SCHEMA public TO app_migrate;
-- Do NOT grant this role to the running application

-- Admin role: break-glass only, not used by any automated process
CREATE ROLE dbre_admin LOGIN PASSWORD 'use-secrets-manager' CREATEDB;
GRANT ALL ON DATABASE mydb TO dbre_admin;
```

### MySQL Role Design

```sql
-- Application: minimal grants
CREATE USER 'app'@'%' IDENTIFIED BY 'use-secrets-manager';
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'app'@'%';

-- Read-only
CREATE USER 'app_ro'@'%' IDENTIFIED BY 'use-secrets-manager';
GRANT SELECT ON mydb.* TO 'app_ro'@'%';

-- Migration runner
CREATE USER 'app_migrate'@'%' IDENTIFIED BY 'use-secrets-manager';
GRANT ALL ON mydb.* TO 'app_migrate'@'%';

FLUSH PRIVILEGES;
```

### Role Separation Summary

| Role | Used by | Grants |
|------|---------|--------|
| `app_rw` | Running application | SELECT, INSERT, UPDATE, DELETE |
| `app_ro` | Analytics, read replicas | SELECT only |
| `app_migrate` | CI/CD migration runner | DDL + DML on schema |
| `dbre_admin` | Human DBREs (break-glass) | Full access |

**Never grant `SUPERUSER` to an application role.**

---

## Encryption in Transit `[B]`

All connections to the database must use TLS. Unencrypted connections expose credentials and data on the wire.

### PostgreSQL: Enforce TLS

```ini
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'

# pg_hba.conf — reject non-SSL connections from app hosts
# TYPE  DATABASE  USER    ADDRESS         METHOD
hostssl all       app_rw  10.0.0.0/8      scram-sha-256
local   all       all                     peer
# reject plain TCP for app roles:
host    all       app_rw  10.0.0.0/8      reject
```

```sql
-- Enforce TLS per user
ALTER USER app_rw SET ssl = required;

-- Verify connection is using TLS
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

### RDS / Aurora: TLS Settings

```hcl
# Terraform: force SSL parameter group
resource "aws_db_parameter_group" "postgres" {
  family = "postgres15"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}
```

```bash
# Connect with SSL verification
psql "host=mydb.rds.amazonaws.com dbname=mydb user=app_rw \
      sslmode=verify-full sslrootcert=rds-ca-cert.pem"
```

**Bad:** `sslmode=disable` or `sslmode=allow` in production connection strings.
**Good:** `sslmode=verify-full` (verifies server certificate, prevents MITM).

---

## Encryption at Rest `[B]`

Disk encryption protects against physical media theft — it does **not** protect against a compromised database user. Both are needed.

### RDS at-Rest Encryption

```hcl
resource "aws_db_instance" "main" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.db.arn
  # Note: cannot enable encryption on an existing unencrypted instance.
  # Must: snapshot → restore encrypted → swap endpoint
}
```

### PostgreSQL: Column-Level Encryption with pgcrypto

For PII columns that need additional protection beyond disk encryption:

```sql
CREATE EXTENSION pgcrypto;

-- Store encrypted
INSERT INTO users (email_encrypted)
VALUES (pgp_sym_encrypt('user@example.com', current_setting('app.encryption_key')));

-- Read decrypted
SELECT pgp_sym_decrypt(email_encrypted::bytea, current_setting('app.encryption_key'))
FROM users WHERE id = 1;
```

**Limitations:** encrypted columns cannot be indexed or searched efficiently. Design this into the schema early — retrofitting is painful.

---

## Secrets Management `[I]`

**The antipattern:** database credentials in environment variables checked into git, or hardcoded in config files.

### Credential Hierarchy (worst → best)

```
❌ Hardcoded in code
❌ In .env committed to git
⚠  In .env NOT committed (still leaks in logs, ps output)
⚠  Plain environment variables (visible in process list)
✓  AWS Secrets Manager / HashiCorp Vault (rotated, audited, short-lived)
```

### AWS Secrets Manager

```python
import boto3
import json

def get_db_credentials(secret_name: str) -> dict:
    client = boto3.client('secretsmanager', region_name='us-east-1')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
creds = get_db_credentials('prod/myapp/db')
conn = psycopg2.connect(
    host=creds['host'],
    dbname=creds['dbname'],
    user=creds['username'],
    password=creds['password'],
    sslmode='verify-full'
)
```

### Credential Rotation Without Downtime

Rotating DB credentials with zero downtime uses the **expand/contract** pattern:

```
Phase 1: Create new credential alongside old one
Phase 2: Update Secrets Manager with new credential
Phase 3: Applications pick up new credential (on next secret refresh)
Phase 4: Verify no connections using old credential
         SELECT usename, count(*) FROM pg_stat_activity GROUP BY usename;
Phase 5: Revoke old credential
         ALTER USER app_rw PASSWORD 'new-password';
         -- or DROP the old user if using separate users per rotation
```

### PgBouncer with SCRAM-SHA-256

```ini
# pgbouncer.ini
[pgbouncer]
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

# userlist.txt (passwords are SCRAM-SHA-256 hashes, not plaintext)
"app_rw" "SCRAM-SHA-256$4096:..."
```

Never store plaintext passwords in PgBouncer's userlist.

---

## Audit Logging `[I]`

Know who ran what query, when — especially for privileged operations and schema changes.

### PostgreSQL: pgaudit Extension

```bash
# Install
apt-get install postgresql-15-pgaudit

# postgresql.conf
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'ddl,role,misc_set'   # Log DDL, role changes, SET commands
pgaudit.log_relation = on           # Include table name in DDL log
```

```sql
-- Per-role audit (log all writes for sensitive roles)
ALTER ROLE dbre_admin SET pgaudit.log = 'all';

-- Verify pgaudit is active
SHOW pgaudit.log;
```

**What to log:**
- `ddl` — all CREATE, ALTER, DROP (always)
- `role` — GRANT, REVOKE, CREATE ROLE (always)
- `write` — INSERT, UPDATE, DELETE on sensitive tables (targeted, not all tables)
- `read` — SELECT (only on PII tables if compliance requires; very high volume)

**What NOT to log by default:** SELECT on all tables — this generates enormous volume and makes the audit log useless.

### MySQL: General Log + Binary Log

```sql
-- Enable general log (use sparingly — high volume)
SET GLOBAL general_log = 'ON';
SET GLOBAL general_log_file = '/var/log/mysql/general.log';

-- Binary log captures all writes (already on for replication)
SHOW VARIABLES LIKE 'log_bin';
SHOW BINARY LOGS;
```

### Alerts to Set on Audit Logs

```yaml
# Alert on high-risk operations (CloudWatch Logs Insights / Datadog)
- DROP TABLE
- TRUNCATE
- ALTER TABLE ... DROP COLUMN
- GRANT ... TO
- CREATE USER
- ALTER USER ... PASSWORD
- pg_terminate_backend (forceful connection kill)
```

---

## PII and Data Classification `[I]`

**The problem:** once PII is in the database without clear classification, compliance (GDPR, CCPA) becomes a data archaeology project.

### Data Classification Table

| Class | Examples | Controls |
|-------|---------|---------|
| PII | name, email, phone, IP address | Column-level encryption or masking, restricted roles |
| Sensitive | SSN, payment card, health data | Column-level encryption, dedicated table, strict access |
| Internal | order totals, product IDs | Standard app access controls |
| Public | product names, prices | No special controls |

### Schema Design for Compliance

```sql
-- Keep PII in a separate table with explicit classification
CREATE TABLE user_pii (
    user_id     BIGINT PRIMARY KEY REFERENCES users(id),
    email       VARCHAR(255) NOT NULL,  -- PII: encrypted at app layer
    full_name   VARCHAR(255),           -- PII
    phone       VARCHAR(20),            -- PII
    created_at  TIMESTAMP DEFAULT NOW(),
    -- GDPR: track consent
    gdpr_consent_at   TIMESTAMP,
    gdpr_consent_version VARCHAR(20)
);

-- Non-PII user data in main table
CREATE TABLE users (
    id          BIGSERIAL PRIMARY KEY,
    username    VARCHAR(50) UNIQUE NOT NULL,
    role        VARCHAR(20) DEFAULT 'user',
    created_at  TIMESTAMP DEFAULT NOW()
);
```

### Right-to-Erasure (GDPR Article 17)

Design for deletion from day one — retrofitting is a significant engineering effort:

```sql
-- Soft delete with PII zeroing (keeps referential integrity, removes data)
UPDATE user_pii SET
    email = 'deleted-' || user_id || '@deleted.invalid',
    full_name = '[DELETED]',
    phone = NULL,
    deleted_at = NOW()
WHERE user_id = :user_id;

-- Hard delete: only if no FK references would break
DELETE FROM user_pii WHERE user_id = :user_id;
```

**Hard delete vs. soft delete:** for right-to-erasure compliance, hard delete is cleaner but requires FK audit. Soft delete with PII zeroing preserves referential integrity while removing the data.

### Data Retention Policy

```sql
-- Archive rows older than retention period before deleting
-- Run as a scheduled job (cron / AWS EventBridge)
INSERT INTO orders_archive
SELECT * FROM orders
WHERE created_at < NOW() - INTERVAL '7 years';

DELETE FROM orders
WHERE created_at < NOW() - INTERVAL '7 years';
```

---

## Row-Level Security (RLS) `[A]`

PostgreSQL RLS restricts which rows a role can see — useful for multi-tenant SaaS where tenant isolation must be enforced at the database layer.

```sql
-- Enable RLS on a table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- applies to table owner too

-- Policy: each app connection can only see its own tenant's rows
-- Application sets current_setting('app.tenant_id') at connection start
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id')::bigint);

-- Application: set tenant context on every connection
SET app.tenant_id = '42';
SELECT * FROM orders;  -- only returns tenant 42's rows
```

**RLS gotchas:**
- Performance: adds a filter to every query — verify with `EXPLAIN ANALYZE`
- Bypassed by superuser — application roles must not be superuser
- Setting `app.tenant_id` must be the first thing done on a connection (before any query)
- Works poorly with connection poolers in session mode if not reset between sessions

**When NOT to use RLS:** if tenant isolation can be done reliably at the application layer, RLS adds complexity for marginal benefit. Use it when the blast radius of an application bug leaking cross-tenant data is unacceptable.

---

## Security Checklist `[B]`

- [ ] Applications connect with a least-privilege role (not superuser)
- [ ] Separate roles for app, read-only, migrations, and admin
- [ ] TLS enforced on all connections (`sslmode=verify-full`)
- [ ] Encryption at rest enabled (RDS `storage_encrypted = true`)
- [ ] Credentials stored in Secrets Manager or Vault — not in code or `.env`
- [ ] Credentials rotated on a schedule (90 days max, 30 days preferred)
- [ ] pgaudit enabled; DDL and role changes logged
- [ ] Alerts set on DROP TABLE, TRUNCATE, GRANT, CREATE USER
- [ ] PII columns classified and documented in schema
- [ ] Data retention policy implemented and tested
- [ ] Right-to-erasure procedure documented and tested

---

## Related Topics

- [Fundamentals](fundamentals.md) — connection pooling, roles
- [Backup & Recovery](backup-recovery.md) — backup encryption
- [Best Practices](best-practices.md) — schema design
- [Platform: Cloud Infrastructure](../platform/cloud-infra.md) — VPC, security groups, IAM
- [SRE: Incident Management](../sre/incident-management.md) — responding to a breach
