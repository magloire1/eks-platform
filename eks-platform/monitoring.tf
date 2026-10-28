resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_monitoring ? 1 : 0

  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = lookup(var.chart_versions, "kube-prometheus-stack", null)
  wait             = true
  timeout          = 900

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention = "15d"
        # Pick up ServiceMonitors/PodMonitors/rules from every namespace (teams ship their own)
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "50Gi" } }
            }
          }
        }
      }
    }
    grafana = {
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hosts            = ["grafana.${var.domain_name}"]
        annotations      = local.alb_platform_annotations
      }
    }
  })]

  depends_on = [
    kubectl_manifest.karpenter_node_pool,
    kubectl_manifest.storage_class_gp3,
    helm_release.aws_lb_controller,
    helm_release.external_dns,
  ]
}
