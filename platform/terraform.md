# Terraform & Infrastructure as Code

[← Platform Home](README.md) | [← Main](../README.md)

---

## Why IaC? `[B]`

Infrastructure as Code = managing infrastructure through version-controlled configuration files instead of manual clicks or scripts.

**Benefits:**
- Reproducible environments (no snowflake servers)
- Code review for infrastructure changes
- Audit trail via git history
- Disaster recovery — recreate infra from code

**Terraform vs alternatives:**

| Tool | Approach | Best for |
|------|----------|---------|
| Terraform | Declarative, multi-cloud | General-purpose IaC |
| Pulumi | Imperative (real code) | Devs who prefer programming languages |
| AWS CDK | Declarative (code) | AWS-only, TypeScript/Python |
| Ansible | Imperative, agentless | Config management, not infra provisioning |
| CloudFormation | Declarative YAML/JSON | AWS-only, no extra tooling |

---

## Terraform Core Concepts `[B]`

### Providers

Plugins that let Terraform talk to APIs (AWS, GCP, Azure, Kubernetes, etc.)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

### Resources

The things you create:

```hcl
resource "aws_s3_bucket" "logs" {
  bucket = "my-app-logs-prod"
}
```

### Data Sources

Read existing infrastructure (not managed by this Terraform):

```hcl
data "aws_vpc" "main" {
  id = "vpc-abc12345"
}
```

### Variables & Outputs

```hcl
variable "environment" {
  type    = string
  default = "staging"
}

output "bucket_arn" {
  value = aws_s3_bucket.logs.arn
}
```

### State

Terraform tracks what it created in a **state file** (`terraform.tfstate`).

**Never commit state to git.** Use remote state backends:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"  # state locking
    encrypt        = true
  }
}
```

---

## Core Workflow `[B]`

```bash
terraform init      # Download providers, initialize backend
terraform plan      # Show what will change (always review!)
terraform apply     # Apply changes
terraform destroy   # Tear down infrastructure
terraform fmt       # Format code
terraform validate  # Validate syntax
```

**Always review `plan` output before `apply`.**

---

## Module Structure `[I]`

Modules = reusable, composable infrastructure components.

### Recommended Layout

```
infrastructure/
├── environments/
│   ├── prod/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── staging/
│       └── ...
└── modules/
    ├── networking/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── rds/
    │   └── ...
    └── eks/
        └── ...
```

### Using a Module

```hcl
module "vpc" {
  source = "../../modules/networking"

  environment  = var.environment
  cidr_block   = "10.0.0.0/16"
  az_count     = 3
}
```

### Public Modules

Terraform Registry has battle-tested modules:
```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  # ...
}
```

---

## State Management `[I]`

### State Locking

Prevents concurrent applies from corrupting state. Use DynamoDB for S3 backend.

### Workspaces

Separate state per environment:

```bash
terraform workspace new staging
terraform workspace select prod
terraform workspace list
```

**Alternative:** Use separate state files per environment (more explicit, easier to manage at scale).

### State Commands

```bash
terraform state list                          # List resources in state
terraform state show aws_instance.web         # Inspect a resource
terraform state mv old_name new_name          # Rename resource in state
terraform state rm aws_instance.old           # Remove from state (not destroy)
terraform import aws_s3_bucket.logs my-bucket # Import existing resource
```

---

## Terraform Best Practices `[I]`

### Code Quality
- Pin provider versions (`~> 5.0`, not `latest`)
- Use `terraform fmt` and `terraform validate` in CI
- Lock file (`terraform.lock.hcl`) must be committed to git
- Use `tflint`, `checkov`, or `terrascan` for static analysis

### Safety
- Always run `plan` before `apply`
- Use `-target` sparingly (creates state drift)
- Never edit state manually
- Protect prod with PR reviews + CI plan output

### Organization
- Small, focused modules (single responsibility)
- Document variables with `description` fields
- Tag all resources consistently

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}
```

---

## Advanced Patterns `[A]`

### Dynamic Blocks

```hcl
resource "aws_security_group" "web" {
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidrs
    }
  }
}
```

### For Expressions

```hcl
locals {
  instance_ids = [for i in aws_instance.web : i.id]
  sg_map       = { for sg in var.security_groups : sg.name => sg.id }
}
```

### Conditional Resources

```hcl
resource "aws_cloudwatch_alarm" "high_cpu" {
  count = var.environment == "prod" ? 1 : 0
  # ...
}
```

### Terragrunt

DRY wrapper around Terraform for managing multiple environments/accounts:
- Eliminates backend config repetition
- Manages dependency ordering between modules
- `run-all plan` across multiple modules

---

## CI/CD Integration `[I]`

```yaml
# GitHub Actions example
- name: Terraform Plan
  run: |
    terraform init
    terraform plan -out=tfplan

- name: Post Plan to PR
  uses: actions/github-script@v6
  # Post plan output as PR comment

- name: Terraform Apply (main branch only)
  if: github.ref == 'refs/heads/main'
  run: terraform apply tfplan
```

Tools: Atlantis (PR-based workflows), Terraform Cloud, Spacelift

→ See [CI/CD Pipelines](cicd.md)

---

## Related Topics

- [Cloud Infrastructure](cloud-infra.md)
- [Kubernetes](kubernetes.md)
- [CI/CD Pipelines](cicd.md)
- [Security & Hardening](security.md)
- [devops-exercises](../resources/devops-exercises/README.md) — Terraform Q&A
