# Copyright (c) 2021 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Authentication Configuration
variable "use_instance_principal" {
  type        = bool
  default     = false
  description = "Whether to use Instance Principal for authentication. If false, user credentials will be used."
}

variable "fingerprint" {
  type        = string
  default     = ""
  description = "API Key Fingerprint for user authentication. Required when use_instance_principal is false."
}

variable "private_key_path" {
  type        = string
  default     = ""
  description = "Path to the private key file for user authentication. Required when use_instance_principal is false."
}

# Networking Configuration Mode
variable "network_configuration_mode" {
  default     = "create_new"
  description = "Whether to create a new VCN or use an existing one"
  type        = string

  validation {
    condition     = contains(["create_new", "bring_your_own"], var.network_configuration_mode)
    error_message = "Network configuration mode must be either 'create_new' or 'bring_your_own'."
  }

}

# Bring Your Own VCN Variables
variable "existing_vcn_id" {
  default     = ""
  description = "OCID of the existing VCN to use. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "existing_endpoint_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for the Kubernetes API endpoint. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "existing_node_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for worker nodes. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "existing_lb_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for load balancers. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

# tflint-ignore: terraform_unused_declarations
variable "existing_pods_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for pods. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

# tflint-ignore: terraform_unused_declarations
variable "existing_services_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for services. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "existing_autonomous_db_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for the Oracle Autonomous Database private endpoint. Required when using existing_cluster_id with paas_rag or enterprise_rag."
  type        = string
}

variable "create_policies" {
  default     = true
  description = "Unchecking box will not create IAM policies with stack. Requires an admin to create policies."
  type        = bool
}

# -----------------------------------
# Corrino User
# -----------------------------------

variable "corrino_admin_username" {
  description = "The user name used to login to OCI AI Blueprints"
  type        = string
}

variable "corrino_admin_password" {
  description = "The password used to login to OCI AI Blueprints"
  type        = string
}

variable "corrino_admin_email" {
  description = "The email address used to identify the OCI AI Blueprints user"
  type        = string
}

variable "share_data_with_corrino_team_enabled" {
  description = "Allow this Terraform to send a small registration file to OCI AI Blueprints team."
  type        = bool
  default     = true
}

# OKE Variables
## OKE Cluster Details
variable "cluster_options_add_ons_is_kubernetes_dashboard_enabled" {
  type    = bool
  default = false
}

## OKE Visibility (Workers and Endpoint)

# tflint-ignore: terraform_unused_declarations
variable "cluster_workers_visibility" {
  type        = string
  default     = "Private"
  description = "The Kubernetes worker nodes that are created will be hosted in public or private subnet(s)"

  validation {
    condition     = var.cluster_workers_visibility == "Private" || var.cluster_workers_visibility == "Public"
    error_message = "Sorry, but cluster visibility can only be Private or Public."
  }
}

variable "cluster_endpoint_visibility_new_vcn" {
  default     = "Public"
  description = "The Kubernetes API endpoint visibility when creating a new VCN"
  type        = string

  validation {
    condition     = var.cluster_endpoint_visibility_new_vcn == "Private" || var.cluster_endpoint_visibility_new_vcn == "Public"
    error_message = "Endpoint visibility must be either 'Private' or 'Public'."
  }
}

variable "cluster_endpoint_visibility_existing_vcn" {
  default     = "Public"
  description = "The Kubernetes API endpoint visibility when using an existing VCN"
  type        = string

  validation {
    condition     = var.cluster_endpoint_visibility_existing_vcn == "Private" || var.cluster_endpoint_visibility_existing_vcn == "Public"
    error_message = "Endpoint visibility must be either 'Private' or 'Public'."
  }
}

# Combined local for backward compatibility
locals {
  cluster_endpoint_visibility = var.network_configuration_mode == "create_new" ? var.cluster_endpoint_visibility_new_vcn : var.cluster_endpoint_visibility_existing_vcn
}

# Deployment mode locals
locals {
  # Deployment mode detection
  deploy_private_k8s_and_loadbalancer = var.deploy_private_k8s_and_loadbalancer
  k8s_endpoint_private                = local.cluster_endpoint_visibility == "Private"

  # ORM PE needed when deploying from ORM with private K8s endpoint
  create_orm_private_endpoint = local.deploy_infrastructure && local.deploy_private_k8s_and_loadbalancer && local.k8s_endpoint_private

  # Operator needed when: LB is private/CIDR-scoped, or K8s endpoint is private
  # Force bastion+operator creation in these cases
  needs_operator = local.deploy_private_k8s_and_loadbalancer && (
    local.k8s_endpoint_private ||
    var.blueprints_endpoint_visibility == "Private"
  )
  create_bastion_effective = var.create_bastion || local.needs_operator

  # Readiness checks should go through operator when ORM can't reach the LB
  readiness_via_operator = local.deploy_infrastructure && local.deploy_private_k8s_and_loadbalancer && local.create_bastion_effective
}

