# CI/CD Pipelines

[← Platform Home](README.md) | [← Main](../README.md)

---

## CI/CD Fundamentals `[B]`

**Continuous Integration (CI):** Automatically build and test every code change.
**Continuous Delivery (CD):** Automatically deploy to staging; manually trigger to prod.
**Continuous Deployment:** Automatically deploy to prod on every passing build.

**Goal:** Make deployment boring. Small, frequent, safe releases.

---

## Pipeline Stages `[B]`

```
Code Push → CI Build → Test → Security Scan → Artifact → Deploy Staging → Deploy Prod
```

Typical stages:

| Stage | What happens | Tools |
|-------|-------------|-------|
| **Lint/Format** | Code style checks | ESLint, black, golangci-lint |
| **Build** | Compile, containerize | Docker, buildkit |
| **Unit Tests** | Fast, isolated tests | pytest, jest, go test |
| **Integration Tests** | Tests with real dependencies | Docker Compose, testcontainers |
| **Security Scan** | SAST, dependency vulnerabilities | Snyk, trivy, semgrep |
| **Publish Artifact** | Push image to registry | ECR, GCR, DockerHub |
| **Deploy Staging** | Automated deploy | Helm, kubectl, ArgoCD |
| **E2E Tests** | Test against staging | Playwright, Cypress |
| **Deploy Prod** | Manual gate or automated | ArgoCD, Spinnaker |

---

## GitHub Actions `[B]`

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.12'

    - name: Install dependencies
      run: pip install -r requirements.txt

    - name: Run tests
      run: pytest --cov=. --cov-report=xml

    - name: Upload coverage
      uses: codecov/codecov-action@v4

  build-and-push:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::123456789:role/github-actions
        aws-region: us-east-1

    - name: Build and push to ECR
      env:
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t my-app:$IMAGE_TAG .
        docker push $ECR_REGISTRY/my-app:$IMAGE_TAG

  deploy-staging:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
    - name: Deploy to staging
      run: |
        helm upgrade --install my-app ./charts/my-app \
          --set image.tag=${{ github.sha }} \
          --namespace staging
```

---

## Progressive Delivery `[I]`

Don't go from 0% to 100% traffic instantly. Reduce blast radius.

### Strategies

| Strategy | Description | When to use |
|----------|-------------|-------------|
| **Blue/Green** | Two identical environments, switch traffic | Zero-downtime, easy rollback |
| **Canary** | Small % of traffic to new version | Catch issues with real traffic |
| **Feature Flags** | Code is deployed, feature is toggled | Decouple deploy from release |
| **Rolling Update** | Replace pods gradually | Default K8s strategy |
| **Shadow/Mirror** | Duplicate traffic to new version | Test with real traffic, no user impact |

### Canary with ArgoCD Rollouts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    canary:
      steps:
      - setWeight: 5    # 5% of traffic
      - pause: {duration: 10m}
      - analysis:
          templates:
          - templateName: success-rate
      - setWeight: 50   # 50% if analysis passed
      - pause: {duration: 10m}
      - setWeight: 100  # full rollout
```

---

## GitOps `[I]`

GitOps = Git is the single source of truth for deployed state.

```
Developer → PR → Merge → Git repo (desired state)
                              ↓
                         ArgoCD/Flux
                              ↓
                    Kubernetes cluster (actual state)
```

**Tools:**
- **ArgoCD** — pull-based, UI + CLI, widely adopted
- **Flux** — pull-based, pure CLI, GitOps toolkit

**Benefits:**
- Full audit trail (git history = deploy history)
- Easy rollback (revert git commit)
- Drift detection (cluster state ≠ git state → alert)

### ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/infra
    path: apps/my-app/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true       # delete resources removed from git
      selfHeal: true    # revert manual cluster changes
```

---

## Artifact Management `[I]`

### Docker Image Best Practices

```dockerfile
# Use specific base image versions
FROM python:3.12.3-slim

# Multi-stage build — keep final image small
FROM python:3.12.3-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.12.3-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .

# Run as non-root
RUN adduser --disabled-password appuser
USER appuser

CMD ["python", "main.py"]
```

### Image Tagging

```
my-app:latest              # AVOID in production
my-app:v1.2.3              # Semantic version — good for releases
my-app:abc1234             # Git SHA — good for traceability
my-app:main-abc1234        # Branch + SHA — best of both
```

---

## Pipeline Security `[I]`

- Use OIDC for cloud auth from CI (no stored credentials)
- Pin actions to commit SHA, not tag (`uses: actions/checkout@v4` → use SHA)
- Scan images for vulnerabilities (trivy, Snyk) — fail build on HIGH/CRITICAL
- Never log secrets; use masked secrets in CI
- Minimal permissions on service accounts

---

## Deployment Checklist `[A]`

Before deploying to production:
- [ ] All tests pass (unit, integration, e2e)
- [ ] Security scan clean
- [ ] Canary or blue/green strategy in place
- [ ] Rollback procedure tested
- [ ] Runbook updated if behavior changes
- [ ] Monitoring/dashboards updated for new metrics
- [ ] On-call aware of deployment
- [ ] Feature flags available if needed

→ See [On-Call & Runbooks](../sre/on-call.md) for deployment communication

---

## Related Topics

- [Terraform & IaC](terraform.md) — infra provisioning in CI/CD
- [Kubernetes](kubernetes.md) — deploy target
- [Security & Hardening](security.md) — pipeline security
- [SRE: On-Call](../sre/on-call.md) — deployment → incident connection
- [devops-exercises](../resources/devops-exercises/README.md)
