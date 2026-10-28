resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = lookup(var.chart_versions, "argo-cd", null)
  wait             = true
  timeout          = 600

  values = [yamlencode({
    global = { domain = "argocd.${var.domain_name}" }

    configs = {
      params = { "server.insecure" = true } # TLS is terminated at the ALB
      cm     = { "application.resourceTrackingMethod" = "annotation" }
      rbac = {
        "policy.default" = "role:readonly"
        # Map SSO groups -> roles here once OIDC/SSO is configured (see docs/04)
        "policy.csv" = ""
      }
    }

    server = {
      replicas = 2
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hostname         = "argocd.${var.domain_name}"
        annotations = merge(local.alb_platform_annotations, {
          "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
        })
      }
    }
    repoServer     = { replicas = 2 }
    applicationSet = { replicas = 2 }
  })]

  depends_on = [
    kubectl_manifest.karpenter_node_pool,
    helm_release.aws_lb_controller,
    helm_release.external_dns,
    aws_acm_certificate_validation.wildcard,
  ]
}

# Optional: private Git repo credentials, pulled from Secrets Manager via External Secrets
resource "kubectl_manifest" "argocd_repo_creds" {
  count = var.gitops_repo_private ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "gitops-repo", namespace = "argocd" }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = "aws-secrets-manager" }
      target = {
        name = "gitops-repo"
        template = {
          metadata = { labels = { "argocd.argoproj.io/secret-type" = "repository" } }
          data = {
            type     = "git"
            url      = var.gitops_repo_url
            username = "{{ .username }}"
            password = "{{ .password }}"
          }
        }
      }
      data = [
        { secretKey = "username", remoteRef = { key = "${var.cluster_name}/platform/gitops-repo", property = "username" } },
        { secretKey = "password", remoteRef = { key = "${var.cluster_name}/platform/gitops-repo", property = "password" } },
      ]
    }
  })

  depends_on = [helm_release.argocd, kubectl_manifest.cluster_secret_store]
}

# One AppProject per team: can only deploy into its own namespace, no cluster-scoped resources,
# and cannot touch quotas/limit ranges.
resource "kubectl_manifest" "argocd_project" {
  for_each = var.teams

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata   = { name = each.key, namespace = "argocd" }
    spec = {
      description              = "Team ${each.key}"
      sourceRepos              = [var.gitops_repo_url]
      destinations             = [{ server = "https://kubernetes.default.svc", namespace = each.key }]
      clusterResourceWhitelist = []
      namespaceResourceBlacklist = [
        { group = "", kind = "ResourceQuota" },
        { group = "", kind = "LimitRange" },
      ]
    }
  })

  depends_on = [helm_release.argocd]
}

# Self-service: any folder teams/<team>/<app>/ in the GitOps repo becomes an Argo CD Application.
resource "kubectl_manifest" "tenant_appset" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata   = { name = "tenant-apps", namespace = "argocd" }
    spec = {
      goTemplate        = true
      goTemplateOptions = ["missingkey=error"]
      generators = [{
        git = {
          repoURL     = var.gitops_repo_url
          revision    = var.gitops_repo_revision
          directories = [{ path = "teams/*/*" }]
        }
      }]
      template = {
        metadata = { name = "{{ index .path.segments 1 }}-{{ index .path.segments 2 }}" }
        spec = {
          project = "{{ index .path.segments 1 }}"
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_revision
            path           = "{{ .path.path }}"
          }
          destination = { server = "https://kubernetes.default.svc", namespace = "{{ index .path.segments 1 }}" }
          syncPolicy = {
            automated   = { prune = true, selfHeal = true }
            syncOptions = ["ServerSideApply=true"]
          }
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
