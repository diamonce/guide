# Security & Hardening

[← Platform Home](README.md) | [← Main](../README.md)

---

## Security Fundamentals `[B]`

**Principle of Least Privilege:** Every system, user, and service should have only the minimum permissions required.

**Defense in Depth:** Multiple layers of security. No single control is sufficient.

**Zero Trust:** Never trust, always verify. Network location doesn't grant trust.

---

## IAM & Access Control `[B]`

### AWS IAM

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject"
    ],
    "Resource": "arn:aws:s3:::my-app-data/*"
  }]
}
```

**Rules:**
- No `*` on actions or resources in production
- Use IAM Roles for services (not access keys)
- Use OIDC for CI/CD → no stored credentials
- Enable MFA for human users, especially for privileged access
- Audit with IAM Access Analyzer

### Kubernetes RBAC

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: my-app
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: my-app
subjects:
- kind: ServiceAccount
  name: my-app
  namespace: my-app
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Never use `cluster-admin` for application service accounts.**

---

## Secrets Management `[I]`

### What NOT to do

- Hardcode secrets in code
- Store secrets in git (even in private repos)
- Put secrets in environment variables that get logged
- Use ConfigMaps for secrets in Kubernetes

### What to do

**AWS Secrets Manager / Parameter Store:**
```python
import boto3
client = boto3.client('secretsmanager')
secret = client.get_secret_value(SecretId='prod/my-app/db-password')
```

**Kubernetes: External Secrets Operator**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: db-credentials
  data:
  - secretKey: password
    remoteRef:
      key: prod/my-app/db-credentials
      property: password
```

**HashiCorp Vault:** Most flexible, works anywhere. Supports dynamic secrets (credentials generated on-demand, auto-expire).

---

## Network Security `[I]`

### VPC Security Layers

```
Internet
    ↓
  WAF (block malicious requests)
    ↓
  ALB (public subnet)
    ↓
Security Group (allow 443 from ALB only)
    ↓
  App servers (private subnet)
    ↓
Security Group (allow DB port from app servers only)
    ↓
  Database (private DB subnet)
```

### Security Groups

```hcl
resource "aws_security_group" "app" {
  name   = "app-servers"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # only from ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Kubernetes Network Policies

→ See [Kubernetes: Network Policies](kubernetes.md#networking)

---

## Container Security `[I]`

### Image Hardening

```dockerfile
# Use minimal base image
FROM gcr.io/distroless/python3-debian12

# Run as non-root
USER nonroot:nonroot

# Read-only filesystem
# (set in K8s securityContext)
```

### Kubernetes Pod Security

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Image Scanning

```bash
# Scan image with trivy
trivy image my-app:v1.2.3

# In CI pipeline — fail on HIGH/CRITICAL
trivy image --exit-code 1 --severity HIGH,CRITICAL my-app:v1.2.3
```

Tools: Trivy, Snyk, Grype, AWS ECR scanning

---

## Compliance & Auditing `[A]`

### Audit Logging

Enable and ship:
- AWS CloudTrail → who did what in AWS
- Kubernetes audit logs → who did what in K8s
- Application audit logs → who did what in the app

### Key Compliance Frameworks

| Framework | Focus | Who needs it |
|-----------|-------|-------------|
| SOC 2 | Security, availability, confidentiality | SaaS companies |
| PCI DSS | Payment card data | Any payment processing |
| HIPAA | Health data | Healthcare apps |
| GDPR | EU personal data | Apps serving EU users |
| ISO 27001 | Information security management | Enterprise contracts |

### Infrastructure Compliance Scanning

```bash
# Checkov — scan Terraform for misconfigurations
checkov -d ./infrastructure

# tfsec — Terraform security scanner
tfsec ./infrastructure

# kube-bench — CIS Kubernetes benchmark
kube-bench run --targets master,node
```

---

## Incident Response (Security) `[A]`

If you suspect a security incident:

1. **Don't panic, don't delete evidence**
2. Isolate affected systems (security group, network ACL)
3. Revoke potentially compromised credentials immediately
4. Preserve logs before any changes
5. Follow your incident response plan
6. Engage security team and legal as appropriate

→ See [Incident Management](../sre/incident-management.md) for general incident process.

---

## Related Topics

- [Terraform & IaC](terraform.md) — security as code
- [Kubernetes](kubernetes.md) — RBAC, network policy, pod security
- [CI/CD Pipelines](cicd.md) — pipeline security
- [Cloud Infrastructure](cloud-infra.md) — IAM, VPC
- [book-of-secret-knowledge](../resources/book-of-secret-knowledge/README.md) — security tools
