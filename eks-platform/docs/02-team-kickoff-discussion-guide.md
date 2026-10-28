# Team Kickoff - What to Discuss

Use this for a 60-minute kickoff per team (bring the tech lead and whoever owns CI/CD). Send the intake form **before** the meeting.

## Agenda
1. **(5 min) Platform overview** - what they get (namespace, quota, GitOps deploys, ALB/DNS/TLS, secrets, metrics) and what they don't (cluster-admin, per-service load balancers, root containers).
2. **(30 min) Walk through the questions below** - fill the intake form together.
3. **(10 min) Walk through the golden path** - show the `gitops-example` app and the PR flow.
4. **(10 min) Agree next steps, owners and a date for the pairing session.**
5. **(5 min) Support & escalation** - channel, office hours, who is on call.

## Questions by topic

### Application
- What services are there? Language/framework? Already containerized? Image registry (ECR)?
- Stateless or stateful? If stateful: where does the data live (RDS/DynamoDB/S3 preferred over in-cluster databases)?
- Ports/protocols (HTTP, gRPC, WebSocket, TCP)? Any long-lived connections or large uploads? (ALB idle timeout, body limits)
- Startup time, graceful shutdown behavior, health endpoints?
- Background workers / cron jobs / queues?

### Traffic & networking
- Who calls it: internet, VPN/internal users, other internal services? -> ingress scheme.
- Desired hostname? (single label: `<team>-<app>.<domain>`)
- What does the app call: other AWS services, on-prem, third-party APIs? Need fixed egress IPs (allow-lists)?
- Cross-team service-to-service calls? (NetworkPolicy exceptions)
- Authentication in front of the app (OIDC on ALB, app-level)?

### Config & secrets
- What secrets exist (DB passwords, API keys, certs)? Where are they today?
- Rotation requirements? (ExternalSecret `refreshInterval`, pod restart on change)
- Per-environment configuration strategy (Kustomize overlays / Helm values).

### AWS access from pods
- Which AWS APIs does the app call (S3, SQS, DynamoDB...)? -> needs a Pod Identity role; agree on the least-privilege policy and who creates it.

### Capacity & scaling
- Expected requests per second, CPU/memory per replica (measure, don't guess), min/max replicas?
- Burst patterns? Scheduled load? Can workloads tolerate interruption (-> spot pool)?
- GPU/ARM/large-memory needs?

### Reliability
- SLO / availability target? Business hours or 24x7?
- Behavior on pod restarts and node replacement (Karpenter consolidates nodes)? Multi-replica safe?
- Required PodDisruptionBudget, multi-AZ spread.
- Backup/restore and RTO/RPO for anything stateful.

### Delivery
- Where is the code (repo), how is the image built and tested (CI), who can merge to main?
- Promotion model (dev -> stage -> prod)? Manual approval gates?
- Rollback expectations. Need canary/blue-green? (-> Argo Rollouts later)

### Observability
- Does the app expose Prometheus metrics (`/metrics`)? Structured JSON logs to stdout?
- Which dashboards/alerts matter? Alert destination (Slack, PagerDuty)?
- Tracing needs?

### Security & compliance
- Data classification (PII, PCI, HIPAA)? Any compliance constraints on where it runs?
- Image scanning in CI? Approved base images? Run as non-root?
- Who needs `kubectl` access, and which SSO group represents them?

### Cost & ownership
- Cost center / tags. Expected monthly size.
- Named owner, backup owner, on-call rotation, Slack channel.

## Intake form (copy per app)
```yaml
team: team-a
app: hello-web
owner: jane@example.com
backup_owner: raj@example.com
slack: "#team-a"
repo: https://github.com/my-company/hello-web
image: <account>.dkr.ecr.<region>.amazonaws.com/team-a/hello-web
container_ready: true
stateful: false
ingress: internal        # internal | internet-facing | none
hostname: team-a-hello-web.example.com
port: 8080
protocol: http
secrets: [DB_PASSWORD, API_KEY]
aws_access: [s3:GetObject on bucket x]
cpu_request: 250m
memory_request: 256Mi
min_replicas: 2
max_replicas: 10
spot_tolerant: false
slo: "99.9%"
metrics_endpoint: /metrics
alert_channel: "#team-a-alerts"
sso_group: team-a-developers
```

## Definition of ready (before the pairing session)
- [ ] Container image builds in CI and is in ECR; runs as non-root
- [ ] Intake form complete
- [ ] Secrets created in Secrets Manager under `<cluster>/<team>/<app>`
- [ ] Team is in the `teams` map and applied; SSO role mapped
- [ ] Health endpoints exist
