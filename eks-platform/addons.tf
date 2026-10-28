# Everything below waits for Karpenter NodePools so pods have somewhere to run.

resource "helm_release" "aws_lb_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = "kube-system"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = lookup(var.chart_versions, "aws-lb-controller", null)
  wait             = true

  values = [yamlencode({
    clusterName  = module.eks.cluster_name
    region       = var.region
    vpcId        = module.vpc.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool, module.lb_controller_pod_identity]
}

resource "helm_release" "external_dns" {
  name             = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = lookup(var.chart_versions, "external-dns", null)
  wait             = true

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress", "service"]
    domainFilters = [var.domain_name]
    policy        = "upsert-only" # never deletes records; switch to "sync" once you trust it
    txtOwnerId    = module.eks.cluster_name
    env           = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
    serviceAccount = {
      create = true
      name   = "external-dns"
    }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool, module.external_dns_pod_identity]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = lookup(var.chart_versions, "cert-manager", null)
  wait             = true

  values = [yamlencode({
    crds           = { enabled = true }
    replicaCount   = 2
    serviceAccount = { create = true, name = "cert-manager" }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool, module.cert_manager_pod_identity]
}

locals {
  acme_servers = {
    letsencrypt-staging = "https://acme-staging-v02.api.letsencrypt.org/directory"
    letsencrypt-prod    = "https://acme-v02.api.letsencrypt.org/directory"
  }
}

resource "kubectl_manifest" "cluster_issuer" {
  for_each = local.acme_servers

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = each.key }
    spec = {
      acme = {
        email               = var.acme_email
        server              = each.value
        privateKeySecretRef = { name = "${each.key}-account-key" }
        solvers = [{
          dns01 = { route53 = { region = var.region, hostedZoneID = var.route53_zone_id } }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = lookup(var.chart_versions, "external-secrets", null)
  wait             = true

  values = [yamlencode({
    installCRDs    = true
    replicaCount   = 2
    serviceAccount = { create = true, name = "external-secrets" }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool, module.external_secrets_pod_identity]
}

# Uses the pod's ambient credentials (EKS Pod Identity) - no keys anywhere.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secrets-manager" }
    spec = {
      provider = { aws = { service = "SecretsManager", region = var.region } }
    }
  })

  depends_on = [helm_release.external_secrets]
}
