# Copyright (c) 2021 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Authentication Configuration
variable "ngc_secret" {
  type        = string
  default     = "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"
  sensitive   = true
  description = "NVIDIA NGC secret for docker registry authentication (nvcr.io) and image pull secrets"
}

variable "ngc_api_secret" {
  type        = string
  default     = "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"
  sensitive   = true
  description = "NVIDIA NGC API secret for accessing NGC services and APIs"
}

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

variable "existing_pods_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for pods. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "existing_services_subnet_id" {
  default     = ""
  description = "OCID of the existing subnet for services. Required when network_configuration_mode is 'bring_your_own'"
  type        = string
}

variable "create_policies" {
  default     = true
  description = "Whether to create policies"
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
  default = false
}

## OKE Visibility (Workers and Endpoint)

variable "cluster_workers_visibility" {
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

## OKE Node Pool Details
variable "node_pool_name" {
  default     = "control-plane"
  description = "Name of the node pool"
}
variable "k8s_version" {
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
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "region" {}
variable "current_user_ocid" {}

# ORM Schema visual control variables
variable "show_advanced" {
  default = false
}

# Bastion and Operator Configuration
variable "create_bastion" {
  type        = bool
  default     = true
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
  default     = "50"
  description = "Boot volume size for bastion instance (in GB)"
}

variable "operator_boot_volume_size_in_gbs" {
  default     = "100"
  description = "Boot volume size for operator instance (in GB)"
}

# Ingress Nginx Configuration
variable "ingress_load_balancer_shape" {
  default     = "flexible" # Flexible, 10Mbps, 100Mbps, 400Mbps or 8000Mps
  description = "Shape that will be included on the Ingress annotation for the OCI Load Balancer creation"
}
variable "ingress_load_balancer_shape_flex_min" {
  default     = "10"
  description = "Enter the minimum size of the flexible shape."
}
variable "ingress_load_balancer_shape_flex_max" {
  default     = "100"
  description = "Enter the maximum size of the flexible shape (Should be bigger than minimum size). The maximum service limit is set by your tenancy limits."
}
variable "ingress_hosts" {
  default     = ""
  description = "Enter a valid full qualified domain name (FQDN). You will need to map the domain name to the EXTERNAL-IP address on your DNS provider (DNS Registry type - A). If you have multiple domain names, include separated by comma. e.g.: mushop.example.com,catshop.com"
}
variable "ingress_hosts_include_nip_io" {
  default     = true
  description = "Include app_name.HEXXX.nip.io on the ingress hosts. e.g.: mushop.HEXXX.nip.io"
}
variable "nip_io_domain" {
  default     = "nip.io"
  description = "Dynamic wildcard DNS for the application hostname. Should support hex notation. e.g.: nip.io"
}
variable "ingress_tls" {
  default     = true
  description = "If enabled, will generate SSL certificates to enable HTTPS for the ingress using the Certificate Issuer"
}
variable "ingress_cluster_issuer" {
  default     = "letsencrypt-prod"
  description = "Certificate issuer type. Currently supports the free Let's Encrypt and Self-Signed. Only *letsencrypt-prod* generates valid certificates"
}
variable "ingress_email_issuer" {
  default     = "no-reply@example.cloud"
  description = "You must replace this email address with your own. The certificate provider will use this to contact you about expiring certificates, and issues related to your account."
}
variable "ingress_nginx_enabled" {
  default     = true
  description = "Enable ingress-nginx controller deployment"
}
variable "cluster_load_balancer_visibility" {
  default     = "Public"
  description = "Load balancer visibility for the cluster. Options: Public, Private"
}
# Deployment Details + Freeform Tags + Defined Tags
variable "oci_tag_values" {
  description = "Tags to be added to the resources"
  default = {
    freeformTags = {
      AppName = "ai-accelerator"
    }
    definedTags = {}
  }
}

variable "accelerator_pack_stack_version" {
  default     = "v0.0.1"
  description = "Stack release version for AI Accelerator Starter Packs"
}

variable "corrino_image_version" {
  default     = "v1.0.11"
  description = "Corrino backend image version"
}

variable "is_nvaie_enabled" {
  default     = true
  description = "whether to enable NVAIE"
}

variable "setup_credential_provider_for_ocir" {
  default     = false
  description = "whether to setup credential provider for OCIR"
}

variable "override_hostnames" {
  default     = false
  description = "whether to override hostnames"
}

variable "nvme_raid_level" {
  default     = 10
  description = "NVMe RAID level"
}

# variable "worker_node_shape" {
#   default     = "BM.GPU4.8"
#   description = "Worker node shape"
# }

# Helm installs
variable "kong_enabled" {
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
    condition     = contains(["cuopt", "vss", "paas_rag", "enterprise_rag"], var.starter_pack_category)
    error_message = "Starter pack category must be 'cuopt', 'vss', 'paas_rag', or 'enterprise_rag'."
  }
}

variable "starter_pack_size" {
  description = "The starter pack size (small, medium, large)"
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large"], var.starter_pack_size)
    error_message = "Starter pack size must be 'small', 'medium', or 'large'."
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

# -----------------------------------
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
  description = "Admin password for the Autonomous Database. Must be at least 12 characters, contain at least 1 uppercase letter, and at least 1 special character. Only required for paas_rag starter pack."
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

variable "cuopt_frontend_enabled" {
  description = "Enable cuopt frontend"
  type        = bool
  default     = false
}

# -----------------------------------
# Starter Pack Configuration Map
# Nested by category, then by size
# Only define sizes that are actually implemented
# -----------------------------------
locals {
  starter_pack_configs = {
    "cuopt" = {
      "small" = {
        blueprint_file                               = var.cuopt_frontend_enabled ? "cuopt-with-marketing-blueprint.json" : "cuopt-blueprint.json"
        deployment_name                              = "cuopt"
        app_namespace                                = "default"
        use_dynamic_url                              = true
        worker_node_shape                            = "BM.GPU4.8"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = var.cuopt_frontend_enabled ? 1 : 0
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = var.cuopt_frontend_enabled ? "150" : "0"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = var.cuopt_frontend_enabled ? "VM.Standard.E5.Flex" : "none"
          ocpus         = var.cuopt_frontend_enabled ? 4 : 0
          memory        = var.cuopt_frontend_enabled ? 32 : 0
        }
        database_storage_size_in_tbs         = 0
        database_compute_count               = 0
        starter_pack_url_deployment          = var.cuopt_frontend_enabled ? "cuopt-2-cuopt" : "cuopt"
        frontend_starter_pack_url_deployment = var.cuopt_frontend_enabled ? "demo-cuopt" : ""
      }
      "medium" = {
        blueprint_file                               = var.cuopt_frontend_enabled ? "cuopt-with-marketing-blueprint.json" : "cuopt-blueprint.json"
        deployment_name                              = "cuopt"
        app_namespace                                = "default"
        use_dynamic_url                              = true
        worker_node_shape                            = "BM.GPU.A100-v2.8"
        worker_node_pool_size                        = 1
        cpu_worker_node_pool_size                    = var.cuopt_frontend_enabled ? 1 : 0
        control_plane_node_pool_size                 = 2
        node_pool_boot_volume_size_in_gbs            = "150"
        cpu_worker_node_pool_boot_volume_size_in_gbs = var.cuopt_frontend_enabled ? "150" : "0"
        control_plane_node_pool_instance_shape = {
          instanceShape = "VM.Standard.E5.Flex"
          ocpus         = 3
          memory        = 64
        }
        cpu_worker_node_pool_instance_shape = {
          instanceShape = var.cuopt_frontend_enabled ? "VM.Standard.E5.Flex" : "none"
          ocpus         = var.cuopt_frontend_enabled ? 4 : 0
          memory        = var.cuopt_frontend_enabled ? 32 : 0
        }
        database_storage_size_in_tbs         = 0
        database_compute_count               = 0
        starter_pack_url_deployment          = var.cuopt_frontend_enabled ? "cuopt-2-cuopt" : "cuopt"
        frontend_starter_pack_url_deployment = var.cuopt_frontend_enabled ? "demo-cuopt" : ""
      }
      # Add "large" here when implemented
    }

    "vss" = {
      "small" = {
        blueprint_file                               = "vss-blueprint.json"
        deployment_name                              = "vss"
        app_namespace                                = "default"
        use_dynamic_url                              = true
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
        database_storage_size_in_tbs         = 0
        database_compute_count               = 0
        starter_pack_url_deployment          = "vss"
        frontend_starter_pack_url_deployment = ""
      }
      "medium" = {
        blueprint_file                               = "vss-blueprint.json"
        deployment_name                              = "vss"
        app_namespace                                = "default"
        use_dynamic_url                              = true
        worker_node_shape                            = "BM.GPU.L40S.4"
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
        database_storage_size_in_tbs         = 0
        database_compute_count               = 0
        starter_pack_url_deployment          = "vss"
        frontend_starter_pack_url_deployment = ""
      }
      # Add "large" here when implemented
    }

    "paas_rag" = {
      "small" = {
        blueprint_file                               = "paas-rag-blueprint.json"
        deployment_name                              = "paas"
        app_namespace                                = "default"
        use_dynamic_url                              = true
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
        database_storage_size_in_tbs         = 2
        database_compute_count               = 4
        starter_pack_url_deployment          = "frontend"
        frontend_starter_pack_url_deployment = ""
      }

      "medium" = {
        blueprint_file                               = "paas-rag-blueprint.json"
        deployment_name                              = "paas"
        app_namespace                                = "default"
        use_dynamic_url                              = true
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
        database_storage_size_in_tbs         = 8
        database_compute_count               = 16
        starter_pack_url_deployment          = "frontend"
        frontend_starter_pack_url_deployment = ""
      }
      # Add "large" here when implemented
    }


    "enterprise_rag" = {
      "small" = {
        blueprint_file                               = ""
        deployment_name                              = "enterprise-rag"
        app_namespace                                = "rag"
        use_dynamic_url                              = false
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
        starter_pack_url_deployment          = "" # Not used (use_dynamic_url = false)
        frontend_starter_pack_url_deployment = "" # Not used
      }
    }
  }

  # Backward compatibility - combined key for existing conditionals
  starter_pack_choice = "${var.starter_pack_category}_${var.starter_pack_size}"

  # Resolved config (maintains existing interface for all consuming resources)
  starter_pack_config = local.starter_pack_configs[var.starter_pack_category][var.starter_pack_size]

  # Deployment name from config
  starter_pack_deployment_name = local.starter_pack_config.deployment_name

  # Deployment used for starter pack URL (e.g., "frontend" for paas_rag, "cuopt-cuopt" for cuopt with frontend)
  starter_pack_url_deployment = local.starter_pack_config.starter_pack_url_deployment

  # Deployment used for frontend URL (only used for cuopt with frontend enabled)
  frontend_starter_pack_url_deployment = local.starter_pack_config.frontend_starter_pack_url_deployment

  # Blueprint content - directly from the organized blueprint map in blueprint_files.tf
  # No need to maintain a separate map here - just reference the nested structure
  starter_pack_blueprint_content = local.starter_pack_blueprints[var.starter_pack_category][var.starter_pack_size]
}

# App Name Locals
locals {
  app_name               = random_string.app_name_autogen.result
  app_name_normalized    = random_string.app_name_autogen.result
  oci_ai_blueprints_link = file("${path.module}/OCI_AI_BLUEPRINTS_LINK")
}

# Networking Locals
locals {
  # Determine which VCN and subnets to use based on configuration mode
  vcn_id = var.network_configuration_mode == "bring_your_own" ? var.existing_vcn_id : oci_core_virtual_network.oke_vcn[0].id

  endpoint_subnet_id = var.network_configuration_mode == "bring_your_own" ? var.existing_endpoint_subnet_id : oci_core_subnet.oke_k8s_endpoint_subnet[0].id

  node_subnet_id = var.network_configuration_mode == "bring_your_own" ? var.existing_node_subnet_id : oci_core_subnet.oke_nodes_subnet[0].id

  lb_subnet_id = var.network_configuration_mode == "bring_your_own" ? var.existing_lb_subnet_id : oci_core_subnet.oke_lb_subnet[0].id

  db_subnet_id = var.network_configuration_mode == "bring_your_own" ? var.existing_lb_subnet_id : oci_core_subnet.oke_db_subnet[0].id # Placeholder for bring_your_own

  # Only create new network resources when in create_new mode
  create_network_resources = var.network_configuration_mode == "create_new"
}

# Dictionary Locals
locals {
  compute_flexible_shapes = [
    "VM.Standard.E3.Flex",
    "VM.Standard.E4.Flex",
    "VM.Standard.A1.Flex"
  ]
}

# Accelerator specific stuff
locals {
  # GPU image needed fcuopt, vss, and enterprise_rag categories (GPU workloads)
  should_import_nvidia_gpu_image = var.starter_pack_category == "cuopt" || var.starter_pack_category == "vss" || var.starter_pack_category == "enterprise_rag"
  should_import_amd_gpu_image    = false # if amd starter pack is added, update this
}

locals {
  # 26ai database needed for paas_rag category
  needs_26ai = var.starter_pack_category == "paas_rag"
}
