# Architecture

[← Home](../README.md)

Software and infrastructure architecture — principles, frameworks, and patterns that apply across every system you build or operate.

---

## Topics

| Topic | What you'll learn |
|-------|------------------|
| [Well-Architected](well-architected.md) | AWS / GCP / Azure frameworks — 6 pillars, key checks, review process |
| [Landing Zones](landing-zones.md) | Multi-account foundations — AWS Control Tower, GCP, Azure, account vending |
| [Best Practices](best-practices.md) | Blast radius, least privilege, scalability, resilience — principles with implementation |
| [External Links](external-links.md) | Official frameworks, books, reference architectures |

---

## Core Principles

These four underpin every section in this domain. Everything else is an implementation detail.

### Blast Radius Minimization
Failures are inevitable. Design so that when something breaks, the impact is bounded and the rest of the system survives.

### Least Privilege
Every identity — human or machine — gets exactly the permissions it needs, nothing more. Granted just-in-time where possible.

### Design for Scale
Systems should scale horizontally. State is the enemy of scale — isolate it, minimize it, replicate it.

### Operational Excellence
Automate everything that runs more than once. If you can't deploy in 10 minutes, recovery from an incident will take an hour.

---

## Architecture Domains

```
Architecture
├── Well-Architected Frameworks (AWS / GCP / Azure)
│   ├── Operational Excellence
│   ├── Security
│   ├── Reliability
│   ├── Performance Efficiency
│   ├── Cost Optimization
│   └── Sustainability
│
├── Landing Zones
│   ├── Account / Project Structure
│   ├── Identity & Access Foundation
│   ├── Network Topology
│   ├── Security Baseline
│   └── Account Vending Machine
│
├── Blast Radius
│   ├── Cell-Based Architecture
│   ├── Bulkheads
│   ├── Account Isolation
│   └── Progressive Delivery
│
└── Scalability Patterns
    ├── Stateless Services
    ├── CQRS / Read Replicas
    ├── Queue-Based Load Leveling
    └── Cell Architecture
```

---

## Quick Decision Framework

```
Building a new service?
  → Apply Well-Architected checklist before launch

Setting up a new cloud environment?
  → Start with a landing zone — never a single account

Something fails — how bad is it?
  → Map the blast radius: which cells/accounts/regions are affected?

Granting access?
  → Least privilege by default; just-in-time for elevated access

System won't scale?
  → Make it stateless → add read replicas → queue load leveling → cell sharding
```

---

## Key Resources

- [system-design-primer](../resources/system-design-primer/README.md) — comprehensive system design reference
- [awesome-system-design](../resources/awesome-system-design/README.md) — curated system design resources
- [github-well-architected](../resources/github-well-architected/README.md) — GitHub's Well-Architected library
- [awesome-scalability](../resources/awesome-scalability/README.md) — scalability patterns from real companies

---

## Learning Path

```
[B] Well-Architected pillars → Landing zones concept → Least privilege basics
[I] Blast radius design → Cell architecture → Account isolation patterns
[A] Multi-region active-active → Chaos engineering → Cost optimization at scale
```

---

[← SRE](../sre/README.md) | [← Platform](../platform/README.md) | [← DBRE](../dbre/README.md) | [← Messaging](../messaging/README.md)
