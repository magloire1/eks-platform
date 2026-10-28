# Platform Engineer Playbook (for you)

## A. Onboarding a team - step by step
**Before the meeting**
1. Send the intake form (`02-...`) and this repo's `03` guide.
2. Confirm SSO group / role ARN. Remember: SSO role ARNs for access entries have **no** `aws-reserved/sso.amazonaws.com/` path.

**Kickoff (60 min)** - see `02`.

**Provision the team** (PR to this repo)
```hcl
teams = {
  team-a = { role_arn = "arn:aws:iam::111122223333:role/AWSReservedSSO_TeamA_abc123", quota = { cpu = "40", memory = "80Gi", pods = "200" } }
}
```
`terraform plan` -> review -> `apply`. Result: namespace, quota, LimitRange, NetworkPolicies, RBAC, Argo project.
Also: create ECR repos, Pod Identity roles they asked for, Secrets Manager prefix, and add CODEOWNERS entry `/teams/team-a/ @org/team-a`.

**Pairing session (90 min)** - run it with *their* app, they drive, you watch:
1. They create `teams/team-a/<app>/` from the example. Open a PR.
2. You review with the checklist below; merge.
3. Watch Argo CD sync; watch Karpenter provision a node (`kubectl get nodeclaims`).
4. Hit the URL; show Grafana, logs, and how to roll back.
5. Break something on purpose (bad image tag) and recover via Git revert.

**After**: they deploy a second change alone; check in after 1 week; collect feedback into the docs.

## B. PR review checklist (tenant manifests)
- [ ] Image pinned (tag/digest), from ECR; not `latest`
- [ ] requests/limits present; replicas >= 2 for prod; PDB; probes
- [ ] No `hostNetwork`, `privileged`, `hostPath`, root user
- [ ] No Secret objects with real data; ExternalSecret instead
- [ ] Ingress: class `alb`, group `tenants`, correct scheme, host `<team>-<app>.<domain>`
- [ ] No `LoadBalancer` services, no `namespace:` override
- [ ] RBAC objects (Role/RoleBinding) reviewed - teams *can* create these inside their own namespace; flag anything granting other teams access. (Hardening: add a Kyverno policy.)

## C. Operations runbook

### First deployment of the platform
```bash
cp terraform.tfvars.example terraform.tfvars   # edit
cp backend.hcl.example backend.hcl             # edit
terraform init -backend-config=backend.hcl
terraform apply -target=module.eks             # stage 1: VPC + cluster (providers need the endpoint)
terraform apply                                # stage 2: everything else
$(terraform output -raw configure_kubectl)
terraform output -raw argocd_initial_password_cmd | sh
```
Then: log in to Argo CD, set up SSO (OIDC), **delete the initial admin secret / disable `admin`**, and pin chart versions from `helm list -A` into `chart_versions`.

### Argo CD SSO / RBAC
Configure OIDC under `configs.cm."oidc.config"` and map groups in `configs.rbac."policy.csv"`, e.g.
`g, <sso-group-team-a>, proj:team-a:developer` (add a `roles` block to the AppProject) and `g, <platform-group>, role:admin`.

### Upgrades
| What | How |
|---|---|
| Helm add-ons | Bump `chart_versions` in staging first; read release notes (Karpenter: CRD chart is upgraded together with the controller) |
| EKS control plane | Run `pluto detect-all-in-cluster` for removed APIs -> bump `cluster_version` **one minor at a time** -> apply -> upgrade addons |
| Nodes | System node group updates via Terraform; Karpenter nodes roll automatically via AMI drift (`al2023@latest`) honoring disruption budgets/PDBs |
Check the Karpenter compatibility matrix for the target Kubernetes version before every control-plane upgrade.

### Adding spot/GPU/ARM pools
Add an entry to `local.karpenter_nodepools` (taint + label so only opted-in workloads land there).

### Break-glass
Platform admins: `platform_admin_role_arns`. Everything is audited via EKS audit logs in CloudWatch. Document who may use it and when.

### Common platform issues
| Symptom | Likely cause |
|---|---|
| Pods Pending, no new nodes | NodePool `limits` hit; no instance type matches requests; subnet IPs exhausted; check `kubectl logs -n kube-system deploy/karpenter` |
| ALB not created | LBC pod unhealthy; subnet tags missing; ingress scheme/group mismatch |
| No DNS record | ExternalDNS logs; host outside `domain_name`; `upsert-only` never deletes (clean up manually) |
| Certificate stuck | `kubectl describe certificate/order/challenge`; Route53 permissions; use staging issuer to test |
| ExternalSecret denied | Secret name not under `<cluster>/`; IAM policy scope in `iam.tf` |
| Argo app OutOfSync loop | Controller-mutated fields; add `ignoreDifferences` |

### Destroying
Delete tenant apps / Ingresses / PVCs first (so ALBs, DNS records and EBS volumes are released), wait for Karpenter nodes to disappear, then `terraform destroy`. Otherwise orphaned ALBs/ENIs block VPC deletion.

## D. Support model (suggested)
- Slack `#platform-help`, weekly office hours, SLA for onboarding requests (e.g. 2 business days).
- Public changelog of platform upgrades with 1-2 weeks' notice for disruptive ones.
- Quarterly survey: time-to-first-deploy, pain points.

## E. Known limitations / next steps
- **Secrets isolation:** the External Secrets role can read everything under `<cluster>/*`; teams are separated by convention and review. For hard isolation: one Pod Identity role + one `ClusterSecretStore` per team.
- **Egress** is unrestricted; add egress NetworkPolicies if required by compliance.
- **Policy engine** (Kyverno), **Velero** backups, **cost allocation** (Kubecost / AWS split cost allocation) and **Argo Rollouts** are not installed.
- ingress-nginx is intentionally not used (upstream retired it); ALB via the AWS Load Balancer Controller is used instead.
