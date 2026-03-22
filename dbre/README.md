# DBRE — Database Reliability Engineering

[← Home](../README.md)

DBRE applies SRE principles to databases. Databases are the most critical and least replaceable part of most systems. Your goal: keep them fast, available, correct, and operable.

---

## Topics

| Topic | What you'll learn |
|-------|------------------|
| [Fundamentals](fundamentals.md) | DB reliability concepts, connection pooling, monitoring |
| [SQL Best Practices](sql.md) | Query writing, anti-patterns, optimization |
| [Anti-Patterns](antipatterns.md) | Design and query anti-patterns (sqlcheck reference) |
| [Performance Tuning](performance.md) | Query optimization, indexes, execution plans |
| [Migrations & Schema Changes](migrations.md) | Safe schema changes, zero-downtime migrations |
| [Backup & Recovery](backup-recovery.md) | Backup strategies, point-in-time recovery, DR |
| [Scaling Databases](scaling.md) | Read replicas, sharding, connection pooling at scale |
| [**Lab Runbook**](lab/runbook.md) | **Docker lab — try everything hands-on (MySQL + HAProxy + ProxySQL + replicas + backups)** |

---

## Learning Path

```
[B] Fundamentals → SQL Best Practices → Backup & Recovery
[I] Performance Tuning → Migrations
[A] Scaling → Distributed databases → DB reliability engineering
```

---

## Key Resources

- [percona-toolkit](../resources/percona-toolkit/README.md) — Battle-tested MySQL/PostgreSQL tools
- [sql-guide](../resources/sql-guide/SQL_interview_questions.txt) — SQL interview Q&A
- [sqlcheck](../resources/sqlcheck/README.md) — SQL anti-pattern detection
- [sql-tips-and-tricks](../resources/sql-tips-and-tricks/README.md) — Practical SQL tips and tricks
- [awesome-mysql](../resources/awesome-mysql/README.md) — MySQL queries, commands and snippets
- [sqlstyle-guide](../resources/sqlstyle-guide/README.md) — SQL style guide for consistent formatting
- [data-engineer-handbook](../resources/data-engineer-handbook/README.md) — Data engineering context
- [awesome-scalability](../resources/awesome-scalability/README.md) — DB scaling patterns

---

[← SRE](../sre/README.md) | [← Platform](../platform/README.md)
