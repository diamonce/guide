# Landing Zones

[← Architecture Home](README.md) | [← Main](../README.md)

A landing zone is a pre-configured, secure, scalable multi-account (or multi-project) cloud environment. It's the foundation everything else runs on. Get this wrong and you rebuild it later under pressure — always harder than building it right the first time.

---

## What a Landing Zone Solves

Without a landing zone, teams create ad-hoc accounts/projects, inconsistent IAM, no central logging, no security baseline, and a sprawl that costs money and creates risk. A landing zone gives you:

| Problem | Landing Zone Solution |
|---------|----------------------|
| One breach exposes everything | Account isolation — blast radius per account |
| No audit trail | Centralized logging account — all CloudTrail, logs aggregated |
| Inconsistent permissions | SCPs / Organization Policies enforce guardrails at the root |
| Manual account creation | Account vending machine — IaC-driven, consistent, fast |
| No network segmentation | Hub-and-spoke VPC topology — shared services in hub |
| Dev/staging/prod mixed | Separate accounts per environment — no cross-contamination |

---

## Core Structure — Account / Project Hierarchy

### AWS Organization Layout

```
Root (Management Account)
├── Security OU
│   ├── Audit Account          ← all CloudTrail, Config, GuardDuty findings
│   └── Log Archive Account    ← S3 buckets for centralized log storage
│
├── Infrastructure OU
│   ├── Network Account        ← Transit Gateway, shared VPCs, DNS
│   └── Shared Services Account ← ECR, internal tooling, Artifactory
│
├── Workloads OU
│   ├── Production OU
│   │   ├── prod-payments
│   │   ├── prod-orders
│   │   └── prod-notifications
│   └── Non-Production OU
│       ├── dev-payments
│       └── staging-orders
│
└── Sandbox OU
    └── dev-sandbox-{engineer}   ← personal sandboxes, auto-expire
```

**Why separate accounts per workload in prod?**
- Blast radius: a security incident in `prod-payments` cannot reach `prod-orders`
- Cost attribution: each account's AWS bill is a clean cost center
- IAM boundary: no accidental cross-service permission bleed
- Quota isolation: one service exhausting EC2 limits doesn't starve another

### GCP Resource Hierarchy

```
Organization
├── Folders
│   ├── Platform
│   │   ├── Project: shared-vpc-host
│   │   ├── Project: logging-central
│   │   └── Project: security-controls
│   ├── Production
│   │   ├── Project: prod-payments
│   │   └── Project: prod-orders
│   ├── Staging
│   └── Development
└── (Organization Policies applied at each folder level)
```

### Azure Management Group Layout

```
Root Management Group
├── Platform
│   ├── Management Subscription      ← Azure Monitor, Log Analytics
│   ├── Connectivity Subscription    ← Hub VNet, ExpressRoute, Azure Firewall
│   └── Identity Subscription        ← Azure AD DS, DNS
└── Landing Zones
    ├── Corp (internal apps)
    │   ├── Sub: payments-prod
    │   └── Sub: orders-prod
    └── Online (internet-facing)
        └── Sub: ecommerce-prod
```

---

## Account Vending Machine

Never create accounts manually. Manual = inconsistent, undocumented, slow.

### AWS Account Factory (Control Tower)

AWS Control Tower is the managed landing zone service. Account Factory provisions new accounts with guardrails pre-applied.

```hcl
# Account Factory for Terraform (AFT)
module "aft" {
  source = "github.com/aws-ia/terraform-aws-control_tower_account_factory"

  ct_management_account_id    = "111111111111"
  log_archive_account_id      = "222222222222"
  audit_account_id            = "333333333333"
  aft_management_account_id   = "444444444444"

  tf_backend_secondary_region = "eu-west-1"
}

# Request a new account
resource "aws_controltower_account" "payments_prod" {
  name      = "prod-payments"
  email     = "aws-prod-payments@company.com"
  tags = {
    Environment = "production"
    Team        = "payments"
    CostCenter  = "cc-1042"
  }
}
```

### Custom Account Vending (without Control Tower)

```python
# account_vending.py — simplified
import boto3

def vend_account(name: str, email: str, ou_id: str, tags: dict) -> str:
    org = boto3.client('organizations')

    # Create account
    response = org.create_account(AccountName=name, Email=email)
    account_id = wait_for_account_creation(response['CreateAccountStatus']['Id'])

    # Move to correct OU
    org.move_account(
        AccountId=account_id,
        SourceParentId=org.list_roots()['Roots'][0]['Id'],
        DestinationParentId=ou_id
    )

    # Apply baseline via CloudFormation StackSet
    cfn = boto3.client('cloudformation')
    cfn.create_stack_instances(
        StackSetName='account-baseline',
        Accounts=[account_id],
        Regions=['us-east-1', 'eu-west-1'],
    )

    return account_id
```

---

## Service Control Policies (AWS SCPs)

SCPs are the guardrails at the Organization level. They apply to every account in the OU — even root users of member accounts cannot override them.

```json
// ✅ Prevent disabling CloudTrail — no account can turn off audit logging
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyCloudTrailDisable",
    "Effect": "Deny",
    "Action": [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail"
    ],
    "Resource": "*"
  }]
}

// ✅ Restrict to approved regions only
{
  "Sid": "DenyNonApprovedRegions",
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["us-east-1", "eu-west-1", "ap-southeast-1"]
    }
  }
}

// ✅ Deny root account usage
{
  "Sid": "DenyRootUser",
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringLike": {
      "aws:PrincipalArn": "arn:aws:iam::*:root"
    }
  }
}

// ✅ Require MFA for IAM operations
{
  "Sid": "RequireMFAForIAM",
  "Effect": "Deny",
  "Action": ["iam:*"],
  "Resource": "*",
  "Condition": {
    "BoolIfExists": {
      "aws:MultiFactorAuthPresent": "false"
    }
  }
}
```

