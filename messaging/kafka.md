# Apache Kafka — Deep Dive

[← Messaging Home](README.md) | [← Main](../README.md)

**Official docs:** [kafka.apache.org/documentation](https://kafka.apache.org/documentation/)
**Resource:** [awesome-kafka](../resources/awesome-kafka/README.md)

Kafka is a distributed commit log. Every message is an immutable, ordered, replicated record. Consumers read at their own pace. Data stays until the retention policy removes it — not when it's consumed.

---

## Core Concepts

### Topic, Partition, Offset

```
Topic: "orders"
┌─ Partition 0 ──────────────────────────────────┐
│  offset: 0    1    2    3    4    5    6    7   │
│         [msg][msg][msg][msg][msg][msg][msg][msg]│
└────────────────────────────────────────────────┘
┌─ Partition 1 ──────────────────────────────────┐
│  offset: 0    1    2    3    4    5             │
│         [msg][msg][msg][msg][msg][msg]          │
└────────────────────────────────────────────────┘
┌─ Partition 2 ──────────────────────────────────┐
│  offset: 0    1    2    3                       │
│         [msg][msg][msg][msg]                    │
└────────────────────────────────────────────────┘
```

- **Topic**: logical channel — like a database table name
- **Partition**: physical unit of parallelism and ordering. Ordering is guaranteed *within* a partition, not across partitions
- **Offset**: monotonically increasing integer per partition. Consumer tracks which offset it has processed
- **Retention**: messages are kept until `retention.ms` or `retention.bytes` is exceeded — not until consumed

### Producer → Broker → Consumer Group

```
Producer
  │  key="customer-123"           ← key determines partition (consistent hashing)
  ▼
Broker (leader for partition 2)
  │
  ├─ Replicates to follower 1
  └─ Replicates to follower 2
          ▲
Consumer Group "payments-service"
  ├─ Consumer A  → reads partition 0
  ├─ Consumer B  → reads partition 1
  └─ Consumer C  → reads partition 2
```

**Consumer group rules:**
- Each partition is assigned to exactly one consumer in a group
- Max parallelism = number of partitions (extra consumers sit idle)
- Different consumer groups are completely independent — each gets all messages

### Replication

```
Partition 0 leader: Broker 1
Partition 0 ISR (In-Sync Replicas): [Broker 1, Broker 2, Broker 3]

Producer sends message → Broker 1 (leader)
                       → Broker 2, 3 replicate
Producer ack returned when: all ISR replicated (acks=all) OR leader only (acks=1)
```

- `replication.factor=3` is the production minimum — survives 1 broker failure
- `min.insync.replicas=2` — producer gets error if < 2 replicas are in sync (prevents silent data loss with `acks=all`)

---

## Critical Configuration

### Producer

```properties
# Durability
acks=all                          # wait for all ISR to confirm write
enable.idempotence=true           # exactly-once at producer level (deduplicates retries)
retries=Integer.MAX_VALUE         # retry forever; idempotence makes this safe

# Performance
compression.type=lz4              # compress batches; lz4 is best speed/ratio balance
linger.ms=5                       # wait 5ms to batch more messages before sending
batch.size=65536                  # 64KB batch size

# Timeouts
delivery.timeout.ms=120000        # total time allowed for a message to be delivered
request.timeout.ms=30000
```

### Consumer

```properties
# Offset management
enable.auto.commit=false          # ALWAYS disable; commit manually after processing
auto.offset.reset=earliest        # for new consumer groups: start from beginning
                                  # latest = only new messages (production default for existing topics)

# Performance & fairness
max.poll.records=500              # how many records per poll()
max.poll.interval.ms=300000       # max time between polls before consumer is considered dead
fetch.min.bytes=1                 # return immediately when any data available
fetch.max.wait.ms=500             # max time to wait if fetch.min.bytes not met

# Session
session.timeout.ms=45000          # broker considers consumer dead after this
heartbeat.interval.ms=15000       # send heartbeat every 15s (must be < session.timeout / 3)
```

### Broker (server.properties)

```properties
# Retention
log.retention.hours=168           # 7 days default; set per-topic to override
log.retention.bytes=-1            # unlimited by default; set to cap storage
log.segment.bytes=1073741824      # 1GB segments; smaller = more files, faster cleanup

# Replication
default.replication.factor=3
min.insync.replicas=2

# Performance
num.partitions=6                  # default partitions for new topics
num.network.threads=8
num.io.threads=16

# Log compaction (for changelog/CDC topics)
log.cleanup.policy=compact        # or delete (default), or compact,delete
```

---

## Delivery Semantics

| Semantic | How | Risk |
|----------|-----|------|
| **At-most-once** | Commit offset before processing | Message loss on consumer crash |
| **At-least-once** | Process, then commit offset | Duplicate processing on crash |
| **Exactly-once** | Idempotent producer + transactional consumer | Highest complexity, highest safety |

### Exactly-Once (EOS) Setup

```java
// Producer side
Properties props = new Properties();
props.put("enable.idempotence", "true");
props.put("transactional.id", "order-processor-1");  // unique per producer instance

producer.initTransactions();

try {
    producer.beginTransaction();
    producer.send(new ProducerRecord<>("output-topic", key, value));
    // Commit consumer offsets atomically with the transaction
    producer.sendOffsetsToTransaction(offsets, consumerGroupMetadata);
    producer.commitTransaction();
} catch (ProducerFencedException e) {
    producer.close();
} catch (KafkaException e) {
    producer.abortTransaction();
}
```

Use EOS for: financial transactions, billing events, any data where duplicates cause real damage.

---

## Schema Registry

Never rely on consumers knowing the schema implicitly. Use a Schema Registry.

```
Producer → serialize with Avro/Protobuf/JSON Schema
         → register schema with Schema Registry (Confluent / Apicurio)
         → include schema ID in message header
         → send to Kafka

Consumer → read schema ID from header
         → fetch schema from Registry (cached after first lookup)
         → deserialize correctly
```

**Evolution rules (Avro — BACKWARD compatible):**
- ✅ Add optional field with a default
- ✅ Remove field with a default
- ❌ Remove required field
- ❌ Change field type
- ❌ Rename field without alias

```bash
# Confluent Schema Registry
docker run -p 8081:8081 confluentinc/cp-schema-registry:latest

# Register schema
curl -X POST http://localhost:8081/subjects/orders-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Order\",...}"}'
```

---

## Consumer Lag Monitoring

Consumer lag = latest offset − consumer's current offset per partition. Lag > 0 means consumers are behind. Lag growing = consumers can't keep up.

```bash
# Built-in CLI
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group payments-service

# Output:
# GROUP            TOPIC     PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# payments-service orders    0          10234           10240           6
# payments-service orders    1          9876            9876            0
# payments-service orders    2          11002           11150           148  ← alert on this
```

**Burrow** — LinkedIn's dedicated consumer lag monitor with trend analysis (not just snapshot):
[github.com/linkedin/Burrow](https://github.com/linkedin/Burrow)

Alert thresholds:
- Lag > 0 and growing: consumer is falling behind — scale consumers or optimize processing
- Lag stable but nonzero: consumer keeping pace but not catching up — acceptable short-term
- Lag = 0: healthy

---

## Operations Runbook

### Add Partitions to an Existing Topic

```bash
# Increase partition count (can only increase, never decrease)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic orders \
  --partitions 12

# WARNING: existing key-based routing changes — some keys will go to different partitions
# Messages already in old partitions are unaffected
# Run during low-traffic periods
```

### Rebalance Partitions Across Brokers

```bash
# Generate a reassignment plan
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --broker-list "1,2,3" \
  --topics-to-move-json-file topics.json \
  --generate

# Execute (throttle to avoid saturating network)
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --throttle 50000000 \  # 50MB/s
  --execute

# Verify
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --verify
```

### Reset Consumer Group Offset

```bash
# Reset to earliest (replay all messages)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group payments-service \
  --topic orders \
  --reset-offsets --to-earliest --execute

# Reset to specific offset
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group payments-service \
  --topic orders:2:10000 \  # partition 2, offset 10000
  --reset-offsets --to-offset 10000 --execute

# Reset to datetime
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group payments-service \
  --topic orders \
  --reset-offsets --to-datetime 2024-01-15T00:00:00.000 --execute
```

### Topic Compaction (Event Sourcing / CDC)

Log compaction keeps only the latest message per key. Tombstone (null value) = delete that key.

```bash
# Configure compaction on an existing topic
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name customer-profiles \
  --alter \
  --add-config cleanup.policy=compact,min.cleanable.dirty.ratio=0.1,segment.ms=86400000
```

---

## KRaft Mode (ZooKeeper Replacement)

Since Kafka 3.3, KRaft (Kafka Raft) replaces ZooKeeper. Kafka 4.0 removes ZooKeeper entirely.

```properties
# kraft/server.properties
process.roles=broker,controller   # or just broker, or just controller
node.id=1
controller.quorum.voters=1@kafka1:9093,2@kafka2:9093,3@kafka3:9093
```

KRaft reduces operational complexity significantly: no separate ZooKeeper cluster to manage, monitor, or upgrade.

---

## Kafka Streams & ksqlDB

**Kafka Streams** — Java library for stream processing within Kafka, no separate cluster.

```java
StreamsBuilder builder = new StreamsBuilder();
KStream<String, Order> orders = builder.stream("orders");
KStream<String, Order> highValue = orders
    .filter((key, order) -> order.getTotal() > 1000);
highValue.to("high-value-orders");

KafkaStreams streams = new KafkaStreams(builder.build(), config);
streams.start();
```

**ksqlDB** — SQL interface over Kafka Streams. Run SQL queries on live Kafka streams.

```sql
-- Create a stream from a topic
CREATE STREAM orders (
    order_id VARCHAR,
    customer_id VARCHAR,
    total DOUBLE
) WITH (KAFKA_TOPIC='orders', VALUE_FORMAT='AVRO');

-- Continuous query: filter high-value orders into a new topic
CREATE STREAM high_value_orders AS
SELECT * FROM orders WHERE total > 1000;

-- Materialized view: running total per customer
CREATE TABLE customer_totals AS
SELECT customer_id, SUM(total) AS lifetime_value
FROM orders GROUP BY customer_id;
```

---

## Related Topics

- [Messaging Best Practices](best-practices.md)
- [Messaging External Links](external-links.md)
- [DBRE Scaling](../dbre/scaling.md) — Kafka as a CDC transport
- [SRE Observability](../sre/observability.md) — monitoring Kafka consumer lag
- [awesome-kafka](../resources/awesome-kafka/README.md)
