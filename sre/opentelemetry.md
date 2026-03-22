# OpenTelemetry & Distributed Tracing

[← Observability](observability.md) | [← SRE Home](README.md) | [← Main](../README.md)

---

## What Is OpenTelemetry? `[B]`

**OpenTelemetry (OTEL)** is the CNCF standard for instrumenting applications to produce **traces, metrics, and logs** in a vendor-neutral way. Instrument once, export to any backend.

**Origin:** merged from OpenTracing (trace API) + OpenCensus (metrics + trace SDK) in 2019.

| What it provides | What it does NOT provide |
|-----------------|-------------------------|
| SDKs (Go, Python, Java, JS, …) | A storage/query backend |
| APIs for traces, metrics, logs | Dashboards or alerting |
| A Collector (agent/gateway) | Specific vendor integrations (those are exporters) |
| Semantic conventions | On-call tooling |

---

## How Traces Work `[B]`

A **trace** represents the full journey of a single request across all services. It is made up of **spans**.

```
Trace: checkout (TraceID: abc123)
│
├── [span] api-gateway          0ms → 130ms
│   ├── [span] auth-service     2ms → 8ms
│   ├── [span] inventory        10ms → 42ms
│   │   └── [span] postgres     12ms → 40ms   ← slow query
│   └── [span] payment-service  45ms → 128ms
│       └── [span] stripe-api   47ms → 126ms  ← external call
```

### Trace Anatomy

| Concept | Description |
|---------|-------------|
| **TraceID** | 128-bit globally unique ID — same across all spans in one request |
| **SpanID** | 64-bit ID unique within a trace |
| **ParentSpanID** | Links child span to its parent; root span has none |
| **Span name** | Human-readable operation name (`POST /checkout`, `db.query`) |
| **Start / end time** | Wall-clock timestamps |
| **Status** | `OK`, `ERROR`, or `UNSET` |
| **Attributes** | Key-value metadata (`http.method`, `db.statement`, `user.id`) |
| **Events** | Timestamped log entries attached to a span |
| **Links** | References to other spans (useful for async / message-driven flows) |

### Trace Context Propagation

For distributed tracing to work, the TraceID + SpanID must flow across every service boundary (HTTP headers, message queue headers, gRPC metadata).

**W3C TraceContext** (the standard — use this):
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             version  traceId                          spanId           flags
```

**B3** (Zipkin legacy, still common):
```
X-B3-TraceId: 4bf92f3577b34da6a3ce929d0e0e4736
X-B3-SpanId:  00f067aa0ba902b7
X-B3-Sampled: 1
```

OTEL propagators extract/inject context automatically in auto-instrumented frameworks. For manual calls (raw HTTP clients, message producers), inject manually.

---

## OTEL Architecture `[I]`

```
Your App
  └── OTEL SDK
        ├── Tracer Provider  → creates Tracers
        ├── Meter Provider   → creates Meters
        └── Logger Provider  → creates Loggers
              │
              │  (via OTLP — gRPC or HTTP)
              ▼
        OTEL Collector
          ├── Receivers   (OTLP, Jaeger, Zipkin, Prometheus, …)
          ├── Processors  (batch, memory_limiter, attributes, sampling)
          └── Exporters   (Jaeger, Tempo, Datadog, OTLP/gRPC, …)
                │
                ▼
         Backend (Jaeger / Grafana Tempo / Honeycomb / Datadog)
```

### Collector: Agent vs Gateway

| Mode | Where it runs | Use case |
|------|--------------|----------|
| **Agent** (sidecar/daemonset) | Same host as app | Local buffering, reduces app-side complexity |
| **Gateway** (standalone cluster) | Centralised | Routing, batching, tail-based sampling, auth |

**Typical production setup:** app → OTLP → local agent → OTLP → central gateway → backend.

---

## Sampling `[I]`

Tracing every request at scale is expensive. Sampling controls what you keep.

| Strategy | How | Trade-offs |
|----------|-----|-----------|
| **Head-based** | Decision at trace start (random %, always-on, never) | Simple, low overhead — misses rare slow/error traces |
| **Tail-based** | Decision after trace completes (Collector sees full trace) | Catches errors/latency outliers — requires buffering all spans |
| **Parent-based** | Child respects parent's sampling decision | Prevents partial traces — must propagate sample flag |

**Recommended defaults:**
- Dev: 100% (always sample)
- Staging: 10–20%
- Production: 1–5% head-based + tail-based rules to keep all errors and p99+ latency

```yaml
# Collector tail-based sampling example
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: keep-slow
        type: latency
        latency: {threshold_ms: 1000}
      - name: probabilistic
        type: probabilistic
        probabilistic: {sampling_percentage: 2}
```

---

## Instrumentation `[I]`

### Auto-Instrumentation (zero-code)

Most frameworks are covered. Add the agent, get spans for HTTP, DB, messaging automatically.

```bash
# Python (Flask, Django, requests, SQLAlchemy, …)
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
opentelemetry-instrument \
  --exporter_otlp_endpoint=http://collector:4317 \
  python app.py
```

```bash
# Java (Spring Boot, JDBC, gRPC, …)
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.exporter.otlp.endpoint=http://collector:4317 \
     -jar app.jar
```

```bash
# Node.js
npm install @opentelemetry/auto-instrumentations-node
node --require @opentelemetry/auto-instrumentations-node/register app.js
```

### Manual Instrumentation

Add custom spans for business logic that auto-instrumentation doesn't cover.

```python
# Python
from opentelemetry import trace

tracer = trace.get_tracer("payment-service")

