# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Kubernetes cluster configuration locals
# Provider configuration should be done separately after cluster creation

locals {
  # ip.ip.ip.ip:6443 - ip is either private or public
  cluster_endpoint_public_full  = try(local.oke_cluster.endpoints[0].public_endpoint, "")
  cluster_endpoint_private_full = try(local.oke_cluster.endpoints[0].private_endpoint, "")

  # Extract just the IP addresses (remove :6443 port)
  cluster_endpoint_public  = try(regex("([^:]+)", local.cluster_endpoint_public_full)[0], "")
  cluster_endpoint_private = try(regex("([^:]+)", local.cluster_endpoint_private_full)[0], "")

  # https://ip.ip.ip.ip:6443 - ip is either private or public
  cluster_endpoint_public_host  = format("https://%s", local.cluster_endpoint_public_full)
  cluster_endpoint_private_host = format("https://%s", local.cluster_endpoint_private_full)


  # CA certificate and other details from kubeconfig (still needed for authentication)
  cluster_ca_certificate = try(base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["clusters"][0]["cluster"]["certificate-authority-data"]), "")
  cluster_id             = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][4], local.oke_cluster.id)
  cluster_region         = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][6], var.region)

  # Validation - this will cause terraform to fail if cluster endpoint is not available
  cluster_endpoint_validation = local.cluster_endpoint_public_full != "" ? local.cluster_endpoint_public_full : (
    # This will cause an error if the cluster endpoint is empty
    can(regex("^https://", "")) ? "" : "ERROR: Cluster endpoint not available"
  )
}

resource "kubernetes_namespace_v1" "cluster_tools" {
  metadata {
    name = "cluster-tools"
  }
}

resource "kubernetes_namespace_v1" "milvus" {
  metadata {
    name = "milvus"
  }
  count = var.starter_pack_category == "vss" ? 1 : 0
}
