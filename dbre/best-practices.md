# DBRE Best Practices — Do's and Don'ts

[← DBRE Home](README.md) | [← Main](../README.md)

Compiled from [sqlcheck](../resources/sqlcheck/README.md), [sql-tips-and-tricks](../resources/sql-tips-and-tricks/README.md), [sqlstyle-guide](../resources/sqlstyle-guide/README.md), [awesome-mysql](../resources/awesome-mysql/README.md), and [awesome-scalability](../resources/awesome-scalability/README.md).

---

## Schema Design

### DO

**Every table must have a primary key**
```sql
-- ✅
CREATE TABLE orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**Use precise data types — match the domain**
```sql
-- ✅ money: DECIMAL, not FLOAT
price       DECIMAL(10, 2)  NOT NULL

-- ✅ dates: proper type, not strings
created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()

-- ✅ flags: BOOLEAN, not INT
is_active   BOOLEAN NOT NULL DEFAULT TRUE

-- ✅ store datetimes in ISO 8601
-- YYYY-MM-DDTHH:MM:SS.SSSSS
```

**Normalize unless you have a proven reason not to**
```sql
-- ✅ separate tags into their own table
CREATE TABLE article_tags (
    article_id BIGINT UNSIGNED NOT NULL,
    tag        VARCHAR(50)     NOT NULL,
    PRIMARY KEY (article_id, tag)
);
```

**Use standard column name suffixes — everyone reads them the same way**

| Suffix | Meaning |
|--------|---------|
| `_id` | primary or foreign key |
| `_status` | flag or enum value |
| `_total` | sum of a collection |
| `_date` | date or timestamp |
| `_num` | numeric field |
| `_name` | name string |
| `_size` | size or length |
| `_addr` | address (physical or network) |

**Enforce constraints at the database level**
```sql
-- ✅ NOT NULL where data should never be missing
-- ✅ FOREIGN KEY for referential integrity
-- ✅ CHECK for valid ranges
ALTER TABLE orders
    ADD CONSTRAINT chk_total CHECK (total >= 0);
```

### DON'T

**Don't use FLOAT/REAL for money — floating point errors compound**
```sql
-- ❌
price FLOAT

-- ✅
price DECIMAL(10, 2)
```

**Don't store multiple values in one column**
```sql
-- ❌ comma-separated tags — can't index, can't join
tags VARCHAR(500)   -- "python,postgres,sre"

-- ✅ separate rows in a join table
```

**Don't use EAV (Entity-Attribute-Value) tables**
```sql
-- ❌ EAV — no type safety, terrible query performance, no constraints
CREATE TABLE user_properties (
    user_id        INTEGER,
    property_name  VARCHAR(100),
    property_value TEXT
);

-- ✅ explicit columns, or JSONB/JSON for genuinely dynamic data
```

**Don't split a logical table across multiple tables for archiving**
```sql
-- ❌
CREATE TABLE orders_2023 (...);
CREATE TABLE orders_2024 (...);

-- ✅ use table partitioning
CREATE TABLE orders (...) PARTITION BY RANGE (created_at);
```

**Don't use generic or ambiguous names**
```sql
-- ❌
CREATE TABLE data (...);
CREATE TABLE info (...);
ALTER TABLE t ADD COLUMN flag INT;

-- ✅ name for what the data actually is
CREATE TABLE customer_orders (...);
ALTER TABLE orders ADD COLUMN is_fulfilled BOOLEAN;
```

---

## Query Writing

### DO

**Always name your columns — never SELECT ***
```sql
-- ❌
SELECT * FROM orders;

-- ✅
SELECT id, customer_id, total, status, created_at FROM orders;
```

**Alias tables in every multi-table query**
```sql
-- ❌ ambiguous
SELECT video_id, series_name FROM video_content
INNER JOIN video_metadata ON video_content.video_id = video_metadata.video_id;

-- ✅ explicit
SELECT vc.video_id, vc.series_name, m.season
FROM video_content AS vc
INNER JOIN video_metadata AS m ON vc.video_id = m.video_id;
```

**Use CTEs for anything nested more than two levels deep**
```sql
-- ❌ nested inline views — hard to debug, hard to read
SELECT vhs.movie, cs.cinema_revenue
FROM (SELECT movie_id, SUM(ticket_sales) AS cinema_revenue FROM tickets GROUP BY movie_id) AS cs
INNER JOIN (SELECT movie, movie_id, SUM(revenue) AS vhs_revenue FROM blockbuster GROUP BY movie, movie_id) AS vhs
ON cs.movie_id = vhs.movie_id;

