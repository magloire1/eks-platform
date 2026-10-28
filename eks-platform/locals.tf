data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  tags = {
    Environment = var.environment
    Platform    = var.cluster_name
    ManagedBy   = "terraform"
  }

  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  zone_arn = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"

  # Only the pre-Karpenter system pieces tolerate the system node taint.
  system_tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]

  # Shared ALB for platform tools (Argo CD, Grafana). Tenants use group "tenants".
  alb_platform_annotations = {
    "alb.ingress.kubernetes.io/scheme"          = var.alb_scheme
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/group.name"      = "platform"
    "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
    "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate_validation.wildcard.certificate_arn
  }
}
