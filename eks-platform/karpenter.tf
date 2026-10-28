module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.37"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions           = true
  enable_pod_identity             = true
  create_pod_identity_association = true # kube-system/karpenter

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# CRDs in their own chart so they can be upgraded (Helm never upgrades crds/ of the main chart)
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = lookup(var.chart_versions, "karpenter", null)

  depends_on = [module.eks]
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = lookup(var.chart_versions, "karpenter", null)
  skip_crds  = true
  wait       = true

  values = [yamlencode({
    replicas     = 2
    nodeSelector = { workload = "system" }
    tolerations  = local.system_tolerations
    settings = {
      clusterName       = module.eks.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }
    controller = {
      resources = {
        requests = { cpu = "500m", memory = "1Gi" }
        limits   = { memory = "1Gi" }
      }
    }
  })]

  depends_on = [module.karpenter, helm_release.karpenter_crd]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role = module.karpenter.node_iam_role_name
      # "@latest" follows new AMIs automatically (drift-based rollout). Pin to a version for stricter change control.
      amiSelectorTerms           = [{ alias = "al2023@latest" }]
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = module.eks.cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = module.eks.cluster_name } }]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpTokens              = "required"
        httpPutResponseHopLimit = 1 # pods cannot reach node IMDS
      }
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "100Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]
    }
  })

  depends_on = [helm_release.karpenter]
}

locals {
  karpenter_nodepools = {
    # Default pool: on-demand, used by everything.
    default = { capacity_types = ["on-demand"], weight = 10, taints = [] }
    # Opt-in spot pool: teams must tolerate workload-class=spot and may select it with nodeSelector.
    spot = {
      capacity_types = ["spot"]
      weight         = 1
      taints         = [{ key = "workload-class", value = "spot", effect = "NoSchedule" }]
    }
  }
}

resource "kubectl_manifest" "karpenter_node_pool" {
  for_each = local.karpenter_nodepools

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = each.key }
    spec = {
      weight = each.value.weight
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = each.value.capacity_types },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "NotIn", values = ["nano", "micro", "small"] },
          ]
          taints      = each.value.taints
          expireAfter = "720h"
        }
      }
      limits = { cpu = tostring(var.karpenter_cpu_limit) }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets             = [{ nodes = "10%" }]
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
