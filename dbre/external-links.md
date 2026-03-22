# External Resources — DBRE & SQL

[← DBRE Home](README.md) | [← Main](../README.md)

Curated external links — bookmarks worth keeping open.

---

## PostgreSQL

| Resource | What it is |
|----------|-----------|
| [PostgreSQL Official Docs](https://www.postgresql.org/docs/current/) | The definitive reference. Search here first before Stack Overflow. |
| [Don't Do This — PostgreSQL Wiki](https://wiki.postgresql.org/wiki/Don%27t_Do_This) | Official list of common PostgreSQL mistakes. Short, dense, read it once a quarter. |
| [modern-sql.com](https://modern-sql.com/) | Deep dives into modern SQL features (window functions, CTEs, lateral joins). Explains what the standard actually says. |

---

## SQL Anti-Patterns & Bad Habits

| Resource | What it is |
|----------|-----------|
| [sqlblog.org/bad-habits](https://sqlblog.org/bad-habits) | Aaron Bertrand's "Bad Habits to Kick" series — practical, opinionated, production-focused. |
| [sqlblog.org](https://sqlblog.org/) | SQL Server and general SQL blog with performance, indexing, and query tuning deep dives. |

---

## PostgreSQL Wiki: Don't Do This — Quick Reference

The most useful items from the wiki (go read the full page):

**Data Types**
- Don't use `char(n)` — use `text` or `varchar`
- Don't use `money` — use `numeric`
- Don't use `timestamp without time zone` — use `timestamptz`
- Don't use `serial` — use `identity` columns (PostgreSQL 10+)

**Authentication & Security**
- Don't use `trust` auth in production
- Don't use superuser for application connections

**Queries**
- Don't use `BETWEEN` for timestamp ranges (use `>=` and `<`)
- Don't use `NOT IN` with a subquery — use `NOT EXISTS`
- Don't use `UPPER()`/`LOWER()` for case-insensitive search — use `citext` or `ILIKE`
- Don't use `LIKE '%foo%'` for search — use full-text search or `pg_trgm`

**Schema**
- Don't use `NULL` to mean "false" or "zero"
- Don't use `EAV` (Entity-Attribute-Value) tables

→ Full list: [wiki.postgresql.org/wiki/Don't_Do_This](https://wiki.postgresql.org/wiki/Don%27t_Do_This)

---

## Aaron Bertrand's Bad Habits — Quick Reference

From [sqlblog.org/bad-habits](https://sqlblog.org/bad-habits):

**Naming**
- Using reserved words as identifiers
- Using `sp_` prefix for stored procedures (conflicts with system procs)
- Inconsistent naming conventions

**Queries**
- `SELECT *` in production code
- Using `NOLOCK` / `READ UNCOMMITTED` as a performance fix
- Putting `GETDATE()` in a `WHERE` clause on an indexed column
- Using `BETWEEN` for date ranges (off-by-one errors)
- Implicit column list in `INSERT`

**Schema Design**
- Using `VARCHAR(MAX)` everywhere instead of appropriate sizes
- Storing delimited lists in a single column
- Not using `NOT NULL` constraints by default

**Performance**
- Cursors and row-by-row processing instead of set-based operations
- Over-indexing (too many indexes slow down writes)

→ Full series: [sqlblog.org/bad-habits](https://sqlblog.org/bad-habits)

---

## modern-sql.com Highlights

- [Window Functions](https://modern-sql.com/feature/filter) — `OVER()`, `PARTITION BY`, `FILTER`
- [Lateral Joins](https://modern-sql.com/feature/lateral) — row-by-row subqueries that reference outer query
- [`WITH` (CTEs)](https://modern-sql.com/feature/with) — common table expressions and recursion
- [Temporal Tables](https://modern-sql.com/feature/application-time-period-table) — built-in time travel
- [`FILTER` clause](https://modern-sql.com/feature/filter) — conditional aggregation without `CASE WHEN`

---

## Related Topics

- [SQL Best Practices](sql.md)
- [Anti-Patterns](antipatterns.md)
- [Performance Tuning](performance.md)
- [sqlcheck](../resources/sqlcheck/README.md) — automated anti-pattern detection
- [sqlstyle-guide](../resources/sqlstyle-guide/README.md) — formatting conventions
