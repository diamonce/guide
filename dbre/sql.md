# SQL Best Practices

[← DBRE Home](README.md) | [← Main](../README.md)

---

## SQL Fundamentals `[B]`

### Query Execution Order

Understanding this prevents many mistakes:

```sql
SELECT   col1, AGG(col2)     -- 6. Select
FROM     table1               -- 1. From
JOIN     table2 ON ...        -- 2. Join
WHERE    condition            -- 3. Filter rows
GROUP BY col1                 -- 4. Group
HAVING   AGG(col2) > 100     -- 5. Filter groups
ORDER BY col1                 -- 7. Sort
LIMIT    10                   -- 8. Limit
```

---

## SQL Anti-Patterns `[B]`

Tools: [sqlcheck](../resources/sqlcheck/README.md) detects these automatically.

### SELECT *

```sql
-- BAD: fetches all columns, breaks if schema changes
SELECT * FROM orders;

-- GOOD: explicit columns
SELECT id, customer_id, total, created_at FROM orders;
```

### Functions on Indexed Columns

```sql
-- BAD: index on created_at is NOT used
SELECT * FROM orders WHERE DATE(created_at) = '2024-01-15';

-- GOOD: range query uses the index
SELECT * FROM orders
WHERE created_at >= '2024-01-15'
  AND created_at < '2024-01-16';
```

### Implicit Type Conversion

```sql
-- BAD: customer_id is integer but compared to string
-- causes implicit cast, can't use index
WHERE customer_id = '12345';

-- GOOD: match the column type
WHERE customer_id = 12345;
```

### N+1 Query Problem

```python
# BAD: 1 query for orders + N queries for customers
orders = db.query("SELECT * FROM orders")
for order in orders:
    customer = db.query(f"SELECT * FROM customers WHERE id={order.customer_id}")
```

```python
# GOOD: 1 query with JOIN
orders = db.query("""
    SELECT o.*, c.name, c.email
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
""")
```

### NULL Handling

```sql
-- BAD: NULL != NULL, this never returns NULL rows
WHERE status != 'active';

-- GOOD: explicit NULL check
WHERE status != 'active' OR status IS NULL;

-- CAREFUL with aggregates:
SELECT AVG(price) FROM products;  -- NULL prices excluded from average
```

### LIKE with Leading Wildcard

```sql
-- BAD: can't use index, full table scan
WHERE name LIKE '%smith';

-- GOOD: leading anchor can use index
WHERE name LIKE 'smith%';

-- For full-text search, use proper FTS:
-- PostgreSQL: tsvector/tsquery or pg_trgm
-- MySQL: FULLTEXT index
```

---

## Window Functions `[I]`

Powerful for analytics without subqueries:

```sql
-- Rank orders by total per customer
SELECT
    customer_id,
    order_id,
    total,
    RANK() OVER (PARTITION BY customer_id ORDER BY total DESC) AS rank_in_customer,
    SUM(total) OVER (PARTITION BY customer_id) AS customer_total,
    LAG(total) OVER (PARTITION BY customer_id ORDER BY created_at) AS prev_order_total
FROM orders;

-- Running total
SELECT
    created_at::date AS day,
    SUM(total) AS daily_revenue,
    SUM(SUM(total)) OVER (ORDER BY created_at::date) AS cumulative_revenue
FROM orders
GROUP BY 1;

-- Percentiles
SELECT
    product_id,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY price) AS p95_price
FROM order_items
GROUP BY product_id;
```

---

## CTEs vs Subqueries `[I]`

```sql
-- Subquery (harder to read for complex logic)
SELECT * FROM (
    SELECT customer_id, SUM(total) AS ltv
    FROM orders
    GROUP BY customer_id
) customer_ltv
WHERE ltv > 1000;

-- CTE (cleaner, reusable in same query)
WITH customer_ltv AS (
    SELECT customer_id, SUM(total) AS ltv
    FROM orders
    GROUP BY customer_id
)
SELECT c.name, ltv.ltv
FROM customer_ltv ltv
JOIN customers c ON c.id = ltv.customer_id
WHERE ltv > 1000;

-- Recursive CTE (hierarchical data)
WITH RECURSIVE subordinates AS (
    SELECT id, name, manager_id, 0 AS depth
    FROM employees
    WHERE manager_id IS NULL  -- root

    UNION ALL

    SELECT e.id, e.name, e.manager_id, s.depth + 1
    FROM employees e
    JOIN subordinates s ON e.manager_id = s.id
)
SELECT * FROM subordinates ORDER BY depth, name;
```

---

## Transactions `[I]`

```sql
BEGIN;

UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

-- Check for problems before committing
SELECT balance FROM accounts WHERE id IN (1, 2);

COMMIT;  -- or ROLLBACK if something's wrong
```

**SAVEPOINT for partial rollbacks:**

```sql
BEGIN;
INSERT INTO orders (customer_id, total) VALUES (1, 500);
SAVEPOINT after_order;

INSERT INTO order_items (...) VALUES (...);
-- Error occurs

ROLLBACK TO SAVEPOINT after_order;
-- order exists, items rolled back

COMMIT;
```

---

## Query Patterns `[I]`

### Upsert (INSERT ... ON CONFLICT)

```sql
-- PostgreSQL
INSERT INTO user_settings (user_id, key, value)
VALUES (1, 'theme', 'dark')
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- MySQL
INSERT INTO user_settings (user_id, key, value)
VALUES (1, 'theme', 'dark')
ON DUPLICATE KEY UPDATE value = VALUES(value);
```

### Bulk Insert

```sql
-- Much faster than individual INSERTs
INSERT INTO events (user_id, event_type, created_at)
VALUES
    (1, 'click', NOW()),
    (2, 'view', NOW()),
    (3, 'purchase', NOW());

-- COPY for PostgreSQL bulk loads (fastest)
COPY events (user_id, event_type, created_at)
FROM '/path/to/data.csv' CSV HEADER;
```

### Pagination

```sql
-- OFFSET pagination (gets slow on large offsets)
SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 1000;

-- Keyset/cursor pagination (fast regardless of position)
SELECT * FROM orders
WHERE id > :last_seen_id
ORDER BY id
LIMIT 20;
```

---

## SQL Code Review Checklist `[I]`

- [ ] No `SELECT *` in production code
- [ ] JOINs have proper indexes on join columns
- [ ] WHERE clauses on indexed columns (no functions on left side)
- [ ] Appropriate isolation level for the transaction
- [ ] Transactions are short (minutes, not hours)
- [ ] Bulk operations instead of row-by-row
- [ ] Pagination uses keyset, not OFFSET for large datasets
- [ ] NULLs handled explicitly

---

## Related Topics

- [Performance Tuning](performance.md) — indexes, EXPLAIN plans
- [Migrations & Schema Changes](migrations.md) — safe ALTER TABLE
- [Fundamentals: Locks](fundamentals.md#locks--deadlocks)
- [sqlcheck](../resources/sqlcheck/README.md) — automated anti-pattern detection
- [sql-guide](../resources/sql-guide/README.md) — SQL learning resource