---

## GCP Organization Policies

GCP equivalent of SCPs — enforced at org, folder, or project level.

```hcl
# Disable service account key creation — use Workload Identity instead
resource "google_org_policy_policy" "disable_sa_key_creation" {
  name   = "organizations/${var.org_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "organizations/${var.org_id}"
  spec {
    rules { enforce = true }
  }
}

# Restrict allowed resource locations
resource "google_org_policy_policy" "restrict_locations" {
  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"
  spec {
    rules {
      values {
        allowed_values = ["in:europe-locations", "in:us-locations"]
      }
    }
  }
}

# Require OS Login for SSH access
resource "google_org_policy_policy" "require_os_login" {
  name   = "organizations/${var.org_id}/policies/compute.requireOsLogin"
  parent = "organizations/${var.org_id}"
  spec {
    rules { enforce = true }
  }
}
```

---

## Network Topology — Hub and Spoke

```
                    ┌──────────────────────────────┐
                    │   Network / Connectivity Hub  │
                    │   - Transit Gateway (AWS)     │
                    │   - Shared VPC (GCP)          │
                    │   - Hub VNet (Azure)          │
                    │   - Firewall, NAT, DNS        │
                    │   - Direct Connect / VPN      │
                    └───────────────┬──────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
    ┌───────┴──────┐       ┌────────┴─────┐       ┌────────┴─────┐
    │  prod-payments│       │  prod-orders │       │  prod-notif  │
    │  VPC/VNet     │       │  VPC/VNet    │       │  VPC/VNet    │
    │  10.1.0.0/16  │       │  10.2.0.0/16 │       │  10.3.0.0/16 │
    └──────────────┘       └─────────────┘       └─────────────┘
```

**Rules:**
- Spoke VPCs never peer directly with each other — all traffic goes through the hub (firewall-inspected)
- Internet egress through centralized NAT in hub (single point of egress control)
- Ingress through centralized load balancer / WAF
- On-premises connectivity through hub only (Direct Connect / ExpressRoute)

```hcl
# AWS Transit Gateway — hub
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Central hub for all VPC connectivity"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
}

# Attach spoke VPC
resource "aws_ec2_transit_gateway_vpc_attachment" "payments" {
  subnet_ids         = aws_subnet.payments_private[*].id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.payments.id
  tags = { Name = "payments-prod-attachment" }
}
```

---

## Security Baseline (Applied to Every Account)

Every account gets these automatically via StackSet / Terraform:

```
✅ CloudTrail enabled in all regions, logs to central S3 (immutable)
✅ AWS Config enabled — records all resource changes
✅ GuardDuty enabled — threat detection
✅ Security Hub enabled — aggregated findings
✅ IAM Access Analyzer — detects overly permissive policies
✅ Default VPC deleted in all regions — accounts start with no network
✅ EBS encryption by default — all new volumes encrypted
✅ S3 public access block — account-level block
✅ Password policy — 16 char min, MFA required, no reuse
✅ Budget alert at $500 threshold — catches runaway cost
```

```hcl
# Terraform module applied to every account via StackSet
module "account_baseline" {
  source = "./modules/account-baseline"

  enable_guardduty        = true
  enable_security_hub     = true
  enable_config           = true
  log_archive_account_id  = var.log_archive_account_id
  central_trail_bucket    = "s3://company-cloudtrail-${var.log_archive_account_id}"

  ebs_default_encryption  = true
  s3_block_public_access  = true
  delete_default_vpc      = true
}
```

---

## Landing Zone Checklist

**Foundation**
- [ ] Management account used ONLY for organization management — no workloads
- [ ] Organization hierarchy matches environment and team structure
- [ ] Account vending machine deployed — no manual account creation
- [ ] SCPs / Organization Policies applied at OU level

**Security**
- [ ] CloudTrail enabled in all regions in all accounts
- [ ] Logs shipped to immutable central S3 / GCS bucket
- [ ] GuardDuty / Security Command Center enabled everywhere
- [ ] Default VPCs deleted from all accounts / projects

**Network**
- [ ] Hub-and-spoke topology — no direct spoke-to-spoke peering
- [ ] All egress through centralized NAT / firewall
- [ ] No 0.0.0.0/0 ingress to anything in private subnets

**Identity**
- [ ] SSO configured (AWS IAM Identity Center / GCP Cloud Identity / Azure AD)
- [ ] No long-lived access keys for humans
- [ ] Permission sets map to least-privilege roles per account

**Operations**
- [ ] Cost allocation tags enforced via SCP
- [ ] Budget alerts per account
- [ ] Sandbox accounts auto-expire after 30 days

---

## Related Topics

- [Well-Architected](well-architected.md) — pillars that landing zones implement
- [Best Practices](best-practices.md) — least privilege, blast radius
- [Platform Security](../platform/security.md) — IAM, secrets, hardening
- [Platform Terraform](../platform/terraform.md) — IaC for landing zone automation
- [Platform Cloud Infrastructure](../platform/cloud-infra.md) — VPC, networking patterns
