# Observability

[← SRE Home](README.md) | [← Main](../README.md)

---

## The Three Pillars `[B]`

| Pillar | What | Tools |
|--------|------|-------|
| **Metrics** | Aggregated numbers over time | Prometheus, Datadog, CloudWatch |
| **Logs** | Timestamped event records | ELK, Loki, Splunk, CloudWatch Logs |
| **Traces** | Request flow across services | Jaeger, Zipkin, Datadog APM, OTEL |

**When to use what:**
- Metrics → detecting *that* something is wrong (alerting, dashboards)
- Logs → understanding *what* happened
- Traces → understanding *where* in the call chain it broke

---

## Metrics `[B]`

### Metric Types (Prometheus model)

| Type | Description | Example |
|------|-------------|---------|
| Counter | Monotonically increasing | `http_requests_total` |
| Gauge | Point-in-time value | `memory_usage_bytes` |
| Histogram | Distribution of values | `request_duration_seconds` |
| Summary | Pre-computed quantiles | `rpc_duration_seconds` |

**Prefer histograms over summaries** — histograms can be aggregated across instances.

### Golden Signals as Metrics

```promql
# Latency — p99 request duration
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Traffic — requests per second
rate(http_requests_total[5m])

# Errors — error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Saturation — CPU usage
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

→ See [SLO/SLI](slo-sla-sli.md) for turning metrics into SLIs.

---

## Logs `[B]`

### Structured Logging

Always prefer structured (JSON) logs over plain text:

```json
{
  "timestamp": "2024-01-15T10:23:45Z",
  "level": "ERROR",
  "service": "payment-api",
  "trace_id": "abc123",
  "user_id": "u_789",
  "message": "Payment processing failed",
  "error": "timeout after 5000ms",
  "duration_ms": 5001
}
```

**Log levels:**
- `ERROR` — something failed, needs investigation
- `WARN` — degraded state, not broken
- `INFO` — normal lifecycle events
- `DEBUG` — verbose, disable in prod

### What to Always Log
- Request ID / correlation ID (for tracing across services)
- Service version / deployment ID
- User/session context (anonymized)
- Duration for all external calls
- All errors with stack traces

---

## Distributed Tracing `[I]`

Traces show how a single request flows through multiple services.

**Key concepts:**
- **Trace** — the full journey of a request
- **Span** — a single operation within a trace (has start time, duration, metadata)
- **Parent/child spans** — represent service-to-service calls
- **TraceID** — 128-bit ID propagated across all service boundaries (W3C `traceparent` header)

**OpenTelemetry (OTEL)** is the standard. Instrument once, export to any backend.

```
Trace: user-checkout (120ms)
├── auth-service (5ms)
├── inventory-service (30ms)
│   └── postgres-query (25ms)
└── payment-service (80ms)  ← bottleneck
    └── stripe-api (78ms)
```

→ See [OpenTelemetry deep dive](opentelemetry.md) — architecture, sampling, instrumentation code, Collector config, backends.

---

## Dashboards `[I]`

### Dashboard Design Principles

1. **USE Method** (for resources: CPU, disk, network):
   - **U**tilization — % time resource is busy
   - **S**aturation — queued/waiting work
   - **E**rrors — error events

2. **RED Method** (for services):
   - **R**ate — requests per second
   - **E**rrors — failed requests per second
   - **D**uration — distribution of response times

3. Layout:
   - Top: overall health (SLO status, error budget)
   - Middle: golden signals
   - Bottom: per-component breakdown

### Grafana Tips
- Use variables for environment/service/region filtering
- Annotate deployments on graphs
- Link panels to runbooks

---

## Alerting `[I]`

### Alert Design

Good alerts are:
- **Actionable** — someone must do something
- **Accurate** — low false-positive rate
- **Timely** — fires before users are impacted
- **Clear** — tell you what broke, link to runbook

### Alert Anti-patterns
- Alerting on causes instead of symptoms (alert on high error rate, not high CPU)
- Too many low-severity pages → alert fatigue
- No runbook link
- Alerts that auto-resolve without investigation

### Burn Rate Alerts vs Threshold Alerts

Prefer burn rate alerts for SLO-based alerting (see [SLO page](slo-sla-sli.md#burn-rate-alerting)).

---

## Observability Maturity `[A]`

```
Level 1: Basic logging + uptime checks
Level 2: Metrics dashboards, threshold alerts
Level 3: Golden signals, structured logs, SLO-based alerting
Level 4: Distributed tracing, anomaly detection
Level 5: Continuous profiling, real-user monitoring (RUM)
```

---

## Tools Reference

| Tool | Category | Notes |
|------|----------|-------|
| Prometheus | Metrics | Pull-based, PromQL |
| Grafana | Visualization | Works with any datasource |
| Loki | Logs | Prometheus-like for logs |
| Jaeger | Tracing | Open source, OTEL native |
| Datadog | All-in-one | SaaS, expensive but powerful |
| New Relic | All-in-one | SaaS |
| OpenTelemetry | Instrumentation | Vendor-neutral standard |
| PagerDuty | Alerting/On-call | See [On-Call](on-call.md) |
| Atlas | Metrics (Netflix) | Open-sourced, extreme scale |
| M3 | Metrics (Uber) | Open-sourced, high cardinality |

## Useful CLI Tools for Observability `[I]`

From [book-of-secret-knowledge](../resources/book-of-secret-knowledge/README.md):

```bash
# Network diagnostics
mtr --report google.com              # traceroute + ping combined
ss -tlnp                             # show listening sockets (faster than netstat)
tcpdump -i eth0 -n port 5432        # capture DB traffic
nmap -sV -p 80,443,5432 host        # port scan with service detection

# System performance
htop                                 # interactive process viewer
iostat -x 1                          # disk I/O statistics
vmstat 1                             # virtual memory stats
sar -n DEV 1                         # network interface stats
perf top                             # CPU profiling (Linux)

# Log analysis
lnav /var/log/app.log                # log file navigator with SQL queries
jq '.level == "ERROR"' app.log       # filter structured JSON logs
goaccess access.log --log-format=COMBINED  # web log analyzer

# HTTP debugging
curl -w "@curl-format.txt" -o /dev/null -s https://api.example.com
httpie GET https://api.example.com   # friendlier than curl
```

---

## Related Topics

- [SLOs / SLIs / SLAs](slo-sla-sli.md)
- [Incident Management](incident-management.md)
- [On-Call & Runbooks](on-call.md)
- [DBRE: Performance Tuning](../dbre/performance.md)
- [book-of-secret-knowledge](../resources/book-of-secret-knowledge/README.md) — CLI tools and one-liners
