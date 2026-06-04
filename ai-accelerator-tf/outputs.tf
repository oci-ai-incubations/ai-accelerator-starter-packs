# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Cluster Information
output "oke_kube_config" {
  value = data.oci_containerengine_cluster_kube_config.oke_kube_config.content
}

output "cluster_id" {
  description = "ID of the OKE cluster"
  value       = local.effective_cluster_id
}

output "cluster_name" {
  description = "Name of the OKE cluster"
  value       = try(local.oke_cluster.name, "existing-cluster")
}

output "cluster_ca_certificate" {
  description = "OKE cluster CA certificate (base64 encoded) -- needed for bring-your-own-cluster provider configuration"
  value       = try(base64encode(local.cluster_ca_certificate), null)
  sensitive   = true
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
  value       = var.network_cidrs["VCN-CIDR"]
}

# Node Pool Information
output "node_pool_id" {
  description = "ID of the node pool"
  value       = local.deploy_infrastructure ? oci_containerengine_node_pool.oke_node_pool[0].id : null
}

output "node_subnet_id" {
  description = "OCID of the worker node subnet"
  value       = local.node_subnet_id
}

output "node_pool_kubernetes_version" {
  description = "Kubernetes version of the node pool"
  value       = local.deploy_infrastructure ? oci_containerengine_node_pool.oke_node_pool[0].kubernetes_version : null
}

output "worker_node_availability_domain" {
  description = "Availability domain selected for worker nodes (user-provided)"
  value       = local.worker_node_availability_domain
}

# Bastion Information (when created)
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = local.create_bastion_effective && local.create_network_resources ? oci_core_instance.bastion[0].public_ip : null
}

output "bastion_ssh_target" {
  description = "Bastion SSH target (username@ip) for easy copy-paste: opc@<bastion_public_ip>"
  value       = local.create_bastion_effective && local.create_network_resources ? "opc@${oci_core_instance.bastion[0].public_ip}" : null
}

output "bastion_private_ssh_key" {
  description = "Private SSH key for bastion access (save as .pem file). Only set when bastion is enabled and no custom SSH public key was provided."
  value       = local.create_bastion_effective && local.create_network_resources && var.ssh_public_key == "" ? tls_private_key.oke_ssh_key[0].private_key_pem : null
  sensitive   = true
}

output "worker_ssh_target_format" {
  description = "SSH target format for worker nodes — substitute <username> (e.g. opc) and <worker_ip> with actual node IP from: kubectl get nodes -o wide"
  value       = local.create_bastion_effective && local.create_network_resources ? "<username>@<worker_ip>" : null
}

output "worker_ssh_via_bastion_command" {
  description = "SSH command template to jump to a worker node via bastion. Replace <path_to_key.pem> and <user>@<worker_ip> with your key path and target (e.g. opc@10.0.97.217)"
  value       = local.create_bastion_effective && local.create_network_resources ? "ssh -o 'ProxyCommand=ssh -i <path_to_key.pem> -o IdentitiesOnly=yes -W %h:%p opc@${oci_core_instance.bastion[0].public_ip}' -i <path_to_key.pem> -o IdentitiesOnly=yes <user>@<worker_ip>" : null
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = local.create_bastion_effective && local.create_network_resources ? oci_core_instance.bastion[0].private_ip : null
}

# Operator Information (when created)
output "operator_private_ip" {
  description = "Private IP address of the operator instance"
  value       = local.create_bastion_effective && local.create_network_resources ? oci_core_instance.operator[0].private_ip : null
}

