output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "argocd_url" {
  value = "https://argocd.${var.domain_name}"
}

output "argocd_initial_password_cmd" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "grafana_url" {
  value = var.enable_monitoring ? "https://grafana.${var.domain_name}" : null
}

output "karpenter_node_role" {
  value = module.karpenter.node_iam_role_name
}

output "acm_certificate_arn" {
  value = aws_acm_certificate_validation.wildcard.certificate_arn
}
