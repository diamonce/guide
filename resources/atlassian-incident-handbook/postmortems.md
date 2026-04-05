# Atlassian Incident Management Handbook — Chapter 3: Incident Postmortems

> Source: Atlassian Incident Management Handbook (©2019 Atlassian, Inc.)
> PDF: https://pages.eml.atlassian.com/rs/594-ATC-127/images/Atlassian-incident-management-handbook-.pdf
> Web: https://www.atlassian.com/incident-management/handbook/postmortems

**Intended use in this guide:** Reference for DB postmortem analysis. The fields, Five Whys technique,
proximate vs. root cause framework, and action categories apply directly to database incident reviews.

---

## What is a postmortem?

A postmortem is a written record of an incident that describes:

- The incident's impact
- The actions taken to mitigate or resolve the incident
- The incident's causes
- Follow-up actions taken to prevent the incident from happening again

> A postmortem seeks to maximize the value of an incident by understanding all contributing causes,
> documenting the incident for future reference and pattern discovery, and enacting effective
> preventative actions to reduce the likelihood or impact of recurrence.
>
> If you think of an incident as an unscheduled investment in the reliability of your system,
> then the postmortem is how you maximize the return on that investment.

---

## When is a postmortem needed?

Always for **severity 1 and 2 ("major") incidents**. Optional for minor incidents.

---

## Who completes the postmortem?

The team that delivers the service that caused the incident nominates one **postmortem owner** — the
person accountable for completing the postmortem through drafting, approval, and publication.

For infrastructure/platform-level incidents (like database outages), a dedicated program manager may
own the postmortem because these incidents cut across multiple teams.

---

## Why should postmortems be blameless?

Blame jeopardizes the success of the postmortem because:

- When people fear career consequences, they hide the truth to protect themselves
- Blaming individuals creates a culture of fear and distrust
- The right question is not "why did person X do this" but **"why did the system allow them to do this,
  or lead them to believe this was the right thing to do"**

**Techniques to create personal safety:**

- Open every postmortem meeting by stating it is blameless and why
- Refer to individuals by role (e.g., "the on-call DB engineer") instead of name
- Frame the timeline, causal chain, and mitigations in terms of systems, processes, and roles — not individuals

> Inspiration: John Allspaw's "Blameless PostMortems and a Just Culture"
> https://codeascraft.com/2012/05/22/blameless-postmortems/

---

## Postmortem process overview

**Key principles:**
- **Single-point accountability** — the postmortem ticket assignee is always accountable
- **Face-to-face meetings** — speeds up analysis and builds shared understanding
- **Engineering leadership review and approval** — sets the right level of rigor
- **SLO for completion** — significant mitigations have an agreed deadline (8 weeks typical)

**Steps the postmortem owner follows:**

1. Create a postmortem ticket and link it to the incident ticket
2. Complete the postmortem issue fields (see below)
3. Use Five Whys to traverse the causal chain and discover underlying causes
4. Prepare a theory of what happened vs. the ideal sequence, and list proposed mitigations
5. Schedule the postmortem meeting; invite the delivery team, impacted teams, and stakeholders
6. Run the meeting (see agenda below)
7. Follow up with engineering managers for time-bound commitments to actions
8. Raise a ticket for each action in the owning team's backlog; link from the postmortem
9. Add approvers to the postmortem ticket and request approval
10. Follow up with approvers until approved
11. Publish the postmortem (Atlassian uses a Confluence blog post)

---

## Postmortem issue fields

