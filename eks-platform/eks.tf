module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs
  cluster_endpoint_private_access      = true

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true # the identity running Terraform

  access_entries = merge(
    {
      for i, arn in var.platform_admin_role_arns : "platform-admin-${i}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      # Team access: no AWS-managed policy; permissions come from the RoleBinding in tenants.tf
      for t, v in var.teams : "team-${t}" => {
        principal_arn     = v.role_arn
        kubernetes_groups = ["team-${t}"]
      } if v.role_arn != null
    }
  )

  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent  = true
      before_compute = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = { most_recent = true }
    coredns    = { most_recent = true } # tolerates CriticalAddonsOnly by default
    metrics-server = {
      most_recent          = true
      configuration_values = jsonencode({ tolerations = local.system_tolerations })
    }
    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
      configuration_values = jsonencode({
        controller = { tolerations = local.system_tolerations }
      })
    }
  }

  # Small tainted node group for Karpenter + core addons. Everything else lands on Karpenter nodes.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m6i.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      labels = { workload = "system" }
      taints = {
        critical = { key = "CriticalAddonsOnly", effect = "NO_SCHEDULE" }
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
