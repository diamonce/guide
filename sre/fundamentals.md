# SRE Fundamentals

[← SRE Home](README.md) | [← Main](../README.md)

---

## What is SRE? `[B]`

SRE is what you get when you treat operations as a software engineering problem. Coined at Google, it replaces the traditional ops/dev wall with shared ownership of reliability.

**Key principle:** Reliability is a feature. It must be engineered, measured, and traded off against velocity.

### SRE vs DevOps

| | SRE | DevOps |
|--|-----|--------|
| Origin | Google | Community/industry |
| Focus | Reliability metrics, error budgets | Culture, collaboration, automation |
| Role | Distinct SRE team | Embedded or shared responsibility |
| Prescriptiveness | High (specific practices) | Low (principles) |

> SRE is an opinionated implementation of DevOps.

---

## The Four Golden Signals `[B]`

Monitor these for any user-facing service:

1. **Latency** — how long requests take (distinguish successful vs failed)
2. **Traffic** — how much demand (RPS, QPS, concurrent users)
3. **Errors** — rate of failed requests (explicit 5xx, implicit wrong data)
4. **Saturation** — how "full" the service is (CPU, memory, queue depth)

→ See [Observability](observability.md) for how to instrument these.

---

## Error Budgets `[B]`

If your SLO is 99.9% availability → you have **0.1% error budget** = ~43 min/month downtime.

- Budget remaining → ship features faster, take risks
- Budget exhausted → freeze releases, focus on reliability

**Why this matters:** It turns reliability into a shared business decision, not a blame game.

→ See [SLOs / SLIs / SLAs](slo-sla-sli.md) for how to define and track these.

---

## Toil `[I]`

Toil = manual, repetitive, automatable operational work that scales with traffic.

**Characteristics of toil:**
- Manual
- Repetitive
- Automatable
- Tactical (not strategic)
- No enduring value
- Grows as service grows

**SRE goal:** Keep toil < 50% of work. The rest = engineering (reducing future toil).

**Common toil examples:**
- Manually restarting pods/services
- Responding to false-positive alerts
- Manual certificate rotations
- Hand-editing config files per deployment

---

## Reliability Hierarchy `[I]`

Before worrying about features, nail these in order:

1. **Monitoring** — know when things break
2. **Incident response** — fix things fast
3. **Postmortems** — learn from failures (blameless)
4. **Testing & release** — catch problems before prod
5. **Capacity planning** — don't run out of runway
6. **Efficiency** — do more with less

→ [Incident Management](incident-management.md) | [On-Call](on-call.md)

---

## Cognitive Load & Oncall Health `[I]`

Signs of an unhealthy SRE practice:
- Alert fatigue (> 5 pages/shift)
- No time for project work
- Incidents repeat without postmortems
- On-call == firefighting, not engineering

→ See [On-Call & Runbooks](on-call.md)

---

## Chaos Engineering `[A]`

Intentionally inject failures to build confidence in the system's resilience.

**Principles:**
1. Define steady state (normal behavior)
2. Hypothesize it continues in both control and experiment groups
3. Introduce realistic failure variables (kill a pod, inject latency, drop a region)
4. Disprove the hypothesis

**Tools:** Chaos Monkey, Litmus, Gremlin, AWS Fault Injection Simulator

→ Related: [Scalability](scalability.md)

---

## Related Topics

- [SLOs / SLIs / SLAs](slo-sla-sli.md)
- [Observability](observability.md)
- [Incident Management](incident-management.md)
- [Platform: Kubernetes](../platform/kubernetes.md)
- [devops-exercises Q&A](../resources/devops-exercises/README.md)
