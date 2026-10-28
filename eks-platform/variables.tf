variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "cluster_name" {
  type    = string
  default = "platform"
}

variable "cluster_version" {
  description = "EKS Kubernetes version. Check what is currently supported: aws eks describe-cluster-versions"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "Must be a /16 (subnet math in vpc.tf assumes it)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  description = "true = one NAT (cheaper, not HA). false = one per AZ."
  type        = bool
  default     = false
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (office/VPN/CI egress IPs)."
  type        = list(string)
}

variable "platform_admin_role_arns" {
  description = "IAM role ARNs (SSO roles: WITHOUT the aws-reserved/sso.amazonaws.com/ path) with cluster-admin. Do not include the role running Terraform; it is added automatically."
  type        = list(string)
  default     = []
}

variable "domain_name" {
  description = "Base domain served by the existing Route53 zone, e.g. example.com"
  type        = string
}

variable "route53_zone_id" {
  description = "ID of the existing public Route53 hosted zone for domain_name"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration (cert-manager)"
  type        = string
}

variable "alb_scheme" {
  description = "internal (VPN/private only) or internet-facing"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["internal", "internet-facing"], var.alb_scheme)
    error_message = "alb_scheme must be internal or internet-facing."
  }
}

variable "gitops_repo_url" {
  description = "Git repo that holds tenant manifests (layout: teams/<team>/<app>/)"
  type        = string
}

variable "gitops_repo_revision" {
  type    = string
  default = "main"
}

variable "gitops_repo_private" {
  description = "If true, Argo CD repo credentials are pulled from Secrets Manager secret <cluster>/platform/gitops-repo (JSON keys: username, password)."
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "karpenter_cpu_limit" {
  description = "Max total vCPU Karpenter may provision per NodePool (cost safety net)."
  type        = number
  default     = 1000
}

variable "chart_versions" {
  description = "Optional Helm chart version pins, keyed by: karpenter, aws-lb-controller, external-dns, cert-manager, external-secrets, argo-cd, kube-prometheus-stack. Unset = latest. PIN THESE after the first successful apply."
  type        = map(string)
  default     = {}
}

variable "teams" {
  description = "Tenants. Each gets a namespace, quota, RBAC, network policy and an Argo CD project."
  type = map(object({
    role_arn = optional(string) # IAM role (SSO role without path) mapped to namespace-scoped edit
    quota = optional(object({
      cpu    = optional(string, "20")
      memory = optional(string, "40Gi")
      pods   = optional(string, "100")
    }), {})
    pod_security = optional(string, "baseline") # baseline | restricted
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.teams) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k))])
    error_message = "Team names must be valid DNS labels (lowercase letters, digits, hyphens)."
  }
}
