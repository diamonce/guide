# Scalability

[← SRE Home](README.md) | [← Main](../README.md)

---

## Scalability Fundamentals `[B]`

Scalability = the ability of a system to handle growing load.

**Two dimensions:**
- **Vertical scaling (scale up)** — bigger machine (more CPU/RAM)
- **Horizontal scaling (scale out)** — more machines

| | Vertical | Horizontal |
|--|----------|-----------|
| Limit | Hardware ceiling | Theoretically unlimited |
| Complexity | Simple | Requires statelessness, load balancing |
| Cost | Expensive at scale | More predictable |
| Downtime | Often requires restart | Rolling updates possible |

---

## Capacity Planning `[I]`

Capacity planning = knowing how much headroom you have before hitting limits.

**Process:**
1. Define resource metrics (CPU, memory, connections, QPS)
2. Measure current utilization and growth rate
3. Project when you'll hit limits
4. Plan scaling actions before you get there

```
Current QPS: 10,000
Growth: +15% / month
System limit: 25,000 QPS
Time to limit: ~6 months
Action: start horizontal scaling project in 3 months
```

**SLO-based capacity planning:**
- Run load tests to find breaking points
- Set capacity targets at 70% utilization (30% headroom)

→ See [DBRE: Scaling Databases](../dbre/scaling.md) for database-specific capacity planning.

---

## Load Testing `[I]`

Test your system before traffic tests it for you.

**Types:**
- **Load test** — expected peak traffic
- **Stress test** — beyond expected peak (find breaking point)
- **Soak test** — sustained load over time (find memory leaks)
- **Spike test** — sudden traffic surge

**Tools:** k6, Locust, Apache JMeter, Gatling, `wrk`, `hey`

```bash
# k6 example
k6 run --vus 100 --duration 30s load-test.js

# hey example
hey -n 10000 -c 200 https://api.example.com/endpoint
```

**What to watch during load tests:**
- Error rate (should stay < SLO threshold)
- p99 latency
- CPU and memory trend
- Connection pool exhaustion
- Garbage collection pauses

---

## Scalability Patterns `[I]`

### Caching

Reduce load on downstream services by caching responses.

| Strategy | When | Tools |
|----------|------|-------|
| CDN | Static assets, public API responses | CloudFront, Fastly |
| Application cache | Repeated computation | Redis, Memcached |
| DB query cache | Expensive reads | Redis, query result cache |

**Cache invalidation is hard.** Consider TTL, write-through, or cache-aside patterns.

### Rate Limiting

Protect services from overload:
- Per-user or per-IP rate limits
- Token bucket / leaky bucket algorithms
- 429 Too Many Requests responses

### Circuit Breakers

Prevent cascade failures:
- If downstream is failing, stop calling it
- Return cached/default response instead
- Allow periodic probes to check recovery

```
Closed → Open → Half-Open → Closed
(normal) (failing) (testing)  (recovered)
```

Tools: Hystrix, Resilience4j, Envoy, Istio

### Bulkhead Pattern

Isolate failures to parts of the system:
- Separate thread pools per downstream
- Separate connection pools per tenant
- Prevents one bad service from exhausting all resources

---

## Database Scalability `[I]`

Quick reference — see [DBRE: Scaling](../dbre/scaling.md) for depth.

- **Read replicas** — scale reads horizontally
- **Connection pooling** — PgBouncer, ProxySQL
- **Sharding** — partition data across multiple DBs
- **Caching layer** — Redis in front of DB
- **CQRS** — separate read/write models

---

## Distributed Systems Concepts `[A]`

### CAP Theorem

A distributed system can only guarantee 2 of 3:
- **C**onsistency — all nodes see the same data
- **A**vailability — every request gets a response
- **P**artition tolerance — system works despite network splits

In practice: partitions happen, so choose between C and A.

### PACELC Extension

Even without partitions, tradeoff between latency (L) and consistency (C).

### Consistency Models

| Model | Guarantee | Example |
|-------|-----------|---------|
| Strong | All reads see latest write | Single leader DB |
| Eventual | All nodes converge eventually | DNS, Cassandra |
| Causal | Causally related ops ordered | DynamoDB |

---

## System Design Checklist `[A]`

When designing for scale, ask:

- [ ] What's the expected QPS? Peak? p99 latency requirement?
- [ ] Which components are stateful? How is state managed?
- [ ] What happens if service X goes down? (Graceful degradation)
- [ ] Where are the synchronous call chains? (Latency cliff)
- [ ] Where is the data? Can it be cached?
- [ ] What are the DB bottlenecks? (Connections, locks, hot rows)
- [ ] Are there single points of failure?
- [ ] How does the system behave at 10x current load?

---

## Related Topics

- [SLOs / SLIs / SLAs](slo-sla-sli.md)
- [Observability](observability.md)
- [DBRE: Scaling Databases](../dbre/scaling.md)
- [Platform: Kubernetes](../platform/kubernetes.md)
- [awesome-scalability](../resources/awesome-scalability/README.md) — deep resource library
- [howtheysre](../resources/howtheysre/README.md) — how companies scaled