def process_payment(order_id: str, amount: float):
    with tracer.start_as_current_span("process_payment") as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("payment.amount", amount)

        try:
            result = charge_card(amount)
            span.set_attribute("payment.status", "success")
            return result
        except CardDeclinedError as e:
            span.set_status(trace.StatusCode.ERROR, str(e))
            span.record_exception(e)
            raise
```

```go
// Go
import "go.opentelemetry.io/otel"

tracer := otel.Tracer("inventory-service")

func checkStock(ctx context.Context, productID string) (int, error) {
    ctx, span := tracer.Start(ctx, "checkStock",
        trace.WithAttributes(
            attribute.String("product.id", productID),
        ),
    )
    defer span.End()

    qty, err := db.QueryContext(ctx, "SELECT qty FROM stock WHERE id = ?", productID)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return 0, err
    }
    span.SetAttributes(attribute.Int("stock.quantity", qty))
    return qty, nil
}
```

### Propagating Context Manually (async / message queues)

```python
# Producer: inject trace context into message headers
from opentelemetry.propagate import inject

headers = {}
inject(headers)  # adds traceparent, tracestate
kafka_producer.send("orders", value=payload, headers=list(headers.items()))

# Consumer: extract trace context from message headers
from opentelemetry.propagate import extract
from opentelemetry import trace

ctx = extract(dict(msg.headers))
with tracer.start_as_current_span("process_order", context=ctx) as span:
    # this span is now a child of the producer's span
    ...
```

---

## Semantic Conventions `[I]`

OTEL defines standard attribute names so backends can parse and correlate data automatically.

| Signal | Key attributes |
|--------|---------------|
| HTTP server | `http.method`, `http.route`, `http.status_code`, `server.address` |
| HTTP client | `http.method`, `url.full`, `http.status_code` |
| Database | `db.system`, `db.name`, `db.statement`, `db.operation` |
| Messaging | `messaging.system`, `messaging.destination.name`, `messaging.operation` |
| RPC | `rpc.system`, `rpc.service`, `rpc.method`, `rpc.grpc.status_code` |
| Errors | `exception.type`, `exception.message`, `exception.stacktrace` |

**Don't invent custom attribute names** for things covered by semantic conventions — backends have first-class support for the standard names.

---

## OTEL Collector Config Reference `[I]`

```yaml
# otel-collector.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
  batch:
    timeout: 5s
    send_batch_size: 1000
  attributes:
    actions:
      - key: env
        value: production
        action: insert

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
  logging:
    verbosity: detailed  # debug only

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, attributes]
      exporters: [otlp/jaeger, otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
```

---

## Backends Comparison `[I]`

| Backend | Type | Best for |
|---------|------|----------|
| **Jaeger** | Open source | Self-hosted, Kubernetes-native |
| **Grafana Tempo** | Open source | Large-scale, integrates with Grafana/Loki/Prometheus |
| **Zipkin** | Open source | Lightweight, older ecosystems |
| **Honeycomb** | SaaS | High-cardinality query, developer experience |
| **Datadog APM** | SaaS | Full-stack observability (metrics + logs + traces) |
| **AWS X-Ray** | SaaS | AWS-native workloads, Lambda tracing |
| **Grafana Cloud** | SaaS/managed | Managed Tempo + integrated with other Grafana signals |

OTEL exporters exist for all of these — switching backends is a config change, not a code change.

---

## Best Practices `[A]`

**Span naming:**
- Use `<verb> <noun>` or `<service>/<operation>`: `POST /orders`, `db.query`, `kafka.consume`
- Be consistent — inconsistent names break grouping in UIs
- Avoid high-cardinality data in span names (use attributes instead): `GET /users/{id}` not `GET /users/12345`

**Attribute hygiene:**
- Always set `http.status_code`, `db.system`, `rpc.method` — backends depend on them
- Add business context: `order.id`, `user.tier`, `payment.method`
- Never put PII/secrets in attributes (logs are different; attributes are indexed)

**Context propagation:**
- Always pass `context.Context` (Go) or current span context (Python/Java) through your call chain
- Validate propagation works: check that trace IDs match across service boundaries in your tracing UI
- For async workflows, always inject at the producer and extract at the consumer

**Sampling:**
- Never sample at the SDK level in production — do it in the Collector so you can change rates without deploys
- Always keep 100% of error spans and slow spans (tail-based)
- Use `parent_based` sampler in the SDK to respect upstream decisions

**Cardinality:**
- Attributes are indexed by backends — high-cardinality values (raw SQL queries, full URLs with IDs) explode storage costs
- Use `db.operation` + `db.table` instead of full `db.statement` in prod, or sanitize

---

## Observability-as-Code Pattern `[A]`

Manage collector config in Git and deploy via Helm/Kustomize:

```
infra/
  otel/
    collector-daemonset.yaml     # agent DaemonSet
    collector-deployment.yaml    # gateway Deployment
    collector-config.yaml        # ConfigMap with pipeline config
    tail-sampling-rules.yaml     # separate ConfigMap, updated frequently
```

Deploy the OTEL Operator for Kubernetes to get auto-instrumentation via annotation:
```yaml
annotations:
  instrumentation.opentelemetry.io/inject-python: "true"
  # → OTEL sidecar injected automatically, no code changes needed
```

---

## Related Topics

- [Observability](observability.md) — metrics, logs, alerting, dashboards
- [SLOs / SLIs / SLAs](slo-sla-sli.md) — turning trace data into SLIs
- [Incident Management](incident-management.md) — using traces during incidents
- [Kafka Deep Dive](../messaging/kafka.md) — trace propagation in messaging
