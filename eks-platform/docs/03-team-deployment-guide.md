# Deploying Your App on the Platform (for application teams)

## What you get
- A namespace named after your team, with a resource quota, default limits, and default-deny ingress network policy.
- GitOps deploys: merge a folder into the platform Git repo and Argo CD deploys it.
- Automatic DNS (ExternalDNS), TLS (ACM wildcard on the ALB; cert-manager for in-cluster certs), secrets (External Secrets), autoscaling (HPA + Karpenter), metrics (Prometheus/Grafana).

## What you don't get (by design)
- Cluster-admin or access to other teams' namespaces.
- Per-service `LoadBalancer` services (use Ingress), privileged/root containers (Pod Security `baseline`, warn on `restricted`), changes to your quota.

## The flow
```
your repo (code) -> CI builds image -> ECR
platform-gitops repo: teams/<team>/<app>/*.yaml  --PR merged-->  Argo CD syncs -> namespace <team>
```

### 1. Container image
- Run as non-root, listen on a port >1024, log to stdout/stderr, handle SIGTERM gracefully.
- Push to ECR (`<account>.dkr.ecr.<region>.amazonaws.com/<team>/<app>:<git-sha>`). **Never use `:latest`.** Nodes can pull from ECR in the same account; cross-account needs a repo policy.

### 2. Create your app folder
In the platform GitOps repo, copy `gitops-example/teams/team-a/hello-web/` to `teams/<your-team>/<your-app>/` and edit. Plain YAML, Kustomize, and Helm charts all work (Argo CD auto-detects). Every folder **two levels under `teams/`** becomes an Application named `<team>-<app>`.

Minimum files: Deployment, Service. Normally also: Ingress, ExternalSecret, HPA, PodDisruptionBudget.

Rules of thumb:
- Always set CPU/memory **requests** (Karpenter sizes nodes from them) and a memory **limit**. Avoid CPU limits unless you have a reason.
- `replicas >= 2` + PDB + `topologySpreadConstraints` across zones for anything that matters.
- Don't put `namespace:` in manifests; Argo deploys into your team namespace and will refuse others.
- You cannot create ResourceQuota/LimitRange or cluster-scoped objects (Argo project blocks them).

### 3. Secrets
1. Create the secret in AWS Secrets Manager, name **`<cluster>/<team>/<app>`**, JSON key/values:
   `aws secretsmanager create-secret --name platform/team-a/my-app --secret-string '{"DB_PASSWORD":"..."}'`
2. Add an `ExternalSecret` (see `externalsecret.yaml`) and reference the generated Kubernetes Secret from your Deployment.
3. Rotate in Secrets Manager; the Secret refreshes hourly. Restart pods to pick up env-var changes (or mount as files).
Never commit secrets to Git.

### 4. Exposing the app
- Use an `Ingress` with `ingressClassName: alb`, `group.name: tenants`, scheme matching the platform (internal by default).
- Hostname: **`<team>-<app>.<domain>`** (single label, so the wildcard certificate matches). DNS record is created for you within ~1-2 minutes.
- Health check path: set `alb.ingress.kubernetes.io/healthcheck-path`.
- Need a certificate inside the cluster (mTLS, non-ALB)? Create a `Certificate` referencing `ClusterIssuer` `letsencrypt-prod` (use `letsencrypt-staging` while testing).

### 5. AWS permissions for your pods (S3, SQS, ...)
Ask the platform team for an **EKS Pod Identity** association: tell us namespace, ServiceAccount name, and the IAM policy needed. Your pod then uses the AWS SDK with no keys.

### 6. Scaling
- Pods: HPA on CPU (example included) or custom metrics.
- Nodes: automatic (Karpenter). New nodes take ~1-2 minutes, so keep `minReplicas` sensible.
- Interruption-tolerant workloads (batch, workers) can use spot nodes:
  ```yaml
  nodeSelector: { karpenter.sh/capacity-type: spot }
  tolerations: [{ key: workload-class, value: spot, effect: NoSchedule }]
  ```
- Nodes are replaced regularly (consolidation, AMI updates, 30-day expiry). Your app **must** survive pod restarts; PDBs limit simultaneous disruption.

### 7. Observability
- Metrics: expose `/metrics` and add a `ServiceMonitor` in your folder (Prometheus picks up all namespaces).
- Logs: write to stdout. Dashboards: Grafana at `grafana.<domain>`.
- Alerts: add a `PrometheusRule`; routing to your channel is configured with the platform team.

### 8. Access with kubectl
```bash
aws sso login --profile <profile>
aws eks update-kubeconfig --name <cluster> --region <region> --profile <profile>
kubectl -n <team> get pods
```
You have `edit` rights in your namespace only. **Prefer changing things in Git**; manual changes are reverted by Argo CD (selfHeal).

### 9. Promotion and rollback
- Deploy = merge a PR that changes the image tag. Rollback = revert the PR (or "History and rollback" in the Argo CD UI for emergencies, then fix Git).
- Multiple environments: use separate folders/overlays per environment (and per cluster if dev and prod clusters exist).

## Troubleshooting
| Symptom | Check |
|---|---|
| App not appearing in Argo CD | Folder must be exactly `teams/<team>/<app>/`; team must exist in the platform `teams` map |
| Argo says "project/namespace not permitted" | Manifest has another `namespace:` or a cluster-scoped kind |
| `exceeded quota` | `kubectl -n <team> describe resourcequota`; trim requests or ask for more quota |
| Pod `Pending` | `kubectl describe pod`; wait ~2 min for a new node; check requests vs. quota, tolerations/nodeSelector |
| `ImagePullBackOff` | Tag exists in ECR? Same account/region? Repo policy for cross-account |
| Pod `CrashLoopBackOff` | `kubectl logs --previous`; probes too aggressive; missing secret |
| ExternalSecret `SecretSyncedError` | Secret name must be under `<cluster>/...`; check JSON keys with `kubectl describe externalsecret` |
| Ingress has no address | `kubectl describe ingress` events; scheme must match platform; group name `tenants` |
| 502/504 from ALB | Pod not ready, wrong port, health check path wrong, NetworkPolicy blocking VPC CIDR |
| Can't reach pod from another namespace | Default-deny; add a NetworkPolicy allowing that namespace |

## Production-readiness checklist
- [ ] Non-root, no `latest` tag, image scanned in CI
- [ ] Requests/limits, HPA, PDB, >= 2 replicas, readiness + liveness probes
- [ ] Graceful shutdown tested (rolling update with no errors)
- [ ] Secrets from Secrets Manager only
- [ ] ServiceMonitor + at least one alert + a dashboard
- [ ] Runbook and owner in the repo README, Slack channel set
- [ ] Rollback rehearsed
