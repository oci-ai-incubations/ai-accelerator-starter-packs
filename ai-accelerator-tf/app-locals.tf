locals {

  ts = timestamp()

  deploy_id = random_string.generated_deployment_name.result

  deploy_application    = var.deploy_application
  use_existing_cluster  = var.existing_cluster_id != ""
  deploy_infrastructure = !local.use_existing_cluster
  effective_cluster_id  = local.use_existing_cluster ? var.existing_cluster_id : local.oke_cluster.id

  # Compound gating locals — single source of truth for repeated count/for_each conditions
  deploy_app_vss      = local.deploy_application && var.starter_pack_category == "vss"
  deploy_app_rag      = local.deploy_application && contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category)
  deploy_app_rag_aiq  = local.deploy_application && var.starter_pack_category == "enterprise_rag_aiq"
  deploy_app_non_rag  = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category)
  deploy_app_26ai     = local.deploy_application && local.needs_26ai
  run_capacity_checks = local.deploy_infrastructure && !var.skip_capacity_check
  uses_gpu            = local.should_import_nvidia_gpu_image

  app = {
    backend_service_name         = "corrino-cp"
    backend_service_name_origin  = "http://corrino-cp"
    backend_service_name_ingress = "corrino-cp-ingress"
    backend_image_uri            = format("${local.ocir.base_uri}/${local.ocir.backend_image}:${var.corrino_image_version}")
    #frontend_image_uri                           = join(":", [local.ocir.base_uri, local.ocir.frontend_image])
    blueprint_portal_image_uri                     = format("${local.ocir.base_uri}:${local.ocir.blueprint_portal_image}-${var.corrino_image_version}")
    deploy_blueprint_image_uri                     = format("${local.ocir.base_uri}:corrino_deployment_scripts-latest")
    recipe_bucket_name                             = "corrino-recipes"
    recipe_validation_enabled                      = "True"
    recipe_validation_shape_availability_enabled   = "True"
    https_flag                                     = "False"
    portal_demo_flag                               = "False"
    blueprints_object_storage_url                  = "https://iduyx1qnmway.objectstorage.us-ashburn-1.oci.customer-oci.com/n/iduyx1qnmway/b/blueprints/o/blueprints.json"
    shared_node_pool_blueprints_object_storage_url = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/Fg9xXHJ0jreGQlI7t0tjjbHQ4TTZrtMb8vEaaN1apQn1JrtPk-iXzxXFXhfTMv6F/n/iduyx1qnmway/b/blueprints/o/shared_node_pools.json"
    shared_node_pool_documentation_url             = "https://github.com/oracle-quickstart/oci-ai-blueprints/tree/main/docs/shared_node_pools"
    blueprint_documentation_url                    = "https://github.com/oracle-quickstart/oci-ai-blueprints/tree/main/docs/api_documentation"
  }

  postgres_db = {
    host     = "bp-postgres"
    port     = "5432"
    db_name  = try(format("%s_db", random_string.postgres_db_name[0].result), "")
    user     = try(format("%s_user", random_string.postgres_db_username[0].result), "")
    password = try(random_string.postgres_db_password[0].result, "")
  }

  ngc_secrets = {
    docker_secret_name         = "ngc-secret"
    nvidia_api_key_envvar_name = "NVIDIA_API_KEY"
    nvidia_api_key_secret_key  = "NVIDIA_API_KEY"
    nvidia_api_key_secret_name = "nvidia-api-secret"

    ngc_api_key_envvar_name = "NGC_API_KEY"
    ngc_api_key_secret_key  = "NGC_API_KEY"
    ngc_api_key_secret_name = "ngc-api-secret"
  }
  # Upload path separated to avoid circular dependencies
  # This only depends on random_uuid which has no resource dependencies
  registration_upload_path = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/7OpjqoxJGKSJ31gSFSNytBbq7l0hEXN0uJP9NKTznJgoElAA9M5G1YXoW757yaHO/n/iduyx1qnmway/b/production-data-repo/o/${random_uuid.registration_id.result}/"

  registration = {
    object_filename = "success.json"
    object_filepath = format("%s/%s-success", abspath(path.root), random_uuid.registration_id.result)
    object_content = jsonencode({
      # Metadata
      registration_id = random_uuid.registration_id.result
      stage           = "success"
      timestamp       = local.ts
      workspace_name  = local.app_name
      deploy_id       = local.deploy_id
      stack_version   = var.accelerator_pack_stack_version
      fqdn            = local.fqdn.name

      # Core OCI Info
      tenancy_ocid          = var.tenancy_ocid
      compartment_ocid      = var.compartment_ocid
      region                = var.region
      starter_pack_category = var.starter_pack_category
      starter_pack_size     = var.starter_pack_size

      # Networking
      vcn_ocid              = try(oci_core_virtual_network.oke_vcn[0].id, null)
      endpoint_subnet_ocid  = try(oci_core_subnet.oke_k8s_endpoint_subnet[0].id, null)
      nodes_subnet_ocid     = try(oci_core_subnet.oke_nodes_subnet[0].id, null)
      lb_subnet_ocid        = try(oci_core_subnet.oke_lb_subnet[0].id, null)
      db_subnet_ocid        = try(oci_core_subnet.oke_db_subnet[0].id, null)
      bastion_subnet_ocid   = try(oci_core_subnet.oke_bastion_subnet[0].id, null)
      operator_subnet_ocid  = try(oci_core_subnet.oke_operator_subnet[0].id, null)
      nat_gateway_ocid      = try(oci_core_nat_gateway.oke_nat_gateway[0].id, null)
      internet_gateway_ocid = try(oci_core_internet_gateway.oke_internet_gateway[0].id, null)
      service_gateway_ocid  = try(oci_core_service_gateway.oke_service_gateway[0].id, null)

      # OKE
      oke_cluster_ocid     = local.effective_cluster_id
      node_pool_ocid       = local.deploy_infrastructure ? oci_containerengine_node_pool.oke_node_pool[0].id : null
      worker_cpu_pool_ocid = try(oci_containerengine_node_pool.worker_cpu_pool[0].id, null)

      # Compute
      bastion_instance_ocid  = try(oci_core_instance.bastion[0].id, null)
      operator_instance_ocid = try(oci_core_instance.operator[0].id, null)

      # Instance Pools / Cluster Network
      worker_instance_config_ocid = try(oci_core_instance_configuration.worker_nodes_configuration[0].id, null)
      worker_instance_pool_ocid   = try(oci_core_instance_pool.worker_nodes_pool[0].id, null)
      worker_cluster_network_ocid = try(oci_core_cluster_network.worker_nodes_cluster_network[0].id, null)

      # Custom Images
      nvidia_image_ocid = try(oci_core_image.nvidia_image[0].id, null)
      amd_image_ocid    = try(oci_core_image.amd_image[0].id, null)

      # Database (26AI)
      autonomous_db_ocid = try(oci_database_autonomous_database.oracle_26ai[0].id, null)

      # IAM
      operator_dg_ocid     = try(oci_identity_dynamic_group.operator_dg[0].id, null)
      instance_dg_ocid     = try(oci_identity_dynamic_group.dyn_group[0].id, null)
      operator_policy_ocid = try(oci_identity_policy.operator_policy[0].id, null)
      instance_policy_ocid = try(oci_identity_policy.oke_instances_tenancy_policy[0].id, null)

      # Configuration Details
      worker_node_shape     = try(local.starter_pack_config.worker_node_shape, null)
      worker_node_pool_size = try(local.starter_pack_config.worker_node_pool_size, null)
      network_config_mode   = var.network_configuration_mode
      load_balancer_ip      = try(local.ingress_controller_load_balancer_ip, null)
    })
    upload_path = local.registration_upload_path
  }

  corrino_tags = {
    "corrino_installed" = "true"
    "corrino_uuid"      = random_uuid.registration_id.result
  }

  addon = {
    grafana_user  = "admin"
    grafana_token = local.grafana_admin_password
  }

  django = {
    logging_level        = "DEBUG"
    secret               = try(random_string.corrino_django_secret[0].result, "")
    allowed_hosts        = join(",", [local.network.localhost, local.network.loopback, local.public_endpoint.api, local.app.backend_service_name])
    csrf_trusted_origins = join(",", [local.network.localhost_origin, local.network.loopback_origin, local.public_endpoint.api_origin_secure, local.public_endpoint.api_origin_insecure, local.app.backend_service_name_origin])
  }

  oci = {
    tenancy_id        = var.tenancy_ocid
    tenancy_namespace = data.oci_objectstorage_namespace.ns.namespace
    namespace_name    = data.oci_objectstorage_namespace.ns.namespace
    compartment_id    = var.compartment_ocid
    oke_cluster_id    = local.effective_cluster_id
    region_name       = var.region
  }

  network = {
    localhost          = "localhost"
    localhost_origin   = "http://localhost"
    loopback           = "127.0.0.1"
    loopback_origin    = "http://127.0.0.1"
    external_ip        = var.ingress_nginx_enabled ? local.ingress_controller_load_balancer_ip : "#Ingress_Not_Deployed"
    oke_node_subnet_id = local.create_network_resources ? oci_core_subnet.oke_nodes_subnet[0].id : var.existing_node_subnet_id
  }

  registry = {
    subdomain                = "iad.ocir.io"
    name                     = "corrino-devops-repository"
    source_tenancy_namespace = "iduyx1qnmway"
  }

  ocir = {
    base_uri      = join("/", [local.registry.subdomain, local.registry.source_tenancy_namespace, local.registry.name])
    backend_image = "oci-corrino-cp"
    #frontend_image         = "corrino-portal"
    blueprint_portal_image = "oci-ai-blueprints-portal"
    cli_util_amd64_image   = "oci-util-amd64"
    cli_util_arm64_image   = "oci-util-arm64"
    pod_util_amd64_image   = "pod-util-amd64"
    pod_util_arm64_image   = "pod-util-arm64"
  }

  domain = {
    corrino_oci_mode = "corrino-oci.com"
    corrino_oci_fqdn = format("%s.corrino-oci.com", random_string.subdomain.result)

    nip_io_mode = "nip.io"
    nip_io_fqdn = format("%s.nip.io", replace(local.network.external_ip, ".", "-"))

    # inference_gateway_fqdn = format("%s.nip.io", replace(local.inference_gateway.external_ip, ".", "-"))

    custom_mode = "custom"
    custom_fqdn = var.fqdn_custom_domain
  }

  fqdn = {
    name                = var.use_custom_dns ? local.domain.custom_fqdn : local.domain.nip_io_fqdn
    is_nip_io_mode      = !var.use_custom_dns
    is_corrino_com_mode = false
    is_custom_mode      = var.use_custom_dns
  }

  public_endpoint = {
    api                 = join(".", ["api", local.fqdn.name])
    api_origin_insecure = join(".", ["http://api", local.fqdn.name])
    api_origin_secure   = join(".", ["https://api", local.fqdn.name])
    #portal              = join(".", ["portal", local.fqdn.name])
    blueprint_portal = join(".", ["blueprints", local.fqdn.name])
    mlflow           = join(".", ["mlflow", local.fqdn.name])
    prometheus       = join(".", ["prometheus", local.fqdn.name])
    grafana          = join(".", ["grafana", local.fqdn.name])
    starter_pack = join(".", [
      local.primary_skin != null
      ? local.primary_skin.subdomain
      : try(local.starter_pack_config.frontend_url, ""),
      local.fqdn.name
    ])
    aiq_frontend = join(".", ["aiq", local.fqdn.name])
  }

  third_party_namespaces = {
    prometheus_namespace = try(kubernetes_namespace_v1.cluster_tools[0].id, "cluster-tools")
  }

  env_universal = [
    {
      name  = "OCI_CLI_PROFILE"
      value = "instance_principal"
    }
  ]

  env_app_jobs = [
    {
      name  = "CP_BACKGROUND_PROCESSING_ENABLED"
      value = "False"
    }
  ]

  env_app_user = [
    {
      name  = "DJANGO_SUPERUSER_USERNAME"
      value = var.corrino_admin_username
    },
    {
      name  = "DJANGO_SUPERUSER_PASSWORD"
      value = var.corrino_admin_password
    },
    {
      name  = "DJANGO_SUPERUSER_EMAIL"
      value = var.corrino_admin_email
    }
  ]

  env_app_api = [
    {
      name  = "CP_BACKGROUND_PROCESSING_ENABLED"
      value = "False"
    }
  ]

  env_app_api_background = [
    {
      name  = "CP_BACKGROUND_PROCESSING_ENABLED"
      value = "True"
    }
  ]

  env_app_configmap = [
    {
      name            = "ADDON_GRAFANA_TOKEN"
      config_map_name = "corrino-configmap"
      config_map_key  = "ADDON_GRAFANA_TOKEN"
    },
    {
      name            = "ADDON_GRAFANA_USER"
      config_map_name = "corrino-configmap"
      config_map_key  = "ADDON_GRAFANA_USER"
    },
    {
      name            = "APP_IMAGE_URI"
      config_map_name = "corrino-configmap"
      config_map_key  = "APP_IMAGE_URI"
    },
    {
      name            = "BACKEND_SERVICE_NAME"
      config_map_name = "corrino-configmap"
      config_map_key  = "BACKEND_SERVICE_NAME"
    },
    {
      name            = "COMPARTMENT_ID"
      config_map_name = "corrino-configmap"
      config_map_key  = "COMPARTMENT_ID"
    },
    {
      name            = "CONTROL_PLANE_VERSION"
      config_map_name = "corrino-configmap"
      config_map_key  = "CONTROL_PLANE_VERSION"
    },
    {
      name            = "DJANGO_ALLOWED_HOSTS"
      config_map_name = "corrino-configmap"
      config_map_key  = "DJANGO_ALLOWED_HOSTS"
    },
    {
      name            = "DJANGO_CSRF_TRUSTED_ORIGINS"
      config_map_name = "corrino-configmap"
      config_map_key  = "DJANGO_CSRF_TRUSTED_ORIGINS"
    },
    {
      name            = "DJANGO_SECRET"
      config_map_name = "corrino-configmap"
      config_map_key  = "DJANGO_SECRET"
    },
    {
      name            = "FRONTEND_HTTPS_FLAG"
      config_map_name = "corrino-configmap"
      config_map_key  = "FRONTEND_HTTPS_FLAG"
    },
    {
      name            = "IMAGE_REGISTRY_BASE_URI"
      config_map_name = "corrino-configmap"
      config_map_key  = "IMAGE_REGISTRY_BASE_URI"
    },
    {
      name            = "LOGGING_LEVEL"
      config_map_name = "corrino-configmap"
      config_map_key  = "LOGGING_LEVEL"
    },
    {
      name            = "NAMESPACE_NAME"
      config_map_name = "corrino-configmap"
      config_map_key  = "NAMESPACE_NAME"
    },
    {
      name            = "OKE_CLUSTER_ID"
      config_map_name = "corrino-configmap"
      config_map_key  = "OKE_CLUSTER_ID"
    },
    {
      name            = "OKE_NODE_SUBNET_ID"
      config_map_name = "corrino-configmap"
      config_map_key  = "OKE_NODE_SUBNET_ID"
    },
    {
      name            = "PUBLIC_ENDPOINT_BASE"
      config_map_name = "corrino-configmap"
      config_map_key  = "PUBLIC_ENDPOINT_BASE"
    },
    {
      name            = "INFERENCE_GATEWAY_BASE"
      config_map_name = "corrino-configmap"
      config_map_key  = "INFERENCE_GATEWAY_BASE"
    },
    {
      name            = "RECIPE_BUCKET_NAME"
      config_map_name = "corrino-configmap"
      config_map_key  = "RECIPE_BUCKET_NAME"
    },
    {
      name            = "RECIPE_VALIDATION_ENABLED"
      config_map_name = "corrino-configmap"
      config_map_key  = "RECIPE_VALIDATION_ENABLED"
    },
    {
      name            = "RECIPE_VALIDATION_SHAPE_AVAILABILITY_ENABLED"
      config_map_name = "corrino-configmap"
      config_map_key  = "RECIPE_VALIDATION_SHAPE_AVAILABILITY_ENABLED"
    },
    {
      name            = "REGION_NAME"
      config_map_name = "corrino-configmap"
      config_map_key  = "REGION_NAME"
    },
    {
      name            = "TENANCY_ID"
      config_map_name = "corrino-configmap"
      config_map_key  = "TENANCY_ID"
    },
    {
      name            = "TENANCY_NAMESPACE"
      config_map_name = "corrino-configmap"
      config_map_key  = "TENANCY_NAMESPACE"
    },
    {
      name            = "API_BASE_URL"
      config_map_name = "corrino-configmap"
      config_map_key  = "BACKEND_SERVICE_NAME"
    },
    {
      name            = "PORTAL_DEMO_FLAG"
      config_map_name = "corrino-configmap"
      config_map_key  = "PORTAL_DEMO_FLAG"
    },
    {
      name            = "BLUEPRINTS_OBJECT_STORAGE_URL"
      config_map_name = "corrino-configmap"
      config_map_key  = "BLUEPRINTS_OBJECT_STORAGE_URL"
    },
    {
      name            = "SHARED_NODE_POOL_BLUEPRINTS_OBJECT_STORAGE_URL"
      config_map_name = "corrino-configmap"
      config_map_key  = "SHARED_NODE_POOL_BLUEPRINTS_OBJECT_STORAGE_URL"
    },
    {
      name            = "SHARED_NODE_POOL_DOCUMENTATION_URL"
      config_map_name = "corrino-configmap"
      config_map_key  = "SHARED_NODE_POOL_DOCUMENTATION_URL"
    },
    {
      name            = "BLUEPRINT_DOCUMENTATION_URL"
      config_map_name = "corrino-configmap"
      config_map_key  = "BLUEPRINT_DOCUMENTATION_URL"
    },
    {
      name            = "DATA_SHARING_ENABLED"
      config_map_name = "corrino-configmap"
      config_map_key  = "DATA_SHARING_ENABLED"
    },
    {
      name            = "DATA_UPLOAD_PATH"
      config_map_name = "corrino-configmap"
      config_map_key  = "DATA_UPLOAD_PATH"
    },
    {
      name            = "DEPLOYMENT_UUID"
      config_map_name = "corrino-configmap"
      config_map_key  = "DEPLOYMENT_UUID"
    },
    {
      name            = "PROMETHEUS_NAMESPACE"
      config_map_name = "corrino-configmap"
      config_map_key  = "PROMETHEUS_NAMESPACE"
    },
    {
      name            = "RELEASE_VERSION"
      config_map_name = "corrino-configmap"
      config_map_key  = "RELEASE_VERSION"
    },
  ]

  env_psql_configmap = [
    {
      name            = "POSTGRES_HOST"
      config_map_name = "corrino-configmap"
      config_map_key  = "POSTGRES_HOST"
    },
    {
      name            = "POSTGRES_PORT"
      config_map_name = "corrino-configmap"
      config_map_key  = "POSTGRES_PORT"
    },
    {
      name            = "POSTGRES_DB"
      config_map_name = "corrino-configmap"
      config_map_key  = "POSTGRES_DB"
    },
    {
      name            = "POSTGRES_USER"
      config_map_name = "corrino-configmap"
      config_map_key  = "POSTGRES_USER"
    },
    {
      name            = "POSTGRES_PASSWORD"
      config_map_name = "corrino-configmap"
      config_map_key  = "POSTGRES_PASSWORD"
    },
  ]

}


