# Architecture Best Practices — Blast Radius, Least Privilege, Scalability

[← Architecture Home](README.md) | [← Main](../README.md)

---

## Blast Radius Minimization

Blast radius = the maximum impact of a single failure. Good architecture makes blast radius small, predictable, and bounded before any failure occurs.

### Account / Project Isolation

The strongest blast radius boundary in cloud is the account boundary. A security incident, runaway cost, IAM misconfiguration, or quota exhaustion in one account cannot cross account boundaries.

```
❌ Everything in one account
   → A misconfigured IAM policy → access to all systems
   → A runaway Lambda → bill shock for the entire company
   → A compromised key → full blast radius

✅ One account per production workload
   prod-payments  /  prod-orders  /  prod-notifications
   → Compromise of prod-payments ≠ access to prod-orders
   → Quota exhaustion in one account doesn't starve another
```

### Cell-Based Architecture

Divide workload into identical, independent cells. Each cell serves a subset of users. A cell failure impacts only that cell's users.

```
                 ┌──── Load Balancer ────┐
                 │    (routes by hash)   │
                 └──────────┬───────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
    ┌─────┴──────┐   ┌──────┴─────┐   ┌──────┴─────┐
    │   Cell A   │   │   Cell B   │   │   Cell C   │
    │ users 0-33%│   │users 33-66%│   │users 66-99%│
    │            │   │            │   │            │
    │ App + DB   │   │ App + DB   │   │ App + DB   │
    │ Cache      │   │ Cache      │   │ Cache      │
    └────────────┘   └────────────┘   └────────────┘
```

Used by Amazon, Netflix, Stripe. A bad deployment to Cell A — caught by canary metrics — doesn't roll to B or C.

**Routing strategy:**
```python
def get_cell(user_id: str, total_cells: int = 3) -> int:
    return int(hashlib.md5(user_id.encode()).hexdigest(), 16) % total_cells

# Same user always → same cell (sticky routing)
# Cell failure → only that user's shard is affected
```

### Bulkheads

Isolate resource pools per consumer type. A slow consumer exhausting the thread pool / connection pool doesn't starve other consumers.

```
❌ Shared connection pool
   → Reporting query holds 100 connections → API requests starve → outage

✅ Separate pools per workload class
   API requests:      pool size 50, timeout 100ms
   Background jobs:   pool size 20, timeout 30s
   Reporting queries: pool size 5,  timeout 300s
```

```python
# Separate thread pools per workload
api_executor = ThreadPoolExecutor(max_workers=50)
batch_executor = ThreadPoolExecutor(max_workers=10)
report_executor = ThreadPoolExecutor(max_workers=3)

# If report_executor is saturated → only reports degrade, API is unaffected
```

### Progressive Delivery (Canary / Ring Deployments)

Release to a small percentage of users first. Limit the blast radius of a bad deployment.

```
Ring 0: internal users only (1% of traffic)
  → validate for 30 minutes
Ring 1: 5% of users
  → validate for 1 hour
Ring 2: 20% of users
  → validate for 2 hours
Ring 3: 100% of users
```

```yaml
# ArgoCD Rollout — canary with automatic analysis
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5      # 5% of traffic to new version
        - pause: {duration: 10m}
        - analysis:         # auto-rollback if error rate > 1%
            templates:
              - templateName: error-rate
        - setWeight: 20
        - pause: {duration: 20m}
        - setWeight: 100
```

### Feature Flags

Decouple deployment from release. Ship code to 100% of servers, enable for 0% of users. Roll out gradually, roll back without a deployment.

```python
# LaunchDarkly / Unleash / Flagsmith
if feature_flags.is_enabled("new-checkout-flow", user_id=user.id):
    return new_checkout_flow(cart)
else:
    return legacy_checkout_flow(cart)
```

**Blast radius of a bad feature:**
- With flags: disable flag → instant rollback for 0% cost
- Without flags: rollback deployment → minutes of downtime risk

### Circuit Breakers

Stop calling a failing dependency. Give it time to recover instead of hammering it with failing requests.

```python
from circuitbreaker import circuit

@circuit(failure_threshold=5, recovery_timeout=30, expected_exception=TimeoutError)
def call_payment_service(payload):
    return payment_client.charge(payload)

# After 5 timeouts in a row:
# → Circuit OPEN: calls fail fast (no timeout wait) for 30 seconds
# → Circuit HALF-OPEN: one test call
# → Circuit CLOSED: back to normal if test succeeds
```

States:
```
CLOSED (healthy) → failure_threshold exceeded → OPEN (fast fail)
                                                    ↓ recovery_timeout
                                               HALF-OPEN (test call)
                                                ↓              ↓
                                            success         failure
                                            CLOSED          OPEN
```

---

## Least Privilege

Every identity — human or machine — gets exactly the permissions it needs for exactly as long as it needs them.

### IAM Principles

```
❌ "just give it admin for now, we'll fix it later"
   → You won't. And the blast radius is maximum.

✅ Start with nothing. Add only what's needed. Verify with Access Analyzer.
```

