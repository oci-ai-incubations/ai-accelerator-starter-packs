# -----------------------------------
# Starter Pack Blueprints
# Organized by category, then by size
# Add new blueprints here when implementing new sizes
# -----------------------------------
locals {
  # cuOpt-only (LiveLabs). Single category, single size (poc).
  starter_pack_blueprints = {
    "cuopt" = {
      "poc" = local._cuopt_blueprint
    }
  }
}

# -----------------------------------
# Individual Blueprint Definitions
# -----------------------------------
locals {
  # Filter out Helm-pack entries (no variable_name). These locals are always
  # evaluated; without the filter, switching to a Helm pack would crash on
  # skin.variable_name access even though nothing reads the result for that pack.
  _cuopt_frontend_deployments = [
    for skin in local.enabled_frontend_skins : {
      name       = skin.variable_name
      exports    = ["service_name"]
      depends_on = concat(["cuopt", "llamastack", "cuopt-backend"], local.enable_auth_service ? ["auth-service"] : [])
      recipe = merge(
        {
          recipe_id                            = replace(skin.variable_name, "_", "-")
          deployment_name                      = replace(skin.variable_name, "_", "-")
          recipe_mode                          = "service"
          recipe_image_uri                     = skin.image_uri
          recipe_replica_count                 = 1
          recipe_flex_shape_ocpu_count         = 1
          recipe_flex_shape_memory_size_in_gbs = 8
          recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
          recipe_use_shared_node_pool          = true
          recipe_container_port                = skin.container_port
          service_endpoint_subdomain           = skin.subdomain
          recipe_container_env = [
            { key = "CUOPT_ENDPOINT", value = "http://$${cuopt.service_name}:80" },
            { key = "LLAMASTACK_ENDPOINT", value = "http://$${llamastack.service_name}:80" },
            { key = "LLAMASTACK_MODEL", value = "" },
            { key = "GOOGLE_MAPS_API_KEY", value = var.google_maps_api_key },
            { key = "ADMIN_USERNAME", value = var.cuopt_frontend_admin_username },
            { key = "ADMIN_PASSWORD", value = var.cuopt_frontend_admin_password },
            { key = "NODE_ENV", value = "production" },
          ]
          recipe_additional_ingress_ports = concat(
            [
              { port_name = "cuopt", service_name = "$${cuopt.service_name}", port = 5000, path = "/cuopt", path_type = "Prefix" },
              { port_name = "llamastack", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1", path_type = "Prefix" },
            ],
            local.cuopt_backend_ingress_route,
            local.auth_service_ingress_route
          )
        },
        var.use_custom_dns ? { service_endpoint_domain = local.public_endpoint.starter_pack } : {}
      )
    }
    if try(skin.variable_name, "") != ""
  ]

  _cuopt_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat(
        [
          {
            name    = "llamastack",
            exports = ["service_name"],
            # auth-service in depends_on when on so Corrino can resolve the
            # $${auth-service.service_name} placeholder in the auth-url annotation
            # injected by backend_ingress_annotations_corrino.
            depends_on = local.enable_auth_service ? ["auth-service"] : [],
            recipe = {
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              recipe_id                             = "llamastack",
              deployment_name                       = "llamastack",
              recipe_mode                           = "service",
              recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3",
              recipe_replica_count                  = 1,
              recipe_flex_shape_ocpu_count          = 1,
              recipe_flex_shape_memory_size_in_gbs  = 8,
              recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape,
              recipe_use_shared_node_pool           = true,
              recipe_container_port                 = "8321",
              recipe_container_command_args         = ["/config/config.yaml"],
              recipe_container_env = [
                { key = "OCI_COMPARTMENT_OCID", value = local.compartment_ocid },
                { key = "OCI_REGION", value = var.genai_region },
                { key = "OCI_AUTH_TYPE", value = "instance_principal" },
              ]
              recipe_secret_mounts = [
                { "name" = "llamastack-inference-config", "mount_location" = "/config" }
              ]
            }
          },
          {
            name    = "cuopt"
            exports = ["service_name"]
            # auth-service in depends_on when on — same reason as the llamastack
            # block above: the auth-url annotation references $${auth-service.service_name}
            # and Corrino's resolver needs auth-service exports collected first.
            depends_on = local.enable_auth_service ? ["auth-service"] : []
            recipe = {
              recipe_additional_ingress_annotations        = local.backend_ingress_annotations_corrino
              recipe_id                                    = "cuopt"
              recipe_mode                                  = "service"
              deployment_name                              = "DEPLOY_NAME-2"
              recipe_image_uri                             = "nvcr.io/nvidia/cuopt/cuopt:25.10.0-cuda12.9-py3.13"
              recipe_container_secret_name                 = local.ngc_secrets.docker_secret_name
              recipe_node_shape                            = local.starter_pack_config.worker_node_shape
              recipe_replica_count                         = 1
              recipe_container_port                        = "5000"
              recipe_nvidia_gpu_count                      = 2
              recipe_use_shared_node_pool                  = true
              recipe_ephemeral_storage_size                = 200
              recipe_shared_memory_volume_size_limit_in_mb = 16384
              recipe_environment_secrets = [
                {
                  envvar_name = local.ngc_secrets.nvidia_api_key_envvar_name
                  secret_name = local.ngc_secrets.nvidia_api_key_secret_name
                  secret_key  = local.ngc_secrets.nvidia_api_key_secret_key
                }
              ]
              recipe_container_command_args = [
                "python",
                "-m",
                "cuopt_server.cuopt_service",
                "-p",
                "5000",
                "-g",
                "2"
              ]
              recipe_liveness_probe_params = {
                port                  = 5000
                scheme                = "HTTP"
                endpoint_path         = "/v2/health/live"
                period_seconds        = 60
                timeout_seconds       = 10
                failure_threshold     = 3
                success_threshold     = 1
                initial_delay_seconds = 1200
              }
              recipe_readiness_probe_params = {
                port                  = 5000
                scheme                = "HTTP"
                endpoint_path         = "/v2/health/ready"
                period_seconds        = 30
                timeout_seconds       = 10
                success_threshold     = 1
                initial_delay_seconds = 20
              }
            }
          },
        ],
        local.cuopt_backend_recipe,
        local._cuopt_frontend_deployments,
        local.auth_service_recipe
      )
    }
  })

}
