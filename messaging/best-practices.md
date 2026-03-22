# Messaging & Queues — Best Practices, Do's and Don'ts

[← Messaging Home](README.md) | [← Main](../README.md)

---

## Apache Kafka

### DO

**Set `acks=all` and `enable.idempotence=true` on producers**
```properties
# ✅ durability + deduplication on retries
acks=all
enable.idempotence=true
retries=2147483647
```
`acks=1` means data can be lost if the leader crashes before replication. `acks=all` + `min.insync.replicas=2` guarantees durability.

**Always commit offsets manually after successful processing**
```python
# ❌ auto-commit — loses messages if consumer crashes mid-processing
enable.auto.commit=true

# ✅ commit after you've handled the message
consumer.poll(timeout)
process(records)
consumer.commit_sync()   # or commit_async with error callback
```

**Partition by a meaningful business key**
```python
# ❌ null key — round-robin partition assignment, no ordering guarantee
producer.send("orders", value=order_json)

# ✅ customer_id as key — all orders for a customer land on same partition, in order
producer.send("orders", key=customer_id, value=order_json)
```

**Set replication factor = 3 in production**
```bash
# ✅ survives 1 broker failure without data loss
kafka-topics.sh --create --topic orders \
  --replication-factor 3 \
  --partitions 12 \
  --bootstrap-server localhost:9092
```

**Use Schema Registry for all topics in shared environments**
```
✅ Avro / Protobuf + Schema Registry → enforces compatibility on publish
✅ BACKWARD compatibility mode → consumers on old schema still work
```
Without this, one team's schema change silently breaks another team's consumer.

**Monitor consumer lag as a primary alert**
```yaml
# ✅ alert when lag is growing, not just when it exists
- alert: KafkaConsumerLagGrowing
  expr: kafka_consumer_lag_sum > 10000 and deriv(kafka_consumer_lag_sum[5m]) > 0
  for: 10m
```

**Use `min.insync.replicas=2` with `acks=all`**
```properties
# ✅ broker-level or topic-level
min.insync.replicas=2
```
Without this, `acks=all` is satisfied by a single broker if only one is in the ISR — no actual durability.

**Set explicit retention per topic**
```bash
# ✅ prevent disk from filling silently
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders \
  --alter --add-config retention.ms=604800000  # 7 days
```

**Use KRaft mode for new deployments**
```
✅ No ZooKeeper dependency
✅ Faster controller failover
✅ Kafka 4.0 drops ZooKeeper entirely — start right
```

---

### DON'T

**Don't use `replication.factor=1` in production**
```bash
# ❌ single broker failure = permanent data loss
--replication-factor 1

# ✅
--replication-factor 3
```

**Don't store large messages in Kafka**
```
❌ 10MB Kafka messages: broker memory pressure, slow replication, consumer OOM
✅ Claim check pattern: store payload in S3, send s3_key in Kafka message
   Max recommended message size: < 1MB (default limit is 1MB)
```

**Don't use too many partitions per broker**
```
Each partition = open file handles + memory for leader/follower tracking
Rule of thumb: 100–4,000 partitions per broker
❌ 10,000 partitions on 3 brokers → controller bottleneck, slow failover
✅ Start with partitions = 2× expected peak consumers
```

**Don't decrease partition count**
```bash
# ❌ Kafka does not allow decreasing partitions — requires topic recreation
# Design partition count with future scale in mind upfront
```

**Don't commit offsets before processing**
```python
# ❌ at-most-once: if crash after commit but before process → lost message
consumer.commit()
process(records)

# ✅ at-least-once
process(records)
consumer.commit()
```

**Don't ignore consumer rebalances**
```python
# ✅ implement a rebalance listener to commit offsets cleanly before rebalance
class RebalanceListener(ConsumerRebalanceListener):
    def on_partitions_revoked(self, revoked):
        consumer.commit()   # commit before losing partition assignment
```

**Don't use `auto.offset.reset=earliest` in production for existing consumer groups**
```
❌ If a consumer group loses its offset (e.g., __consumer_offsets topic TTL),
   earliest will replay the entire topic — potentially millions of events
✅ Set auto.offset.reset=latest for new consumer groups reading live data
✅ Use earliest only for replay scenarios, explicitly and deliberately
```

