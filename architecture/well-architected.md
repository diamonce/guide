# Well-Architected Frameworks

[← Architecture Home](README.md) | [← Main](../README.md)

AWS, GCP, and Azure each publish a Well-Architected Framework. Different names, nearly identical pillars. This page maps all three, extracts the most actionable checks, and gives you the review process.

---

## The Pillars — All Three Clouds

| Pillar | AWS | GCP | Azure |
|--------|-----|-----|-------|
| **Operational Excellence** | ✅ | ✅ | ✅ |
| **Security** | ✅ | ✅ | ✅ |
| **Reliability** | ✅ | ✅ | ✅ |
| **Performance Efficiency** | ✅ | ✅ | ✅ |
| **Cost Optimization** | ✅ | ✅ | ✅ |
| **Sustainability** | ✅ (added 2021) | ✅ | ✅ |

Official docs:
- AWS: [docs.aws.amazon.com/wellarchitected](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- GCP: [cloud.google.com/architecture/framework](https://cloud.google.com/architecture/framework)
- Azure: [learn.microsoft.com/azure/well-architected](https://learn.microsoft.com/en-us/azure/well-architected/)

---

## Pillar 1 — Operational Excellence

> Run and monitor systems to deliver business value and continually improve processes.

### Key Principles

- **Everything as code** — infrastructure, config, runbooks, alerts. If it's not in Git, it doesn't exist.
- **Annotate and document** — every system must have an owner, an on-call rotation, and a runbook.
- **Make frequent, small, reversible changes** — deploy often, roll back fast.
- **Anticipate failure** — game days, chaos injection, runbook drills.
- **Learn from all operational events** — every incident produces a blameless postmortem.

### Checks

- [ ] All infrastructure defined in Terraform / IaC
- [ ] Deployments are automated, no manual SSH-and-change
- [ ] Every service has a runbook linked from its alert
- [ ] Rollback takes < 5 minutes
- [ ] On-call rotation documented and tested
- [ ] Metrics and dashboards exist before launch, not after the first incident

---

## Pillar 2 — Security

> Protect information, systems, and assets.

### Key Principles

- **Implement a strong identity foundation** — centralized identity (SSO), MFA enforced, no shared accounts.
- **Apply least privilege** — see [Best Practices → Least Privilege](best-practices.md).
- **Enable traceability** — every action logged, logs immutable, alerts on anomalies.
- **Automate security best practices** — SCPs, policy-as-code (OPA, Sentinel), GuardDuty, Security Hub.
- **Protect data in transit and at rest** — TLS everywhere, encryption at rest mandatory.
- **Prepare for security events** — incident response runbook, IR retainer, breach notification plan.

### Checks

- [ ] MFA enforced for all human accounts — no exceptions
- [ ] No long-lived IAM access keys (use roles, IRSA, Workload Identity)
- [ ] Root account has no access keys and is not used for daily work
- [ ] CloudTrail / Audit Log / Activity Log enabled in all regions
- [ ] Secrets in Secrets Manager or Vault — never in environment variables or code
- [ ] S3 buckets / GCS / Blob Storage: block public access unless explicitly required
- [ ] VPC / VNet: no 0.0.0.0/0 ingress rules to databases or internal services
- [ ] Vulnerability scanning in CI pipeline (Trivy, Snyk, Dependabot)
- [ ] Penetration test completed in the last 12 months for production systems

---

## Pillar 3 — Reliability

> Ensure a workload performs its intended function correctly and consistently.

### Key Principles

- **Automatically recover from failure** — health checks, auto-healing, auto-scaling, automated failover.
- **Test recovery procedures** — don't find out your backup is corrupt during an incident.
- **Scale horizontally** — add more instances, not bigger ones.
- **Stop guessing capacity** — auto-scaling based on real metrics.
- **Manage change in automation** — runbooks for changes, not ad-hoc SSH sessions.

### Key Reliability Targets

| Availability | Downtime / year | Downtime / month |
|-------------|----------------|-----------------|
| 99% | 3.65 days | 7.2 hours |
| 99.9% | 8.7 hours | 43 minutes |
| 99.95% | 4.4 hours | 21 minutes |
| 99.99% | 52 minutes | 4.3 minutes |
| 99.999% | 5.3 minutes | 26 seconds |

→ Cross-reference: [SRE SLOs](../sre/slo-sla-sli.md) for how to define and measure these.

### Checks

- [ ] SLOs defined and measured for every user-facing service
- [ ] Multi-AZ deployment for all stateful services
- [ ] Database automated backups tested with restore verification
- [ ] Auto-scaling configured with realistic min/max bounds
- [ ] Chaos engineering runbook exists and has been run in the last quarter
- [ ] Dependencies on external services have circuit breakers and fallbacks
- [ ] Failover tested — don't assume it works until you've proven it

---

## Pillar 4 — Performance Efficiency

> Use resources efficiently to meet system requirements and maintain that efficiency as demand changes.

### Key Principles

- **Democratize advanced technologies** — use managed services (RDS, ElastiCache, Kinesis) instead of running your own.
- **Go global in minutes** — CDN, edge caching, multi-region deployment.
- **Use serverless architectures** — Lambda, Cloud Run, Cloud Functions eliminate capacity management for bursty workloads.
- **Experiment more often** — benchmarking is cheap; premature optimization is expensive.
- **Consider mechanical sympathy** — choose the right tool: columnar DB for analytics, cache for hot reads, queue for async work.

### Performance Hierarchy

```
1. Eliminate the work entirely (cache, precompute)
2. Do less work (index, query optimization)
3. Do it faster (right instance type, network proximity)
4. Do it in parallel (horizontal scaling, async queues)
5. Do it closer to the user (CDN, edge, read replicas)
```

### Checks

- [ ] Performance baselines measured before launch (p50, p95, p99 latency)
- [ ] Caching strategy defined: CDN for static, Redis/ElastiCache for hot application data
- [ ] Database queries analyzed with EXPLAIN — no full table scans on large tables
- [ ] Right-sized instances — not the largest available "to be safe"
- [ ] CDN in front of all static assets and public APIs

---

## Pillar 5 — Cost Optimization

> Avoid unnecessary costs.

### Key Principles

- **Implement Cloud Financial Management** — someone owns the bill; every team sees their costs.
- **Adopt a consumption model** — pay for what you use, not what you provision.
- **Measure overall efficiency** — cost per transaction, cost per user, cost per GB processed.
- **Stop spending money on undifferentiated heavy lifting** — managed services pay for themselves in engineering time.
- **Analyze and attribute expenditure** — tag everything; charge back to teams.

### High-Impact Cost Actions

```
1. Reserved Instances / Committed Use → 40–70% savings on stable workloads
2. Spot / Preemptible instances → 70–90% savings for fault-tolerant batch
3. Right-sizing → eliminate instances running at < 20% CPU
4. Delete idle resources → unattached EBS volumes, unused EIPs, orphaned snapshots
5. S3 lifecycle policies → move old data to Glacier / Archive
6. NAT Gateway → expensive at scale; use VPC endpoints for AWS services
7. Data transfer → egress costs are real; design to minimize cross-AZ/cross-region traffic
```

### Checks

- [ ] Cost allocation tags enforced via SCP / Organization Policy
- [ ] Cost anomaly detection alerts configured
- [ ] Reserved capacity purchased for production databases and stable compute
- [ ] Spot instances used for CI/CD, batch processing, dev environments
- [ ] S3 / GCS lifecycle rules on all buckets
- [ ] Budget alerts set at 80% and 100% of expected monthly spend

---

## Pillar 6 — Sustainability

> Minimize environmental impacts.

### Key Principles

- **Understand your impact** — measure carbon footprint; cloud providers publish region-level carbon intensity data.
- **Establish sustainability goals** — reduce kWh per unit of work over time.
- **Maximize utilization** — idle compute still burns power; consolidate and right-size.
- **Adopt newer, more efficient hardware** — newer instance generations (e.g., Graviton3) deliver more compute per watt.
- **Use managed services** — cloud providers optimize utilization at scale better than individual tenants can.

### Quick Wins

```
→ Move batch workloads to low carbon-intensity regions (AWS Carbon Footprint Tool)
→ Use Graviton (AWS) / Tau T2D (GCP) instances — better performance per watt
→ Serverless for bursty workloads — zero compute when idle
→ Delete what you don't use — storage and compute both have carbon cost
```

---

## AWS Well-Architected Tool

AWS offers a free tool to run structured reviews against the framework.

```bash
# Via CLI: create a workload and run a review
aws wellarchitected create-workload \
  --workload-name "order-service" \
  --description "Order processing microservice" \
  --review-owner "platform-team@company.com" \
  --environment PRODUCTION \
  --aws-regions us-east-1 eu-west-1 \
  --lenses "wellarchitected"

# List all lens review questions
aws wellarchitected list-answers \
  --workload-id <workload-id> \
  --lens-alias "wellarchitected"
```

Run a review:
1. [console.aws.amazon.com/wellarchitected](https://console.aws.amazon.com/wellarchitected/)
2. Create workload → select lenses → answer ~58 questions across all 6 pillars
3. Review generates a report with High/Medium risk findings and improvement plan

→ Full question list: [AWS WAF Appendix — Questions and Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/framework/appendix.html)

---

## GitHub Well-Architected

GitHub publishes its own Well-Architected library covering reliability, security, operations, and governance for GitHub-hosted systems.

→ [github-well-architected](../resources/github-well-architected/README.md)
→ [Platform External Links — Governance](../platform/external-links.md)

Key GitHub-specific areas:
- Branch protection and rulesets
- CODEOWNERS for automatic review assignment
- Secret scanning and push protection
- Audit log streaming to SIEM
- Required workflows at org level

---

## Related Topics

- [Landing Zones](landing-zones.md) — cloud foundation that implements security and reliability pillars
- [Best Practices](best-practices.md) — blast radius, least privilege, scalability
- [SRE SLOs](../sre/slo-sla-sli.md) — reliability pillar in practice
- [Platform Security](../platform/security.md) — security pillar implementation
- [Platform Terraform](../platform/terraform.md) — operational excellence pillar in IaC
