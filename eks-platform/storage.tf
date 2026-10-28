# gp3 default. EKS ships a gp2 StorageClass flagged default too; Kubernetes uses the NEWEST default,
# so gp3 wins. Optionally un-default gp2:  kubectl patch sc gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
resource "kubectl_manifest" "storage_class_gp3" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name        = "gp3"
      annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
    }
    provisioner          = "ebs.csi.aws.com"
    parameters           = { type = "gp3", encrypted = "true" }
    volumeBindingMode    = "WaitForFirstConsumer"
    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
  })

  depends_on = [module.eks]
}
