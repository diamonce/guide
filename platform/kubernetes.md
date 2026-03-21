# Kubernetes

[← Platform Home](README.md) | [← Main](../README.md)

---

## Core Concepts `[B]`

Kubernetes (K8s) = container orchestration platform. It schedules, scales, and heals containerized workloads.

### Key Objects

| Object | Purpose |
|--------|---------|
| **Pod** | Smallest deployable unit (1+ containers) |
| **Deployment** | Manages replicated Pods, rolling updates |
| **Service** | Stable network endpoint for Pods |
| **ConfigMap** | Non-sensitive configuration |
| **Secret** | Sensitive data (base64 encoded, not encrypted by default) |
| **Namespace** | Logical cluster partition |
| **Ingress** | HTTP/HTTPS routing into the cluster |
| **PersistentVolume** | Storage abstraction |
| **HorizontalPodAutoscaler** | Auto-scale based on metrics |

---

## Essential kubectl Commands `[B]`

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes

# Namespace work
kubectl get pods -n my-namespace
kubectl get all -n my-namespace

# Deployment
kubectl apply -f deployment.yaml
kubectl rollout status deployment/my-app -n my-namespace
kubectl rollout history deployment/my-app -n my-namespace
kubectl rollout undo deployment/my-app -n my-namespace

# Debugging
kubectl describe pod my-pod-xyz -n my-namespace
kubectl logs my-pod-xyz -n my-namespace
kubectl logs my-pod-xyz -n my-namespace --previous   # crashed container
kubectl exec -it my-pod-xyz -n my-namespace -- /bin/sh

# Resource inspection
kubectl get events -n my-namespace --sort-by='.lastTimestamp'
kubectl top pods -n my-namespace
kubectl top nodes
```

---

## Deployment Anatomy `[B]`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0      # zero-downtime rolling update
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:v1.2.3  # always use specific tags, never :latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## Resource Management `[I]`

### Requests vs Limits

- **Requests** = guaranteed resources (used for scheduling)
- **Limits** = maximum allowed (enforced by kernel)

**Always set both.** Without requests, scheduler can't make good decisions. Without limits, one Pod can starve others.

### QoS Classes

| Class | Condition | Eviction Priority |
|-------|-----------|------------------|
| Guaranteed | requests == limits | Last |
| Burstable | requests < limits | Middle |
| BestEffort | no requests/limits | First |

### LimitRanges & ResourceQuotas

```yaml
# ResourceQuota per namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: my-team
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
```

---

## Health Probes `[I]`

| Probe | Failure action | Use for |
|-------|---------------|---------|
| **Liveness** | Restart container | Detect deadlocks, hung process |
| **Readiness** | Remove from Service | App not ready to serve traffic |
| **Startup** | Hold other probes | Slow-starting apps |

**Common mistake:** Using liveness probe for things that need restart when they should be readiness (e.g., DB connection temporarily lost → don't restart the pod, just remove from load balancer).

---

## Autoscaling `[I]`

### Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Vertical Pod Autoscaler (VPA)

Recommends/automatically adjusts resource requests. Use in "recommend" mode first.

### Cluster Autoscaler / Karpenter

Scales **nodes** when Pods can't be scheduled. Karpenter (AWS) is faster and more flexible.

---

## Networking `[I]`

### Service Types

| Type | Scope | Use case |
|------|-------|---------|
| ClusterIP | Cluster-internal | Service-to-service |
| NodePort | External via node port | Dev/testing |
| LoadBalancer | External via cloud LB | Production external traffic |
| ExternalName | DNS alias | External service in cluster DNS |

### Ingress

Routes external HTTP/HTTPS to Services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /v2
        pathType: Prefix
        backend:
          service:
            name: api-v2
            port:
              number: 80
```

Controllers: nginx-ingress, Traefik, AWS ALB Ingress, Kong

### Network Policies

Default: all pods can talk to all pods. NetworkPolicy restricts this:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
```

---

## Debugging Common Issues `[I]`

| Symptom | Check |
|---------|-------|
| Pod stuck in `Pending` | `kubectl describe pod` → events, node capacity, taints |
| Pod `CrashLoopBackOff` | `kubectl logs --previous`, check liveness probe |
| Pod `OOMKilled` | Increase memory limit, check for memory leak |
| Service not reachable | Label selectors match? Endpoints exist? `kubectl get endpoints` |
| Deployment stuck | `kubectl rollout status`, check readiness probe |

---

## Production Checklist `[A]`

- [ ] Resource requests and limits set on all containers
- [ ] Liveness and readiness probes configured
- [ ] `podDisruptionBudget` set (prevents all pods evicted at once)
- [ ] Replicas > 1 (no single point of failure)
- [ ] Pod anti-affinity (spread pods across nodes/AZs)
- [ ] Never use `:latest` image tag
- [ ] Secrets managed properly (external-secrets-operator, Vault)
- [ ] NetworkPolicy in place
- [ ] HPA configured for variable workloads
- [ ] RBAC: least privilege service accounts

---

## Related Topics

- [Terraform & IaC](terraform.md) — provision EKS/GKE clusters
- [CI/CD Pipelines](cicd.md) — deploy to Kubernetes
- [Security & Hardening](security.md) — RBAC, secrets, network policy
- [SRE: Observability](../sre/observability.md) — metrics from K8s
- [SRE: Scalability](../sre/scalability.md) — scaling patterns
- [devops-exercises](../resources/devops-exercises/README.md) — K8s Q&A
