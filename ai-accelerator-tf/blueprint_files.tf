locals {
  cuopt_small_blueprint = jsonencode({
    recipe_id                               = "cuopt"
    recipe_mode                            = "service"
    deployment_name                        = "cuopt2gpunvi"
    recipe_image_uri                       = "nvcr.io/nvidia/cuopt/cuopt:25.10.0-cuda12.9-py3.13"
    recipe_container_secret_name           = local.ngc_secrets.docker_secret_name
    recipe_node_shape                      = "BM.GPU4.8"
    recipe_replica_count                   = 8
    recipe_container_port                  = "5000"
    recipe_nvidia_gpu_count                = 1
    recipe_use_shared_node_pool            = true
    recipe_ephemeral_storage_size          = 200
    recipe_shared_memory_volume_size_limit_in_mb = 16384
    recipe_environment_secrets = [
      {
        envvar_name   = local.ngc_secrets.nvidia_api_key_envvar_name
        secret_name   = local.ngc_secrets.nvidia_api_key_secret_name
        secret_key    = local.ngc_secrets.nvidia_api_key_secret_key
      }
    ]
    recipe_container_command_args = [
      "python",
      "-m",
      "cuopt_server.cuopt_service",
      "-p",
      "5000",
      "-g",
      "1"
    ]
    recipe_liveness_probe_params = {
      port                   = 5000
      scheme                 = "HTTP"
      endpoint_path          = "/v2/health/live"
      period_seconds         = 60
      timeout_seconds        = 10
      failure_threshold      = 3
      success_threshold      = 1
      initial_delay_seconds  = 1200
    }
    recipe_readiness_probe_params = {
      port                   = 5000
      scheme                 = "HTTP"
      endpoint_path          = "/v2/health/ready"
      period_seconds         = 30
      timeout_seconds        = 10
      success_threshold      = 1
      initial_delay_seconds  = 20
    }
  })
}