**Don't couple consumer logic to specific partition counts**
```python
# ❌ hardcoded partition-specific logic breaks when partitions change
if partition == 0:
    process_region_a()

# ✅ let Kafka handle routing via message key
```

---

## RabbitMQ

### DO

**Always use durable queues and persistent messages for important work**
```python
# ✅ queue survives broker restart
channel.queue_declare(queue='orders', durable=True)

# ✅ message survives broker restart
channel.basic_publish(
    exchange='',
    routing_key='orders',
    body=message,
    properties=pika.BasicProperties(delivery_mode=2)  # persistent
)
```

**Enable publisher confirms**
```python
# ✅ broker confirms message was written to disk
channel.confirm_delivery()
channel.basic_publish(...)
# Raises exception if broker couldn't confirm — you can retry
```

**Set a Dead Letter Exchange (DLX) on every critical queue**
```python
# ✅ failed messages go to DLX instead of disappearing
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={
        'x-dead-letter-exchange': 'orders.dlx',
        'x-message-ttl': 86400000,     # messages expire after 24h if not consumed
        'x-max-length': 100000         # prevent unbounded queue growth
    }
)
# Create the DLX exchange and bind a DLQ
channel.exchange_declare('orders.dlx', 'fanout', durable=True)
channel.queue_declare('orders.dlq', durable=True)
channel.queue_bind('orders.dlq', 'orders.dlx')
```

**Set prefetch count to limit in-flight messages per consumer**
```python
# ✅ prevents one consumer from taking all messages and stalling
channel.basic_qos(prefetch_count=10)
```
Without this, a slow consumer receives all queued messages, holds them in memory, and causes head-of-line blocking.

**Use separate vhosts per environment**
```bash
# ✅ complete isolation — dev consumer can't accidentally consume prod messages
rabbitmqctl add_vhost production
rabbitmqctl add_vhost staging
rabbitmqctl set_permissions -p production app-user ".*" ".*" ".*"
```

**Use `basic_ack` only after successful processing**
```python
# ✅ message requeued if consumer crashes before ack
def callback(ch, method, properties, body):
    try:
        process(body)
        ch.basic_ack(delivery_tag=method.delivery_tag)
    except Exception:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        # requeue=False → goes to DLX
```

**Monitor queue depth and consumer count**
```bash
# ✅ key metrics to alert on
rabbitmqctl list_queues name messages consumers memory

# Queue depth growing with consumers present → consumers too slow
# Consumer count = 0 on a populated queue → consumers dead
```

---

### DON'T

**Don't use `basic_ack` with `multiple=True` carelessly**
```python
# ❌ acknowledges ALL messages up to this delivery tag
# If you're wrong about which were processed, messages are lost
ch.basic_ack(delivery_tag=method.delivery_tag, multiple=True)

# ✅ ack individually unless you're certain about batch semantics
ch.basic_ack(delivery_tag=method.delivery_tag, multiple=False)
```

**Don't use the default exchange for everything**
```python
# ❌ default exchange = direct routing to queue by name — no flexibility
channel.basic_publish(exchange='', routing_key='orders', body=msg)

# ✅ use topic/direct/fanout exchanges for routing flexibility
channel.exchange_declare('events', 'topic', durable=True)
channel.basic_publish(exchange='events', routing_key='orders.created', body=msg)
```

**Don't let queues grow unbounded**
```python
# ❌ no length limit → broker runs out of memory or disk
channel.queue_declare(queue='orders', durable=True)

# ✅ set limits, use lazy queues for large backlogs
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={
        'x-max-length': 100000,
        'x-overflow': 'reject-publish',    # or dead-letter-publish-confirm
        'x-queue-mode': 'lazy'             # store to disk, don't RAM-buffer
    }
)
```

**Don't ignore the management plugin for ops**
```bash
# ✅ enable the UI — essential for debugging
rabbitmq-plugins enable rabbitmq_management
# UI at http://localhost:15672
```

---

## Amazon SQS / SNS

### DO

