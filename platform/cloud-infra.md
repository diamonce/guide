# Cloud Infrastructure

[← Platform Home](README.md) | [← Main](../README.md)

---

## Cloud Fundamentals `[B]`

The big three:

| Provider | Kubernetes | Managed DB | Object Storage | Serverless |
|----------|-----------|------------|----------------|------------|
| **AWS** | EKS | RDS, Aurora | S3 | Lambda |
| **GCP** | GKE | Cloud SQL, AlloyDB | GCS | Cloud Functions |
| **Azure** | AKS | Azure SQL, Cosmos | Blob Storage | Azure Functions |

**Multi-cloud reality:** Most companies pick one cloud. Tooling (Terraform, K8s, OTEL) provides portability where it matters.

---

## Networking Fundamentals `[B]`

### VPC / Virtual Network

```
VPC: 10.0.0.0/16
├── Public subnet:  10.0.1.0/24  (internet-facing: ALB, NAT GW)
├── Public subnet:  10.0.2.0/24  (AZ-2)
├── Private subnet: 10.0.10.0/24 (app servers, K8s nodes)
├── Private subnet: 10.0.11.0/24 (AZ-2)
├── Private subnet: 10.0.20.0/24 (databases)
└── Private subnet: 10.0.21.0/24 (databases AZ-2)
```

**Key rules:**
- Databases NEVER in public subnets
- App servers in private subnets, accessed via load balancer
- Use NAT Gateway for outbound internet from private subnets
- Use Security Groups (instance-level) + NACLs (subnet-level) for access control

### DNS

- Route53 (AWS), Cloud DNS (GCP), Azure DNS
- Private hosted zones for internal service discovery
- Health check routing — failover to healthy endpoint automatically

---

## Compute `[I]`

### EC2 / VM Best Practices

- Use Launch Templates (not Launch Configurations)
- Auto Scaling Groups for horizontal scaling
- Spot/Preemptible instances for cost savings on non-critical workloads (40-90% cheaper)
- Always use instance metadata service v2 (IMDSv2) for security

### Container Options

| Option | Good for | Not good for |
|--------|---------|-------------|
| EKS/GKE/AKS | Complex microservices, large teams | Simple single services |
| ECS (AWS) | AWS-native, simpler than K8s | Multi-cloud, complex scheduling |
| Cloud Run (GCP) | Serverless containers, variable load | Long-running jobs |
| Fargate (AWS) | Serverless containers on ECS/EKS | Cost-sensitive high-throughput |

### Serverless

Lambda/Cloud Functions: great for event-driven, bursty, short-lived work.

**Cold start problem:** First invocation is slow. Mitigations: provisioned concurrency, keep-alive pings, optimize package size.

---

## Storage `[I]`

### Object Storage (S3/GCS)

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "my-app-data-prod"
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
```

**Always enable:** versioning, encryption, access logging, block public access.

### Block Storage (EBS/Persistent Disk)

- gp3 is default for most workloads (better than gp2, same cost or cheaper)
- io2 for high-IOPS databases
- Snapshots for backups → see [DBRE: Backup & Recovery](../dbre/backup-recovery.md)

### File Storage (EFS/Filestore)

- Shared filesystem across multiple instances/pods
- Use for: shared configuration, content uploads, legacy apps
- More expensive than S3; only use when POSIX filesystem is needed

---

## Load Balancing `[I]`

| AWS | Type | Use case |
|-----|------|---------|
| ALB | Application (L7) | HTTP/HTTPS, path routing, microservices |
| NLB | Network (L4) | TCP, UDP, extreme performance, fixed IP |
| CLB | Classic (deprecated) | Legacy only |

**ALB features:**
- Path-based and host-based routing
- Target groups (instances, IPs, Lambda, K8s pods)
- Native integration with WAF, Shield, Cognito
- HTTP/2, WebSocket support

---

## Cost Management `[I]`

### Common Cost Mistakes

1. Oversized instances (right-size with CloudWatch metrics)
2. Unattached EBS volumes after instance termination
3. Old snapshots never deleted
4. Data transfer costs ignored (same-region: free; cross-region: $$$)
5. NAT Gateway overuse (expensive — $0.045/GB processed)
6. Unused Elastic IPs

### Cost Optimization Strategies

- **Reserved Instances / Savings Plans** — commit 1-3 years, save 40-60%
- **Spot Instances** — 60-90% discount, handle interruptions
- **S3 Intelligent-Tiering** — auto moves data to cheaper tiers
- **Right-sizing** — use AWS Compute Optimizer recommendations
- **Lifecycle policies** — delete old logs, move to Glacier

### Tagging for Cost Attribution

```hcl
locals {
  tags = {
    Team        = "platform"
    Service     = "my-app"
    Environment = "prod"
    CostCenter  = "eng-platform"
  }
}
```

Enable **AWS Cost Allocation Tags** → filter billing by team/service.

---

## High Availability Patterns `[A]`

### Multi-AZ

Run in at least 2 (prefer 3) Availability Zones:
- Separate failure domains (power, network, physical)
- ALB routes away from unhealthy AZ
- RDS Multi-AZ: automatic failover in 1-2 min

### Multi-Region

For disaster recovery or global user base:
- Active-Active: both regions serve traffic (complex, most resilient)
- Active-Passive: primary region, failover to secondary (simpler, more downtime)
- Cross-region replication: S3, DynamoDB, RDS read replicas

### Recovery Objectives

| Metric | Definition | Target |
|--------|-----------|--------|
| **RTO** | Recovery Time Objective — max acceptable downtime | Hours for tier-2, minutes for tier-1 |
| **RPO** | Recovery Point Objective — max acceptable data loss | Hours for tier-2, near-zero for critical |

→ See [DBRE: Backup & Recovery](../dbre/backup-recovery.md) for database-specific recovery.

---

## Related Topics

- [Terraform & IaC](terraform.md) — provision all of the above as code
- [Kubernetes](kubernetes.md) — EKS/GKE setup
- [Security & Hardening](security.md) — IAM, VPC security
- [DBRE: Backup & Recovery](../dbre/backup-recovery.md)
- [SRE: Scalability](../sre/scalability.md)
- [book-of-secret-knowledge](../resources/book-of-secret-knowledge/README.md) — AWS/cloud CLI one-liners
