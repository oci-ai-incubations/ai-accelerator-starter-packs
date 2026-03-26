# Copyright (c) 2020-2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  region       = var.region
  auth         = var.use_instance_principal ? "InstancePrincipal" : null

  user_ocid        = var.use_instance_principal ? null : var.current_user_ocid
  fingerprint      = var.use_instance_principal ? null : var.fingerprint
  private_key_path = var.use_instance_principal ? null : var.private_key_path
}

provider "oci" {
  alias        = "home_region"
  tenancy_ocid = var.tenancy_ocid
  region       = data.oci_identity_regions.home_region.regions[0]["name"]
  auth         = var.use_instance_principal ? "InstancePrincipal" : null

  user_ocid        = var.use_instance_principal ? null : var.current_user_ocid
  fingerprint      = var.use_instance_principal ? null : var.fingerprint
  private_key_path = var.use_instance_principal ? null : var.private_key_path
}

# tflint-ignore: terraform_unused_declarations
provider "oci" {
  alias        = "current_region"
  tenancy_ocid = var.tenancy_ocid
  region       = var.region
  auth         = var.use_instance_principal ? "InstancePrincipal" : null

  user_ocid        = var.use_instance_principal ? null : var.current_user_ocid
  fingerprint      = var.use_instance_principal ? null : var.fingerprint
  private_key_path = var.use_instance_principal ? null : var.private_key_path
}

# Separate provider for OCI Generative AI resources (dedicated AI cluster, endpoint, model lookup).
# GenAI dedicated hosting is only available in specific regions (e.g., us-chicago-1), which may
# differ from var.region where the OKE cluster and other infrastructure are deployed.
# Note that llama stack uses var.genai_region at the application level to call the GenAI inference
# API, but this provider is needed to create the actual OCI resources (cluster, endpoint) in that region.
provider "oci" {
  alias        = "genai_region"
  tenancy_ocid = var.tenancy_ocid
  region       = var.genai_region
  auth         = var.use_instance_principal ? "InstancePrincipal" : null

  user_ocid        = var.use_instance_principal ? null : var.current_user_ocid
  fingerprint      = var.use_instance_principal ? null : var.fingerprint
  private_key_path = var.use_instance_principal ? null : var.private_key_path
}

# New configuration to avoid Terraform Kubernetes provider interpolation. https://registry.terraform.io/providers/hashicorp/kubernetes/2.2.0/docs#stacking-with-managed-kubernetes-cluster-resources
# Currently need to uncheck to refresh (--refresh=false) when destroying or else the terraform destroy will fail

# Kubernetes and Helm providers configuration
provider "kubernetes" {
  host                   = local.provider_host
  tls_server_name        = local.provider_tls_server_name
  cluster_ca_certificate = local.cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args = [
      "ce",
      "cluster",
      "generate-token",
      "--cluster-id",
      local.cluster_id,
      "--region",
      local.cluster_region
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.provider_host
    tls_server_name        = local.provider_tls_server_name
    cluster_ca_certificate = local.cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args = [
        "ce",
        "cluster",
        "generate-token",
        "--cluster-id",
        local.cluster_id,
        "--region",
        local.cluster_region
      ]
    }
  }
}