**Use SQS FIFO queues when order matters**
```python
# ✅ FIFO + MessageGroupId = ordered delivery per group
sqs.send_message(
    QueueUrl=fifo_queue_url,
    MessageBody=json.dumps(order),
    MessageGroupId=customer_id,          # ordering per customer
    MessageDeduplicationId=order_id      # deduplication within 5 minutes
)
```

**Always set a visibility timeout longer than your max processing time**
```python
# ❌ default 30s — if processing takes 45s, message becomes visible again → duplicate
# ✅ set to 2× expected processing time
sqs.create_queue(
    QueueName='orders',
    Attributes={'VisibilityTimeout': '120'}  # 2 minutes
)

# Extend visibility timeout for long-running tasks
sqs.change_message_visibility(
    QueueUrl=queue_url,
    ReceiptHandle=receipt_handle,
    VisibilityTimeout=120
)
```

**Set a Dead Letter Queue with maxReceiveCount**
```python
# ✅ after 3 failures, message goes to DLQ — prevents infinite retry loop
redrive_policy = {
    'deadLetterTargetArn': dlq_arn,
    'maxReceiveCount': '3'
}
sqs.set_queue_attributes(
    QueueUrl=queue_url,
    Attributes={'RedrivePolicy': json.dumps(redrive_policy)}
)
```

**Use SNS → SQS fan-out for multiple consumers**
```
✅ One SNS topic → multiple SQS queues
   Each queue has its own processing rate, retry policy, DLQ
   Consumers are completely decoupled from each other
```

**Use long polling to reduce empty API calls**
```python
# ❌ short polling → many empty responses, more API cost
sqs.receive_message(QueueUrl=url)

# ✅ long polling → waits up to 20s for messages, fewer API calls
sqs.receive_message(QueueUrl=url, WaitTimeSeconds=20)
```

**Process messages idempotently**
```python
# SQS guarantees at-least-once delivery (standard queues)
# Your consumer MUST be idempotent

def process_order(order_id, data):
    if db.exists(f"processed:{order_id}"):
        return  # already handled
    db.process(order_id, data)
    db.mark_processed(f"processed:{order_id}")
```

---

### DON'T

**Don't use SQS standard queues when order is critical**
```
❌ Standard SQS: best-effort ordering, at-least-once → duplicates + reordering
✅ SQS FIFO: exactly-once within deduplication window, ordered per MessageGroupId
```

**Don't delete messages before processing**
```python
# ❌ message deleted before processing → data loss on crash
sqs.delete_message(ReceiptHandle=receipt_handle)
process(message)

# ✅ delete only after confirmed processing
process(message)
sqs.delete_message(ReceiptHandle=receipt_handle)
```

**Don't poll SQS in a tight loop with no wait**
```python
# ❌ burns money and CPU
while True:
    response = sqs.receive_message(QueueUrl=url)
    if not response['Messages']:
        time.sleep(0)  # immediately polls again

# ✅
response = sqs.receive_message(QueueUrl=url, WaitTimeSeconds=20, MaxNumberOfMessages=10)
```

---

## General Messaging Principles

### DO

**Design consumers to be idempotent** — every broker delivers at-least-once. Assume duplicates will happen.

**Use the Outbox Pattern for transactional publishing**
```sql
-- ✅ write to DB + outbox in one transaction → guaranteed publish
BEGIN;
INSERT INTO orders (id, customer_id, total) VALUES (...);
INSERT INTO outbox (aggregate_id, event_type, payload) VALUES (...);
COMMIT;
-- Separate outbox worker publishes to Kafka/SQS and deletes row
```

**Set message TTL / expiration everywhere**
```
✅ A message that can't be processed after N hours is usually a bug, not a backlog
✅ TTL forces you to reason about what "stale" means for your domain
```

**Implement circuit breakers on consumers**
```
✅ If downstream (DB, API) is down, stop consuming instead of building lag
✅ Lag in Kafka is recoverable; corrupted DB state from half-processed messages is not
```

**Test your DLQ handling** — an unmonitored DLQ that fills silently is worse than no DLQ.

**Document the schema, ownership, and SLO of every topic/queue** in a service catalog.

---

### DON'T

**Don't use a message broker as a database**
```
❌ Kafka topic as the only storage for state → retention expiry = data loss
✅ Kafka as a transport; PostgreSQL/DynamoDB as the system of record
✅ Exception: compacted topics with infinite retention for CDC/event sourcing
```