## OKE Node Pool Details
variable "node_pool_name" {
  type        = string
  default     = "control-plane"
  description = "Name of the node pool"
}
variable "k8s_version" {
  type        = string
  default     = "v1.34.1"
  description = "Kubernetes version installed on your master and worker nodes"
}
# variable "worker_node_pool_size" {
#   default     = 1
#   description = "The number of worker nodes in the node pool."
# }

# variable "control_plane_node_pool_instance_shape" {
#   type = map(any)
#   default = {
#     "instanceShape" = "VM.Standard.E5.Flex"
#     "ocpus"         = 3
#     "memory"        = 64
#   }
#   description = "A shape is a template that determines the number of OCPUs, amount of memory, and other resources allocated to a newly created instance for the Worker Node. Select at least 2 OCPUs and 16GB of memory if using Flex shapes"
# }

# Network Details
## CIDRs
variable "network_cidrs" {
  type = map(string)

  default = {
    VCN-CIDR                                 = "10.0.0.0/16"
    ENDPOINT-SUBNET-REGIONAL-CIDR            = "10.0.80.0/20"
    NODES-SUBNET-REGIONAL-CIDR               = "10.0.96.0/20"
    LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR = "10.0.112.0/20"
    LB-SUBNET-APPS-REGIONAL-CIDR             = "10.0.128.0/20"
    DB-SUBNET-REGIONAL-CIDR                  = "10.0.2.0/24"
    PODS-SUBNET-REGIONAL-CIDR                = "172.16.0.0/16"
    SERVICES-SUBNET-REGIONAL-CIDR            = "172.17.0.0/16"
    BASTION-SUBNET-REGIONAL-CIDR             = "10.0.192.0/20"
    OPERATOR-SUBNET-REGIONAL-CIDR            = "10.0.208.0/20"
    ALL-CIDR                                 = "0.0.0.0/0"
  }
}

