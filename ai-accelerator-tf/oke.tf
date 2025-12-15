# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# OKE Cluster
resource "oci_containerengine_cluster" "oke_cluster" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.k8s_version
  name               = "AI-Accel-OKE-${random_string.deploy_id.result}"
  vcn_id             = local.vcn_id

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  endpoint_config {
    is_public_ip_enabled = local.cluster_endpoint_visibility == "Public" ? true : false
    subnet_id            = local.endpoint_subnet_id
    nsg_ids              = []
  }

  options {
    service_lb_subnet_ids = [local.lb_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = var.cluster_options_add_ons_is_kubernetes_dashboard_enabled
      is_tiller_enabled               = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    kubernetes_network_config {
      pods_cidr     = lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")
      services_cidr = lookup(var.network_cidrs, "SERVICES-SUBNET-REGIONAL-CIDR")
    }
  }
  type  = "ENHANCED_CLUSTER"
  count = var.network_configuration_mode == "create_new" ? 1 : 0

  depends_on = [
    oci_core_subnet.oke_k8s_endpoint_subnet,
    oci_core_subnet.oke_nodes_subnet,
    oci_core_subnet.oke_lb_subnet
  ]
}

# OKE Cluster for existing VCN
resource "oci_containerengine_cluster" "oke_cluster_existing_vcn" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.k8s_version
  name               = "AI-Accel-OKE-${random_string.deploy_id.result}"
  vcn_id             = local.vcn_id

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  endpoint_config {
    is_public_ip_enabled = local.cluster_endpoint_visibility == "Public" ? true : false
    subnet_id            = local.endpoint_subnet_id
    nsg_ids              = []
  }

  options {
    service_lb_subnet_ids = [local.lb_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = var.cluster_options_add_ons_is_kubernetes_dashboard_enabled
      is_tiller_enabled               = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    kubernetes_network_config {
      pods_cidr     = lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")
      services_cidr = lookup(var.network_cidrs, "SERVICES-SUBNET-REGIONAL-CIDR")
    }
  }

  count = var.network_configuration_mode == "bring_your_own" ? 1 : 0
}

# Local to get the correct cluster based on configuration mode
locals {
  oke_cluster = var.network_configuration_mode == "create_new" ? oci_containerengine_cluster.oke_cluster[0] : oci_containerengine_cluster.oke_cluster_existing_vcn[0]
}

# OKE Node Pool
resource "oci_containerengine_node_pool" "oke_node_pool" {
  cluster_id         = local.oke_cluster.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.k8s_version
  name               = var.node_pool_name

  node_config_details {
    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = local.node_subnet_id
      }
    }

    size = var.control_plane_node_pool_size

    nsg_ids = []
  }

  node_shape = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape

  dynamic "node_shape_config" {
    for_each = length(regexall("Flex", local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape)) > 0 ? [1] : []
    content {
      ocpus         = local.starter_pack_config.control_plane_node_pool_instance_shape.ocpus
      memory_in_gbs = local.starter_pack_config.control_plane_node_pool_instance_shape.memory
    }
  }

  node_source_details {
    image_id    = data.oci_core_images.oracle_linux.images[0].id
    source_type = "IMAGE"

    boot_volume_size_in_gbs = var.node_pool_boot_volume_size_in_gbs
  }

  initial_node_labels {
    key   = "name"
    value = var.node_pool_name
  }

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.oke_ssh_key[0].public_key_openssh
}

# Generate SSH key pair if not provided
resource "tls_private_key" "oke_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
  count     = var.ssh_public_key == "" ? 1 : 0
}

data "oci_containerengine_cluster_kube_config" "oke_kube_config" {
  cluster_id = oci_containerengine_cluster.oke_cluster[0].id
}

output "oke_kube_config" {
  value = data.oci_containerengine_cluster_kube_config.oke_kube_config.content
}