# SSH Key Information
output "ssh_private_key" {
  description = "Generated SSH private key (only if no public key was provided)"
  value       = local.deploy_infrastructure && var.ssh_public_key == "" ? tls_private_key.oke_ssh_key[0].private_key_pem : null
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key used for instances"
  value       = var.ssh_public_key != "" ? var.ssh_public_key : (local.deploy_infrastructure ? tls_private_key.oke_ssh_key[0].public_key_openssh : null)
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to the cluster"
  value = local.create_bastion_effective && local.create_network_resources ? {
    bastion_ssh              = "ssh -i <private_key_file> opc@${oci_core_instance.bastion[0].public_ip}"
    operator_ssh_via_bastion = "ssh -i <private_key_file> -J opc@${oci_core_instance.bastion[0].public_ip} opc@${oci_core_instance.operator[0].private_ip}"
    kubectl_setup            = "After connecting to operator instance, run: ./configure_oke.sh"
    } : {
    direct_access = local.cluster_endpoint_visibility == "Public" ? "Configure kubectl with: oci ce cluster create-kubeconfig --cluster-id ${local.effective_cluster_id}" : "Cluster has private endpoint - use bastion/operator setup"
  }
}

# Kubeconfig Command
output "kubeconfig_command" {
  description = "Command to generate kubeconfig file"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${local.effective_cluster_id} --file $HOME/.kube/config --region ${local.region} --token-version 2.0.0"
}

# Load Balancer IP Address
output "external_ip" {
  description = "Public IP address of the ingress load balancer. If Custom DNS is enabled, configure DNS A records to point your domain(s) to this IP."
  value       = local.deploy_application && var.use_custom_dns ? local.network.external_ip : "N/A - Using automatic nip.io domain"
}

# Custom DNS Domain - shows the wildcard A-record domain that needs to be configured
output "custom_dns_domain" {
  description = "If Custom DNS is enabled, create a wildcard A-record for this domain pointing to the Load Balancer IP above."
  value       = var.use_custom_dns ? "*.${var.fqdn_custom_domain}" : "N/A - Custom DNS not enabled"
}

# Load Balancer Subnet Information
output "lb_subnet_bp_control_plane_id" {
  description = "ID of the load balancer subnet for blueprints control plane"
  value       = local.lb_subnet_id
}

output "lb_subnet_apps_id" {
  description = "ID of the load balancer subnet for applications"
  value       = local.lb_subnet_id
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
  value       = local.deploy_application ? local.public_endpoint.starter_pack : null
}

output "blueprints_portal_url" {
  description = "Portal FQDN"
  value       = local.deploy_application ? local.public_endpoint.blueprint_portal : null
}

output "corrino_api_url" {
  description = "Corrino API URL"
  value       = local.deploy_application ? local.public_endpoint.api : null
}

output "prometheus_url" {
  description = "Prometheus FQDN"
  value       = local.deploy_application ? local.public_endpoint.prometheus : null
}

output "grafana_url" {
  description = "Grafana FQDN"
  value       = local.deploy_application ? local.public_endpoint.grafana : null
}

output "corrino_admin_username" {
  description = "Corrino admin username"
  value       = var.corrino_admin_username
}

output "corrino_admin_password" {
  description = "Corrino admin password"
  value       = local.corrino_admin_password
  sensitive   = true
}

output "corrino_admin_email" {
  description = "Corrino admin email"
  value       = var.corrino_admin_email
}

output "grafana_admin_username" {
  description = "Grafana admin username"
  value       = local.deploy_application ? local.addon.grafana_user : null
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = local.deploy_application ? nonsensitive(local.addon.grafana_token) : null
}

# Autonomous Database Outputs
output "autonomous_database_id" {
  description = "OCID of the Autonomous Database"
  value       = local.deploy_app_26ai ? oci_database_autonomous_database.oracle_26ai[0].id : null
}

output "autonomous_database_name" {
  description = "Name of the Autonomous Database"
  value       = local.deploy_app_26ai ? oci_database_autonomous_database.oracle_26ai[0].db_name : null
}

output "connection_strings" {
  description = "Connection strings for the Autonomous Database"
  value       = local.deploy_app_26ai ? oci_database_autonomous_database.oracle_26ai[0].connection_strings : null
  sensitive   = true
}

output "private_endpoint" {
  description = "Private endpoint details"
  value       = local.deploy_app_26ai ? oci_database_autonomous_database.oracle_26ai[0].private_endpoint : null
}

