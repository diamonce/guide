# Database Anti-Patterns

[← DBRE Home](README.md) | [← Main](../README.md)

Based on [sqlcheck](../resources/sqlcheck/README.md) — detects these automatically. Run it on your SQL before deploying.

```bash
# Install and run sqlcheck
sqlcheck -f queries.sql
sqlcheck -f queries.sql -v  # verbose, explains each anti-pattern
```

---

## Category 1: Logical Design Anti-Patterns `[I]`

Problems in how you model data — hard to fix later.

### Multi-Valued Attributes

Storing multiple values in a single column:

```sql
-- BAD: comma-separated tags in one column
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    tags VARCHAR(500)  -- "python,postgres,sre"
);
-- Can't index, can't query efficiently, hard to join

-- GOOD: separate table
CREATE TABLE article_tags (
    article_id INTEGER REFERENCES articles(id),
    tag VARCHAR(50) NOT NULL,
    PRIMARY KEY (article_id, tag)
);
```

### Entity-Attribute-Value (EAV)

```sql
-- BAD: EAV pattern — looks flexible, is a nightmare
CREATE TABLE user_properties (
    user_id INTEGER,
    property_name VARCHAR(100),
    property_value TEXT
);
-- No type safety, terrible query performance, no constraints

-- GOOD: explicit columns, or JSONB for truly dynamic attributes
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    metadata JSONB  -- for genuinely flexible attributes
);
CREATE INDEX CONCURRENTLY idx_users_metadata ON users USING GIN(metadata);
```

### Missing Primary Keys

Every table must have a primary key. Without it:
- Replication can break (MySQL/Postgres)
- Duplicate rows can silently accumulate
- Joins become ambiguous

```sql
-- Always define a PK
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,  -- or UUID
    -- ...
);
```

### Generic Primary Keys

```sql
-- BAD: generic column name obscures meaning
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,  -- id of what?
    -- ...
);

-- BETTER: use id conventionally but be consistent
-- If you use "id" everywhere, it's fine — just be consistent
-- Avoid: entity_id, record_id, key, pk
```

### Recursive Dependencies

Self-referencing foreign keys without care:

```sql
-- Hierarchical data (categories, org charts)
-- Fine to do, but needs care with deletes and queries
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL
);

-- Query with recursive CTE (see sql.md)
```

---

## Category 2: Physical Design Anti-Patterns `[I]`

How data is stored and indexed.

### Imprecise Data Types

```sql
-- BAD: storing money as float (floating point errors)
price FLOAT

-- GOOD: use NUMERIC/DECIMAL for money
price NUMERIC(10, 2)

-- BAD: storing dates as strings
created_at VARCHAR(20)  -- "2024-01-15"

-- GOOD: use proper date types
created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()

-- BAD: storing booleans as 0/1 integers
is_active INTEGER

-- GOOD:
is_active BOOLEAN NOT NULL DEFAULT TRUE
```

### Too Many Indexes

Every index:
- Slows down writes (INSERT/UPDATE/DELETE must update all indexes)
- Consumes disk space and memory

```sql
-- Audit index usage periodically
SELECT indexname, idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan ASC;

-- Drop indexes with 0 scans (after confirming not needed)
DROP INDEX CONCURRENTLY idx_orders_old_column;
```

**Rule of thumb:** If an index hasn't been used in 30 days, it's probably not needed.

### Wrong Index Column Order

```sql
-- Query pattern: WHERE status = 'active' AND created_at > '2024-01-01'
-- Equality column FIRST, range column SECOND
CREATE INDEX idx_orders_status_created ON orders(status, created_at);

-- The reverse index (created_at, status) is far less useful for this query
```

---

## Category 3: Query Anti-Patterns `[B]`

Problems in how you write SQL — catchable in code review.

See [SQL Best Practices](sql.md) for full treatment. Quick reference:

### SELECT * (Implicit Columns)

```sql
-- BAD
SELECT * FROM orders;

-- GOOD
SELECT id, customer_id, total, status FROM orders;
```

**Why:** Wastes network, prevents index-only scans, breaks if columns change.