| Field | Instructions | Example |
|-------|-------------|---------|
| **Incident summary** | Summarize in a few sentences: severity, what happened, how long | "Between 14:30–15:00, N customers experienced X. Triggered by deployment at T. Detected by [system]. Mitigated by [action]." |
| **Leadup** | Circumstances that led to this incident — prior changes that introduced latent bugs | "At T on D, a change was introduced to [service] that caused [impact]." |
| **Fault** | What didn't work as expected; attach graphs/data | "N responses were incorrectly sent to X% of requests over [time period]." |
| **Impact** | What customers experienced; how many; support cases raised | "For N minutes, X% of customers experienced [symptoms]. N support tickets raised." |
| **Detection** | How and when detected; how to cut detection time in half | "Incident detected when [alert] fired and [team] was paged. Delayed by [reason]." |
| **Response** | Who responded, when, how; delays or barriers | "After being paged at T, engineer came online at T+4m. Escalation needed because [reason]." |
| **Recovery** | How and when service was restored; how to cut recovery time in half | Describe the sequence of actions that restored service. |
| **Timeline** | Detailed chronological timeline, timestamped with timezone | Include: leadup, start of impact, detection, escalations, decisions, changes, end of impact. |
| **Five Whys** | Apply Five Whys root cause technique; document as a numbered list or diagram | 1. Service went down because DB was locked. 2. Because too many DB writes. 3. Because change increased writes unexpectedly. 4. Because no load testing process. 5. Because we've never hit this scale before. |
| **Root cause** | The thing that needs to change to stop this class of incident recurring | "A bug in [service] connection pool handling led to leaked connections under failure conditions." |
| **Backlog check** | Was there anything in the backlog that would have prevented this? Why wasn't it done? | Honest assessment of past prioritization decisions. |
| **Recurrence** | Has this root cause caused incidents before? If yes, why did it happen again? | "Same root cause resulted in incidents HOT-13432, HOT-14932." |
| **Lessons learned** | What went well, what could have gone better, where did we get lucky? | Three numbered lessons. |
| **Corrective actions** | What are we doing to prevent recurrence? Who owns each? By when? | Numbered list with owner and due date for each action. |

---

## Proximate vs. root causes

> Finding the optimal place in the chain of events is the real art of a postmortem.
> Use Five Whys to go "up the chain" and find root causes.

| Term | Definition |
|------|-----------|
| **Proximate cause** | The reason that directly led to this incident |
| **Root cause** | The optimal place in the chain of events where a change will prevent this *entire class* of incident |

**Examples:**

| Scenario | Proximate cause & action | Root cause | Root cause mitigation |
|----------|--------------------------|------------|----------------------|
| Services had no monitoring/alerting | Configure monitoring for these services | No process for standing up new services with monitoring | Create a process for standing up new services and teach the team |
| Logs not reaching logging service | Incorrect role provided. Correct the role. | Can't tell when logging from an environment isn't working | Add monitoring and alerting on missing logs for any environment |
| AWS fault caused connection pool exhaustion | Get the AWS postmortem | Bug in connection pool handling led to leaked connections under failure conditions, combined with lack of visibility | Fix the bug and add monitoring to detect similar situations before they have impact |

---

## Categories of causes

| Category | Definition | What to do |
|----------|-----------|------------|
| **Bug** | A code change by the team | Test. Canary deploys. Incremental rollouts. Feature flags. |
| **Change** | A non-code change (config, infrastructure, process) | Improve change review and change management processes. |
| **Scale** | Failure to scale — blind to resource constraints or lack of capacity planning | Monitor and alert on resource constraints. Build a capacity plan. |
| **Architecture** | Design misalignment with operational conditions | Review your design. Consider platform changes. |
| **Dependency** | Third-party service fault | Manage risk: build resilience or accept and plan for occasional outages. |
| **Unknown** | Indeterminable cause | Improve observability: add logging, monitoring, debugging. |

---

## Root causes with external dependencies (SLE framework)

When an external dependency (AWS, cloud provider, SaaS vendor) fails:

- **SLE (Service Level Expectation)** — your reasonable expectation of the external service's reliability
- SLAs from suppliers are often too minimal or toothless to be useful in practice

| SLE result | What to do |
|------------|-----------|
| **SLE exceeded** (external performed worse than expected) | Review their postmortem. Adjust expectations downward and increase resilience. If unacceptable, change providers. |
| **SLE met** (external performed as expected, but we were impacted anyway) | We need to build resilience to this type of failure — it's our problem to solve. |
| **No SLE defined** | The service owner must establish and communicate an SLE so dependent teams know what resilience to build. |

---

## Postmortem actions

Actions should address: short-term fix AND long-term prevention.

