# Database Defect Escape Analysis (DEA) Template

[← DBRE Home](README.md) | [← Main](../README.md)

> **Use for: quality gate failures** — a defect existed before production and slipped through.
> Question: *which gate should have caught this and why didn't it?*
> Blameless. Use roles not names.

| Use DEA | Use Postmortem |
|---------|---------------|
| Backup script bug not caught in code review | MySQL failover caused outage |
| Migration caused corruption staging didn't catch | Replication lag exceeded SLO |
| Schema change deployed without DBA review | Disk full, backup failed |

---

| Field | Value |
|-------|-------|
| ID | DEA-YYYY-NNN |
| Date introduced | YYYY-MM-DD |
| Date escaped to prod | YYYY-MM-DD |
| Date detected | YYYY-MM-DD |
| Component | e.g. backup script, migration, config change |
| Owner | |
| Status | Draft / In Review / Approved |

---

## Summary
> What was the defect, where introduced, what impact in production. 3–5 sentences.

---

## Escape Timeline

| Stage | Date | Passed / Skipped / Missing |
|-------|------|---------------------------|
| Introduced | | |
| Code review | | |
| Automated tests / CI | | |
| Staging | | |
| DBA / DBRE review | | |
| Change approval | | |
| Escaped to production | | |
| Detected | | How: alert / manual / customer report |

---

## Gate Analysis

| Gate | Existed? | Should have caught it? | Why it didn't |
|------|----------|----------------------|---------------|
| Code review | ☐ | ☐ | |
| Unit / integration tests | ☐ | ☐ | |
| CI pipeline | ☐ | ☐ | |
| Staging environment | ☐ | ☐ | |
| Production-scale data test | ☐ | ☐ | |
| DBA / DBRE review | ☐ | ☐ | |
| Change approval / runbook | ☐ | ☐ | |

**Escape point** (gate that should have caught it):

**Root cause** (why that gate failed — avoid "human error", ask why the process allowed it):

---

## Impact

| Duration | Systems affected | Data integrity impact | Rollback required |
|----------|-----------------|----------------------|------------------|
| | | Yes / No | Yes / No |

---

## Corrective Actions
> Focus on strengthening gates, not just fixing the specific defect. At least one must address the escape point.

| # | Gate | Action | Owner | Due | Ticket |
|---|------|--------|-------|-----|--------|
| 1 | Fix defect | | | | |
| 2 | Escape point | | | | |
| 3 | Add missing gate | | | | |
| 4 | Detect future | | | | |

`Fix defect` · `Strengthen gate` · `Add missing gate` · `Improve detection`

---

## Lessons Learned

| Gate that worked | Gate that should have caught this | Gate we didn't have but should |
|-----------------|----------------------------------|-------------------------------|
| | | |

---

## Approval

| Approver (role) | Escape point agreed | Actions agreed | Date |
|----------------|---------------------|---------------|------|
| | ☐ | ☐ | |