variable "blueprints_endpoint_visibility" {
  default     = "Public"
  description = "The visibility of the blueprints endpoint"
  type        = string
  validation {
    condition     = var.blueprints_endpoint_visibility == "Private" || var.blueprints_endpoint_visibility == "Public"
    error_message = "Blueprints endpoint visibility must be either 'Private' or 'Public'."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "apps_endpoint_visibility" {
  default     = "Private"
  description = "The visibility of the apps endpoint"
  type        = string
  validation {
    condition     = var.apps_endpoint_visibility == "Private" || var.apps_endpoint_visibility == "Public"
    error_message = "Apps endpoint visibility must be either 'Private' or 'Public'."
  }
}

# OCI Provider
variable "tenancy_ocid" {
  type = string
}
variable "compartment_ocid" {
  type = string
}
variable "region" {
  type = string
}
variable "current_user_ocid" {
  type = string
}

# ORM Schema visual control variables
# tflint-ignore: terraform_unused_declarations
variable "show_advanced" {
  type    = bool
  default = false
}

# ORM Deployment Configuration
variable "deploy_private_k8s_and_loadbalancer" {
  type        = bool
  default     = false
  description = "Deploys a completely private stack not accessible via internet. More secure, but the final URL will not be accessible from the public internet without first port forwarding. Suitable for production deployments."
}

# Bastion and Operator Configuration
variable "create_bastion" {
  type        = bool
  default     = false
  description = "Whether to create bastion and operator instances for private cluster access"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for bastion and operator instances. If empty, a new key pair will be generated."
}

variable "bastion_instance_shape" {
  type = map(any)
  default = {
    "instanceShape" = "VM.Standard.E5.Flex"
    "ocpus"         = 1
    "memory"        = 8
  }
  description = "Shape configuration for the bastion instance"
}

variable "operator_instance_shape" {
  type = map(any)
  default = {
    "instanceShape" = "VM.Standard.E5.Flex"
    "ocpus"         = 2
    "memory"        = 16
  }
  description = "Shape configuration for the operator instance"
}

variable "bastion_boot_volume_size_in_gbs" {
  type        = string
  default     = "50"
  description = "Boot volume size for bastion instance (in GB)"
}

variable "operator_boot_volume_size_in_gbs" {
  type        = string
  default     = "100"
  description = "Boot volume size for operator instance (in GB)"
}

# Ingress Nginx Configuration
variable "ingress_load_balancer_shape" {
  type        = string
  default     = "flexible" # Flexible, 10Mbps, 100Mbps, 400Mbps or 8000Mps
  description = "Shape that will be included on the Ingress annotation for the OCI Load Balancer creation"
}
variable "ingress_load_balancer_shape_flex_min" {
  type        = string
  default     = "10"
  description = "Enter the minimum size of the flexible shape."
}
variable "ingress_load_balancer_shape_flex_max" {
  type        = string
  default     = "100"
  description = "Enter the maximum size of the flexible shape (Should be bigger than minimum size). The maximum service limit is set by your tenancy limits."
}
# tflint-ignore: terraform_unused_declarations
variable "ingress_hosts" {
  type        = string
  default     = ""
  description = "Enter a valid full qualified domain name (FQDN). You will need to map the domain name to the EXTERNAL-IP address on your DNS provider (DNS Registry type - A). If you have multiple domain names, include separated by comma. e.g.: mushop.example.com,catshop.com"
}
# tflint-ignore: terraform_unused_declarations
variable "ingress_hosts_include_nip_io" {
  type        = bool
  default     = true
  description = "Include app_name.HEXXX.nip.io on the ingress hosts. e.g.: mushop.HEXXX.nip.io"
}
# tflint-ignore: terraform_unused_declarations
variable "nip_io_domain" {
  type        = string
  default     = "nip.io"
  description = "Dynamic wildcard DNS for the application hostname. Should support hex notation. e.g.: nip.io"
}
# tflint-ignore: terraform_unused_declarations
variable "ingress_tls" {
  type        = bool
  default     = true
  description = "If enabled, will generate SSL certificates to enable HTTPS for the ingress using the Certificate Issuer"
}
# tflint-ignore: terraform_unused_declarations
variable "ingress_cluster_issuer" {
  type        = string
  default     = "letsencrypt-prod"
  description = "Certificate issuer type. Currently supports the free Let's Encrypt and Self-Signed. Only *letsencrypt-prod* generates valid certificates"
}
# tflint-ignore: terraform_unused_declarations
variable "ingress_email_issuer" {
  type        = string
  default     = "no-reply@example.cloud"
  description = "You must replace this email address with your own. The certificate provider will use this to contact you about expiring certificates, and issues related to your account."
}
variable "ingress_nginx_enabled" {
  type        = bool
  default     = true
  description = "Enable ingress-nginx controller deployment"
}

# Auth-service integration (per-user JWT, RS256 + JWKS).
# When enabled, deploys accelerator-pack-auth-service alongside the pack and routes
# /auth/* through the frontend ingress. Pack backends verify JWTs locally (RS256)
# by fetching the auth-service JWKS document.
variable "enable_auth_service" {
  type        = bool
  default     = false
  description = "When true, deploy accelerator-pack-auth-service alongside the pack and route /auth/* through the frontend ingress. Per-user JWT auth (RS256). The auth-service pod generates and rotates its own RSA signing keypair; pack backends fetch its JWKS and verify tokens locally."
}

variable "auth_service_extra_trusted_issuers" {
  type        = string
  default     = ""
  description = "Optional comma-separated extra trusted token issuer URLs (integration mode — e.g. an Oracle IDCS, Microsoft Entra, or customer auth-service issuer URL). Pack BEs accept tokens from any issuer on this list in addition to the bundled auth-service. Each issuer must publish a JWKS at {issuer}/.well-known/jwks.json. Ignored when enable_auth_service is false."
  validation {
    condition = var.auth_service_extra_trusted_issuers == "" || alltrue([
      for s in split(",", var.auth_service_extra_trusted_issuers) :
      trimspace(s) == "" || (can(regex("^https://", trimspace(s))) && !can(regex("[[:space:]]", trimspace(s))))
    ])
    error_message = "Each trusted issuer URL must start with https:// and contain no internal whitespace."
  }
}

variable "auth_service_jwks_cache_ttl_seconds" {
  type        = number
  default     = 3600
  description = "JWKS public-key cache TTL on pack backends. Lower values speed up incident-response key rotation; higher values reduce JWKS fetch volume."
  validation {
    condition     = var.auth_service_jwks_cache_ttl_seconds >= 60 && var.auth_service_jwks_cache_ttl_seconds <= 86400
    error_message = "JWKS cache TTL must be between 60 and 86400 seconds."
  }
}

variable "enable_client_credentials_grant" {
  type        = bool
  default     = true
  description = "Master switch for OAuth2 client_credentials grant (service-account tokens). Set to false to disable issuance of new service-account tokens cluster-wide; existing tokens remain valid until their natural expiry. Use as an incident-response containment lever when service-account credentials are compromised. Ignored when enable_auth_service=false."
}

# OIDC SSO provider toggles. Each enables a single provider; both can be on at
# once. The provider's URL / client_id / client_secret vars are only consumed
# when its toggle is true. The auth-service container receives the env vars
# regardless (empty when off) for forward compatibility with env-driven seeding.
variable "enable_oracle_oidc_idcs" {
  type        = bool
  default     = false
  description = "Enable Oracle Identity Cloud Service as an OIDC provider for the auth-service. Requires auth_oidc_oracle_idcs_issuer_url + auth_oidc_oracle_idcs_client_id + auth_oidc_oracle_idcs_client_secret. Ignored when enable_auth_service is false."
}

variable "enable_microsoft_entra_oidc" {
  type        = bool
  default     = false
  description = "Enable Microsoft Entra (Azure AD) as an OIDC provider for the auth-service. Requires auth_oidc_microsoft_entra_tenant_id + auth_oidc_microsoft_entra_client_id + auth_oidc_microsoft_entra_client_secret. Ignored when enable_auth_service is false."
}

variable "auth_service_image_version" {
  type        = string
  default     = "v1.1.0-7e87642"
  description = "Image tag for accelerator-pack-auth-service. Image: iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service. Pinned in TF (hidden from the ORM Resource Manager UI) so the pack ships fully-versioned across the stack; bump the default in vars.tf to roll forward. Never set to 'latest'."
  validation {
    condition     = var.auth_service_image_version != "latest" && var.auth_service_image_version != ""
    error_message = "auth_service_image_version must be a pinned tag (semver or commit SHA), never 'latest' or empty."
  }
}

# cuOpt EV-routing backend (cuopt-ev-routing-backend) — FastAPI service that
# powers the cuopt frontend's /api/* routes. Pinned in TF (hidden from the
# ORM Resource Manager UI) so the pack ships fully-versioned across the
# stack; bump the default here to roll forward.
variable "cuopt_backend_image_version" {
  type        = string
  default     = "17728f4"
  description = "Image tag for cuopt-ev-routing-backend. Image: iad.ocir.io/iduyx1qnmway/corrino-devops-repository/cuopt-ev-routing-backend. Never set to 'latest'."
  validation {
    condition     = var.cuopt_backend_image_version != "latest" && var.cuopt_backend_image_version != ""
    error_message = "cuopt_backend_image_version must be a pinned tag (semver or commit SHA), never 'latest' or empty."
  }
}

variable "cuopt_openweathermap_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "OpenWeatherMap API key for the cuOpt backend's /api/weather/* routes. Empty triggers mock-data fallback in the backend."
}

variable "cuopt_tls_verify" {
  type        = bool
  default     = true
  description = "When true, the cuopt-backend's httpx clients verify TLS on calls to in-cluster cuopt + llamastack. Default true (production-safe). Set false only when the in-cluster upstreams present self-signed certs (common on first deploy)."
}

# OIDC providers (Oracle IDCS + Microsoft Entra). Provider records are NOT seeded
# from env vars at boot; they must be registered post-deploy via the auth-service
# admin API (POST /auth/providers). The variables below are plumbed into the
# auth-service container for future env-driven seeding and for documentation.
variable "auth_oidc_oracle_idcs_issuer_url" {
  type        = string
  default     = ""
  description = "Oracle IDCS OIDC issuer URL — the bare identity-domain base (e.g., https://idcs-tenant.identity.oraclecloud.com). Do NOT include /.well-known/openid-configuration; auth-service appends that path itself when fetching the discovery doc. Empty disables this provider."
}

variable "auth_oidc_oracle_idcs_client_id" {
  type        = string
  default     = ""
  description = "Oracle IDCS OIDC client ID. Empty disables this provider."
}

variable "auth_oidc_oracle_idcs_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Oracle IDCS OIDC client secret. Required when auth_oidc_oracle_idcs_client_id is set."
}

