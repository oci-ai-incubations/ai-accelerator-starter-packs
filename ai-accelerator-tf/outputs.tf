# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Cluster Information
output "cluster_id" {
  description = "ID of the OKE cluster"
  value       = local.oke_cluster.id
}

output "cluster_name" {
  description = "Name of the OKE cluster"
  value       = local.oke_cluster.name
}

output "public_cluster_endpoint_full" {
  description = "Kubernetes API endpoint (public)"
  value       = local.cluster_endpoint_public_full
}

output "private_cluster_endpoint_full" {
  description = "Kubernetes API endpoint (private)"
  value       = local.cluster_endpoint_private_full
}

output "public_cluster_endpoint" {
  description = "Kubernetes API endpoint (public)"
  value       = local.cluster_endpoint_public
}

output "private_cluster_endpoint" {
  description = "Kubernetes API endpoint (private)"
  value       = local.cluster_endpoint_private
}

output "cluster_endpoint_visibility" {
  description = "Visibility of the Kubernetes API endpoint"
  value       = local.cluster_endpoint_visibility
}

# Network Information
output "vcn_id" {
  description = "ID of the VCN"
  value       = local.vcn_id
}

output "vcn_cidr" {
  description = "CIDR block of the VCN"
  value       = lookup(var.network_cidrs, "VCN-CIDR")
}

# Node Pool Information
output "node_pool_id" {
  description = "ID of the node pool"
  value       = oci_containerengine_node_pool.oke_node_pool.id
}

output "node_pool_kubernetes_version" {
  description = "Kubernetes version of the node pool"
  value       = oci_containerengine_node_pool.oke_node_pool.kubernetes_version
}

# Bastion Information (when created)
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = var.create_bastion && local.create_network_resources ? oci_core_instance.bastion[0].public_ip : null
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = var.create_bastion && local.create_network_resources ? oci_core_instance.bastion[0].private_ip : null
}

# Operator Information (when created)
output "operator_private_ip" {
  description = "Private IP address of the operator instance"
  value       = var.create_bastion && local.create_network_resources ? oci_core_instance.operator[0].private_ip : null
}

# SSH Key Information
output "ssh_private_key" {
  description = "Generated SSH private key (only if no public key was provided)"
  value       = var.ssh_public_key == "" ? tls_private_key.oke_ssh_key[0].private_key_pem : null
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key used for instances"
  value       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.oke_ssh_key[0].public_key_openssh
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to the cluster"
  value = var.create_bastion && local.create_network_resources ? {
    bastion_ssh = "ssh -i <private_key_file> opc@${oci_core_instance.bastion[0].public_ip}"
    operator_ssh_via_bastion = "ssh -i <private_key_file> -J opc@${oci_core_instance.bastion[0].public_ip} opc@${oci_core_instance.operator[0].private_ip}"
    kubectl_setup = "After connecting to operator instance, run: ./configure_oke.sh"
  } : {
    direct_access = local.cluster_endpoint_visibility == "Public" ? "Configure kubectl with: oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id}" : "Cluster has private endpoint - use bastion/operator setup"
  }
}

# Kubeconfig Command
output "kubeconfig_command" {
  description = "Command to generate kubeconfig file"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${local.oke_cluster.id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0"
}

# Load Balancer Subnet Information
output "lb_subnet_bp_control_plane_id" {
  description = "ID of the load balancer subnet for blueprints control plane"
  value       = local.create_network_resources ? oci_core_subnet.oke_lb_subnet[0].id : var.existing_lb_subnet_id
}

output "lb_subnet_apps_id" {
  description = "ID of the load balancer subnet for applications"
  value       = local.create_network_resources ? oci_core_subnet.oke_lb_subnet_apps[0].id : var.existing_lb_subnet_id
}

# Deployment Information
output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_string.deploy_id.result
}

output "app_name" {
  description = "Application name"
  value       = local.app_name
}