### NULL Misuse

```sql
-- BAD: this doesn't catch NULLs
WHERE status <> 'cancelled'

-- GOOD
WHERE status <> 'cancelled' OR status IS NULL

-- BAD: NULL comparison always returns NULL (never TRUE)
WHERE last_login = NULL

-- GOOD
WHERE last_login IS NULL
```

### ORDER BY RAND()

```sql
-- BAD: full table scan + sort every time
SELECT * FROM products ORDER BY RAND() LIMIT 10;

-- GOOD: keyset random sampling
SELECT * FROM products
WHERE id >= (SELECT FLOOR(RANDOM() * MAX(id)) FROM products)
LIMIT 10;
```

### Pattern Matching with Leading Wildcard

```sql
-- BAD: can't use index
WHERE email LIKE '%@gmail.com'

-- GOOD: use pg_trgm for arbitrary pattern matching with indexing
CREATE EXTENSION pg_trgm;
CREATE INDEX CONCURRENTLY idx_users_email_trgm ON users USING GIN(email gin_trgm_ops);
-- Now LIKE '%@gmail.com' can use the trigram index
```

### Excessive JOINs

```sql
-- If you have > 5 JOINs in a query, ask:
-- 1. Is the schema denormalized enough for the query pattern?
-- 2. Should this be a materialized view?
-- 3. Is this OLAP query running against an OLTP database?
```

### Unnecessary DISTINCT

```sql
-- BAD: DISTINCT masking a JOIN problem (cartesian product)
SELECT DISTINCT o.id
FROM orders o
JOIN order_items oi ON oi.order_id = o.id;
-- DISTINCT here hides that the JOIN multiplies rows

-- GOOD: use EXISTS or subquery
SELECT o.id
FROM orders o
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);
```

### Nested Subqueries (Correlated)

```sql
-- BAD: correlated subquery runs once per row (N×M)
SELECT o.id,
  (SELECT SUM(quantity) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
FROM orders o;

-- GOOD: JOIN with aggregation
SELECT o.id, COALESCE(oi.item_count, 0)
FROM orders o
LEFT JOIN (
    SELECT order_id, SUM(quantity) AS item_count
    FROM order_items
    GROUP BY order_id
) oi ON oi.order_id = o.id;
```

---

## Category 4: Application Anti-Patterns `[B]`

### Readable Passwords

```sql
-- NEVER store plaintext passwords
CREATE TABLE users (
    password VARCHAR(255)  -- if storing the actual password text, THIS IS WRONG
);

-- ALWAYS store hashed passwords
-- Use bcrypt, argon2, or scrypt at the application layer
-- Never hash in SQL (MD5/SHA are not password hashes)
```

### No Connection Pooling

Connecting directly from app to DB without pooling:
- Each connection costs ~5-10MB RAM on the DB
- Connection establishment adds ~10-50ms latency
- DB crashes under connection storms

→ See [Fundamentals: Connection Pooling](fundamentals.md#connection-pooling)

### String Building SQL (SQL Injection)

```python
# BAD: SQL injection vulnerability
query = f"SELECT * FROM users WHERE name = '{user_input}'"

# GOOD: parameterized queries
cursor.execute("SELECT * FROM users WHERE name = %s", (user_input,))
```

---

## Running SQLCheck

```bash
# Run against a file
sqlcheck -f schema.sql
sqlcheck -f queries.sql -v

# Common findings and what they mean:
# [critical] SELECT * usage          → specify columns
# [critical] NULL comparison         → use IS NULL / IS NOT NULL
# [major]    No primary key          → add PK to every table
# [major]    Multi-valued attribute  → normalize the data model
# [minor]    Implicit column usage   → be explicit in INSERTs
```

→ [sqlcheck](../resources/sqlcheck/README.md) for full documentation and installation.

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Performance Tuning](performance.md) — indexing in depth
- [Migrations & Schema Changes](migrations.md) — fixing anti-patterns safely
- [sqlcheck submodule](../resources/sqlcheck/README.md)
- [sql-guide submodule](../resources/sql-guide/README.md)