variable "auth_oidc_microsoft_entra_tenant_id" {
  type        = string
  default     = ""
  description = "Microsoft Entra (Azure AD) tenant ID. Empty disables this provider."
}

variable "auth_oidc_microsoft_entra_client_id" {
  type        = string
  default     = ""
  description = "Microsoft Entra (Azure AD) OIDC client ID. Empty disables this provider."
}

variable "auth_oidc_microsoft_entra_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Microsoft Entra (Azure AD) OIDC client secret. Required when auth_oidc_microsoft_entra_client_id is set."
}
# tflint-ignore: terraform_unused_declarations
variable "cluster_load_balancer_visibility" {
  type        = string
  default     = "Public"
  description = "Load balancer visibility for the cluster. Options: Public, Private"
}
# Deployment Details + Freeform Tags + Defined Tags
# tflint-ignore: terraform_unused_declarations
variable "oci_tag_values" {
  type = object({
    freeformTags = optional(map(string))
    definedTags  = optional(map(any))
  })
  description = "Tags to be added to the resources"
  default = {
    freeformTags = {
      AppName = "ai-accelerator"
    }
    definedTags = {}
  }
}

variable "accelerator_pack_stack_version" {
  type        = string
  default     = "v0.0.8"
  description = "Stack release version for AI Accelerator Starter Packs"
}

variable "corrino_image_version" {
  type        = string
  default     = "v1.0.12-hotfix1"
  description = "Corrino backend image version"
}

# tflint-ignore: terraform_unused_declarations
variable "setup_credential_provider_for_ocir" {
  type        = bool
  default     = false
  description = "whether to setup credential provider for OCIR"
}

