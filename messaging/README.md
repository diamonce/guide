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
