# Engineering Skills Guide

> **Dmytro Chernenko's** personal guide to the engineering universe — a fast-navigation reference across SRE, Platform Engineering, DBRE, Messaging, and Architecture.
>
> ### [Browse the rendered site → diamonce.github.io/guide](https://diamonce.github.io/guide/)

---

## Domains

| Domain | Focus | Entry Point |
|--------|-------|-------------|
| **SRE** | Reliability, observability, incident response | [sre/README.md](sre/README.md) |
| **Platform Engineering** | Terraform, Kubernetes, CI/CD, cloud infra | [platform/README.md](platform/README.md) |
| **DBRE** | Database reliability, performance, scaling | [dbre/README.md](dbre/README.md) |
| **Messaging** | Kafka, RabbitMQ, SQS/SNS, Pulsar, NATS | [messaging/README.md](messaging/README.md) |
| **Architecture** | Well-Architected, landing zones, blast radius, least privilege | [architecture/README.md](architecture/README.md) |

---

## SRE

- [Fundamentals & Concepts](sre/fundamentals.md)
- [SLOs / SLIs / SLAs](sre/slo-sla-sli.md)
- [Observability](sre/observability.md)
- [OpenTelemetry & Tracing](sre/opentelemetry.md)
- [Incident Management](sre/incident-management.md)
- [On-Call & Runbooks](sre/on-call.md)
- [Scalability](sre/scalability.md)
- [Case Studies](sre/case-studies.md) — Airbnb, Booking.com, Capital One, Dropbox, eBay, Etsy, GitHub, Google, Pinterest, Shopify, Slack, Spotify, Stripe, Twitter, Uber (real links, no hallucinations)

## Platform Engineering

- [Terraform & IaC](platform/terraform.md)
- [Kubernetes](platform/kubernetes.md)
- [CI/CD Pipelines](platform/cicd.md)
- [Cloud Infrastructure](platform/cloud-infra.md)
- [Security & Hardening](platform/security.md)
- [Practice & Interview Prep](platform/practice.md) — 2,600+ exercises
- [External Links](platform/external-links.md) — GitHub Well-Architected governance

## DBRE

- [Database Landscape](dbre/databases.md) — PostgreSQL, MySQL, Oracle, MongoDB, Redis, Cassandra, ClickHouse, Aurora, DynamoDB, Spanner, Cosmos DB, CockroachDB, PlanetScale
- [Fundamentals](dbre/fundamentals.md)
- [SQL Best Practices](dbre/sql.md)
- [Anti-Patterns](dbre/antipatterns.md)
- [Best Practices — Do's and Don'ts](dbre/best-practices.md) — schema design, queries, indexing, naming, tools
- [Performance Tuning](dbre/performance.md)
- [Migrations & Schema Changes](dbre/migrations.md)
- [Backup & Recovery](dbre/backup-recovery.md)
- [Scaling Databases](dbre/scaling.md)
- [Lab Runbook](dbre/lab/runbook.md) — Docker lab: MySQL replication + HAProxy + ProxySQL + backups + failover
- [External Links](dbre/external-links.md) — official docs for 15 databases, PostgreSQL Don't Do This, sqlblog

## Messaging

- [Overview & System Comparison](messaging/README.md) — Kafka vs RabbitMQ vs SQS/SNS vs Pulsar vs NATS vs Redis Streams; broker selection table; all fan-out patterns
- [Kafka Deep Dive](messaging/kafka.md) — partitions, consumer groups, exactly-once, schema registry, consumer lag, KRaft, Kafka Streams
- [Best Practices](messaging/best-practices.md) — do's/don'ts for Kafka, RabbitMQ, SQS/SNS; pre-deploy checklist
- [External Links](messaging/external-links.md) — official docs, free O'Reilly books, Jay Kreps' foundational log essay

## Architecture

- [Overview & Core Principles](architecture/README.md)
- [Well-Architected](architecture/well-architected.md) — AWS / GCP / Azure 6 pillars, availability table, checklists
- [Landing Zones](architecture/landing-zones.md) — multi-account org design, SCPs, GCP org policies, account vending, hub-and-spoke Transit Gateway
- [Best Practices](architecture/best-practices.md) — blast radius (cell architecture, bulkheads, circuit breakers, canary), least privilege (IRSA, permission boundaries, JIT), scalability (CQRS, queue leveling, caching layers)
- [External Links](architecture/external-links.md) — official frameworks, system design books, reference architectures

---

## Resource Library

The repos below are checked-out copies of open-source projects vendored here for offline browsing and cross-linking. **All content rights belong to the original authors.** See each repo's license for details.

| Repo | Domain | Description |
|------|--------|-------------|
| [awesome-sre](resources/awesome-sre/README.md) | SRE | Curated SRE resources, tools, books |
| [howtheysre](resources/howtheysre/README.md) | SRE | How 60+ real companies do SRE — blog posts, talks, incident reports |
| [sre-collection](resources/sre-collection/README.md) | SRE | SRE job/interview collection |
| [devops-exercises](resources/devops-exercises/README.md) | Platform/SRE | 2,600+ practice Q&A across DevOps topics |
| [devops-collection](resources/devops-collection/README.md) | Platform | DevOps tools and resources |
| [book-of-secret-knowledge](resources/book-of-secret-knowledge/README.md) | Platform/Security | CLI tools, one-liners, cheatsheets |
| [github-well-architected](resources/github-well-architected/README.md) | Platform | GitHub Well-Architected — reliability, security, governance |
| [awesome-scalability](resources/awesome-scalability/README.md) | Architecture | System design & scalability patterns from real companies |
| [system-design-primer](resources/system-design-primer/README.md) | Architecture | The most comprehensive system design reference on GitHub |
| [awesome-system-design](resources/awesome-system-design/README.md) | Architecture | Curated system design resources, papers, implementations |
| [awesome-chaos-engineering](resources/awesome-chaos-engineering/README.md) | Architecture/SRE | Chaos engineering tools, books, papers, and game days |
| [percona-toolkit](resources/percona-toolkit/README.md) | DBRE | MySQL/PostgreSQL DBA toolkit (pt-osc, pt-query-digest, pt-table-checksum) |
| [sqlcheck](resources/sqlcheck/README.md) | DBRE | SQL anti-pattern detection — run in CI |
| [sql-tips-and-tricks](resources/sql-tips-and-tricks/README.md) | DBRE | Practical SQL tips and tricks |
| [sqlstyle-guide](resources/sqlstyle-guide/README.md) | DBRE | SQL style guide for consistent formatting |
| [awesome-mysql](resources/awesome-mysql/README.md) | DBRE | MySQL queries, commands and snippets |
| [awesome-postgres](resources/awesome-postgres/README.md) | DBRE | PostgreSQL resources, tools, extensions |
| [awesome-mongodb](resources/awesome-mongodb/README.md) | DBRE | MongoDB resources and tools |
| [awesome-redis](resources/awesome-redis/README.md) | DBRE | Redis resources, patterns, tooling |
| [awesome-nosql-guides](resources/awesome-nosql-guides/README.md) | DBRE | NoSQL patterns, guides, comparisons |
| [awesome-kafka](resources/awesome-kafka/README.md) | Messaging | Kafka tools, clients, libraries, resources |
| [data-engineer-handbook](resources/data-engineer-handbook/README.md) | DBRE/Data | Data engineering roadmap & resources |
| [sql-guide](resources/sql-guide/SQL_interview_questions.txt) | DBRE | SQL interview Q&A |

---

## Contributing

Found something wrong, outdated, or missing? Pull requests are welcome.
This is a living document — if a pattern clicked for you or you know a better source, open a PR.