# tflint-ignore: terraform_unused_declarations
variable "override_hostnames" {
  type        = bool
  default     = false
  description = "whether to override hostnames"
}

variable "nvme_raid_level" {
  type        = number
  default     = 10
  description = "NVMe RAID level"
}

# variable "worker_node_shape" {
#   default     = "BM.GPU4.8"
#   description = "Worker node shape"
# }

# Helm installs
# tflint-ignore: terraform_unused_declarations
variable "kong_enabled" {
  type        = bool
  default     = false
  description = "Install kong inference gateway"
}

# -----------------------------------
# Corrino FQDN
# -----------------------------------

variable "use_custom_dns" {
  description = "Enable to use your own custom domain instead of the automatic nip.io domain."
  type        = bool
  default     = false
}

variable "fqdn_custom_domain" {
  description = "Your custom FQDN can be a simple top-level domain or an A-Record for a top-level domain. Either method requires that you modify the domain registrar records to send traffic to the load balancer public IP that is provisioned for you."
  type        = string
  default     = ""
}

# Legacy variable - kept for backward compatibility, derived from use_custom_dns
# tflint-ignore: terraform_unused_declarations
variable "fqdn_domain_mode_selector" {
  type    = string
  default = "nip.io"
}

# -----------------------------------
# Starter Pack Configuration
# -----------------------------------

variable "starter_pack_category" {
  description = "The starter pack category. Set via starter_pack_category.auto.tfvars"
  type        = string
  # No default here - schema.yaml provides the default for Resource Manager portal
  # Default is set in schema.yaml per category (paas_rag, cuopt, vss, enterprise_rag)
  validation {
    condition     = contains(["cuopt", "vss", "paas_rag", "enterprise_rag", "enterprise_rag_aiq", "warehouse_pick_path", "dox_pack"], var.starter_pack_category)
    error_message = "Starter pack category must be 'cuopt', 'vss', 'paas_rag', 'enterprise_rag', 'enterprise_rag_aiq', 'warehouse_pick_path', or 'dox_pack'."
  }
}

variable "starter_pack_size" {
  description = "The starter pack size (poc, small, medium, large)"
  type        = string
  default     = "small"
  validation {
    condition     = contains(["poc", "small", "medium", "large"], var.starter_pack_size)
    error_message = "Starter pack size must be 'poc', 'small', 'medium', or 'large'."
  }
}

variable "skip_capacity_check" {
  description = "Skip the compute capacity pre-validation. Enable this only if you are certain capacity exists or want to bypass the pre-check. Note: Deployment may still fail later if capacity is unavailable."
  type        = bool
  default     = false
}

variable "worker_node_availability_domain" {
  description = "Availability domain to use for worker nodes. Required for GPU starter packs (cuopt, vss, enterprise_rag). Optional for paas_rag. When skip_capacity_check is false, capacity will be validated for this AD. When skip_capacity_check is true, capacity validation is skipped."
  type        = string
  default     = ""
}

variable "deploy_application" {
  description = "When false, all application-layer resources are skipped. Use this to create an infrastructure-only stack."
  type        = bool
  default     = true
}

variable "existing_cluster_id" {
  description = "OCID of an existing OKE cluster to deploy onto. When provided, all infrastructure creation (VCN, OKE cluster, node pools) is skipped and the app layer deploys directly onto the existing cluster."
  type        = string
  default     = ""
  validation {
    condition     = var.existing_cluster_id == "" || can(regex("^ocid1\\.cluster\\.", var.existing_cluster_id))
    error_message = "existing_cluster_id must be empty or a valid OKE cluster OCID."
  }
}

# -----------------------------------
variable "tavily_api_key" {
  description = "Tavily API key used by the AIQ Research Assistant for web search integration. Optional; leave empty to disable Tavily-powered search."
  type        = string
  default     = ""
  sensitive   = true
}

# 26ai Autonomous Database Variables
# -----------------------------------

variable "db_name" {
  description = "Name of the Autonomous Database (must be uppercase alphanumeric)"
  type        = string
  default     = "ORACLE26AI"
}

variable "db_display_name" {
  description = "Display name for the Autonomous Database"
  type        = string
  default     = "Oracle Database 26ai"
}

variable "db_username" {
  description = "Admin username for the Autonomous Database"
  type        = string
  default     = "ADMIN"
}

variable "db_password" {
  description = "Admin password for the Autonomous Database. Must be at least 12 characters, contain at least 1 uppercase letter, and at least 1 special character. Required for starter pack categories that provision the 26ai database: paas_rag, enterprise_rag, enterprise_rag_aiq."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.db_password == null ? true : length(var.db_password) >= 12
    error_message = "Database password must be at least 12 characters long."
  }

  validation {
    condition     = var.db_password == null ? true : can(regex("[A-Z]", var.db_password))
    error_message = "Database password must contain at least one uppercase letter."
  }

  validation {
    condition     = var.db_password == null ? true : can(regex("[^a-zA-Z0-9]", var.db_password))
    error_message = "Database password must contain at least one special character (non-alphanumeric character)."
  }
}

