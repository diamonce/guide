# Messaging & Queues

[← Home](../README.md)

Message brokers, event streaming, and queue systems are the connective tissue of distributed systems. This section covers every major system, when to use each, and how to operate them reliably.

---

## Topics

| Topic | What you'll learn |
|-------|------------------|
| [Kafka](kafka.md) | Deep dive — partitions, consumer groups, exactly-once, operations |
| [Best Practices](best-practices.md) | Do's and don'ts across Kafka, RabbitMQ, SQS, and general messaging |
| [External Links](external-links.md) | Official docs, design guides, benchmark references |

---

## System Comparison

| System | Model | Ordering | Retention | Throughput | Best For |
|--------|-------|----------|-----------|------------|----------|
| **Apache Kafka** | Log / pub-sub | Per partition | Configurable (days/forever) | Millions/s | Event streaming, audit log, CDC |
| **RabbitMQ** | Message queue | Per queue | Until consumed | Tens of thousands/s | Task queues, routing, RPC |
| **Amazon SQS** | Queue | Best-effort (FIFO: per group) | Up to 14 days | Unlimited (managed) | Decoupling AWS services, serverless |
| **Amazon SNS** | Pub/sub fanout | None | None (fire-and-forget) | Unlimited (managed) | Fan-out to SQS/Lambda/HTTP |
| **Apache Pulsar** | Log + queue | Per partition | Configurable | Millions/s | Multi-tenant, geo-replication, Kafka alternative |
| **NATS** | Pub/sub / queue | Per stream (JetStream) | JetStream only | Very high | Low-latency microservices, IoT |
| **Google Pub/Sub** | Pub/sub | Best-effort (ordering key for strict) | 7 days | Unlimited (managed) | GCP event pipelines |
| **Azure Service Bus** | Queue + topic | Per session | Up to 14 days | Managed | Azure ecosystem, enterprise messaging |
| **Redis Streams** | Log | Per stream | Configurable | High | Lightweight streaming, in-process events |

---

## Messaging Patterns

### Point-to-Point (Queue)
One producer, one consumer processes each message. Work distribution. Used by SQS, RabbitMQ queues.
```
Producer → [Queue] → Consumer A (processes message, removed from queue)
                   → Consumer B (waiting — gets next message)
```

### Publish / Subscribe (Topic)
One producer, many consumers each get a copy. Used by Kafka topics, SNS, Pub/Sub.
```
Producer → [Topic] → Consumer Group A (analytics)
                   → Consumer Group B (notifications)
                   → Consumer Group C (audit log)
```

### Fan-out (SNS → SQS)
SNS delivers to multiple SQS queues simultaneously. Standard AWS decoupling pattern.
```
SNS Topic → SQS Queue A (email service)
          → SQS Queue B (audit service)
          → SQS Queue C (analytics)
          → Lambda (real-time processor)
```

### Dead Letter Queue (DLQ)
Failed messages go to a DLQ after N retries. Prevents poison messages from blocking queues.
```
Producer → Queue → Consumer (fails 3×) → DLQ → Alert / Manual review
```

### Outbox Pattern
Prevents the dual-write problem: write to DB and message broker atomically.
```
1. Write to orders table + outbox table in one transaction
2. Outbox worker reads new rows, publishes to Kafka/SQS
3. Delete from outbox after publish confirmed
```
Eliminates race conditions between DB commit and broker publish.

### Claim Check (Large Payload)
Kafka/SQS have message size limits (Kafka: 1MB default, SQS: 256KB). Store payload in S3, send only a pointer.
```
Producer → S3 (full payload) → Kafka message: { "s3_key": "events/2024/order-123.json" }
Consumer → reads Kafka message → fetches from S3
```

### Saga Pattern (Distributed Transactions)
Sequence of local transactions, each publishing an event that triggers the next step. On failure: compensating transactions.
```
Order Service → OrderCreated event
  → Payment Service → PaymentProcessed event
    → Inventory Service → InventoryReserved event
      → Shipping Service → ShipmentCreated event

On failure at any step → compensating events (PaymentRefunded, InventoryReleased)
```

---

## When to Use What

| Scenario | Recommended | Why |
|----------|-------------|-----|
| High-throughput event streaming (millions/s) | **Kafka** | Durable log, replay, consumer groups scale independently |
| Audit log / event sourcing | **Kafka** (compacted topic) | Immutable, replayable, retains history |
| Change Data Capture (CDC) from DB | **Kafka** + Debezium | Reads DB binlog, streams changes as events |
| Task queue — background jobs | **RabbitMQ** or **SQS** | Work distribution, one consumer per message |
| Complex routing (topic/header/fanout) | **RabbitMQ** | Exchange types give fine-grained routing control |
| Serverless / AWS-native workloads | **SQS + SNS** | Zero ops, triggers Lambda, pay-per-use |
| Fan-out to multiple AWS services | **SNS → SQS** | One publish, N independent queues with own retry/DLQ |
| Ordered processing per entity | **Kafka** (keyed) or **SQS FIFO** | Kafka: per partition; SQS FIFO: per MessageGroupId |
| Low-latency microservice messaging (< 1ms) | **NATS** | In-memory, no persistence overhead by default |
| Multi-region active-active | **Kafka** (MirrorMaker 2) or **Pulsar** | Pulsar has native geo-replication; Kafka needs MirrorMaker |
| GCP-native event pipeline | **Google Pub/Sub** | Serverless, integrates with Dataflow, BigQuery |
| Azure-native messaging | **Azure Service Bus** | Sessions, DLQ, transactions in the Azure ecosystem |
| Real-time stream processing + SQL | **Kafka + ksqlDB** or **Flink** | Continuous queries over live event streams |
| Lightweight in-app event bus | **Redis Streams** | Already have Redis? Streams add durable pub/sub |
| Request-reply (synchronous) | **gRPC / HTTP** | Don't use a broker for sync — wrong tool |
| Small team, no ops capacity | **SQS / SNS** or **managed Kafka (Confluent/MSK)** | Remove operational complexity entirely |

