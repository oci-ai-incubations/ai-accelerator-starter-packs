# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Kubernetes cluster configuration locals
# Provider configuration should be done separately after cluster creation

locals {
  # Full endpoints from the cluster resource
  cluster_endpoint_public_full  = local.oke_cluster.endpoints[0].public_endpoint
  cluster_endpoint_private_full = local.oke_cluster.endpoints[0].private_endpoint
  
  # Extract just the IP addresses (remove :6443 port)
  cluster_endpoint_public  = try(regex("([^:]+)", local.cluster_endpoint_public_full)[0], "")
  cluster_endpoint_private = try(regex("([^:]+)", local.cluster_endpoint_private_full)[0], "")
  
  # Use full endpoint for kubernetes provider (needs the full URL)
  cluster_endpoint = local.oke_cluster.endpoints[0].kubernetes
  
  # CA certificate and other details from kubeconfig (still needed for authentication)
  cluster_ca_certificate = try(base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["clusters"][0]["cluster"]["certificate-authority-data"]), "")
  cluster_id             = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][4], "")
  cluster_region         = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][6], var.region)
}

resource "kubernetes_namespace" "cluster_tools" {
  metadata {
    name = "cluster-tools"
  }
}