**Role per service, not shared roles:**
```hcl
# ✅ Each service gets its own role with minimal permissions
resource "aws_iam_role" "payments_service" {
  name = "payments-service-role"
  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.eks.url}:sub" = "system:serviceaccount:payments:payments-api"
        }
      }
    }]
  })
}

# Only what payments needs
resource "aws_iam_role_policy" "payments_service" {
  role = aws_iam_role.payments_service.id
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = "arn:aws:dynamodb:*:*:table/payments-*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:payments/*"
      }
    ]
  })
}
```

**No long-lived keys — use roles everywhere:**
```
AWS:   IAM Roles for EC2 / IRSA for EKS / Cognito for Lambda
GCP:   Workload Identity Federation — no service account keys
Azure: Managed Identity — no client secrets in code
```

**Resource-level permissions, not `*`:**
```json
// ❌ Way too broad
{ "Action": "s3:*", "Resource": "*" }

// ✅ Scoped to exactly what's needed
{ "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::company-payments-uploads/*" }
```

**Permission Boundaries:**
```hcl
# Prevent delegated admins from escalating beyond their boundary
resource "aws_iam_policy" "developer_boundary" {
  name = "developer-permission-boundary"
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:*", "s3:*", "lambda:*", "dynamodb:*"]
        Resource = "*"
      },
      {
        # Even if developer creates a role, it can't have IAM admin
        Effect   = "Deny"
        Action   = ["iam:CreateUser", "iam:AttachRolePolicy", "organizations:*"]
        Resource = "*"
      }
    ]
  })
}
```

### Just-in-Time Access

Humans should not have persistent elevated access. Elevate when needed, revoke automatically.

```
AWS: IAM Identity Center → temporary role assumption with time-limited sessions
GCP: Privileged Access Manager → just-in-time grants with approval workflow
Azure: Privileged Identity Management (PIM) → activate role for N hours, then expires
HashiCorp Vault: dynamic secrets → short-lived credentials generated on-demand
```

```bash
# Vault dynamic AWS credentials — expires in 1 hour, never stored
vault read aws/creds/prod-readonly

# Key         Value
# lease_duration  1h
# access_key  ASIAXXX...
# secret_key  xxx...
# (automatically revoked after 1h)
```

### Audit Everything

Least privilege only works if you know what's being used and can detect misuse.

```
✅ CloudTrail / GCP Audit Logs / Azure Monitor — every API call logged
✅ AWS IAM Access Analyzer — flags policies that allow public or cross-account access
✅ AWS Access Advisor — shows which permissions were actually used in last 90 days
✅ GCP Policy Analyzer — test what a principal can do before granting
✅ Alert on: root login, new IAM user created, policy attached to user (not role), SCP changed
```

```bash
# Find unused permissions in the last 90 days (use to prune roles)
aws iam get-service-last-accessed-details \
  --job-id $(aws iam generate-service-last-accessed-details \
    --arn arn:aws:iam::123456789012:role/payments-service \
    --query 'JobId' --output text)
```

---

## Scalability Patterns

### Stateless Services

State is the enemy of horizontal scale. A stateless service can run N copies with zero coordination.

```
❌ Stateful: session data stored in process memory
   → User hits server A → session exists
   → Load balancer sends next request to server B → session not found → 401

✅ Stateless: session data in Redis
   → Server A writes session to Redis
   → Server B reads session from Redis
   → Any server can handle any request
```

**Rule:** If you can kill and replace any instance without a user noticing, your service is stateless.

### Horizontal vs. Vertical Scaling

```
Vertical (scale up):   t3.medium → t3.xlarge → t3.4xlarge
  ✅ Simple, no code changes
  ❌ Single point of failure, has a ceiling, expensive

Horizontal (scale out): 2 instances → 10 instances → 100 instances
  ✅ No ceiling, fault-tolerant, cost-linear with load
  ❌ Requires stateless design, needs load balancer
```

Always design for horizontal. Vertical is a short-term fix.

### Auto-Scaling

```hcl
# AWS Auto Scaling Group
resource "aws_autoscaling_group" "api" {
  min_size         = 2      # always at least 2 for HA
  max_size         = 20
  desired_capacity = 4

  # Scale on CPU — simple and reliable
  target_tracking_configuration {
    predefined_metric_type = "ASGAverageCPUUtilization"
    target_value           = 60.0   # scale when CPU hits 60%
  }

  # Or scale on custom metric (SQS queue depth, request rate, etc.)
  target_tracking_configuration {
    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"
    }
    target_value = 100  # scale to keep queue depth ~100
  }
}
```

### CQRS — Command Query Responsibility Segregation

Separate read and write paths. Reads scale independently from writes.

```
Write path:  POST /orders  → Primary DB (strong consistency, ACID)
Read path:   GET  /orders  → Read replica / ElastiCache (eventual consistency OK)

                    ┌──── Write ────┐     ┌──── Read ────┐
App Server A ──────►│  Primary DB   │────►│  Replica 1   │◄─── App Server B
                    │  (1 instance) │     │  (N instances)│
                    └───────────────┘     │  Replica 2   │
                                          │  ElastiCache  │
                                          └──────────────┘
```

