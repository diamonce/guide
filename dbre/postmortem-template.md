# Database Postmortem Template

[← DBRE Home](README.md) | [← Main](../README.md)

> **Use for: operational failures** — outage, failover, replication break, backup failure.
> Blameless. Use roles not names. → [Handbook](../resources/atlassian-incident-handbook/postmortems.md)

---

| Field | Value |
|-------|-------|
| ID | PM-YYYY-NNN |
| Date | YYYY-MM-DD |
| Severity | SEV1 / SEV2 / SEV3 |
| DB / Cluster | |
| Owner | |
| Status | Draft / In Review / Approved |

---

## Summary
> What failed, duration, how detected, how resolved. 3–5 sentences.

---

## Timeline

| Time (UTC) | Event |
|-----------|-------|
| | Leadup (change, job, config that created the condition) |
| | Fault began |
| | Detected |
| | Mitigation started |
| | Service restored |

Detection gap: ___ &nbsp;&nbsp; Response gap: ___

---

## Five Whys

1. Why did users/services experience impact? →
2. Why? →
3. Why? →
4. Why? →
5. Why? →

**Root cause:**

**Category:** `Bug` / `Change` / `Scale` / `Architecture` / `Dependency` / `Unknown`
**DB sub-type:** `Connection handling` / `Replication` / `Mount/storage` / `Migration` / `Backup` / `Config drift` / `Monitoring gap`

---

## Impact

| Duration | Systems affected | Users affected | Data loss | Replication impacted |
|----------|-----------------|---------------|-----------|---------------------|
| | | | Yes / No | Yes / No |

---

## Corrective Actions
> Actionable (verb + outcome) · Specific · Bounded (definition of done). At least one must address root cause.

| # | Category | Action | Owner | Due | Ticket |
|---|----------|--------|-------|-----|--------|
| 1 | Prevent | | | | |
| 2 | Detect | | | | |
| 3 | Mitigate | | | | |

`Investigate` · `Mitigate this incident` · `Repair damage` · `Detect future` · `Mitigate future` · `Prevent future`

---

## Lessons Learned

| Went well | Could have gone better | Got lucky |
|-----------|----------------------|-----------|
| | | |

---

## Approval

| Approver (role) | Root cause agreed | Actions agreed | Date |
|----------------|------------------|---------------|------|
| | ☐ | ☐ | |
