# DBRE — Database Reliability Engineering

[← Home](../README.md)

DBRE applies SRE principles to databases. Databases are the most critical and least replaceable part of most systems. Your goal: keep them fast, available, correct, and operable.

---

## Topics

| Topic | What you'll learn |
|-------|------------------|
| [Database Landscape](databases.md) | Every major engine — relational, NoSQL, cloud-native; pros/cons, decision framework |
| [Fundamentals](fundamentals.md) | DB reliability concepts, connection pooling, monitoring |
| [SQL Best Practices](sql.md) | Query writing, anti-patterns, optimization |
| [Anti-Patterns](antipatterns.md) | Design and query anti-patterns (sqlcheck reference) |
| [Security](security.md) | Access control, encryption, secrets management, audit logging, PII/compliance |
| [Performance Tuning](performance.md) | Query optimization, indexes, execution plans |
| [Migrations & Schema Changes](migrations.md) | Safe schema changes, zero-downtime migrations, rollback strategies |
| [Backup & Recovery](backup-recovery.md) | Backup strategies, point-in-time recovery, DR |
| [Observability](observability.md) | Monitoring stack, exporters, alert hierarchy, Prometheus/Grafana, replication lag |
| [HA & Failover](ha-failover.md) | ProxySQL routing, Orchestrator, failover runbooks, replica provisioning, MySQL upgrades |
| [Load Testing & VM Optimization](load-testing.md) | sysbench, mysqlslap, InnoDB tuning, OS settings, cloud VM sizing |
| [Scaling Databases](scaling.md) | Read replicas, sharding, connection pooling at scale |
| [**Lab Runbook**](lab/runbook.md) | **Docker lab — try everything hands-on (MySQL + HAProxy + ProxySQL + replicas + backups)** |
| [Best Practices](best-practices.md) | Do's and don'ts — schema design, queries, indexing, tools, naming |
| [External Links](external-links.md) | PostgreSQL docs, Don't Do This wiki, sqlblog bad habits, modern-sql |
| [**Postmortem Template**](postmortem-template.md) | **Operational failures — outage, failover, replication break, backup failure** |
| [**DEA Template**](dea-template.md) | **Defect Escape Analysis — defects that slipped through quality gates to production** |

---

## Learning Path

```
[B] Database Landscape → Fundamentals → SQL Best Practices → Backup & Recovery → Security
[I] Performance Tuning → Migrations → Observability → HA & Failover → Best Practices
[A] Scaling → Distributed databases → DB reliability engineering
```

---

## Key Resources

- [percona-toolkit](../resources/percona-toolkit/README.md) — Battle-tested MySQL/PostgreSQL tools
- [sql-guide](../resources/sql-guide/SQL_interview_questions.txt) — SQL interview Q&A
- [sqlcheck](../resources/sqlcheck/README.md) — SQL anti-pattern detection
- [sql-tips-and-tricks](../resources/sql-tips-and-tricks/README.md) — Practical SQL tips and tricks
- [awesome-mysql](../resources/awesome-mysql/README.md) — MySQL queries, commands and snippets
- [awesome-postgres](../resources/awesome-postgres/README.md) — PostgreSQL resources and tools
- [awesome-mongodb](../resources/awesome-mongodb/README.md) — MongoDB resources and tools
- [awesome-redis](../resources/awesome-redis/README.md) — Redis resources and tools
- [awesome-nosql-guides](../resources/awesome-nosql-guides/README.md) — NoSQL patterns and guides
- [sqlstyle-guide](../resources/sqlstyle-guide/README.md) — SQL style guide for consistent formatting
- [data-engineer-handbook](../resources/data-engineer-handbook/README.md) — Data engineering context
- [awesome-scalability](../resources/awesome-scalability/README.md) — DB scaling patterns
- [atlassian-incident-handbook](../resources/atlassian-incident-handbook/postmortems.md) — Postmortem framework, Five Whys, blameless culture (DB postmortem reference)

---

[← SRE](../sre/README.md) | [← Platform](../platform/README.md)
