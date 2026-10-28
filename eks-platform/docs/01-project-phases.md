# Platform Project Phases

Goal: one company EKS platform, provisioned by Terraform, that multiple teams use **self-service** through GitOps.

| Phase | Name | Rough duration | Owner |
|---|---|---|---|
| 0 | Discovery & decisions | 1-2 weeks | You + engineering leads |
| 1 | Foundation (VPC, EKS, nodes) | 1 week | You |
| 2 | Platform add-ons | 1-2 weeks | You |
| 3 | Tenancy & guardrails | 1 week | You + security |
| 4 | Pilot team onboarding | 2-4 weeks | You + 1-2 friendly teams |
| 5 | General rollout | ongoing, 1-2 teams / sprint | You + team leads |
| 6 | Operate & improve | continuous | Platform team |

Durations are placeholders; adjust to your team size.

---

## Phase 0 - Discovery & decisions
**Do**
- Run the kickoff with each team (`02-team-kickoff-discussion-guide.md`) and collect the intake forms.
- Decide the open architecture questions and write them down (a one-page ADR each):
  - One cluster per environment (dev/stage/prod) vs. one shared cluster with namespaces. **Recommended: at least a separate prod cluster**; the same Terraform deploys both with different tfvars.
  - Ingress: internal-only (VPN) vs internet-facing; public vs private DNS zone.
  - Identity: AWS IAM Identity Center (SSO) groups -> team roles.
  - Git: which repo hosts tenant manifests; branch protection and CODEOWNERS per `teams/<team>/`.
  - Account structure: separate AWS account for the platform? Where do ECR repos live?
  - Cost model: who pays for nodes (showback by namespace/label?).
  - Support model: office hours, Slack channel, on-call expectations.
**Deliverables**: ADRs, team intake forms, agreed domain name, Route53 zone, SSO groups list.
**Exit criteria**: every decision above has an owner and an answer; AWS account, Route53 zone and Terraform state bucket exist.

## Phase 1 - Foundation
**Do**: `terraform apply -target=module.eks` (VPC + EKS + system node group + core addons).
**Deliverables**: cluster reachable via `kubectl`, API access restricted to office/VPN CIDRs, logging enabled, admin access via SSO role.
**Exit criteria**: all nodes Ready; CoreDNS, VPC CNI, EBS CSI, metrics-server healthy; `kubectl top nodes` works.

## Phase 2 - Platform add-ons
**Do**: full `terraform apply`.
Installs: Karpenter (+ default and spot NodePools), AWS Load Balancer Controller, ExternalDNS, cert-manager (+ Let's Encrypt issuers), External Secrets (+ ClusterSecretStore), Argo CD (+ self-service ApplicationSet), kube-prometheus-stack, gp3 StorageClass, wildcard ACM cert.
**Exit criteria (smoke tests)**
- [ ] Deploy `gitops-example` -> pod scheduled on a **Karpenter-provisioned** node.
- [ ] Ingress creates an ALB; ExternalDNS creates the record; HTTPS works with the ACM cert.
- [ ] A test `Certificate` from `letsencrypt-staging` becomes Ready.
- [ ] ExternalSecret syncs a test secret from Secrets Manager.
- [ ] Argo CD UI reachable; initial admin password rotated; SSO configured.
- [ ] Grafana shows node and pod metrics.

## Phase 3 - Tenancy & guardrails
**Do**: define `teams` in tfvars; configure Argo CD SSO groups; add admission policy.
**Deliverables**: per-team namespace, quota, LimitRange, default-deny NetworkPolicy, RBAC, Argo CD project.
**Recommended additions** (not in the Terraform yet): Kyverno or ValidatingAdmissionPolicy to enforce "no `latest` tags, requests/limits required, approved registries only"; AWS Budgets / Kubecost; backup of cluster state (Velero) if you run stateful workloads.
**Exit criteria**: a test user from team A can deploy in `team-a` and **cannot** read or change `team-b` (verify with `kubectl auth can-i`).

## Phase 4 - Pilot
**Do**: onboard 1-2 friendly teams end-to-end using `03-team-deployment-guide.md` and the playbook in `04-platform-playbook.md`. Pair with them for the first deployment.
**Deliverables**: pilot apps in production traffic or at least staging; list of friction points; docs updated from their feedback.
**Exit criteria**: pilot team deploys a change via PR with **no help from you**; rollback tested; alert fires and reaches the right channel.

## Phase 5 - Rollout
**Do**: onboard remaining teams in waves; run a 45-min "deploy to the platform" workshop; keep office hours.
**Metrics**: teams onboarded, time-to-first-deploy, number of platform support tickets, deploy frequency.

## Phase 6 - Operate & improve
- Monthly: Karpenter/Argo/cert-manager chart upgrades (staging first). Quarterly: EKS version upgrade (see runbook).
- Review cost per namespace, right-size quotas, check unused namespaces.
- Backlog candidates: Argo Rollouts (canary), Kyverno policies, service mesh (only if needed), Velero, per-team Secrets Manager roles, image signing.

## Risks to track
| Risk | Mitigation |
|---|---|
| Noisy neighbor / runaway cost | Quotas, Karpenter `limits`, budgets |
| Single shared ALB hits 100-rule limit | Use more ALB groups (`group.name`) per team when needed |
| Cluster upgrade breaks a team | Deprecation scan (`pluto`/`kubent`) before every upgrade, PDBs required |
| Platform team is the bottleneck | Self-service ApplicationSet, docs, golden-path example |
| Leaked secret in Git | Secrets only via ExternalSecret; secret scanning in CI |
