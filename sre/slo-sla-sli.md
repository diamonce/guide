# SLOs, SLIs, and SLAs

[← SRE Home](README.md) | [← Main](../README.md)

---

## The Three Acronyms `[B]`

| Term | Full Name | Owner | Audience |
|------|-----------|-------|----------|
| **SLI** | Service Level Indicator | Engineering | Internal |
| **SLO** | Service Level Objective | Engineering | Internal |
| **SLA** | Service Level Agreement | Business/Legal | External (customers) |

---

## SLI — What You Measure `[B]`

An SLI is a quantitative measure of a service behavior.

**Good SLI formula:**
```
SLI = (good events / total events) × 100
```

**Examples:**
- `successful HTTP requests / total HTTP requests` → availability
- `requests < 200ms / total requests` → latency
- `correct responses / total responses` → correctness
- `processed jobs / attempted jobs` → throughput

**What makes a good SLI:**
- Directly reflects user experience
- Measurable in production
- Has a clear definition of "good" vs "bad"

→ See [Observability](observability.md) for instrumentation.

---

## SLO — What You Target `[B]`

An SLO is the target value for an SLI over a time window.

```
SLO: 99.9% of requests return HTTP 2xx over a 30-day rolling window
```

**Time windows:**
- Rolling (last 30 days) — more responsive to current behavior
- Calendar (monthly/quarterly) — easier to reason about for business

**Choosing a target:**
- Start with what users actually need, not what sounds impressive
- 99.9% ≠ always better than 99% — higher SLOs cost more to maintain
- Leave room for an error budget

**Error Budget:**
```
Error Budget = 1 - SLO
99.9% SLO → 0.1% budget → 43.8 min/month
99.5% SLO → 0.5% budget → 3.65 hrs/month
99.0% SLO → 1.0% budget → 7.3 hrs/month
```

→ See [Fundamentals: Error Budgets](fundamentals.md#error-budgets)

---

## SLA — What You Promise `[I]`

An SLA is a contract with a customer. If violated, there are consequences (refunds, credits).

**SLA < SLO (always):**

```
SLO: 99.9%  ←  internal target
SLA: 99.5%  ←  customer promise (more conservative)
```

The gap between SLO and SLA is your buffer for incidents before customer impact triggers penalties.

---

## Defining SLOs in Practice `[I]`

### Step 1: Identify critical user journeys
- Login flow, checkout, data export, API response

### Step 2: Pick SLIs per journey
- Availability SLI: % successful requests
- Latency SLI: % requests under threshold (e.g., p99 < 500ms)

### Step 3: Set targets
- Look at historical data
- Ask: "At what point do users complain?"
- Start conservative — tighten as you learn

### Step 4: Implement tracking
- Prometheus + Grafana, Datadog, New Relic, Google Cloud Monitoring

### Step 5: Set up alerting on burn rate
- Alert when you're consuming error budget too fast (not when you cross the SLO)

---

## Burn Rate Alerting `[A]`

Burn rate = how fast you're consuming error budget vs the expected rate.

```
Burn Rate = (error rate) / (1 - SLO)

Example:
SLO = 99.9% → error budget = 0.1%
If error rate = 1% → burn rate = 10x
At 10x burn: 30-day budget exhausted in 3 days
```

**Multi-window alerting (Google approach):**

| Window | Burn Rate | Severity |
|--------|-----------|----------|
| 1h + 5m | > 14.4x | Page immediately |
| 6h + 30m | > 6x | Page (business hours) |
| 3d + 6h | > 1x | Ticket |

---

## Common Mistakes `[I]`

- Setting SLOs based on what's easy to measure, not user experience
- 100% SLO (impossible, prevents all deployments)
- SLO = SLA (no buffer for incidents)
- Not sharing SLOs with product/business teams
- Ignoring the error budget — tracking it but not acting on it

---

## Related Topics

- [Fundamentals: Error Budgets](fundamentals.md#error-budgets)
- [Observability](observability.md)
- [Incident Management](incident-management.md)
- [awesome-sre resources](../resources/awesome-sre/README.md)
