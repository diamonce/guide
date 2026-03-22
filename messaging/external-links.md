# External Resources — Messaging & Queues

[← Messaging Home](README.md) | [← Main](../README.md)

---

## Official Documentation

| System | Docs | Notes |
|--------|------|-------|
| Apache Kafka | [kafka.apache.org/documentation](https://kafka.apache.org/documentation/) | Definitive reference — design, configuration, ops |
| Confluent Platform | [docs.confluent.io](https://docs.confluent.io/) | Kafka + Schema Registry + ksqlDB docs |
| RabbitMQ | [rabbitmq.com/docs](https://www.rabbitmq.com/docs) | Exchanges, routing, clustering, monitoring |
| Amazon SQS | [docs.aws.amazon.com/sqs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/) | FIFO, DLQ, visibility timeout |
| Amazon SNS | [docs.aws.amazon.com/sns](https://docs.aws.amazon.com/sns/latest/dg/) | Fan-out, filtering, delivery retries |
| Apache Pulsar | [pulsar.apache.org/docs](https://pulsar.apache.org/docs/) | Multi-tenancy, geo-replication, Functions |
| NATS | [docs.nats.io](https://docs.nats.io/) | JetStream persistence, queue groups |
| Google Pub/Sub | [cloud.google.com/pubsub/docs](https://cloud.google.com/pubsub/docs) | Ordering keys, push vs. pull subscriptions |
| Azure Service Bus | [learn.microsoft.com/azure/service-bus-messaging](https://learn.microsoft.com/en-us/azure/service-bus-messaging/) | Sessions, DLQ, transactions |
| ksqlDB | [ksqldb.io/docs](https://ksqldb.io/docs/latest/) | SQL over Kafka streams |
| Apache Flink | [nightlies.apache.org/flink/flink-docs-stable](https://nightlies.apache.org/flink/flink-docs-stable/) | Stateful stream processing |

---

## Design & Architecture

| Resource | What it is |
|----------|-----------|
| [Kafka: The Definitive Guide (free PDF)](https://www.confluent.io/resources/kafka-the-definitive-guide-v2/) | O'Reilly book, free from Confluent — the Kafka reference book |
| [Designing Event-Driven Systems (free PDF)](https://www.confluent.io/designing-event-driven-systems/) | Ben Stopford — patterns for event-driven architecture with Kafka |
| [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/) | Hohpe & Woolf — canonical messaging patterns (Gregor Hohpe is on AWS architecture board) |
| [Martin Fowler — Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html) | Foundational article on event sourcing |
| [Martin Fowler — CQRS](https://martinfowler.com/bliki/CQRS.html) | Command Query Responsibility Segregation |
| [Martin Fowler — Saga Pattern](https://martinfowler.com/articles/patterns-of-distributed-systems/two-phase-commit.html) | Distributed transaction coordination |
| [Transactional Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html) | microservices.io — solving dual-write |
| [The Log: What every software engineer should know about real-time data](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) | Jay Kreps (Kafka creator) — the foundational essay |

---

## Kafka Operations & Internals

| Resource | What it is |
|----------|-----------|
| [Kafka Improvement Proposals (KIPs)](https://cwiki.apache.org/confluence/display/KAFKA/Kafka+Improvement+Proposals) | Track new Kafka features at design stage |
| [Confluent Blog](https://www.confluent.io/blog/) | Deep dives on Kafka internals, Schema Registry, Kafka Streams |
| [Burrow — Consumer Lag Monitoring](https://github.com/linkedin/Burrow) | LinkedIn's consumer lag evaluator |
| [AKHQ — Kafka UI](https://github.com/tchiotludo/akhq) | Browse topics, consumers, schemas |
| [kcat (kafkacat)](https://github.com/edenhill/kcat) | CLI producer/consumer/metadata tool |

---

## RabbitMQ

| Resource | What it is |
|----------|-----------|
| [RabbitMQ Tutorials](https://www.rabbitmq.com/tutorials) | Official tutorials — 7 tutorials from Hello World to topics and RPC |
| [awesome-rabbitmq](../resources/awesome-rabbitmq/README.md) | Curated RabbitMQ resources and tooling |
| [RabbitMQ Production Checklist](https://www.rabbitmq.com/docs/production-checklist) | Official hardening guide before going to production |
| [Lazy Queues](https://www.rabbitmq.com/docs/lazy-queues) | For high-backlog queues — moves messages to disk |

---

## Benchmarks & Comparisons

| Resource | What it is |
|----------|-----------|
| [Kafka vs Pulsar vs RabbitMQ (Confluent)](https://www.confluent.io/kafka-vs-pulsar/) | Confluent's comparison (biased but technically detailed) |
| [TPC benchmarks for message brokers](https://activemq.apache.org/performance) | ActiveMQ performance data — useful baseline |

---

## Related Topics

- [Kafka Deep Dive](kafka.md)
- [Best Practices](best-practices.md)
- [awesome-kafka](../resources/awesome-kafka/README.md)
- [DBRE Scaling](../dbre/scaling.md) — Kafka as CDC transport
- [SRE Observability](../sre/observability.md)
