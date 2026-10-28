resource "kubectl_manifest" "team_namespace" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = each.key
      labels = {
        team                                 = each.key
        "pod-security.kubernetes.io/enforce" = each.value.pod_security
        "pod-security.kubernetes.io/warn"    = "restricted"
      }
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "team_quota" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ResourceQuota"
    metadata   = { name = "team-quota", namespace = each.key }
    spec = {
      hard = {
        "requests.cpu"    = each.value.quota.cpu
        "requests.memory" = each.value.quota.memory
        "limits.memory"   = each.value.quota.memory
        pods              = each.value.quota.pods
        "services.loadbalancers" = "0" # use Ingress, not per-service NLBs
      }
    }
  })

  depends_on = [kubectl_manifest.team_namespace]
}

resource "kubectl_manifest" "team_limit_range" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "LimitRange"
    metadata   = { name = "defaults", namespace = each.key }
    spec = {
      limits = [{
        type           = "Container"
        defaultRequest = { cpu = "100m", memory = "128Mi" }
        default        = { memory = "512Mi" }
      }]
    }
  })

  depends_on = [kubectl_manifest.team_namespace]
}

resource "kubectl_manifest" "team_netpol_default_deny" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "default-deny-ingress", namespace = each.key }
    spec       = { podSelector = {}, policyTypes = ["Ingress"] }
  })

  depends_on = [kubectl_manifest.team_namespace]
}

# Allow: same namespace, ALB traffic (target-type ip => source is in the VPC CIDR), Prometheus scraping.
resource "kubectl_manifest" "team_netpol_allow_platform" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata   = { name = "allow-platform-ingress", namespace = each.key }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [{
        from = [
          { podSelector = {} },
          { ipBlock = { cidr = var.vpc_cidr } },
          { namespaceSelector = { matchLabels = { "kubernetes.io/metadata.name" = "monitoring" } } },
        ]
      }]
    }
  })

  depends_on = [kubectl_manifest.team_namespace]
}

# Team members (IAM role -> group team-<name>) get the built-in "edit" role, in their namespace only.
resource "kubectl_manifest" "team_rolebinding" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata   = { name = "team-edit", namespace = each.key }
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "edit" }
    subjects   = [{ apiGroup = "rbac.authorization.k8s.io", kind = "Group", name = "team-${each.key}" }]
  })

  depends_on = [kubectl_manifest.team_namespace]
}