-- ✅ CTEs — each step is named and readable
WITH cinema_sales AS (
    SELECT movie_id, SUM(ticket_sales) AS cinema_revenue
    FROM tickets
    GROUP BY movie_id
),
vhs_sales AS (
    SELECT movie, movie_id, SUM(revenue) AS vhs_revenue
    FROM blockbuster
    GROUP BY movie, movie_id
)
SELECT vhs.movie, vhs.vhs_revenue, cs.cinema_revenue
FROM cinema_sales AS cs
INNER JOIN vhs_sales AS vhs ON cs.movie_id = vhs.movie_id;
```

**Use NOT EXISTS instead of NOT IN**
```sql
-- ❌ NOT IN breaks silently when subquery returns any NULL
SELECT * FROM employees
WHERE department_id NOT IN (SELECT id FROM departments);
-- If any id is NULL → returns zero rows (wrong)

-- ✅ NOT EXISTS handles NULLs correctly and is faster
SELECT * FROM employees AS e
WHERE NOT EXISTS (
    SELECT 1 FROM departments AS d WHERE d.id = e.department_id
);
```

**Match data types to avoid implicit casting**
```sql
-- ❌ video_id is VARCHAR, comparing to integer → implicit cast, no index
WHERE video_id = 200050

-- ✅ match the column type
WHERE video_id = '200050'
```

**Use BETWEEN for ranges, IN() for lists**
```sql
-- ❌
WHERE created_at >= '2024-01-01' AND created_at <= '2024-12-31'
  AND status = 'paid' OR status = 'shipped' OR status = 'pending'

-- ✅
WHERE created_at BETWEEN '2024-01-01' AND '2024-12-31'
  AND status IN ('paid', 'shipped', 'pending')
```

**Use the 1=1 trick for toggleable WHERE clauses**
```sql
-- ✅ easy to comment/uncomment conditions during development
SELECT * FROM orders
WHERE 1=1
-- AND status = 'pending'
  AND created_at > NOW() - INTERVAL '7 days';
```

**Use USING when join columns have the same name**
```sql
-- ✅ USING deduplicates the column in the result set
SELECT * FROM album
INNER JOIN artist USING (artist_id);
```

**Comment why, not what**
```sql
-- ❌
-- Join orders to customers
JOIN customers ON customers.id = orders.customer_id

-- ✅
-- Left join: include orders with deleted customers for financial audit trail
LEFT JOIN customers ON customers.id = orders.customer_id
```

### DON'T

**Don't put functions on indexed columns in WHERE**
```sql
-- ❌ index on created_at is unused
WHERE DATE(created_at) = '2024-01-15'
WHERE YEAR(created_at) = 2024

-- ✅ use a range instead
WHERE created_at >= '2024-01-15' AND created_at < '2024-01-16'
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
```

**Don't name a calculated field the same as an existing column**
```sql
-- ❌ GROUP BY resolves to original column, not the alias
SELECT LEFT(product, 1) AS product, MAX(revenue)
FROM products
GROUP BY product;   -- groups by original column!

-- ✅ use a distinct alias
SELECT LEFT(product, 1) AS product_letter, MAX(revenue)
FROM products
GROUP BY product_letter;
```

**Don't use GROUP BY column position in production code**
```sql
-- ❌ fragile — breaks if SELECT order changes
GROUP BY 1, 2
ORDER BY 3 DESC

-- ✅ explicit names
GROUP BY customer_id, status
ORDER BY total DESC
```

**Don't use ORDER BY RAND() for sampling**
```sql
-- ❌ full table scan + sort every time
SELECT * FROM products ORDER BY RAND() LIMIT 10;

-- ✅ keyset random sampling
SELECT * FROM products
WHERE id >= (SELECT FLOOR(RAND() * (SELECT MAX(id) FROM products)))
LIMIT 10;
```

**Don't use LIKE with a leading wildcard**
```sql
-- ❌ can't use index
WHERE email LIKE '%@gmail.com'

-- ✅ use trigram index (PostgreSQL pg_trgm, MySQL FULLTEXT)
-- or anchor the pattern
WHERE email LIKE 'john%'
```

**Don't use UNION when UNION ALL is enough**
```sql
-- ❌ sorts + deduplicates unnecessarily if data is already unique
SELECT id FROM table_a UNION SELECT id FROM table_b

-- ✅ if no duplicates exist or you don't care
SELECT id FROM table_a UNION ALL SELECT id FROM table_b
```

**Don't use DISTINCT to hide a broken JOIN**
```sql
-- ❌ DISTINCT masking a Cartesian product
SELECT DISTINCT o.id FROM orders o JOIN order_items oi ON oi.order_id = o.id;

-- ✅ use EXISTS
SELECT o.id FROM orders o
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);
```

---

## Indexing

### DO

- Index every foreign key column
- Create composite indexes with equality columns first, range columns last
- Use `CREATE INDEX CONCURRENTLY` (PostgreSQL) or `pt-online-schema-change` (MySQL) — never block production
- Audit unused indexes monthly and drop them

```sql
-- ✅ equality first, range second
CREATE INDEX idx_orders_status_created ON orders(status, created_at);

-- ✅ covering index — avoids heap access entirely
CREATE INDEX idx_orders_covering ON orders(customer_id) INCLUDE (total, status);

