# Database Landscape — Engines, Cloud Services & Selection Guide

[← DBRE Home](README.md) | [← Main](../README.md)

Reference guide covering every major database category: what each engine is, when to use it, cloud-managed equivalents, what the cloud abstracts away, and honest pros/cons.

---

## Taxonomy

```
Databases
├── Relational (SQL / ACID)
│   ├── PostgreSQL
│   ├── MySQL / MariaDB
│   └── Oracle Database
├── Document
│   └── MongoDB
├── Key-Value / In-Memory
│   └── Redis
├── Wide-Column
│   └── Apache Cassandra
├── Columnar / OLAP
│   └── ClickHouse
├── Search
│   └── Elasticsearch
└── Cloud-Native / Distributed SQL
    ├── Amazon Aurora
    ├── Amazon DynamoDB
    ├── Google Cloud Spanner
    ├── Azure Cosmos DB
    ├── CockroachDB
    └── PlanetScale
```

---

## Relational Databases (SQL)

### PostgreSQL

**Official docs:** [postgresql.org/docs/current](https://www.postgresql.org/docs/current/)
**Resource:** [awesome-postgres](../resources/awesome-postgres/README.md)

The gold standard for general-purpose relational workloads. Most SQL-compliant open-source database available.

| Attribute | Detail |
|-----------|--------|
| License | PostgreSQL License (MIT-like, free forever) |
| Replication | Streaming (physical) + Logical |
| Transactions | Full ACID, MVCC |
| Horizontal scale | Vertical by default; Citus for sharding |
| Extension ecosystem | PostGIS, pg_trgm, TimescaleDB, pgvector, Citus |

**Strengths**
- Best SQL standard compliance of any open-source DB
- JSONB: full relational + document hybrid in one engine
- Advanced index types: B-tree, Hash, GIN, GiST, BRIN, partial, expression
- Window functions, CTEs, lateral joins, full-text search built-in
- Row-level security, logical replication, table partitioning

**Weaknesses**
- You manage HA, failover, and replication yourself (use [Patroni](https://github.com/zalando/patroni))
- MVCC bloat — `VACUUM` must run regularly or tables degrade
- No built-in clustering; read scaling requires explicit replica setup
- Multi-master not supported natively

**Avoid when:** Your team can't manage `pg_hba.conf`, replication lag, and VACUUM tuning. Use a cloud-managed option instead.

→ Anti-patterns: [dbre/external-links.md — Don't Do This](external-links.md)
→ Performance tuning: [dbre/performance.md](performance.md)

---

### MySQL / MariaDB

**Official docs:** [dev.mysql.com/doc](https://dev.mysql.com/doc/) | [MariaDB docs](https://mariadb.com/kb/en/)
**Resource:** [awesome-mysql](../resources/awesome-mysql/README.md)

The most deployed open-source database worldwide. Powers WordPress, Shopify, GitHub (on Vitess), Airbnb, Twitter.

| Attribute | Detail |
|-----------|--------|
| License | GPL v2 (Community), commercial (Enterprise) |
| Replication | Async statement/row/mixed; GTID-based |
| Transactions | InnoDB: ACID. MyISAM: no transactions (don't use) |
| Horizontal scale | Vitess for sharding; ProxySQL for routing |
| Storage engines | InnoDB (use this), MyISAM (legacy), RocksDB |

**Strengths**
- Largest operational knowledge base — virtually every problem is documented
- Fast reads; InnoDB buffer pool tuning is well understood
- GTID replication simplifies replica management and failover
- [Percona Toolkit](../resources/percona-toolkit/README.md) — battle-tested operational tooling
- pt-online-schema-change / gh-ost: zero-downtime schema changes

**Weaknesses**
- Weaker SQL compliance than PostgreSQL (e.g., `GROUP BY` quirks, `ONLY_FULL_GROUP_BY` off by default historically)
- JSON support added later; less capable than PostgreSQL JSONB
- No native parallel query (added partially in MySQL 8)
- No table inheritance, no window functions until MySQL 8

**Avoid when:** You need complex analytical queries, JSONB, advanced SQL features — use PostgreSQL.

→ Lab: [dbre/lab/runbook.md](lab/runbook.md) — full MySQL replication + HAProxy + ProxySQL hands-on
→ Tooling: [percona-toolkit](../resources/percona-toolkit/README.md)

---

### Oracle Database

**Official docs:** [docs.oracle.com/database](https://docs.oracle.com/en/database/)

Enterprise standard for financial systems, ERP (SAP, Oracle E-Business Suite), and regulated industries. The most feature-complete commercial RDBMS.

| Attribute | Detail |
|-----------|--------|
| License | Commercial; extremely expensive |
| Replication | Data Guard, GoldenGate (extra cost) |
| Transactions | Full ACID, multi-version |
| Horizontal scale | RAC (Real Application Clusters) |
| HA | Data Guard with automatic failover |

**Strengths**
- Most mature optimizer of any RDBMS — handles pathological queries better than anyone
- RAC: active-active clustering across nodes — unique capability
- Advanced Compression, In-Memory Column Store, partitioning — enterprise features first
- PL/SQL: extensive stored procedure ecosystem
- Strongest enterprise support SLAs

**Weaknesses**
- Licensing is a legal and financial minefield — CPU licensing, named user licensing, feature packs
- Lock-in is extreme — PL/SQL, Oracle-specific SQL syntax, RAC
- Operational complexity requires DBAs with Oracle-specific certs
- Most organizations running Oracle are doing so because they're stuck, not by choice

**Avoid when:** You're greenfield. Use PostgreSQL instead. Only stay on Oracle if legacy code or compliance mandates it, or use [Amazon RDS for Oracle](https://aws.amazon.com/rds/oracle/) to at least remove the ops burden.

---

## Document Databases

### MongoDB

**Official docs:** [mongodb.com/docs](https://www.mongodb.com/docs/)
**Resource:** [awesome-mongodb](../resources/awesome-mongodb/README.md)

Document store built for flexible, nested data. JSON-native. Horizontal scaling via sharding is first-class.

| Attribute | Detail |
|-----------|--------|
| License | SSPL (v5+); BSL |
| Data model | BSON documents (binary JSON) |
| Transactions | Multi-document ACID since 4.0 |
| Horizontal scale | Native sharding, replica sets |
| Query language | MQL (MongoDB Query Language) + aggregation pipeline |

**Strengths**
- Schema flexibility: add fields without migrations — good for rapid iteration
- Rich aggregation pipeline: `$lookup`, `$unwind`, `$facet`, `$graphLookup`
- Native horizontal sharding — shard by any key
- MongoDB Atlas: best-in-class managed offering with Search, Data API, Charts
- Strong geospatial query support

**Weaknesses**
- No true joins — `$lookup` is expensive; denormalization is the pattern
- Historically eventual consistency; requires careful read/write concern tuning
- SSPL license means cloud providers can't offer it freely — only MongoDB Inc. can (hence Atlas)
- Query patterns must be designed upfront around document structure
- Without schema validation, production data quality drifts fast

**Avoid when:** Your data is highly relational (many entities with complex relationships). Use PostgreSQL.

→ Patterns reference: [awesome-nosql-guides](../resources/awesome-nosql-guides/README.md)

---

## Key-Value / In-Memory

### Redis

**Official docs:** [redis.io/docs](https://redis.io/docs/)
**Resource:** [awesome-redis](../resources/awesome-redis/README.md)

In-memory data structure server. The universal caching layer and the best tool for session storage, rate limiting, pub/sub, and leaderboards.

| Attribute | Detail |
|-----------|--------|
| License | RSALv2 / SSPLv1 (v7.4+); BSD (v7.2 and below) |
| Data model | Strings, Hashes, Lists, Sets, Sorted Sets, Streams, Bitmaps, HyperLogLog |
| Persistence | RDB snapshots + AOF (append-only file) |
| Replication | Async primary-replica; Redis Cluster for sharding |
| Transactions | MULTI/EXEC (optimistic locking with WATCH) |

**Strengths**
- Sub-millisecond latency — nothing is faster for in-memory access
- Sorted sets: leaderboards, priority queues, range queries by score
- Streams: persistent, consumer-group message queue (like a lightweight Kafka)
- Lua scripting for atomic multi-step operations
- TTL on every key — natural cache expiry
- Pub/Sub for real-time event broadcasting

**Weaknesses**
- Data must fit in RAM — expensive at scale
- Persistence is secondary: RDB+AOF adds latency; pure in-memory is the performance mode
- Redis Cluster: hash slot model limits some multi-key operations
- License changed in 2024 — [Valkey](https://valkey.io/) is the open-source fork maintained by AWS, Google, Alibaba

**Primary use cases**
```
Cache layer           → SET key value EX 3600
Session storage       → HSET session:{id} user_id 42 expires_at ...
Rate limiting         → INCR + EXPIRE
Leaderboard           → ZADD + ZREVRANK
Job queue             → LPUSH + BRPOP (or Redis Streams)
Pub/Sub               → PUBLISH / SUBSCRIBE
Distributed lock      → SET key value NX EX (Redlock algorithm)
```

→ Scaling pattern: cache-aside, write-through, write-behind — see [dbre/scaling.md](scaling.md)

---

## Wide-Column

### Apache Cassandra

**Official docs:** [cassandra.apache.org/doc](https://cassandra.apache.org/doc/latest/)

Masterless, linearly scalable wide-column store designed for high write throughput across multiple data centers. Born at Facebook, open-sourced, adopted by Netflix, Apple, Discord.

| Attribute | Detail |
|-----------|--------|
| License | Apache 2.0 |
| Data model | Partitioned rows, clustering columns |
| Consistency | Tunable: ONE, QUORUM, ALL |
| Replication | Multi-DC, configurable replication factor |
| Query language | CQL (Cassandra Query Language — SQL-like) |

**Strengths**
- True masterless — no single point of failure, no leader election
- Linear horizontal scale: add nodes, get throughput
- Multi-region active-active out of the box
- Excellent for time-series data (Discord messages, IoT sensor readings)
- Write path is extremely fast — LSM tree, writes to memtable + commitlog only

**Weaknesses**
- Query patterns must match the data model — design tables for queries, not normalization
- No joins, no aggregations, no ad-hoc queries
- Eventual consistency by default — QUORUM adds latency
- Compaction and tombstone management require ops expertise
- Counter columns are a footgun

**Avoid when:** You need ad-hoc queries, complex relationships, or ACID. Cassandra forces you to model upfront.

---

## Columnar / OLAP

### ClickHouse

**Official docs:** [clickhouse.com/docs](https://clickhouse.com/docs/)

Columnar OLAP database for analytics at scale. Powers Cloudflare, Contentsquare, Criteo analytics pipelines.

| Attribute | Detail |
|-----------|--------|
| License | Apache 2.0 |
| Data model | Column-oriented tables |
| Ingestion | Kafka, S3, HTTP, native client |
| Query language | SQL (extended) |
| Compression | LZ4 / ZSTD per column |

**Strengths**
- Fastest analytical query engine for aggregations on large datasets
- Vectorized query execution — uses SIMD instructions
- Excellent compression — columnar storage compresses 5–15× better than row storage
- Real-time ingestion at billions of rows/day
- MergeTree table engine: sorted, partitioned, indexed — very flexible

**Weaknesses**
- Not for OLTP: high-frequency single-row updates are expensive
- Eventual consistency in distributed mode — ReplicatedMergeTree has caveats
- JOINs are less efficient than in OLTP databases — denormalize first
- Complex to operate: sharding, replication, ZooKeeper dependency (or ClickHouse Keeper)

**Avoid when:** You need transactional workloads. Use PostgreSQL or MySQL for OLTP, ClickHouse for analytics on top.

---

## Cloud-Native Databases

### Amazon Aurora

**Official docs:** [aws.amazon.com/rds/aurora](https://aws.amazon.com/rds/aurora/)

AWS-built relational database with MySQL and PostgreSQL compatibility. Separates storage from compute — the storage layer is a distributed, self-healing 6-way replicated volume.

| Attribute | Detail |
|-----------|--------|
| Compatibility | MySQL 8.x or PostgreSQL 15.x wire protocol |
| Storage | Auto-scales to 128 TB, 6 copies across 3 AZs |
| Failover | Automatic, typically < 30 seconds |
| Read replicas | Up to 15 Aurora Replicas (< 10ms replica lag typical) |
| Serverless v2 | Auto-scales compute in 0.5 ACU increments |

**What Aurora abstracts away vs. self-managed:**

| You no longer manage | How Aurora handles it |
|---------------------|-----------------------|
| Storage provisioning | Auto-scales; no pre-allocated disk |
| Replication setup | Built into storage layer — always 6 copies |
| Failover configuration | Automatic; promotes replica to primary |
| Backup | Continuous to S3; PITR to any second |
| Patching | Managed maintenance windows |
| Multi-AZ setup | Free — storage is always multi-AZ |

**Pros**
- Drop-in replacement for MySQL/PostgreSQL — minimal app changes
- 5× throughput of standard MySQL on same hardware (AWS claim)
- Global Database: replicate across regions with < 1s lag
- Aurora Serverless v2: scale to zero, ideal for dev/staging

**Cons**
- 3–4× more expensive than running RDS MySQL/PostgreSQL
- Not 100% compatible — some MySQL/Postgres-specific features differ
- Storage is AWS-proprietary — migrating off requires mysqldump / pg_dump
- Vendor lock-in: Aurora-specific features (Serverless, Global DB) don't port

→ Scaling patterns: [dbre/scaling.md](scaling.md)

---

### Amazon DynamoDB

**Official docs:** [docs.aws.amazon.com/dynamodb](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)

Fully managed, serverless key-value and document database. No servers to provision, no capacity to pre-plan (On-Demand mode). AWS's flagship NoSQL offering.

| Attribute | Detail |
|-----------|--------|
| Data model | Key-Value + Document (JSON) |
| Consistency | Eventual (default) or Strong (per-request) |
| Scale | Unlimited — AWS handles sharding automatically |
| Latency | Single-digit milliseconds at any scale |
| Pricing | On-Demand (pay per request) or Provisioned (reserve capacity) |

**What DynamoDB abstracts away:**

| You no longer manage | How DynamoDB handles it |
|---------------------|------------------------|
| Sharding | Automatic partition management |
| Replication | 3-way across AZs — always on |
| Failover | Transparent — no concept of a primary |
| Indexes | GSIs and LSIs replace most query patterns |
| Capacity | On-Demand mode: auto-scales instantly |
| Backups | Point-in-time recovery, on-demand backups |

**Pros**
- True serverless — zero operational overhead
- DynamoDB Streams: event-driven architecture, trigger Lambdas on changes
- Global Tables: multi-region active-active, built-in conflict resolution
- DAX (DynamoDB Accelerator): in-memory cache, microsecond latency
- TTL: automatic item expiry — no cron jobs needed

**Cons**
- Highest lock-in of any database — no open-source equivalent, no standard API
- Query flexibility is limited by your key design — table scans are expensive
- Transactions cost 2× read/write units
- 400 KB item size limit
- GSI consistency is eventual — can cause stale reads

**Avoid when:** Your access patterns aren't known upfront, or you need ad-hoc queries. The data model must be designed around access patterns — not the other way around.

---

### Google Cloud Spanner

**Official docs:** [cloud.google.com/spanner/docs](https://cloud.google.com/spanner/docs)

The only database that offers globally distributed ACID transactions with external consistency. Spans regions with a single logical database.

| Attribute | Detail |
|-----------|--------|
| Compatibility | GoogleSQL dialect or PostgreSQL dialect |
| Transactions | Global ACID — no other database does this at scale |
| Consistency | External consistency (stronger than serializability) |
| Scale | Horizontal — add nodes, get linear throughput |
| Availability | 99.999% SLA (five nines) |

**What Spanner abstracts away:**
- Every problem that comes with running distributed databases: split-brain, two-phase commit latency, replication lag, global clock synchronization (solved with TrueTime)
- Cross-region schema migrations without downtime
- Any concept of "primary region" — all regions are equal

**Pros**
- The only solution for global ACID at scale — nothing else comes close
- SQL interface (GoogleSQL or PostgreSQL dialect)
- Automatic sharding, replication, failover — completely managed
- Interleaved tables for parent-child locality (like foreign key + colocation)

**Cons**
- Most expensive managed database — compute + storage + replication all billed
- GCP-only — no multi-cloud, no self-hosted option
- Maximum lock-in: no migration path that doesn't involve a full data export
- Performance depends on good key design — hotspot partitions kill throughput
- Learning curve: interleaving, read-write transactions vs. read-only transactions

**Use when:** You're building a financial system, booking platform, or inventory system that genuinely needs consistency across multiple geographic regions with no tolerance for split-brain.

---

### Azure Cosmos DB

**Official docs:** [learn.microsoft.com/azure/cosmos-db](https://learn.microsoft.com/en-us/azure/cosmos-db/)

Microsoft's globally distributed, multi-model database. Unique in offering multiple API compatibility layers over the same underlying storage engine.

| Attribute | Detail |
|-----------|--------|
| APIs | NoSQL (native), MongoDB, Cassandra, Gremlin (graph), Table |
| Consistency | 5 tunable levels: Strong → Bounded Staleness → Session → Consistent Prefix → Eventual |
| Distribution | Multi-region, multi-write active-active |
| Pricing | RU/s (Request Units) model — abstractly charged per operation complexity |

**Pros**
- Only database offering 5 tunable consistency levels — model your consistency/latency trade-off explicitly
- API compatibility: migrate from Mongo, Cassandra, or Azure Table without changing app code
- Global distribution: < 10ms reads anywhere in the world
- 99.999% SLA for multi-region writes

**Cons**
- RU/s pricing model is opaque and hard to predict — surprise bills are common
- MongoDB API compatibility is not perfect — newer MongoDB drivers and features lag
- Azure-only — deep integration with Azure Functions, Logic Apps creates additional lock-in
- Partition key choice is permanent and critical — wrong choice = hot partitions and re-architecture

---

### CockroachDB

**Official docs:** [cockroachlabs.com/docs](https://www.cockroachlabs.com/docs/)

Distributed SQL database inspired by Spanner. PostgreSQL wire-compatible. Cloud-agnostic, self-hostable, or managed (CockroachDB Cloud).

| Attribute | Detail |
|-----------|--------|
| Compatibility | PostgreSQL wire protocol |
| Transactions | Serializable ACID globally |
| Scale | Horizontal, automatic sharding |
| Replication | Raft consensus, configurable replication factor |

**Pros**
- Postgres-compatible — existing Postgres tooling, drivers, and ORMs work
- Self-hostable or managed — not locked to a single cloud
- Automatic geo-partitioning: pin rows to specific regions for data residency compliance
- Surviving node failures without manual intervention

**Cons**
- Not 100% Postgres compatible — some extensions and features don't work
- Distributed transaction overhead vs. single-node Postgres — latency for simple queries is higher
- BSL license (non-commercial free; commercial requires subscription)
- Smaller community than Postgres or MySQL

---

### PlanetScale

**Official docs:** [planetscale.com/docs](https://planetscale.com/docs)

MySQL-compatible database built on [Vitess](https://vitess.io/) (the same engine that scales YouTube/GitHub/Shopify). Adds git-like schema branching.

| Attribute | Detail |
|-----------|--------|
| Compatibility | MySQL wire protocol |
| Scaling | Vitess horizontal sharding, invisible to the application |
| Schema changes | Non-blocking — uses Vitess Online DDL |
| Branching | Schema branches: test migrations on a branch before merging to production |

**Pros**
- Schema branching is genuinely novel — catch bad migrations before they hit production
- Non-blocking DDL by default — no pt-osc or gh-ost needed
- Vitess sharding abstracts horizontal scale entirely from the application

**Cons**
- No foreign key enforcement (Vitess limitation) — referential integrity must be in the application
- MySQL-only — not Postgres
- Managed-only — can't self-host PlanetScale (can self-host raw Vitess)

---

## Cloud vs. Self-Managed — Full Comparison

### What Cloud Databases Abstract Away

| Responsibility | Self-Managed | Cloud-Managed |
|---------------|-------------|---------------|
| **Storage provisioning** | Pre-allocate, resize, manage volumes | Auto-scales (Aurora, Spanner, DynamoDB) |
| **Replication setup** | Configure, test, monitor | Built-in and automatic |
| **Failover** | Build with Patroni, MHA, Orchestrator, manual | Automatic — 30s–2min typically |
| **Backups** | Script mysqldump / pg_basebackup + test restores | Continuous, PITR built-in |
| **Patching / upgrades** | Plan, test, execute maintenance windows | Managed maintenance windows |
| **Connection pooling** | Deploy PgBouncer / ProxySQL separately | Often built-in or one-click |
| **Monitoring** | Deploy Prometheus + Grafana + alerting | CloudWatch, Cloud Monitoring, built-in metrics |
| **Hardware failure** | Replace node, resync replica, promote | Transparent — you never see it |
| **Multi-AZ / DR** | Configure cross-AZ replication, test failover | Config toggle — handled by provider |

### Cost Reality

```
Self-managed on EC2/VMs:   ~1× (infrastructure only)
RDS / Cloud SQL:           ~2–3× (infra + management fee)
Aurora:                    ~3–5× vs. self-managed MySQL/Postgres
DynamoDB / Spanner:        Unpredictable — scales with workload
```

Rule of thumb: cloud-managed costs 2–4× more in raw compute dollars but saves significant engineering time. The break-even is roughly when your DBA/SRE time cost exceeds the premium.

### Lock-in Risk Spectrum

```
Lowest lock-in                                    Highest lock-in
|--------------------------------------------------|
PostgreSQL  MySQL  MongoDB  CockroachDB  Aurora  DynamoDB/Spanner/Cosmos
```

Aurora is moderate: it speaks MySQL/PostgreSQL wire protocol, so migrating out is `mysqldump` + target setup. DynamoDB, Spanner, Cosmos have no standard export format and no equivalent elsewhere.

---

## Decision Framework

```
Is your data relational with complex queries?
  Yes → PostgreSQL (self) or Aurora PostgreSQL (managed)

Do you need global ACID across regions?
  Yes → Cloud Spanner or CockroachDB

Is the workload read-heavy with simple access patterns?
  Yes → DynamoDB (On-Demand) or Aurora with read replicas

Do you need sub-millisecond response times?
  Yes → Redis (cache) + DynamoDB/Aurora as primary

Is the schema flexible / document-shaped?
  Yes → MongoDB (Atlas if managed) or PostgreSQL JSONB

Is it an analytics / OLAP workload?
  Yes → BigQuery, ClickHouse, Redshift — not OLTP databases

Are you on a Microsoft stack?
  Yes → Azure SQL / Cosmos DB fits naturally

Do you need high write throughput, multi-DC, time-series?
  Yes → Cassandra

Are you stuck on Oracle?
  Migrate path → Aurora PostgreSQL + AWS Schema Conversion Tool
  Stay path → RDS for Oracle to at least remove ops burden
```

---

## Tools Reference

| Tool | Purpose | Link |
|------|---------|-------|
| Percona Toolkit | MySQL/PostgreSQL operational tooling | [percona-toolkit](../resources/percona-toolkit/README.md) |
| pt-online-schema-change | Zero-downtime MySQL schema changes | [percona-toolkit](../resources/percona-toolkit/README.md) |
| gh-ost | GitHub's zero-downtime MySQL migrations | [github.com/github/gh-ost](https://github.com/github/gh-ost) |
| Patroni | PostgreSQL HA with auto-failover | [github.com/zalando/patroni](https://github.com/zalando/patroni) |
| PgBouncer | PostgreSQL connection pooler | [pgbouncer.org](https://www.pgbouncer.org/) |
| ProxySQL | MySQL proxy: read/write split, pooling | [proxysql.com](https://proxysql.com/) |
| Vitess | MySQL horizontal sharding (powers PlanetScale) | [vitess.io](https://vitess.io/) |
| Valkey | Open-source Redis fork (post license change) | [valkey.io](https://valkey.io/) |
| db-engines.com | Database popularity ranking and comparison | [db-engines.com/en/ranking](https://db-engines.com/en/ranking) |
| AWS Schema Conversion Tool | Migrate Oracle/SQL Server schemas to open-source | [AWS SCT](https://aws.amazon.com/dms/schema-conversion-tool/) |

---

## Related Topics

- [DBRE Fundamentals](fundamentals.md)
- [SQL Best Practices](sql.md)
- [Best Practices — Do's and Don'ts](best-practices.md)
- [Anti-Patterns](antipatterns.md)
- [Performance Tuning](performance.md)
- [Scaling Databases](scaling.md)
- [Backup & Recovery](backup-recovery.md)
- [External Links](external-links.md) — PostgreSQL docs, Don't Do This wiki
- [awesome-postgres](../resources/awesome-postgres/README.md)
- [awesome-mongodb](../resources/awesome-mongodb/README.md)
- [awesome-redis](../resources/awesome-redis/README.md)
- [awesome-nosql-guides](../resources/awesome-nosql-guides/README.md)
- [awesome-mysql](../resources/awesome-mysql/README.md)
- [awesome-scalability](../resources/awesome-scalability/README.md)