**Don't put sensitive data in messages without encryption**
```
❌ PII, credentials, payment card data in plaintext Kafka messages
✅ Encrypt sensitive fields at application level before publishing
✅ Or reference the record by ID and fetch from the encrypted DB on the consumer side
```

**Don't build synchronous request-reply on top of an async broker**
```
❌ HTTP-over-Kafka: producer sends request, blocks waiting for response on a reply topic
   → you've built a slower, more complex HTTP call with no benefits
✅ If you need synchronous request-reply → use HTTP/gRPC directly
✅ Async patterns belong in async pipelines; don't fight the model
```

**Don't skip the dead letter queue**
```
❌ No DLQ → poison messages block queue forever, or silently disappear
✅ DLQ + alert on DLQ message count > 0 → you know when something breaks
```

**Don't ignore backpressure**
```
❌ Producer publishes at max speed regardless of consumer capacity
✅ Monitor consumer lag / queue depth; slow down or scale consumers proactively
```

---

## Tools Reference

| Tool | Purpose | Link |
|------|---------|-------|
| **Burrow** | Kafka consumer lag monitoring with trend analysis | [github.com/linkedin/Burrow](https://github.com/linkedin/Burrow) |
| **AKHQ** (formerly KafkaHQ) | Kafka UI — browse topics, consumers, schema registry | [github.com/tchiotludo/akhq](https://github.com/tchiotludo/akhq) |
| **Kafka UI** | Modern Kafka management UI by Provectus | [github.com/provectus/kafka-ui](https://github.com/provectus/kafka-ui) |
| **kcat** (kafkacat) | CLI Swiss Army knife for Kafka — produce/consume/metadata | [github.com/edenhill/kcat](https://github.com/edenhill/kcat) |
| **kafka-consumer-groups.sh** | Built-in CLI: lag, offset reset, group management | bundled with Kafka |
| **Confluent Schema Registry** | Schema validation and evolution enforcement | [docs.confluent.io/platform/current/schema-registry](https://docs.confluent.io/platform/current/schema-registry/index.html) |
| **Apicurio Registry** | Open-source schema registry (alternative to Confluent) | [apicur.io/registry](https://www.apicur.io/registry/) |
| **Kafka Streams** | Java stream processing library, no separate cluster | bundled with Kafka |
| **ksqlDB** | SQL over Kafka streams | [ksqldb.io](https://ksqldb.io/) |
| **Apache Flink** | Stateful stream processing at scale, Kafka-native | [flink.apache.org](https://flink.apache.org/) |
| **RabbitMQ Management Plugin** | UI + HTTP API for RabbitMQ monitoring and ops | bundled with RabbitMQ |
| **Toxiproxy** | Network fault injection — test consumer behavior under failures | [github.com/Shopify/toxiproxy](https://github.com/Shopify/toxiproxy) |
| **LocalStack** | Local AWS emulation — SQS, SNS, Kinesis without real AWS | [localstack.cloud](https://localstack.cloud/) |

---

## Pre-Deploy Checklist

- [ ] Replication factor ≥ 3 for every Kafka topic in production
- [ ] `min.insync.replicas=2` configured
- [ ] `acks=all` on producers for critical topics
- [ ] `enable.idempotence=true` on producers
- [ ] Auto-commit disabled; manual commit after processing
- [ ] Consumer lag alerting configured (Burrow or Prometheus)
- [ ] Schema Registry in use for Avro/Protobuf topics
- [ ] Dead letter queue / exchange defined for every critical queue
- [ ] DLQ monitored — alert on any message arriving
- [ ] Message TTL / retention set explicitly
- [ ] Consumers are idempotent — verified with duplicate injection test
- [ ] Outbox pattern used where DB + publish must be atomic
- [ ] Visibility timeout (SQS) > max processing time

---

## Related Topics

- [Kafka Deep Dive](kafka.md)
- [External Links](external-links.md)
- [DBRE Scaling](../dbre/scaling.md) — Kafka as CDC transport
- [SRE Observability](../sre/observability.md) — consumer lag monitoring
- [Platform CI/CD](../platform/cicd.md) — event-driven deployment patterns