### Queue-Based Load Leveling

Don't let spikes hit your database or downstream services directly. Queue absorbs the spike; workers drain at a controlled rate.

```
❌ Direct call under load spike
   10,000 req/s → DB → DB overwhelmed → timeouts cascade

✅ Queue absorbs spike
   10,000 req/s → SQS Queue → 100 workers → DB at 100 req/s
   Queue depth grows during spike, drains when load normalizes
```

```python
# Producer: fast, just enqueues
sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(order))

# Consumer: controlled pace with backpressure
while True:
    messages = sqs.receive_message(MaxNumberOfMessages=10, WaitTimeSeconds=20)
    for msg in messages.get('Messages', []):
        process_order(msg)               # controlled DB write rate
        sqs.delete_message(...)
```

### Caching Strategy

```
Layer 1 — Browser / CDN (edge)
  ✅ Static assets: JS, CSS, images — long TTL (1 year with content hash)
  ✅ Public API responses: Cache-Control: max-age=60

Layer 2 — Application cache (Redis / Memcached)
  ✅ Hot database rows: user profiles, product catalog
  ✅ Expensive computed results: recommendation scores, aggregates
  ✅ Sessions

Layer 3 — Database query cache
  ✅ PostgreSQL: pg_stat_statements to identify hot queries
  ✅ Index coverage eliminates disk seeks

Cache invalidation strategies:
  TTL-based: simple, may serve stale data
  Write-through: update cache on every write (consistent, more writes)
  Cache-aside: app reads from cache; on miss, loads from DB and populates cache
  Event-driven: Kafka/SNS event → Lambda invalidates cache entry on change
```

### Database Read Scaling

```
Single DB → Primary + Read Replica → Primary + N Replicas → Connection Pool
                                                                    ↓
                                                           PgBouncer / ProxySQL
                                                           routes to replica

Scale order:
1. Add read replicas (handles 80% of read-heavy apps)
2. Add connection pool (handles connection exhaustion)
3. Add cache layer (handles hot-spot reads)
4. Partition large tables (handles storage / write throughput)
5. Only then: consider sharding
```

---

## Design Principles Summary

| Principle | Implementation |
|-----------|---------------|
| **Blast radius** | Account isolation, cell architecture, bulkheads, circuit breakers, canary deployments |
| **Least privilege** | Role per service, no wildcards, IRSA/Workload Identity, permission boundaries, JIT access, access advisor |
| **Stateless** | Sessions in Redis, config from env/secrets manager, no local disk state |
| **Horizontal scale** | Auto-scaling groups, stateless services, read replicas, queue-based leveling |
| **Immutable infrastructure** | Replace, don't modify — new AMI/image per deploy, no SSH into prod |
| **Fail fast** | Circuit breakers, timeouts on every external call, health checks |
| **Observability first** | Metrics, logs, traces in place before launch — not after the first incident |
| **Automate everything** | If you do it twice, automate it. If it's manual, it will be wrong eventually. |

---

## Pre-Launch Architecture Checklist

**Blast Radius**
- [ ] Production workloads in dedicated accounts/projects
- [ ] Canary / ring deployment strategy defined
- [ ] Circuit breakers on all external service calls
- [ ] Feature flags in place for risky new features
- [ ] Cell or shard boundary identified if needed

**Least Privilege**
- [ ] No wildcard `*` resource ARNs in production IAM policies
- [ ] No long-lived access keys for any human or service
- [ ] Service-specific roles — not shared admin roles
- [ ] IAM Access Analyzer run — zero public or cross-account findings
- [ ] Root account secured, access keys deleted

**Scalability**
- [ ] Services are stateless — verified by killing an instance during load test
- [ ] Auto-scaling configured with tested scale-out and scale-in behavior
- [ ] Cache layer in front of high-read database queries
- [ ] Connection pooling in place (PgBouncer / RDS Proxy / ProxySQL)
- [ ] Load test run at 3× expected peak — system survived

**Operational**
- [ ] Runbook exists for every alert
- [ ] Rollback procedure documented and tested
- [ ] Incident response process documented
- [ ] On-call rotation staffed

---

## Related Topics

- [Well-Architected](well-architected.md) — pillar framework
- [Landing Zones](landing-zones.md) — account isolation in practice
- [SRE Scalability](../sre/scalability.md) — CAP theorem, load patterns
- [Platform Security](../platform/security.md) — IAM, secrets, hardening
- [DBRE Scaling](../dbre/scaling.md) — database-specific scale patterns
- [Messaging Best Practices](../messaging/best-practices.md) — queue-based load leveling
- [system-design-primer](../resources/system-design-primer/README.md) — comprehensive system design reference
- [awesome-system-design](../resources/awesome-system-design/README.md) — curated system design resources