---

## Fan-out Patterns

Fan-out = one event published once, delivered to multiple independent consumers. Critical for decoupling services.

### SNS → SQS (AWS canonical pattern)

Each downstream service owns its SQS queue. Failures in one service don't affect others.

```
                    ┌─ SQS: email-service     (retries 3×, DLQ: email-dlq)
                    │
SNS: order.created ─┼─ SQS: inventory-service (retries 5×, DLQ: inventory-dlq)
                    │
                    ├─ SQS: analytics-service (retries 1×, no DLQ — best-effort)
                    │
                    └─ Lambda: fraud-check    (immediate, synchronous fan-out leg)
```

**Why SQS in front of Lambda (not SNS → Lambda directly)?**
- SQS buffers: Lambda throttling doesn't lose messages
- SQS retries independently per queue
- SQS DLQ catches Lambda failures; SNS → Lambda has no DLQ

```python
# Subscribe SQS queues to SNS topic (Terraform)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.order_created.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.email_service.arn
}

# SNS filter policy — email service only gets paid orders
resource "aws_sns_topic_subscription" "email_filtered" {
  filter_policy = jsonencode({
    status = ["paid", "refunded"]
  })
}
```

### Kafka Consumer Groups (fan-out with replay)

Each consumer group reads the full topic independently. Unlike SNS/SQS, messages persist — new consumer groups can replay from the beginning.

```
Kafka Topic: orders
  │
  ├─ Consumer Group: payments-service     (at offset 10,240)
  ├─ Consumer Group: analytics-service    (at offset 10,195 — 45 behind)
  ├─ Consumer Group: notification-service (at offset 10,240)
  └─ Consumer Group: audit-service        (at offset 0 — replaying history)
```

One team adding a new consumer group never touches other groups. No SNS subscription management needed.

### RabbitMQ Fanout Exchange

Delivers to all bound queues unconditionally — no routing key used.

```
                    ┌─ Queue: email-worker
                    │
Fanout Exchange ────┼─ Queue: sms-worker
                    │
                    └─ Queue: push-notification-worker
```

```python
# Declare fanout exchange
channel.exchange_declare('order.notifications', 'fanout', durable=True)

# Each service binds its own queue — routing key ignored
channel.queue_bind('email-worker',  'order.notifications', routing_key='')
channel.queue_bind('sms-worker',    'order.notifications', routing_key='')
channel.queue_bind('push-worker',   'order.notifications', routing_key='')

# Publish once → all three queues receive a copy
channel.basic_publish(exchange='order.notifications', routing_key='', body=msg)
```

### RabbitMQ Topic Exchange (selective fan-out)

Routing key pattern matching. More control than fanout — queues receive only matching events.

```
Topic Exchange: events
  │
  ├─ Queue: payments  (binding: orders.#)        ← gets orders.created, orders.paid, orders.refunded
  ├─ Queue: shipping  (binding: orders.paid)     ← gets only orders.paid
  └─ Queue: all-events (binding: #)              ← gets everything
```

```python
channel.exchange_declare('events', 'topic', durable=True)
channel.queue_bind('payments', 'events', routing_key='orders.#')
channel.queue_bind('shipping', 'events', routing_key='orders.paid')

# Only shipping and payments receive this:
channel.basic_publish(exchange='events', routing_key='orders.paid', body=msg)
```

### Fan-out Anti-patterns

```
❌ Shared queue for multiple consumer types
   → one consumer starves the others; tight coupling

❌ SNS → Lambda directly for high-volume fan-out
   → no buffering, Lambda throttling = dropped messages

❌ Broadcasting large payloads to all consumers
   → use claim check: put payload in S3, fan-out the S3 key

❌ Fan-out with a synchronous call chain
   → if one downstream is slow, the whole fan-out blocks
   → async fan-out only; fire and forget per leg
```

---

## Cloud-Managed vs. Self-Managed

| | Self-Managed (Kafka / RabbitMQ) | Cloud-Managed (SQS / SNS / Pub/Sub) |
|--|--------------------------------|--------------------------------------|
| **Setup** | Cluster config, ZooKeeper/KRaft, networking | Zero setup — API only |
| **Ops burden** | Broker tuning, partition rebalancing, upgrades | None |
| **Cost** | Infra only; high engineering time | Pay per message/GB — can be expensive at scale |
| **Ordering** | Strong (per partition) | Weak (SQS standard); strong (SQS FIFO, per group) |
| **Retention** | Unlimited | 14 days max (SQS), 7 days (Pub/Sub) |
| **Replay** | Yes — seek to any offset | No — once consumed, gone |
| **Throughput ceiling** | Very high — your infra limit | Effectively unlimited (managed) |
| **Lock-in** | None — open source | High — especially Kinesis/Pub/Sub |

---

## Learning Path

```
[B] Patterns (pub/sub, queue, fan-out) → SQS/SNS (managed, zero ops)
[I] RabbitMQ (routing, DLX, confirms) → Kafka basics (topics, partitions, consumer groups)
[A] Kafka operations → Exactly-once semantics → Schema Registry → Kafka Streams / Flink
```

---

## Key Resources

- [awesome-kafka](../resources/awesome-kafka/README.md) — curated Kafka tools, clients, and resources
- [awesome-scalability](../resources/awesome-scalability/README.md) — messaging patterns at scale

---

[← DBRE](../dbre/README.md) | [← SRE](../sre/README.md) | [← Platform](../platform/README.md)
