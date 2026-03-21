# Scaling Databases

[← DBRE Home](README.md) | [← Main](../README.md)

---

## When to Scale `[B]`

Signs your database needs scaling attention:

- CPU consistently > 70%
- Connection pool exhausted (connection wait times increasing)
- Query latency p99 degrading over time
- Replication lag growing
- Disk I/O saturation
- Lock contention increasing

**Before scaling hardware, exhaust software options:**
1. Optimize slow queries ([Performance Tuning](performance.md))
2. Add appropriate indexes
3. Tune connection pooling ([Fundamentals: Connection Pooling](fundamentals.md#connection-pooling))
4. Cache frequently-read data
5. *Then* scale

---

## Read Replicas `[I]`

Offload read traffic from the primary.

```
                    ┌─ Read Replica 1 ─── Analytics queries
Primary ─── WAL ──►─┤
(writes)            └─ Read Replica 2 ─── Application reads
```

**When to use:**
- Read-heavy workloads (reporting, analytics)
- Application can tolerate some replication lag
- Separate analytics from OLTP queries

**When NOT to use:**
- Reads that must see writes immediately (use primary for these)
- If replication lag is regularly > your SLO tolerance

### Routing Read/Write Traffic

```python
# SQLAlchemy with read/write splitting
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

write_engine = create_engine("postgresql://primary.db/mydb")
read_engine = create_engine("postgresql://replica.db/mydb")

WriteSession = sessionmaker(bind=write_engine)
ReadSession = sessionmaker(bind=read_engine)

# Or use a proxy: ProxySQL (MySQL), PgBouncer pools, Pgpool-II
```

### Aurora Read Replicas

Aurora supports up to 15 read replicas with shared storage (< 10ms lag typical):

```hcl
resource "aws_rds_cluster_instance" "read_replica" {
  count              = 2
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.r6g.xlarge"
  engine             = "aurora-postgresql"
}
```

---

## Connection Pooling at Scale `[I]`

Connection limits:

```
PostgreSQL: max_connections = 200 (default)
Each connection: ~5-10MB RAM
100 connections = 500MB-1GB RAM
```

With many app instances, connection pooling is essential:

```
50 app pods × 10 connections each = 500 connections → exceeds max_connections

Solution:
50 app pods → PgBouncer (10 connections to PgBouncer each = 500 app connections)
PgBouncer → 20 connections → PostgreSQL
```

→ See [Fundamentals: Connection Pooling](fundamentals.md#connection-pooling)

---

## Vertical Scaling (Scale Up) `[I]`

Increasing instance size:

```
db.t3.medium (2 vCPU, 4GB) → db.r6g.2xlarge (8 vCPU, 64GB)
```

**With RDS:**
```bash
aws rds modify-db-instance \
  --db-instance-identifier prod-db \
  --db-instance-class db.r6g.2xlarge \
  --apply-immediately  # or during next maintenance window
```

**Downtime:** Standard RDS requires a brief failover (~60 seconds for Multi-AZ). Aurora is usually online.

**Right-sizing:**
- CPU: target 60-70% average, headroom for spikes
- RAM: buffer pool should fit working dataset
- IOPS: check CloudWatch `ReadIOPS` and `WriteIOPS`

---

## Caching Layer `[I]`

Redis/Memcached in front of the database for frequently-read, rarely-changing data.

### Cache-Aside Pattern

```python
def get_user(user_id: int) -> dict:
    cache_key = f"user:{user_id}"

    # Try cache first
    cached = redis.get(cache_key)
    if cached:
        return json.loads(cached)

    # Miss: read from DB
    user = db.query("SELECT * FROM users WHERE id = %s", user_id)

    # Store in cache with TTL
    redis.setex(cache_key, 3600, json.dumps(user))  # 1 hour TTL

    return user

def update_user(user_id: int, data: dict):
    db.execute("UPDATE users SET ... WHERE id = %s", user_id)
    redis.delete(f"user:{user_id}")  # Invalidate cache
```

### Write-Through Cache

```python
def update_user(user_id: int, data: dict):
    db.execute("UPDATE users SET ... WHERE id = %s", user_id)
    redis.setex(f"user:{user_id}", 3600, json.dumps(data))  # Update cache
```

### What to Cache

| Good candidates | Bad candidates |
|----------------|----------------|
| User profiles | Financial balances |
| Product catalog | Inventory counts |
| Configuration | Orders in progress |
| Reference data | Anything requiring strong consistency |

---

## Sharding `[A]`

Horizontal partitioning: split data across multiple databases.

```
Shard 1: user_id 1-1,000,000       → db-shard-01
Shard 2: user_id 1,000,001-2,000,000 → db-shard-02
Shard 3: user_id 2,000,001+        → db-shard-03
```

**Sharding strategies:**
- **Range-based** — by ID or date range (simple, but hot shards possible)
- **Hash-based** — `shard = hash(user_id) % num_shards` (even distribution, harder to rebalance)
- **Directory-based** — lookup table maps key → shard (flexible, extra hop)

**Sharding complexity:**
- Cross-shard queries are expensive or impossible
- No cross-shard transactions
- Rebalancing when adding shards is hard
- Requires application-level shard routing

**Use sharding only when other options are exhausted.** Most companies never need it.

### PostgreSQL Partitioning (Alternative to Sharding)

Partition a single large table for performance (all data in one DB):

```sql
-- Range partitioning by date
CREATE TABLE orders (
    id BIGSERIAL,
    created_at TIMESTAMP NOT NULL,
    customer_id INTEGER,
    total DECIMAL(10,2)
) PARTITION BY RANGE (created_at);

CREATE TABLE orders_2024_01 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE orders_2024_02 PARTITION OF orders
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Queries with partition pruning only scan relevant partitions
SELECT * FROM orders
WHERE created_at BETWEEN '2024-01-15' AND '2024-01-31';
-- → only scans orders_2024_01
```

---

## Distributed Databases `[A]`

When PostgreSQL/MySQL can't scale further:

| Database | Type | Strength |
|----------|------|---------|
| CockroachDB | Distributed SQL | PostgreSQL-compatible, true ACID |
| YugabyteDB | Distributed SQL | PostgreSQL-compatible, multi-region |
| Cassandra | Wide-column NoSQL | Extreme write scale, eventual consistency |
| DynamoDB | Key-value/document | Serverless scale, AWS-native |
| Vitess | MySQL proxy | YouTube/Slack approach to sharding MySQL |

**Migration to distributed DB is a major multi-year effort. Exhaust vertical and read-scaling options first.**

---

## Scaling Decision Framework `[I]`

```
Problem: DB is slow/overloaded
    │
    ├── Is it a specific query? → Performance tuning, indexes
    │
    ├── Is it read-heavy? → Read replicas + caching
    │
    ├── Is it connection pressure? → Better connection pooling
    │
    ├── Is it write-heavy? → Vertical scale, batch writes, async processing
    │
    ├── Is the dataset just huge? → Partitioning, archiving old data
    │
    └── All of the above exhausted? → Sharding or distributed DB
```

---

## Real-World Database Scaling `[A]`

From [awesome-scalability](../resources/awesome-scalability/README.md) and [howtheysre](../resources/howtheysre/README.md):

| Company | Scale | Approach |
|---------|-------|---------|
| Instagram | 1B+ users | PostgreSQL sharded by user_id, no NoSQL, Django ORM |
| GitHub | Billions of git objects | MySQL with Vitess-style sharding, extensive caching |
| Shopify | Black Friday peaks | MySQL + PlanetScale (Vitess), aggressive connection pooling |
| Notion | Explosive growth | PostgreSQL, vertical scaling + read replicas first |
| Discord | Message history | Cassandra for messages (append-only workload, no updates) |
| Stripe | Financial transactions | PostgreSQL, strong ACID, sharding by merchant |

**What Instagram teaches us:**
- Stayed on PostgreSQL to 1B users
- Sharding was the hard part, not the choice of database
- Having to add NoSQL would have added complexity without clarity

**What Discord teaches us:**
- Choose data model based on access patterns, not hype
- Cassandra is excellent for append-only, time-series, high-write workloads
- Don't use Cassandra for relational data with complex queries

---

## Related Topics

- [Performance Tuning](performance.md) — optimize before scaling
- [Fundamentals: Connection Pooling](fundamentals.md#connection-pooling)
- [Backup & Recovery](backup-recovery.md) — replicas and HA
- [SRE: Scalability](../sre/scalability.md) — system-level scaling patterns
- [Platform: Cloud Infrastructure](../platform/cloud-infra.md) — RDS, Aurora, ElastiCache
- [awesome-scalability](../resources/awesome-scalability/README.md) — real-world scaling stories
- [data-engineer-handbook](../resources/data-engineer-handbook/README.md) — data engineering at scale