-- ✅ partial index — smaller, faster
CREATE INDEX idx_active_orders ON orders(customer_id) WHERE status = 'active';
```

### DON'T

- Don't index every column — writes update every index
- Don't put range columns before equality columns in composite indexes
- Don't use `CREATE INDEX` (blocking) in production without a maintenance window
- Don't let unused indexes pile up

```sql
-- ❌ wrong order — this index won't help for "WHERE status = ? AND created_at > ?"
CREATE INDEX idx_wrong ON orders(created_at, status);
```

---

## Transactions & Concurrency

### DO

- Keep transactions short — seconds, not minutes
- Acquire locks in consistent order across all transactions
- Use `SELECT ... FOR UPDATE` explicitly when you need a row lock
- Use `SKIP LOCKED` for queue processing

```sql
-- ✅ queue worker pattern
SELECT id, payload FROM jobs
WHERE status = 'pending'
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

### DON'T

- Don't hold transactions open while waiting for user input or external API calls
- Don't use `READ UNCOMMITTED` as a "performance fix" — dirty reads corrupt data
- Don't catch deadlock errors and silently swallow them — retry and log

---

## Tools — What to Use

| Task | Tool | Notes |
|------|------|-------|
| Detect SQL anti-patterns | [sqlcheck](../resources/sqlcheck/README.md) | Run in CI before deploy |
| Lint SQL formatting | sqlfluff | Enforces sqlstyle conventions |
| Format SQL ad-hoc | poorsql.com | Online formatter |
| Online schema change (MySQL) | `pt-online-schema-change` | No table locks |
| Query analysis (MySQL) | `pt-query-digest` | Reads slow query log |
| Find duplicate indexes | `pt-duplicate-key-checker` | Run monthly |
| Verify replica data | `pt-table-checksum` | Catch silent drift |
| Fix replica drift | `pt-table-sync` | After checksum mismatch |
| MySQL proxy / read-write split | ProxySQL | Route SELECTs to replicas |
| MySQL load balancer | HAProxy | Health-check aware routing |
| Distributed SQL queries | Presto / Trino | Query across multiple data sources |
| PostgreSQL config baseline | PGTune (pgtune.leopard.in.ua) | Hardware-specific starting point |

→ Full Percona Toolkit reference: [percona-toolkit](../resources/percona-toolkit/README.md)

---

## Naming Conventions

| Object | Convention | Example |
|--------|-----------|---------|
| Tables | snake_case, singular or collective | `customer_order`, `staff` |
| Columns | snake_case, singular | `first_name`, `created_at` |
| Indexes | `idx_table_column(s)` | `idx_orders_customer_id` |
| Foreign keys | `fk_table_referenced` | `fk_orders_customers` |
| Stored procedures | verb + noun | `get_active_orders` |
| Aliases | first letter(s) of words | `orders AS o`, `customers AS c` |

**Never:**
- `tbl_`, `sp_`, `fn_` prefixes
- camelCase
- Reserved keywords as identifiers
- Ambiguous names: `data`, `info`, `flag`, `value`

---

## At Scale — Patterns That Work

From [awesome-scalability](../resources/awesome-scalability/README.md) and real company cases:

**Read replicas before sharding** — Instagram ran PostgreSQL to 1B users with replicas and no NoSQL.

**Connection pooling is not optional at scale**
- PgBouncer (PostgreSQL) — transaction mode, 20 DB connections serving 1,000 app connections
- ProxySQL (MySQL) — query routing + pooling in one

**Sharding order of operations:**
1. Optimize queries
2. Add indexes
3. Add read replicas
4. Cache hot data (Redis)
5. Partition large tables
6. Only then: shard

**Parallel replication matters** — untuned replica lag under load kills read replicas' usefulness. Booking.com, GitHub, Shopify all had to tune this explicitly.

**Zero-downtime migrations are non-negotiable** — use expand/contract pattern, `pt-online-schema-change`, or `gh-ost`. Never lock a production table.

→ See [Migrations](migrations.md) and [Scaling](scaling.md) for depth.

---

## Quick Checklist — Before Merging a DB Change

- [ ] No `SELECT *` in new code
- [ ] All new indexes created with `CONCURRENTLY` / `pt-osc`
- [ ] Schema changes use expand/contract (backward compatible)
- [ ] Large data updates are batched (< 1,000 rows per transaction)
- [ ] `sqlcheck` run on new SQL files
- [ ] Transaction duration is bounded (no open-ended waits inside transactions)
- [ ] Foreign keys defined for all relationships
- [ ] NOT NULL on columns that should never be empty
- [ ] Replication lag monitored during rollout

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Anti-Patterns](antipatterns.md)
- [Performance Tuning](performance.md)
- [Migrations & Schema Changes](migrations.md)
- [Scaling Databases](scaling.md)
- [External Links](external-links.md) — PostgreSQL "Don't Do This", sqlblog bad habits
- [Lab Runbook](lab/runbook.md) — try everything hands-on
