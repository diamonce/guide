# External Resources — Platform Engineering

[← Platform Home](README.md) | [← Main](../README.md)

---

## Governance & Best Practices

| Resource | What it is |
|----------|-----------|
| [GitHub Well-Architected: Governance Policies Best Practices](https://wellarchitected.github.com/library/governance/recommendations/governance-policies-best-practices/) | GitHub's opinionated recommendations on governance policies — branch protection, required reviews, rulesets, org-level controls. Practical, not theoretical. |
| [github-well-architected (source)](../resources/github-well-architected/README.md) | Full Well-Architected library source — reliability, security, operations, governance content. |

### Key Takeaways from GitHub Well-Architected Governance

**Branch Protection**
- Require pull request reviews before merging (at least 1, ideally 2 for critical repos)
- Require status checks (CI must pass) before merge
- Require branches to be up to date before merging
- Restrict who can push to `main`/`master` directly
- Enable "Require signed commits" for regulated environments

**Rulesets (GitHub's modern branch protection)**
- Apply rules at org level, not per-repo (scales better)
- Target by branch pattern (`main`, `release/*`)
- Enforce across forks too

**Code Owners**
- Use `CODEOWNERS` file to auto-assign reviewers by directory/file type
- Combine with required reviews so the right team always reviews their area

```
# .github/CODEOWNERS
/infrastructure/     @platform-team
/dbre/               @dbre-team
*.tf                 @platform-team
```

**Secrets & Security**
- Enable secret scanning on all repos
- Enable push protection (blocks commits containing secrets)
- Use Dependabot for dependency vulnerability alerts

**Audit & Compliance**
- Audit log streaming — pipe GitHub audit logs to your SIEM
- Required workflows — enforce org-wide CI checks even on repo-level overrides
- Environment protection rules — require approvals for production deployments

---

## Related Topics

- [Security & Hardening](security.md)
- [CI/CD Pipelines](cicd.md) — branch protection as part of deployment safety
- [Terraform & IaC](terraform.md) — governance as code
