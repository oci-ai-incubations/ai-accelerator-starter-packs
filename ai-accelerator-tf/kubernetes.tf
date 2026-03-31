# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Kubernetes cluster configuration locals
# Provider configuration should be done separately after cluster creation

locals {
  # Server URL from kubeconfig (works for both created and existing clusters)
  kubeconfig_server_url = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["clusters"][0]["cluster"]["server"], "")

  # ip.ip.ip.ip:6443 - ip is either private or public
  cluster_endpoint_public_full  = try(local.oke_cluster.endpoints[0].public_endpoint, "")
  cluster_endpoint_private_full = try(local.oke_cluster.endpoints[0].private_endpoint, "")

  # Extract just the IP addresses (remove :6443 port)
  cluster_endpoint_public  = try(regex("([^:]+)", local.cluster_endpoint_public_full)[0], "")
  cluster_endpoint_private = try(regex("([^:]+)", local.cluster_endpoint_private_full)[0], "")

  # https://ip.ip.ip.ip:6443 - ip is either private or public
  cluster_endpoint_public_host = local.cluster_endpoint_public_full != "" ? format("https://%s", local.cluster_endpoint_public_full) : local.kubeconfig_server_url

  # ORM PE endpoint: https://<reachable_ip>:6443
  cluster_orm_endpoint = local.create_orm_private_endpoint ? format(
    "https://%s:6443",
    data.oci_resourcemanager_private_endpoint_reachable_ip.oke[0].ip_address
  ) : ""

  # Provider host selection priority: ORM PE > public > kubeconfig server URL
  provider_host = local.create_orm_private_endpoint ? local.cluster_orm_endpoint : local.cluster_endpoint_public_host

  # TLS server name must match the real endpoint hostname for cert validation when using ORM PE
  provider_tls_server_name = local.create_orm_private_endpoint ? local.cluster_endpoint_private : null

  # CA certificate and other details from kubeconfig (still needed for authentication)
  cluster_ca_certificate = try(base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["clusters"][0]["cluster"]["certificate-authority-data"]), "")
  cluster_id             = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][4], local.effective_cluster_id)
  cluster_region         = try(yamldecode(data.oci_containerengine_cluster_kube_config.oke.content)["users"][0]["user"]["exec"]["args"][6], var.region)
}

resource "kubernetes_namespace_v1" "cluster_tools" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "cluster-tools"
  }
}

resource "kubernetes_namespace_v1" "milvus" {
  metadata {
    name = "milvus"
  }
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0
}
