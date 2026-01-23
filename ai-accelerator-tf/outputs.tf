# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Cluster Information
output "oke_kube_config" {
  value = data.oci_containerengine_cluster_kube_config.oke_kube_config.content
}

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
    bastion_ssh              = "ssh -i <private_key_file> opc@${oci_core_instance.bastion[0].public_ip}"
    operator_ssh_via_bastion = "ssh -i <private_key_file> -J opc@${oci_core_instance.bastion[0].public_ip} opc@${oci_core_instance.operator[0].private_ip}"
    kubectl_setup            = "After connecting to operator instance, run: ./configure_oke.sh"
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
  value       = local.create_network_resources ? oci_core_subnet.oke_lb_subnet[0].id : var.existing_lb_subnet_id
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

output "starter_pack_deployment_name" {
  description = "Starter pack deployment name"
  value       = local.starter_pack_deployment_name
}

output "starter_pack_url" {
  description = "Starter pack FQDN"
  value = var.starter_pack_category == "vss" ? (
    local.vss_dynamic_url != "" ?
    local.vss_dynamic_url :
    local.public_endpoint.starter_pack
  ) : local.public_endpoint.starter_pack
}

output "paas_rag_url" {
  description = "Paas RAG FQDN"
  value = var.starter_pack_category == "paas_rag" ? "https://frontend-paas.${local.fqdn.name}" : "#Paas RAG Starter Pack Disabled"
}

output "starter_pack_marketing_url" {
  description = "Starter pack marketing FQDN"
  value = var.starter_pack_category == "cuopt" ? (
    var.cuopt_marketing_enabled ? local.cuopt_marketing_url : "#Marketing Disabled"
  ) : "#Marketing Disabled"
}

output "blueprints_portal_url" {
  description = "Portal FQDN"
  value       = local.public_endpoint.blueprint_portal
}

output "corrino_api_url" {
  description = "Corrino API URL"
  value       = local.public_endpoint.api
}

output "prometheus_url" {
  description = "Prometheus FQDN"
  value       = local.public_endpoint.prometheus
}

output "grafana_url" {
  description = "Grafana FQDN"
  value       = local.public_endpoint.grafana
}

output "corrino_admin_username" {
  description = "Corrino admin username"
  value       = var.corrino_admin_username
}

output "corrino_admin_password" {
  description = "Corrino admin password"
  value       = var.corrino_admin_password
}

output "corrino_admin_email" {
  description = "Corrino admin email"
  value       = var.corrino_admin_email
}

output "grafana_admin_username" {
  description = "Grafana admin username"
  value       = local.addon.grafana_user
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = nonsensitive(local.addon.grafana_token)
}

# Autonomous Database Outputs
output "autonomous_database_id" {
  description = "OCID of the Autonomous Database"
  value       = local.needs_26ai ? oci_database_autonomous_database.oracle_26ai[0].id : null
}

output "autonomous_database_name" {
  description = "Name of the Autonomous Database"
  value       = local.needs_26ai ? oci_database_autonomous_database.oracle_26ai[0].db_name : null
}

output "connection_strings" {
  description = "Connection strings for the Autonomous Database"
  value       = local.needs_26ai ? oci_database_autonomous_database.oracle_26ai[0].connection_strings : null
  sensitive   = true
}

output "private_endpoint" {
  description = "Private endpoint details"
  value       = local.needs_26ai ? oci_database_autonomous_database.oracle_26ai[0].private_endpoint : null
}

output "db_subnet_id" {
  description = "OCID of the database subnet"
  value       = local.create_network_resources ? oci_core_subnet.oke_db_subnet[0].id : null
}

output "db_username" {
  description = "Admin username for the Oracle 26ai Autonomous Database"
  value       = var.db_username
}

output "db_password" {
  description = "Admin password for the Oracle 26ai Autonomous Database"
  value       = var.db_password
  sensitive   = true
}

output "paas_rag_bucket_id" {
  description = "OCID of the PaaS RAG specific Object Storage bucket (if created)"
  value       = var.starter_pack_category == "paas_rag" ? oci_objectstorage_bucket.paas_rag_bucket[0].id : null
}

output "paas_rag_bucket_name" {
  description = "Name of the PaaS RAG specific Object Storage bucket (if created)"
  value       = var.starter_pack_category == "paas_rag" ? oci_objectstorage_bucket.paas_rag_bucket[0].name : null
}

output "object_storage_namespace" {
  description = "Namespace for Object Storage"
  value       = data.oci_objectstorage_namespace.ns.namespace
}