| Category | Question | Examples |
|----------|----------|---------|
| **Investigate** | What happened and why? | Logs analysis, request path diagramming, heap dumps |
| **Mitigate this incident** | What immediate actions did we take? | Rolling back, pushing configs, communicating with users |
| **Repair damage** | How did we resolve collateral damage? | Restoring data, fixing machines, removing traffic re-routes |
| **Detect future incidents** | How do we decrease time to detect similar failures? | Monitoring, alerting, plausibility checks |
| **Mitigate future incidents** | How do we reduce severity/duration of future similar incidents? | Graceful degradation, dashboards, playbooks, process changes |
| **Prevent future incidents** | How do we prevent recurrence? | Stability improvements, better tests, input validation, provisioning changes |

> "Mitigate future incidents" and "Prevent future incidents" are your most likely source of actions
> that address the root cause. Be sure to get at least one of these.

**Well-crafted actions are:**

- **Actionable** — phrase as a sentence starting with a verb; results in a useful outcome, not a process.
  ("Enumerate the list of critical dependencies" ✓ vs. "Investigate dependencies" ✗)
- **Specific** — scope as narrowly as possible; make clear what is and is not included
- **Bounded** — indicate how to tell when it is finished

**Examples of improving action wording:**

| Weak | Strong |
|------|--------|
| Investigate monitoring for this scenario | Add alerting for all cases where this service returns >1% errors |
| Fix the issue that caused the outage | Handle invalid postal code in user address form input safely |
| Make sure engineer checks DB schema can be parsed before updating | Add automated pre-submit check for schema changes |

---

## Postmortem meeting

**Convene once:** the postmortem owner has completed the issue fields and developed a strong theory of causes.

**Standard agenda:**

1. Open by stating this is a blameless postmortem and why
2. Walk through the timeline of events; add or correct as needed
3. Present theory of incident causes and proposed mitigations; build shared understanding
4. Generate actions using **open thinking** ("What could we do to prevent this class of incident?")
   — avoid **closed thinking** ("Why weren't we monitoring system X?")
5. Ask: "What went well / What could have gone better / Where did we get lucky?"
6. Thank everyone for their time and input

**After the meeting:** follow up with managers to get time-bound commitments to actions — the meeting
is a poor context for prioritization decisions.

**Invitation template:**
> Please join me for a blameless postmortem of [link to incident], where we [summary of incident].
> The goal is to understand all contributing causes, document the incident for future reference,
> and decide on actions to reduce the likelihood or impact of recurrence.

---

## Postmortem approvals

Approvers (service owners, managers) confirm:

1. Agreement with the root cause finding
2. Agreement that the "Priority Actions" are an acceptable way to address it

Approvers often identify additional actions or causal chains not covered by proposed actions —
this adds significant value to the process.

---

## Tracking postmortem actions

- **Priority Action** — significant mitigations addressing the root cause (must be completed)
- **Improvement Action** — other improvements identified during the postmortem

Track all actions in your issue tracker (Jira, Linear, etc.) linked from the postmortem issue.
This allows tracking which incidents still represent a risk of recurrence.

---

## DB-specific application notes

When applying this framework to database incidents:

- **Five Whys for DB incidents** often surface: missing monitoring, connection pool configuration,
  runbook gaps, or query/schema changes without adequate testing
- **Detection** field: for DB incidents, common detection failures are alert threshold too high,
  missing replication lag alerts, or no backup verification alerts
- **Proximate vs. root cause**: a slow query causing an outage is proximate;
  the root cause is usually "no slow query alerting" or "no query review in migration process"
- **Backlog check**: was there a known issue (index bloat, autovacuum behind, disk growth)
  that was deprioritized?
- **Categories**: most DB incidents fall into Bug (schema migration), Change (config change),
  Scale (unexpected growth), or Architecture (connection pooling design)

---

## Related topics

- [DBRE Observability](../../dbre/observability.md) — monitoring stack to detect DB incidents early
- [DBRE Backup & Recovery](../../dbre/backup-recovery.md) — DR playbooks
- [DBRE Migrations](../../dbre/migrations.md) — migration failure recovery
- [SRE Incident Management](../../sre/incident-management.md) — incident response process