variable "aws_access_key_id" {
  description = "AWS-compatible access key ID for S3-compatible Object Storage. If not provided, one will be generated automatically. Only used for the paas_rag starter pack."
  type        = string
  sensitive   = true
  default     = null
}

variable "aws_secret_access_key" {
  description = "AWS-compatible secret access key for S3-compatible Object Storage. If not provided, one will be generated automatically. Only used for the paas_rag starter pack."
  type        = string
  sensitive   = true
  default     = null
}

variable "db_compute_count" {
  description = "Number of ECPU cores for the database"
  type        = number
  default     = 4
}

variable "db_data_storage_size_in_tbs" {
  description = "Data storage size in TBs"
  type        = number
  default     = 1
}

variable "db_license_model" {
  description = "License model: BRING_YOUR_OWN_LICENSE or LICENSE_INCLUDED"
  type        = string
  default     = "LICENSE_INCLUDED"
}

variable "db_workload_type" {
  description = "Workload type: LH (Lakehouse), OLTP, DW, AJD, APEX"
  type        = string
  default     = "LH"
}

variable "genai_region" {
  description = "Region for the GenAI service"
  type        = string
  default     = "us-chicago-1"
}

variable "llamastack_region" {
  description = "OCI region whose GenAI model catalog LlamaStack reads from. Decoupled from genai_region (which controls the DAC) because the DAC must follow GPU capacity while the chat/embedding catalog only exists in some regions (e.g. Llama-4 is Chicago-only as of 2026)."
  type        = string
  default     = "us-chicago-1"
}

variable "dac_model_id" {
  description = "HuggingFace model ID to import and deploy on the Dedicated AI Cluster (e.g. Qwen/Qwen3-VL-235B-A22B-Instruct)."
  type        = string
  default     = "Qwen/Qwen3-VL-235B-A22B-Instruct"
}

variable "dac_unit_shape" {
  description = "GPU shape for the Dedicated AI Cluster. Must have sufficient memory for the selected model."
  type        = string
  default     = "H100_X8"
}

variable "dac_billing_acknowledgement" {
  description = "Acknowledge that the Dedicated AI Cluster will be billed hourly until the stack is destroyed."
  type        = bool
  default     = false
}

variable "google_maps_api_key" {
  description = "Google Maps API key for the cuOpt frontend map visualization"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cuopt_frontend_admin_username" {
  description = "Admin username for the cuOpt frontend login"
  type        = string
  default     = ""
}

variable "cuopt_frontend_admin_password" {
  description = "Admin password for the cuOpt frontend login"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.cuopt_frontend_admin_password == "" || (length(var.cuopt_frontend_admin_password) >= 8 && can(regex("[0-9]", var.cuopt_frontend_admin_password)))
    error_message = "Password must be at least 8 characters and contain at least one number."
  }
}