output "autonomous_db_subnet_id" {
  description = "OCID of the Autonomous Database subnet"
  value       = local.autonomous_db_subnet_id
}

output "db_username" {
  description = "Admin username for the Oracle 26ai Autonomous Database"
  value       = var.db_username
}

output "db_password" {
  description = "Admin password for the Oracle 26ai Autonomous Database"
  value       = local.db_password
  sensitive   = true
}

output "object_storage_namespace" {
  description = "Namespace for Object Storage"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "selected_worker_node_availability_domain" {
  description = "Availability domain selected for worker nodes (for debugging)"
  value       = local.worker_node_availability_domain
}

# Version Information
output "ai_accelerator_stack_version" {
  description = "AI Accelerator Starter Packs stack version"
  value       = file("${path.module}/AI_ACCELERATOR_STACK_VERSION")
}

# Frontend Skin Information
output "frontend_skin_name" {
  description = "Selected frontend skin"
  value       = local.deploy_application ? local.frontend_skin_name : null
}

output "frontend_skin_provider" {
  description = "Provider of the selected frontend skin"
  value       = local.deploy_application ? local.frontend_skin_provider : null
}

output "frontend_skins_learn_more" {
  description = "URL for frontend skin documentation"
  value       = local.frontend_skins_catalog.learn_more_url
}

output "auth_service_curl_example" {
  description = <<-EOT
    Worked curl example for obtaining a JWT from auth-service and using
    it to call a protected backend endpoint. Replace
    <admin@example.com> / <password> with credentials registered in the
    auth-service. The first registered user is auto-promoted to admin
    via AUTH_AUTO_ADMIN_FIRST_USER=true; subsequent users default to
    "pending" and must be granted a role by an admin. Access tokens are
    short-lived (default 15 min — refresh via POST /auth/refresh with
    the paired refresh token). For machine-to-machine traffic see
    POST /auth/oauth/token (Client Credentials grant) — register the
    service account first with POST /auth/clients.
  EOT
  value = local.enable_auth_service && local.deploy_application ? format(
    "# 1. Log in and capture the access token:\nTOKEN=$(curl -sk -X POST https://%s/auth/login \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"email\":\"<admin@example.com>\",\"password\":\"<password>\"}' \\\n  | jq -r .access_token)\n\n# 2. Call a protected backend endpoint with the bearer:\ncurl -sk -H \"Authorization: Bearer $TOKEN\" https://%s/api/<endpoint>",
    local.public_endpoint.starter_pack,
    local.public_endpoint.starter_pack,
  ) : "Auth service is disabled."
}

output "frontend_skin_urls" {
  description = "Map of enabled frontend skin keys to their URLs — one entry per enabled cuopt skin. Empty for deploy_application=false. ORM renders map keys alphabetically."
  value = local.deploy_application ? {
    for skin in local.enabled_frontend_skins :
    skin.key => "https://${skin.subdomain}.${local.fqdn.name}"
  } : {}
}

output "sso_callback_redirect_uris" {
  description = <<-EOT
    Expected SSO callback URLs to register in your IdP's Confidential Application
    (OCI IAM Identity Domains "Redirect URL" field, Entra "Redirect URI" field, etc.)
    when enable_auth_service = true. The `{slug}` placeholder is the auth-service
    provider slug you register via POST /auth/providers — typically "oracle-idcs"
    for IDCS, "azure-entra" for Microsoft Entra. The path lives outside /auth/* on
    purpose: the ingress routes /auth/* unconditionally to the auth-service pod,
    which would shadow any FE callback under that prefix. Empty when auth-service
    is disabled or the application isn't deployed.
  EOT
  value = local.enable_auth_service && local.deploy_application ? {
    for skin in local.enabled_frontend_skins :
    skin.key => "https://${skin.subdomain}.${local.fqdn.name}/sso/callback/{slug}"
  } : {}
}