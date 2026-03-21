# Real-World SRE Case Studies

[← SRE Home](README.md) | [← Main](../README.md)

From [howtheysre](../resources/howtheysre/README.md) — how actual companies run reliability engineering.

---

## By Topic

### Incident Management & Postmortems
- **Airbnb** — incident classification and postmortem process at scale
- **Atlassian** — StatusPage and public incident communication
- **Google** — blameless postmortems (origin of the practice)
- **Slack** — incident response automation and runbook tooling
- **PagerDuty** — ironically, their own incident management evolution

### Observability & Monitoring
- **Netflix** — Atlas metrics platform, distributed tracing at scale
- **Uber** — M3 metrics (open-sourced), Jaeger distributed tracing (open-sourced)
- **Shopify** — moving from Nagios to modern observability
- **LinkedIn** — Kafka-based observability pipeline
- **Cloudflare** — handling 50M+ metrics/second

### On-Call & Toil Reduction
- **Google** — defining toil, keeping it < 50% of SRE time
- **Dropbox** — reducing on-call burden through automation
- **GitHub** — ChatOps for incident response (Hubot)
- **Etsy** — "Who's On Call?" tooling, rotation design

### SLOs & Error Budgets
- **Google** — origin of SLOs and error budgets (SRE Book)
- **Spotify** — rolling out SLOs org-wide
- **Honeycomb** — observability-driven SLOs
- **CRE program** — Customer Reliability Engineering (Google)

### Chaos Engineering
- **Netflix** — Chaos Monkey, Chaos Kong, FIT (Failure Injection Testing)
- **Amazon** — GameDay exercises, simulating region failures
- **LinkedIn** — Storm (internal chaos platform)
- **Twilio** — chaos engineering in CI pipeline

### Kubernetes & Container Operations
- **Airbnb** — migrating to Kubernetes, Kubernetes at scale
- **Lyft** — Envoy proxy (open-sourced), service mesh adoption
- **Pinterest** — Kubernetes migration from static infrastructure
- **Zalando** — Kubernetes on AWS, open-sourcing multiple K8s operators

### Scalability & Capacity Planning
- **Netflix** — EVCache, regionalized architecture, chaos for capacity testing
- **Twitter** — move from monolith to microservices (the hard lessons)
- **WhatsApp** — 2M connections/server with Erlang
- **Discord** — handling 2.5M concurrent users, Go → Rust for hot paths
- **Instagram** — scaling PostgreSQL to hundreds of millions of users

### Platform Engineering
- **Spotify** — Backstage (open-sourced internal developer portal)
- **Netflix** — Spinnaker (open-sourced continuous delivery)
- **Uber** — internal platform evolution (μDeploy, Peloton)
- **LinkedIn** — LinkedIn's deployment system (LiPS)

---

## By Company (Highlights)

| Company | Key Contribution | Link |
|---------|-----------------|------|
| Netflix | Chaos engineering, Spinnaker, Atlas, EVCache | [howtheysre](../resources/howtheysre/README.md) |
| Google | SRE book, SLOs, error budgets, blameless postmortems | [awesome-sre](../resources/awesome-sre/README.md) |
| Uber | Jaeger tracing, M3 metrics, H3 (spatial) | [howtheysre](../resources/howtheysre/README.md) |
| Airbnb | Kubernetes migration, incident management | [howtheysre](../resources/howtheysre/README.md) |
| Spotify | Backstage IDP, SLO rollout | [howtheysre](../resources/howtheysre/README.md) |
| Lyft | Envoy proxy, service mesh at scale | [howtheysre](../resources/howtheysre/README.md) |
| Cloudflare | Massive observability, global traffic management | [howtheysre](../resources/howtheysre/README.md) |
| Discord | Scaling real-time communication, Rust for performance | [howtheysre](../resources/howtheysre/README.md) |
| GitHub | ChatOps, GitHub Actions (dogfooding), deployment tooling | [howtheysre](../resources/howtheysre/README.md) |

---

## Patterns That Emerge

Reading across companies, these patterns appear consistently:

1. **Toil automation comes before reliability improvement** — manual ops must die first
2. **Internal platforms get open-sourced** — Backstage, Spinnaker, Envoy, Jaeger, M3 all started internal
3. **SLO adoption is a culture change, not just a metric** — requires product buy-in
4. **Chaos engineering scales with confidence** — start small, scope blast radius
5. **On-call health is a leading indicator** — unhealthy on-call = reliability problems downstream
6. **Observability investment always pays off** — MTTD/MTTR drop dramatically

---

## Related Topics

- [Fundamentals](fundamentals.md) — concepts behind the practices
- [Incident Management](incident-management.md)
- [On-Call & Runbooks](on-call.md)
- [Scalability](scalability.md)
- [howtheysre submodule](../resources/howtheysre/README.md) — full company list with links
- [awesome-sre submodule](../resources/awesome-sre/README.md) — curated blog posts and talks
