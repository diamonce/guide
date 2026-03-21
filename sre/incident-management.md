# Incident Management

[← SRE Home](README.md) | [← Main](../README.md)

---

## Incident Lifecycle `[B]`

```
Detection → Triage → Mitigation → Resolution → Postmortem
```

---

## Severity Levels `[B]`

Define these clearly so everyone knows the response expectations:

| Severity | User Impact | Response Time | Example |
|----------|-------------|---------------|---------|
| **SEV1** | Complete outage | Immediate, 24/7 | Site down, data loss |
| **SEV2** | Major feature broken | < 30 min, 24/7 | Checkout failing, login broken |
| **SEV3** | Partial degradation | Business hours | Slow reports, minor feature down |
| **SEV4** | Minimal impact | Next sprint | Cosmetic bug, edge-case failure |

---

## Detection `[B]`

Sources of incident detection:
1. Monitoring alert fires → pager (PagerDuty, OpsGenie)
2. User/customer report → support ticket
3. Internal report → Slack/chat
4. Automated health check fails

**Minimize time-to-detect:**
- SLO-based burn rate alerts (not just threshold alerts)
- Synthetic monitoring / uptime checks
- RUM (Real User Monitoring)

→ See [Observability: Alerting](observability.md#alerting)

---

## Triage `[I]`

First 5 minutes of an incident:

1. **Acknowledge** the alert — stop the pager
2. **Assess scope** — how many users affected? Which services?
3. **Set severity** — based on impact matrix above
4. **Declare incident** — create incident channel (#inc-YYYYMMDD-service)
5. **Assign roles**:
   - **Incident Commander (IC)** — coordinates, drives to resolution
   - **Technical Lead** — digs into the problem
   - **Comms Lead** — updates stakeholders

**IC does NOT debug.** IC coordinates.

---

## Mitigation vs Resolution `[I]`

| | Mitigation | Resolution |
|--|------------|------------|
| Goal | Stop user impact | Fix root cause |
| Speed | As fast as possible | Thorough |
| Examples | Rollback, feature flag off, redirect traffic | Fix bug, patch infra, update config |

**Prioritize mitigation over root cause analysis during the incident.**

Common mitigations:
- `kubectl rollout undo deployment/my-service`
- Disable feature flag
- Scale up horizontally
- Failover to backup region
- Rate-limit or shed load
- Restore from backup (DBRE → see [Backup & Recovery](../dbre/backup-recovery.md))

---

## Communication During Incidents `[I]`

**Internal (Slack/Teams):**
- Single incident channel, named consistently
- Status updates every 15-30 min: `[UPDATE 14:35] Still investigating. Auth service logs show DB timeouts. Working on mitigation.`
- No blame, no speculation

**External (Status Page):**
- Update status page within 5-10 min of SEV1/SEV2
- Be honest but avoid technical jargon
- Update every 30 min minimum

**Escalation:**
- Page the on-call expert for the affected component
- Loop in management for SEV1 > 30 min

---

## Postmortems `[I]`

A postmortem is a blameless written analysis done after every SEV1/SEV2.

### Blameless Culture

People make mistakes. The system allowed the mistake to have impact. Fix the system.

> "We don't punish people for making mistakes. We fix the conditions that made the mistake possible."

### Postmortem Template

```markdown
## Incident: [title]
**Date:** YYYY-MM-DD
**Duration:** X hours Y min
**Severity:** SEV1/SEV2
**Author(s):**

## Summary
[2-3 sentence summary of what happened, impact, and resolution]

## Timeline
| Time | Event |
|------|-------|
| 14:00 | Alert fired for elevated error rate |
| 14:03 | On-call acknowledged |
| 14:15 | Root cause identified (bad deploy) |
| 14:20 | Rollback initiated |
| 14:25 | Service restored |

## Root Cause
[Describe the technical root cause]

## Contributing Factors
- [Factor 1]
- [Factor 2]

## Impact
- Users affected: ~5,000
- Duration: 25 minutes
- Revenue impact: ~$X

## What Went Well
- Detection was fast (3 min from alert to ack)
- Runbook was accurate

## What Went Poorly
- No canary deployment caught this
- Alert was too noisy, delayed response

## Action Items
| Action | Owner | Due |
|--------|-------|-----|
| Add canary deployment step | @alice | 2024-02-01 |
| Tune alert threshold | @bob | 2024-01-25 |
```

---

## Incident Metrics to Track `[A]`

- **MTTD** — Mean Time to Detect
- **MTTA** — Mean Time to Acknowledge
- **MTTM** — Mean Time to Mitigate
- **MTTR** — Mean Time to Resolve
- **MTBF** — Mean Time Between Failures
- **Incident frequency** — count per week/month by severity

Track these trends over time. Improving MTTD and MTTM has the highest user impact.

---

## Related Topics

- [On-Call & Runbooks](on-call.md)
- [Observability](observability.md)
- [SLOs / SLIs / SLAs](slo-sla-sli.md)
- [DBRE: Backup & Recovery](../dbre/backup-recovery.md)
- [howtheysre](../resources/howtheysre/README.md) — real incident case studies
