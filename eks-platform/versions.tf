terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.95" }
    helm    = { source = "hashicorp/helm", version = "~> 2.17" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.1" }
  }

  # Partial config: supply bucket/key/region in backend.hcl (see backend.hcl.example)
  backend "s3" {}
}