# -----------------------------------
# Starter Pack Configuration Map
# Nested by category, then by size
# Only define sizes that are actually implemented
# -----------------------------------
locals {
  starter_pack_configs = {
    "cuopt" = {
      "poc" = {
        blueprint_file                               = "cuopt-with-marketing-blueprint.json"
        deployment_name                              = "cuopt"
        app_namespace                                = "default"
        nvaie_enabled                                = false
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "VM.GPU.A10.2"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 4
          memory        = 32
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      "small" = {
        blueprint_file                               = "cuopt-with-marketing-blueprint.json"
        deployment_name                              = "cuopt"
        app_namespace                                = "default"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU4.8"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 4
          memory        = 32
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      "medium" = {
        blueprint_file                               = "cuopt-with-marketing-blueprint.json"
        deployment_name                              = "cuopt"
        app_namespace                                = "default"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU.A100-v2.8"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 4
          memory        = 32
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      # Add "large" here when implemented
    }

    "vss" = {
      "poc" = {
        blueprint_file                               = "vss-blueprint.json"
        deployment_name                              = "vss"
        app_namespace                                = "default"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "VM.GPU.A10.2"
        worker_node_pool_size                        = 2
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 16
          memory        = 260
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      "small" = {
        blueprint_file                               = "vss-blueprint.json"
        deployment_name                              = "vss"
        app_namespace                                = "default"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU4.8"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "200"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 32
          memory        = 128
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      "medium" = {
        blueprint_file                               = "vss-blueprint.json"
        deployment_name                              = "vss"
        app_namespace                                = "default"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU.L40S-NC.4"
        worker_node_pool_size                        = 2
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "200"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 32
          memory        = 128
        }
        database_storage_size_in_tbs = 0
        database_compute_count       = 0
      }
      # Add "large" here when implemented
    }

    "paas_rag" = {
      "small" = {
        blueprint_file                               = "paas-rag-blueprint.json"
        deployment_name                              = "paas"
        app_namespace                                = "default"
        nvaie_enabled                                = false
        create_ngc_secrets_in_cluster                = false
        worker_node_shape                            = "none"
        worker_node_pool_size                        = 0
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "100"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 6
          memory        = 48
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 12
          memory        = 96
        }
        database_storage_size_in_tbs = 2
        database_compute_count       = 4
      }

      "medium" = {
        blueprint_file                               = "paas-rag-blueprint.json"
        deployment_name                              = "paas"
        app_namespace                                = "default"
        nvaie_enabled                                = false
        create_ngc_secrets_in_cluster                = false
        worker_node_shape                            = "none"
        worker_node_pool_size                        = 0
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "100"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 6
          memory        = 48
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 12
          memory        = 96
        }
        database_storage_size_in_tbs = 8
        database_compute_count       = 16
      }
      # Add "large" here when implemented
    }

    "dox_pack" = {
      "small" = {
        blueprint_file                               = "dox-pack-blueprint.json"
        deployment_name                              = "dox-pack"
        app_namespace                                = "default"
        nvaie_enabled                                = false
        create_ngc_secrets_in_cluster                = false
        worker_node_shape                            = "none"
        worker_node_pool_size                        = 0
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "100"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 6
          memory        = 48
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 12
          memory        = 96
        }
        database_storage_size_in_tbs = 2
        database_compute_count       = 4
        frontend_url                 = "dox-frontend"
      }
    }

    "enterprise_rag" = {
      "small" = {
        blueprint_file                               = ""
        deployment_name                              = "enterprise-rag"
        app_namespace                                = "rag"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU4.8"
        worker_node_pool_size                        = 2
        cpu_worker_node_pool_size                    = 0
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "120"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "0"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "none"
          ocpus         = 0
          memory        = 0
        }
        database_storage_size_in_tbs = 2
        database_compute_count       = 4
        frontend_url                 = "frontend-erag" # Not used
      }
    }

    "enterprise_rag_aiq" = {
      "small" = {
        blueprint_file                               = ""
        deployment_name                              = "enterprise-rag"
        app_namespace                                = "rag"
        aiq_namespace                                = "aiq"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU4.8"
        worker_node_pool_size                        = 2
        cpu_worker_node_pool_size                    = 0
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "120"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "0"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "none"
          ocpus         = 0
          memory        = 0
        }
        database_storage_size_in_tbs = 2
        database_compute_count       = 4
        frontend_url                 = "aiq"
      }
      "medium" = {
        blueprint_file                               = ""
        deployment_name                              = "enterprise-rag"
        app_namespace                                = "rag"
        aiq_namespace                                = "aiq"
        nvaie_enabled                                = true
        create_ngc_secrets_in_cluster                = true
        worker_node_shape                            = "BM.GPU.A100-v2.8"
        worker_node_pool_size                        = 2
        cpu_worker_node_pool_size                    = 0
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "120"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "0"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "none"
          ocpus         = 0
          memory        = 0
        }
        database_storage_size_in_tbs = 8
        database_compute_count       = 16
        frontend_url                 = "aiq"
      }
    }

    "warehouse_pick_path" = {
      "small" = {
        blueprint_file                               = "warehouse-pick-path-blueprint.json"
        deployment_name                              = "wpp"
        app_namespace                                = "default"
        nvaie_enabled                                = false
        create_ngc_secrets_in_cluster                = false
        use_dynamic_url                              = true
        worker_node_shape                            = "VM.GPU.A10.1"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = 1
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = "150"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 8
          memory        = 64
        }
        database_storage_size_in_tbs = 2
        database_compute_count       = 4
        api_url                      = "wpp-backend"
        frontend_url                 = "wpp"
      }
    }

  }


  # Resolved config (maintains existing interface for all consuming resources)
  starter_pack_config = local.starter_pack_configs[var.starter_pack_category][var.starter_pack_size]

  # Deployment name - unique per blueprint version (random_id changes only when canonical blueprint content changes)
  # enterprise_rag and enterprise_rag_aiq use Helm (not blueprints), so random_id.blueprint_deploy_id doesn't exist for them
  starter_pack_deployment_name = !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) && local.deploy_application ? (
    "${local.starter_pack_config.deployment_name}-${random_id.blueprint_deploy_id[0].hex}"
  ) : local.starter_pack_config.deployment_name

  # Blueprint content: raw uses placeholder "DEPLOY_NAME"; resolved content uses actual deployment name.
  # Canonical content (DEPLOY_NAME -> config.deployment_name) is hashed to drive job re-runs only when blueprint changes.
  starter_pack_blueprint_raw     = local.starter_pack_blueprints[var.starter_pack_category][var.starter_pack_size]
  canonical_blueprint_content    = !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? replace(local.starter_pack_blueprint_raw, "DEPLOY_NAME", local.starter_pack_config.deployment_name) : ""
  starter_pack_blueprint_content = !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? replace(local.starter_pack_blueprint_raw, "DEPLOY_NAME", local.starter_pack_deployment_name) : local.starter_pack_blueprint_raw
}

