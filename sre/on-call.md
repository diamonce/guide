# On-Call & Runbooks

[← SRE Home](README.md) | [← Main](../README.md)

---

## On-Call Basics `[B]`

On-call = you're responsible for responding to production incidents outside business hours.

**Healthy on-call:**
- < 2 incidents per shift that require action
- < 25% of on-call time spent on incidents
- Runbooks exist for all common alerts
- Primary + secondary rotation (backup always available)

**Unhealthy on-call:**
- Alert storms, constant pages
- No runbooks → tribal knowledge only
- Single-person rotation, no backup
- Same incidents repeat (no postmortems)

---

## Rotation Structure `[B]`

```
Week 1:  Alice (primary)  →  Bob (secondary/backup)
Week 2:  Bob   (primary)  →  Carol (secondary)
Week 3:  Carol (primary)  →  Alice (secondary)
```

**Tools:** PagerDuty, OpsGenie, VictorOps

**Best practices:**
- Handoff meeting/notes at rotation change
- Always have a secondary who can be escalated to
- Adjust rotations for time zones (follow-the-sun)
- Compensate on-call fairly (time off, extra pay)

---

## Escalation Policies `[I]`

```
Alert fires
  → Primary on-call (2 min to ack)
  → Secondary on-call (5 min)
  → Engineering Manager (10 min)
  → VP Engineering (15 min, SEV1 only)
```

Configure this in PagerDuty/OpsGenie. Never let an alert die in silence.

---

## Runbooks `[I]`

A runbook is a step-by-step guide for responding to a specific alert.

### Runbook Template

```markdown
# Runbook: [Alert Name]

## Alert
**Name:** high_error_rate_payment_service
**Fires when:** Error rate > 1% for 5 minutes
**Severity:** SEV2

## Impact
Payment processing is degraded. Users cannot complete purchases.

## Quick Checks
1. Check service health: `kubectl get pods -n payments`
2. Check recent deployments: `kubectl rollout history deployment/payment-service`
3. Check DB connectivity: [link to DB dashboard]
4. Check upstream dependencies: [Stripe status page]

## Diagnosis Steps
1. Check error logs:
   ```
   kubectl logs -n payments -l app=payment-service --since=15m | grep ERROR
   ```
2. Check if errors correlate with a recent deploy (check deployment annotation in Grafana)
3. Check DB slow query log → [DBRE runbook link]

## Mitigation Options

### Option A: Rollback (if recent deploy)
```bash
kubectl rollout undo deployment/payment-service -n payments
```
Wait 2 min, verify error rate drops.

### Option B: Scale up (if load-related)
```bash
kubectl scale deployment/payment-service --replicas=10 -n payments
```

### Option C: Disable feature flag
Go to LaunchDarkly → disable `new_payment_flow`

## Resolution
Confirm error rate < 0.1% for 10 minutes. Close incident. File postmortem if SEV1/SEV2.

## Contacts
- Payment team Slack: #team-payments
- DB issues: #team-dbre or [DBRE on-call](../dbre/README.md)
- Stripe issues: [Stripe status](https://status.stripe.com)

## Related Runbooks
- [DB connection pool exhausted](../dbre/fundamentals.md)
- [High latency](../sre/observability.md)
```

---

## Alert Quality `[I]`

Every alert should answer:
1. **What** is broken?
2. **Who** is affected?
3. **What to do** (link to runbook)?

**Alert review checklist:**
- [ ] Has a runbook link
- [ ] Severity is correctly set
- [ ] Not a duplicate of another alert
- [ ] Has been actionable in the last 30 days
- [ ] Fires on symptoms, not causes

**Kill alerts that:**
- Fire repeatedly but resolve on their own
- Require no action
- Are always suppressed/silenced

---

## On-Call Hygiene `[I]`

**Before your shift:**
- Read handoff notes from previous on-call
- Check if there are open incidents/degradations
- Verify your pager is working (test page yourself)
- Make sure laptop is charged, VPN accessible

**During your shift:**
- Keep phone nearby (silent but vibrate) during off-hours
- Log every page and action taken (even if auto-resolved)
- If unsure, escalate — don't hero-debug for 2 hours alone

**After your shift:**
- Write handoff notes
- File tickets for recurring issues
- Propose runbook improvements for anything that confused you

---

## Reducing On-Call Burden `[A]`

Priority order:

1. **Eliminate alert** — is it even necessary?
2. **Automate response** — can a bot handle it?
3. **Improve runbook** — reduce time-to-mitigate
4. **Fix root cause** — so it never fires again
5. **Tune threshold** — reduce false positives

**Auto-remediation examples:**
- Auto-restart pod on OOMKill
- Auto-scale on CPU > 80%
- Auto-rollback on error rate spike post-deploy

---

## Related Topics

- [Incident Management](incident-management.md)
- [Observability: Alerting](observability.md#alerting)
- [SLOs / SLIs / SLAs](slo-sla-sli.md)
- [Platform: CI/CD](../platform/cicd.md) — deploy safety, canary releases
- [devops-exercises](../resources/devops-exercises/README.md)
