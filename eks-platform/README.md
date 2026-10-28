# EKS Platform (Terraform)

Multi-tenant EKS cluster with a GitOps platform, provisioned end to end by Terraform.

## What gets deployed
| Layer | Components |
|---|---|
| Network | VPC (3 AZs, private/public subnets, NAT per AZ), subnet tags for ALB + Karpenter discovery |
| Cluster | EKS (access entries / API auth, KMS secret encryption, audit logs), small tainted system node group, EKS add-ons: Pod Identity agent, VPC CNI (prefix delegation + NetworkPolicy), CoreDNS, kube-proxy, metrics-server, EBS CSI |
| Autoscaling | Karpenter (default on-demand pool + opt-in spot pool), interruption queue, consolidation |
| Traffic | AWS Load Balancer Controller (ALB, shared via ingress groups), ExternalDNS (Route53), ACM wildcard cert |
| Certificates | cert-manager + Let's Encrypt staging/prod ClusterIssuers (DNS-01 via Route53) |
| Secrets | External Secrets Operator + ClusterSecretStore for AWS Secrets Manager (Pod Identity, no static keys) |
| GitOps | Argo CD (HA-ish, ALB ingress) + ApplicationSet: folder `teams/<team>/<app>` = deployed app |
| Tenancy | Per team: namespace, Pod Security labels, ResourceQuota, LimitRange, default-deny NetworkPolicy, RBAC, Argo CD AppProject |
| Observability | kube-prometheus-stack (Prometheus, Alertmanager, Grafana), gp3 default StorageClass |

All AWS permissions use **EKS Pod Identity** with least-privilege policies.

## Prerequisites
- Terraform >= 1.10, AWS CLI v2, kubectl, helm (optional)
- An existing public Route53 hosted zone for your domain
- S3 bucket for Terraform state
- AWS credentials with rights to create VPC/EKS/IAM/ACM/Route53 records
- A Git repo for tenant manifests (copy `gitops-example/` into it)

## Deploy
```bash
cp terraform.tfvars.example terraform.tfvars && cp backend.hcl.example backend.hcl   # edit both
terraform init -backend-config=backend.hcl
terraform apply -target=module.eks      # stage 1: network + cluster
terraform apply                         # stage 2: add-ons, tenancy, GitOps
```
(The two stages avoid the classic "Helm/kubectl providers need a cluster that doesn't exist yet" problem on a brand-new environment. Later applies are a single step.)

## Layout
```
*.tf                  Terraform (vpc, eks, iam, karpenter, addons, argocd, tenants, monitoring, ...)
gitops-example/       Golden-path app for tenants (Deployment, Service, Ingress, ExternalSecret, HPA, PDB)
docs/01-project-phases.md                  Project phases, deliverables, exit criteria, risks
docs/02-team-kickoff-discussion-guide.md   What to discuss with each team + intake form
docs/03-team-deployment-guide.md           How teams deploy (share with developers)
docs/04-platform-playbook.md               Your onboarding script, PR checklist, runbook, limitations
```

## Important notes
- **Not yet applied or validated.** This was written without access to Terraform or AWS. Run `terraform init && terraform validate && terraform plan` in a sandbox account first and expect small fixes (module/chart input names change between releases).
- Helm chart versions are unpinned by default (latest). Pin them in `chart_versions` after the first good apply. Check `cluster_version` is currently supported by EKS and compatible with your Karpenter version.
- Security defaults to an **internal** ALB; the EKS API is restricted to `api_allowed_cidrs` (required input).
- Costs: 3 NAT gateways, ALBs, the system node group, and Karpenter nodes. Set `single_nat_gateway = true` for non-prod.