# App Name Locals
locals {
  app_name = random_string.app_name_autogen.result
}

# Networking Locals
locals {
  # Determine which VCN and subnets to use based on configuration mode
  # When using an existing cluster, network resources are not created -- use existing_* vars or null
  vcn_id = local.use_existing_cluster ? var.existing_vcn_id : (
    var.network_configuration_mode == "bring_your_own" ? var.existing_vcn_id : oci_core_virtual_network.oke_vcn[0].id
  )

  endpoint_subnet_id = local.use_existing_cluster ? var.existing_endpoint_subnet_id : (
    var.network_configuration_mode == "bring_your_own" ? var.existing_endpoint_subnet_id : oci_core_subnet.oke_k8s_endpoint_subnet[0].id
  )

  node_subnet_id = local.use_existing_cluster ? var.existing_node_subnet_id : (
    var.network_configuration_mode == "bring_your_own" ? var.existing_node_subnet_id : oci_core_subnet.oke_nodes_subnet[0].id
  )

  lb_subnet_id = local.use_existing_cluster ? var.existing_lb_subnet_id : (
    var.network_configuration_mode == "bring_your_own" ? var.existing_lb_subnet_id : oci_core_subnet.oke_lb_subnet[0].id
  )

  autonomous_db_subnet_id = local.use_existing_cluster ? var.existing_autonomous_db_subnet_id : (
    var.network_configuration_mode == "bring_your_own" ? var.existing_autonomous_db_subnet_id : oci_core_subnet.oke_db_subnet[0].id
  )

  # Only create new network resources when in create_new mode and creating infrastructure
  create_network_resources = local.deploy_infrastructure && var.network_configuration_mode == "create_new"
}

# Accelerator specific stuff
locals {
  # GPU image needed fcuopt, vss, and enterprise_rag categories (GPU workloads)
  should_import_nvidia_gpu_image = var.starter_pack_category == "cuopt" || var.starter_pack_category == "vss" || var.starter_pack_category == "enterprise_rag" || var.starter_pack_category == "enterprise_rag_aiq" || var.starter_pack_category == "warehouse_pick_path"
  should_import_amd_gpu_image    = false # if amd starter pack is added, update this
}

locals {
  # 26ai database needed for paas_rag, enterprise_rag, enterprise_rag_aiq,
  # warehouse_pick_path, dox_pack, and cuopt (when enable_auth_service=true,
  # the auth-service backs onto 26ai).
  # Packs that natively need 26ai for their own workload, plus any pack that
  # has enable_auth_service=true (auth-service is backed by 26ai). cuopt only
  # provisions 26ai when auth-service is on.
  needs_26ai = contains(["paas_rag", "enterprise_rag", "enterprise_rag_aiq", "warehouse_pick_path", "dox_pack"], var.starter_pack_category) || var.enable_auth_service
}

# ---------------------------------------------------------------------------
# Frontend Skin Toggles (one per blueprint-pack skin)
# ---------------------------------------------------------------------------

variable "skin_cuopt_core" {
  type        = bool
  description = "Enable the 'Vehicle Route Optimizer Frontend (Core App)' skin"
  default     = true
}

variable "skin_cuopt_partner" {
  type        = bool
  description = "Enable the 'Oracle Interactive - Route visualization (Partner Contributed)' skin"
  default     = false
}

variable "skin_vss_core" {
  type        = bool
  description = "Enable the 'Oracle Custom - Enhanced search (Core App)' skin"
  default     = true
}

variable "skin_paas_rag_core" {
  type        = bool
  description = "Enable the 'Oracle Net - Chat interface (Core App)' skin"
  default     = true
}

variable "skin_wpp_core" {
  type        = bool
  description = "Enable the 'Warehouse Pick Path Optimizer Frontend (Core App)' skin"
  default     = true
}

variable "skin_dox_pack_core" {
  type        = bool
  description = "Enable the 'Document Extractor Frontend (Core App)' skin"
  default     = true
}

# Helm-pack skin selectors (single-select enum). Empty string resolves to catalog default.
variable "skin_enterprise_rag" {
  type        = string
  description = "Frontend skin for enterprise_rag (single-select). Empty = catalog default."
  default     = ""
}

variable "skin_enterprise_rag_aiq" {
  type        = string
  description = "Frontend skin for enterprise_rag_aiq (single-select). Empty = catalog default."
  default     = ""
}
