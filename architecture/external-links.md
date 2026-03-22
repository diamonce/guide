# External Resources — Architecture

[← Architecture Home](README.md) | [← Main](../README.md)

---

## Well-Architected Frameworks (Official)

| Resource | What it is |
|----------|-----------|
| [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) | The definitive AWS reference — 6 pillars, 100+ best practice questions |
| [AWS Well-Architected Tool](https://console.aws.amazon.com/wellarchitected/) | Free interactive review tool in the AWS console |
| [AWS Well-Architected Labs](https://wellarchitectedlabs.com/) | Hands-on labs for each pillar — actually run the checks |
| [GCP Architecture Framework](https://cloud.google.com/architecture/framework) | Google's equivalent — 6 pillars with GCP-specific guidance |
| [GCP Architecture Center](https://cloud.google.com/architecture) | Reference architectures, blueprints, and deployment guides |
| [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/) | Microsoft's 5-pillar framework with Azure Advisor integration |
| [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/) | Reference architectures, design patterns, anti-patterns |
| [GitHub Well-Architected](../resources/github-well-architected/README.md) | GitHub's reliability, security, and governance library |

---

## Landing Zones & Multi-Account

| Resource | What it is |
|----------|-----------|
| [AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/) | Managed landing zone service — account factory, guardrails, dashboard |
| [Account Factory for Terraform (AFT)](https://github.com/aws-ia/terraform-aws-control_tower_account_factory) | IaC-driven account vending on top of Control Tower |
| [AWS Landing Zone Accelerator](https://github.com/awslabs/landing-zone-accelerator-on-aws) | Opinionated, compliance-ready landing zone for regulated industries |
| [GCP Cloud Foundation Toolkit](https://cloud.google.com/foundation-toolkit) | Terraform blueprints for GCP landing zones |
| [GCP Assured Workloads](https://cloud.google.com/assured-workloads/docs) | Compliance controls for regulated GCP workloads |
| [Azure Landing Zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) | Microsoft Cloud Adoption Framework landing zones |
| [Terraform Landing Zones](https://github.com/Azure/caf-terraform-landingzones) | Azure landing zones in Terraform |

---

## System Design

| Resource | What it is |
|----------|-----------|
| [System Design Primer](../resources/system-design-primer/README.md) | donnemartin's comprehensive system design guide — the most-starred resource on GitHub for this topic |
| [Awesome System Design](../resources/awesome-system-design/README.md) | Curated list of system design resources, papers, case studies |
| [High Scalability Blog](http://highscalability.com/) | Real architecture case studies — how companies actually scaled |
| [Martin Fowler's Architecture Guide](https://martinfowler.com/architecture/) | Patterns of Enterprise Application Architecture, microservices, DDD |
| [The Architecture of Open Source Applications](https://aosabook.org/en/) | Deep dives into how real systems (nginx, git, LLVM) are structured |

---

## Blast Radius & Resilience

| Resource | What it is |
|----------|-----------|
| [AWS re:Invent — Cell-Based Architecture](https://www.youtube.com/watch?v=swQbA4zub20) | Amazon's presentation on cell-based architecture patterns |
| [Netflix Tech Blog — Chaos Engineering](https://netflixtechblog.com/tagged/chaos-engineering) | Netflix's approach to failure injection and resilience |
| [Chaos Engineering (book)](https://www.oreilly.com/library/view/chaos-engineering/9781492043850/) | O'Reilly book — principled approach to system resilience |
| [Principia Maleficarium](https://github.com/dastergon/awesome-chaos-engineering) | awesome-chaos-engineering — tools, papers, presentations |
| [resilience4j](https://resilience4j.readme.io/) | Circuit breaker, retry, rate limiter library for JVM |
| [Hystrix (Netflix)](https://github.com/Netflix/Hystrix) | Circuit breaker library (now in maintenance mode — use resilience4j) |

---

## Least Privilege & IAM

| Resource | What it is |
|----------|-----------|
| [AWS IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) | Detects overly permissive policies and public access |
| [AWS IAM Policy Simulator](https://policysim.aws.amazon.com/) | Test IAM policies before deploying |
| [GCP Policy Analyzer](https://cloud.google.com/iam/docs/managing-policies) | Understand what a principal can access before granting |
| [Open Policy Agent (OPA)](https://www.openpolicyagent.org/) | Policy-as-code engine — enforce least privilege in CI/CD |
| [HashiCorp Vault](https://www.vaultproject.io/) | Dynamic secrets, just-in-time access, PKI, secret leasing |
| [Checkov](https://www.checkov.io/) | Static analysis for IaC — catches overly permissive policies in Terraform before apply |

---

## Scalability

| Resource | What it is |
|----------|-----------|
| [awesome-scalability](../resources/awesome-scalability/README.md) | Curated scalability patterns from real companies |
| [Designing Data-Intensive Applications](https://dataintensive.net/) | Martin Kleppmann — the essential book on scalable data systems |
| [USE Method](https://www.brendangregg.com/usemethod.html) | Brendan Gregg's Utilization/Saturation/Errors framework for performance |
| [Latency Numbers Every Programmer Should Know](https://colin-scott.github.io/personal_website/research/interactive_latency.html) | Interactive version of the classic table |

---

## Reference Architectures

| Resource | What it is |
|----------|-----------|
| [AWS Solutions Library](https://aws.amazon.com/solutions/) | Pre-built, vetted AWS architectures for common use cases |
| [GCP Solutions Architecture](https://cloud.google.com/architecture/all-articles) | GCP reference architectures by industry and use case |
| [Azure Architecture Icons](https://learn.microsoft.com/en-us/azure/architecture/icons/) | Official icons for drawing Azure architecture diagrams |
| [draw.io / diagrams.net](https://www.diagrams.net/) | Free diagramming tool with cloud provider icon sets |
| [Excalidraw](https://excalidraw.com/) | Quick hand-drawn style diagrams — great for architecture sketches |

---

## Related Topics

- [Well-Architected](well-architected.md)
- [Landing Zones](landing-zones.md)
- [Best Practices](best-practices.md)
- [Platform Security](../platform/security.md)
- [Platform Terraform](../platform/terraform.md)
- [SRE Scalability](../sre/scalability.md)
- [DBRE Scaling](../dbre/scaling.md)
