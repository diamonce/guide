# Engineering Skills Guide

Personal navigation hub for SRE, Platform Engineering (Terraform/IaC), DBRE, Messaging, and Architecture skills. Browse the site at [diamonce.github.io/guide](https://diamonce.github.io/guide/).

---

## Domains

| Domain | Focus | Entry Point |
|--------|-------|-------------|
| **SRE** | Reliability, observability, incident response | [sre/README.md](sre/README.md) |
| **Platform Engineering** | Terraform, Kubernetes, CI/CD, cloud infra | [platform/README.md](platform/README.md) |
| **DBRE** | Database reliability, performance, scaling | [dbre/README.md](dbre/README.md) |
| **Messaging** | Kafka, RabbitMQ, SQS/SNS, queues, event streaming | [messaging/README.md](messaging/README.md) |
| **Architecture** | Well-Architected, landing zones, blast radius, least privilege, scalability | [architecture/README.md](architecture/README.md) |

---

## SRE

- [Fundamentals & Concepts](sre/fundamentals.md)
- [SLOs / SLIs / SLAs](sre/slo-sla-sli.md)
- [Observability](sre/observability.md)
- [Incident Management](sre/incident-management.md)
- [On-Call & Runbooks](sre/on-call.md)
- [Scalability](sre/scalability.md)
- [Case Studies](sre/case-studies.md) — Netflix, Google, Uber, Airbnb, Discord...

## Platform Engineering

- [Terraform & IaC](platform/terraform.md)
- [Kubernetes](platform/kubernetes.md)
- [CI/CD Pipelines](platform/cicd.md)
- [Cloud Infrastructure](platform/cloud-infra.md)
- [Security & Hardening](platform/security.md)
- [Practice & Interview Prep](platform/practice.md) — 2,600+ exercises

## Architecture

- [Overview & Core Principles](architecture/README.md)
- [Well-Architected](architecture/well-architected.md) — AWS / GCP / Azure 6 pillars, review checklists
- [Landing Zones](architecture/landing-zones.md) — multi-account foundations, SCPs, account vending, hub-and-spoke networking
- [Best Practices](architecture/best-practices.md) — blast radius, least privilege, scalability, circuit breakers, cell architecture
- [External Links](architecture/external-links.md) — official frameworks, system design books, reference architectures

## Messaging

- [Overview & System Comparison](messaging/README.md) — Kafka vs RabbitMQ vs SQS vs Pulsar vs NATS
- [Kafka Deep Dive](messaging/kafka.md) — partitions, consumer groups, exactly-once, operations
- [Best Practices](messaging/best-practices.md) — do's/don'ts for Kafka, RabbitMQ, SQS
- [External Links](messaging/external-links.md) — official docs, design essays, benchmarks

## DBRE

- [Database Landscape](dbre/databases.md) — every engine compared: PostgreSQL, MySQL, Oracle, MongoDB, Redis, Aurora, DynamoDB, Spanner, Cosmos
- [Database Reliability Fundamentals](dbre/fundamentals.md)
- [SQL Best Practices](dbre/sql.md)
- [Anti-Patterns](dbre/antipatterns.md) — design & query anti-patterns
- [Best Practices — Do's and Don'ts](dbre/best-practices.md)
- [Performance Tuning](dbre/performance.md)
- [Migrations & Schema Changes](dbre/migrations.md)
- [Backup & Recovery](dbre/backup-recovery.md)
- [Scaling Databases](dbre/scaling.md)

---

## Resource Library (Submodules)

| Repo | Domain | Description |
|------|--------|-------------|
| [awesome-sre](resources/awesome-sre/README.md) | SRE | Curated SRE resources, tools, books |
| [howtheysre](resources/howtheysre/README.md) | SRE | How real companies do SRE |
| [sre-collection](resources/sre-collection/README.md) | SRE | SRE job/interview collection |
| [devops-exercises](resources/devops-exercises/README.md) | Platform/SRE | Practice Q&A across DevOps topics |
| [devops-collection](resources/devops-collection/README.md) | Platform | DevOps tools and resources |
| [book-of-secret-knowledge](resources/book-of-secret-knowledge/README.md) | Platform/Security | CLI tools, one-liners, cheatsheets |
| [awesome-scalability](resources/awesome-scalability/README.md) | Scalability | System design & scalability patterns |
| [data-engineer-handbook](resources/data-engineer-handbook/README.md) | DBRE/Data | Data engineering roadmap & resources |
| [percona-toolkit](resources/percona-toolkit/README.md) | DBRE | MySQL/PostgreSQL DBA toolkit |
| [sql-guide](resources/sql-guide/SQL_interview_questions.txt) | DBRE | SQL interview Q&A |
| [sqlcheck](resources/sqlcheck/README.md) | DBRE | Anti-pattern detection in SQL |
| [github-well-architected](resources/github-well-architected/README.md) | Platform | GitHub Well-Architected library — reliability, security, governance |
| [sql-tips-and-tricks](resources/sql-tips-and-tricks/README.md) | DBRE | Practical SQL tips and tricks |
| [awesome-mysql](resources/awesome-mysql/README.md) | DBRE | MySQL queries, commands and snippets |
| [awesome-postgres](resources/awesome-postgres/README.md) | DBRE | PostgreSQL resources, tools, extensions |
| [awesome-mongodb](resources/awesome-mongodb/README.md) | DBRE | MongoDB resources and tools |
| [awesome-redis](resources/awesome-redis/README.md) | DBRE | Redis resources, patterns, tooling |
| [awesome-nosql-guides](resources/awesome-nosql-guides/README.md) | DBRE | NoSQL patterns, guides, comparisons |
| [awesome-kafka](resources/awesome-kafka/README.md) | Messaging | Kafka tools, clients, libraries, resources |
| [system-design-primer](resources/system-design-primer/README.md) | Architecture | Comprehensive system design reference — the most complete guide available |
| [awesome-system-design](resources/awesome-system-design/README.md) | Architecture | Curated system design resources, case studies, papers |
| [sqlstyle-guide](resources/sqlstyle-guide/README.md) | DBRE | SQL style guide for consistent formatting |

---

## Skill Progression

```
Beginner  →  Intermediate  →  Advanced
   [B]            [I]            [A]
```

Each topic page marks concepts with these levels. Start at [B], move forward as you get comfortable.
