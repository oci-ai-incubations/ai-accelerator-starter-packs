# -----------------------------------
# Starter Pack Blueprints
# Organized by category, then by size
# Add new blueprints here when implementing new sizes
# -----------------------------------
locals {
  starter_pack_blueprints = {
    "cuopt" = {
      "poc"    = local._cuopt_blueprint
      "small"  = local._cuopt_blueprint
      "medium" = local._cuopt_blueprint
      # Add "large" here when implemented
    }
    "vss" = {
      "poc"    = local._vss_poc_blueprint
      "small"  = local._vss_small_blueprint
      "medium" = local._vss_medium_blueprint
      # Add "large" here when implemented
    }
    "paas_rag" = {
      "small"  = local._paas_rag_small_blueprint
      "medium" = local._paas_rag_small_blueprint
      # Add "large" here when implemented
    }
    "dox_pack" = {
      "small" = local._dox_pack_small_blueprint
    }
    # enterprise_rag is deployed via Helm, not OCI AI Blueprints - no blueprint content needed
    "enterprise_rag" = {
      "small" = ""
      # Add "medium" here when implemented
      # Add "large" here when implemented
    }
    "enterprise_rag_aiq" = {
      "small"  = ""
      "medium" = ""
      # Helm-managed deployment; no blueprint artefact required
    }
    "warehouse_pick_path" = {
      "small" = local._warehouse_pick_path_small_blueprint
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
      depends_on = concat(["cuopt", "llamastack", "cuopt-backend"], var.enable_auth_service ? ["auth-service"] : [])
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
            depends_on = var.enable_auth_service ? ["auth-service"] : [],
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
                { key = "OCI_COMPARTMENT_OCID", value = var.compartment_ocid },
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
            depends_on = var.enable_auth_service ? ["auth-service"] : []
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
              recipe_nvidia_gpu_count                      = var.starter_pack_size == "poc" ? 2 : 8
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
                var.starter_pack_size == "poc" ? "2" : "8"
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

  _vss_poc_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat([
        {
          name       = "llamastack"
          exports    = ["service_name"]
          depends_on = var.enable_auth_service ? ["auth-service"] : []
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "llamastack"
            deployment_name                       = "llamastack"
            recipe_mode                           = "service"
            recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3"
            recipe_node_pool_size                 = 1
            recipe_replica_count                  = 1
            recipe_flex_shape_ocpu_count          = 1
            recipe_flex_shape_memory_size_in_gbs  = 8
            recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_container_port                 = "8321"
            recipe_container_command_args         = ["/config/config.yaml"]
            recipe_use_shared_node_pool           = true
            service_endpoint_subdomain            = "llamastack"
            recipe_container_env = [
              { key = "OCI_COMPARTMENT_OCID", value = var.compartment_ocid },
              { key = "OCI_REGION", value = var.genai_region },
              { key = "OCI_AUTH_TYPE", value = "instance_principal" }
            ]
            recipe_secret_mounts = [
              { "name" = "llamastack-inference-config", "mount_location" = "/config" }
            ]
          }
        },
        {
          name       = "elasticsearch"
          exports    = ["internal_dns_name"]
          depends_on = var.enable_auth_service ? ["auth-service"] : []
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "elasticsearch-standalone"
            recipe_mode                           = "service"
            deployment_name                       = "elasticsearch-deployment-group"
            recipe_host_port                      = "9200"
            recipe_image_uri                      = "docker.io/elasticsearch:9.1.2"
            recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_node_pool_size                 = 1
            recipe_flex_shape_ocpu_count          = 4
            recipe_flex_shape_memory_size_in_gbs  = 64
            recipe_container_env = [
              { key = "discovery.type", value = "single-node" },
              { key = "xpack.security.enabled", value = "false" },
              { key = "ES_JAVA_OPTS", value = "-Xms6g -Xmx6g" }
            ]
            recipe_replica_count        = 1
            recipe_container_port       = "9200"
            recipe_use_shared_node_pool = true
            recipe_additional_ingress_ports = [
              { port_name = "transport", path = "/", port = 9300 }
            ]
          }
        },
        {
          name       = "neo4j"
          exports    = ["internal_dns_name"]
          depends_on = concat(["elasticsearch"], var.enable_auth_service ? ["auth-service"] : [])
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_mode                           = "service"
            deployment_name                       = "neo4j-deployment-group"
            recipe_host_port                      = "7687"
            recipe_image_uri                      = "docker.io/neo4j:5.26.4"
            recipe_flex_shape_ocpu_count          = 4
            recipe_flex_shape_memory_size_in_gbs  = 64
            recipe_node_pool_size                 = 1
            recipe_configmaps = [
              {
                data = {
                  "config.yaml" = "SampleConfig:\n  sampleValue: 0\n"
                }
                name           = "configs"
                default_mode   = 420
                mount_location = "/opt/configs"
              },
              {
                data = {
                  "start.sh"  = "#!/bin/bash\nexport NEO4J_AUTH=\"$${DB_USERNAME}/$${DB_PASSWORD}\"\nexport NEO4JLABS_PLUGINS='[\"apoc\"]'\n\ntini -g -- /startup/docker-entrypoint.sh neo4j\n"
                  "script.sh" = "#The scripts can be used as commands in the Initcontainers or as container commands.\n#Size of script file can not exceed 1 MiB\n"
                }
                name           = "scripts"
                default_mode   = 493
                mount_location = "/opt/scripts"
              },
              {
                data           = { ".placeholder" = "" }
                name           = "workload"
                default_mode   = 420
                mount_location = "/opt/workload-config"
              }
            ]
            recipe_node_shape        = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_replica_count     = 1
            recipe_container_port    = "7687"
            recipe_container_command = ["bash", "/opt/scripts/start.sh"]
            recipe_environment_secrets = [
              { secret_key = "username", envvar_name = "DB_USERNAME", secret_name = "neo4j-creds" },
              { secret_key = "password", envvar_name = "DB_PASSWORD", secret_name = "neo4j-creds" }
            ]
            recipe_startup_probe_params = {
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
              failure_threshold = 30
            }
            recipe_liveness_probe_params = {
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
              failure_threshold = 3
            }
            recipe_readiness_probe_params = {
              port                  = 7687
              scheme                = "TCP"
              period_seconds        = 5
              timeout_seconds       = 1
              failure_threshold     = 3
              initial_delay_seconds = 5
            }
            recipe_use_shared_node_pool = true
            recipe_additional_ingress_ports = [
              { port_name = "http", path = "/", port = 7474 }
            ]
          }
        },
        {
          name       = "embedding"
          exports    = ["internal_dns_name"]
          depends_on = concat(["neo4j"], var.enable_auth_service ? ["auth-service"] : [])
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            pvcs = {
              volumes = [
                { name = "nemo-embed-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
              retain_after_undeploy = false
            }
            recipe_id         = "nemo-embedding-nim"
            recipe_mode       = "service"
            deployment_name   = "nemo-embedding-deployment-group"
            recipe_host_port  = "8000"
            recipe_image_uri  = "nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0"
            recipe_node_shape = local.starter_pack_config.worker_node_shape
            recipe_container_env = [
              { key = "NIM_TRT_ENGINE_HOST_CODE_ALLOWED", value = "1" },
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_replica_count    = 1
            recipe_container_port   = "8000"
            recipe_nvidia_gpu_count = 1
            recipe_storage_group_id = 1000
            recipe_environment_secrets = [
              { secret_key = "NGC_API_KEY", envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret" }
            ]
            recipe_use_shared_node_pool  = true
            recipe_container_secret_name = "ngc-secret"
            recipe_liveness_probe_params = {
              port                  = 8000
              scheme                = "HTTP"
              endpoint_path         = "/v1/health/ready"
              period_seconds        = 30
              timeout_seconds       = 20
              failure_threshold     = 3
              initial_delay_seconds = 10
            }
          }
        },
        {
          name       = "rerank"
          exports    = ["internal_dns_name"]
          depends_on = concat(["embedding"], var.enable_auth_service ? ["auth-service"] : [])
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            pvcs = {
              volumes = [
                { name = "nemo-rerank-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
              retain_after_undeploy = false
            }
            recipe_id         = "nemo-rerank-nim"
            recipe_mode       = "service"
            deployment_name   = "nemo-rerank-deployment-group"
            recipe_host_port  = "8000"
            recipe_image_uri  = "nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0"
            recipe_node_shape = local.starter_pack_config.worker_node_shape
            recipe_container_env = [
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_replica_count    = 1
            recipe_container_port   = "8000"
            recipe_nvidia_gpu_count = 1
            recipe_storage_group_id = 1000
            recipe_environment_secrets = [
              { secret_key = "NGC_API_KEY", envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret" }
            ]
            recipe_use_shared_node_pool  = true
            recipe_container_secret_name = "ngc-secret"
            recipe_liveness_probe_params = {
              port                  = 8000
              scheme                = "HTTP"
              endpoint_path         = "/v1/health/ready"
              period_seconds        = 10
              timeout_seconds       = 20
              failure_threshold     = 100
              initial_delay_seconds = 10
            }
          }
        },
        {
          name       = "riva"
          exports    = ["internal_dns_name"]
          depends_on = concat(["rerank"], var.enable_auth_service ? ["auth-service"] : [])
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            pvcs = {
              volumes = [
                { name = "riva-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 100 }
              ]
              retain_after_undeploy = false
            }
            recipe_id         = "riva-nim"
            recipe_mode       = "service"
            deployment_name   = "riva-deployment-group"
            recipe_host_port  = "9000"
            recipe_image_uri  = "nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us:2.0.0"
            recipe_node_shape = local.starter_pack_config.worker_node_shape
            recipe_container_env = [
              { key = "NIM_HTTP_API_PORT", value = "9000" },
              { key = "NIM_GRPC_API_PORT", value = "50051" },
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" },
              { key = "NIM_TAGS_SELECTOR", value = "name=parakeet-0-6b-ctc-riva-en-us,mode=all" }
            ]
            recipe_replica_count    = 1
            recipe_container_port   = "9000"
            recipe_nvidia_gpu_count = 1
            recipe_storage_group_id = 1000
            recipe_environment_secrets = [
              { secret_key = "NGC_API_KEY", envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret" }
            ]
            recipe_use_shared_node_pool  = true
            recipe_container_secret_name = "ngc-secret"
            recipe_liveness_probe_params = {
              port                  = 9000
              scheme                = "HTTP"
              endpoint_path         = "/v1/health/ready"
              period_seconds        = 30
              timeout_seconds       = 20
              failure_threshold     = 3
              initial_delay_seconds = 10
            }
            recipe_additional_ingress_ports = [
              { port_name = "grpc", path = "/", port = 50051 }
            ]
          }
        },
        {
          name    = "vss"
          exports = ["service_name"]
          depends_on = concat(
            ["llamastack", "embedding", "rerank", "riva", "elasticsearch", "neo4j"],
            var.enable_auth_service ? ["auth-service"] : [],
          )
          recipe = merge(
            {
              pvcs = {
                volumes = [
                  { name = "vss-ngc-model-cache", mount_location = "/tmp/via-ngc-model-cache", volume_size_in_gbs = 1000 }
                ]
                retain_after_undeploy = false
              }
              input_file_system = local.deploy_app_vss ? [
                {
                  file_system_ocid   = oci_file_storage_file_system.vss_fss[0].id
                  mount_target_ocid  = oci_file_storage_mount_target.vss_mount_target[0].id
                  mount_location     = "/mnt/fss"
                  volume_size_in_gbs = 1000
                }
              ] : []
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              deployment_name                       = "vss-deployment-group"
              recipe_mode                           = "service"
              recipe_host_port                      = "9000"
              recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/vss-engine:2.4.0-poc-custom-c105566"
              recipe_configmaps = [
                {
                  data = {
                    "start.sh" = "#!/bin/bash\nset -e\n\n# Pre-create the shared FSS cache dir that vss-download-service (uid 1001)\n# writes into. vss runs with recipe_storage_group_id=1000 so it has write\n# access to /mnt/fss; chmod 0777 lets the downloader's uid use the same\n# dir without remounting or shifting gids.\nmkdir -p /mnt/fss/cache\nchmod 0777 /mnt/fss/cache\n\n# Check Riva specific environment variables and set them if not set.\nif [ -z \"$${RIVA_ASR_SERVER_URI}\" ]; then\n    export RIVA_ASR_SERVER_URI=\"riva-service\"\n    echo \"RIVA_ASR_SERVER_URI was not set. Using default value: $RIVA_ASR_SERVER_URI\"\nfi\n\nif [ -z \"$${RIVA_ASR_GRPC_PORT}\" ]; then\n    export RIVA_ASR_GRPC_PORT=\"50051\"\nfi\n\nif [ -z \"$${RIVA_ASR_HTTP_PORT}\" ]; then\n    export RIVA_ASR_HTTP_PORT=\"9000\"\nfi\n\nif [ -z \"$${ENABLE_RIVA_SERVER_READINESS_CHECK}\" ]; then\n    export ENABLE_RIVA_SERVER_READINESS_CHECK=\"false\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_IS_NIM}\" ]; then\n    export RIVA_ASR_SERVER_IS_NIM=\"true\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_USE_SSL}\" ]; then\n    export RIVA_ASR_SERVER_USE_SSL=\"false\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_API_KEY}\" ]; then\n    export RIVA_ASR_SERVER_API_KEY=\"\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_FUNC_ID}\" ]; then\n    export RIVA_ASR_SERVER_FUNC_ID=\"\"\nfi\n\nif [ -z \"$${INSTALL_PROPRIETARY_CODECS}\" ]; then\n    export INSTALL_PROPRIETARY_CODECS=\"false\"\nfi\n\nif [ -z \"$${OPENAI_API_KEY_NAME}\" ]; then\n    export OPENAI_API_KEY_NAME=\"openai-api-key\"\nfi\n\nif [ -z \"$${NVIDIA_API_KEY_NAME}\" ]; then\n    export NVIDIA_API_KEY_NAME=\"nvidia-api-key\"\nfi\n\nif [ -z \"$${NGC_API_KEY_NAME}\" ]; then\n    export NGC_API_KEY_NAME=\"ngc-api-key\"\nfi\n\nif [ -f \"/var/secrets/secrets.json\" ]; then\n    if grep -q \"$${OPENAI_API_KEY_NAME}\" \"/var/secrets/secrets.json\"; then\n        export OPENAI_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$${OPENAI_API_KEY_NAME}\\\"]\" -r)\n    fi\n    if grep -q \"$${NVIDIA_API_KEY_NAME}\" \"/var/secrets/secrets.json\"; then\n        export NVIDIA_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$${NVIDIA_API_KEY_NAME}\\\"]\" -r)\n    fi\n    if grep -q \"$${NGC_API_KEY_NAME}\" \"/var/secrets/secrets.json\"; then\n        export NGC_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$${NGC_API_KEY_NAME}\\\"]\" -r)\n    fi\nfi\n\nmkdir -p /tmp/via\ncp /opt/configs/guardrails_config.yaml /opt/nvidia/via/guardrails_config/config.yml\ncp /opt/configs/ca_rag_config.yaml /tmp/via/default_config.yaml\nexport CA_RAG_CONFIG=\"/tmp/via/default_config.yaml\"\ncp /opt/configs/cv_pipeline_tracker_config.yml /tmp/default_tracker_config.yml\nexport CV_PIPELINE_TRACKER_CONFIG=\"/tmp/default_tracker_config.yml\"\n\nmkdir -p /tmp/huggingface-via\nexport HF_HOME=/tmp/huggingface-via\nexport NGC_MODEL_CACHE=/tmp/via-ngc-model-cache\nexport CUPY_CACHE_DIR=/tmp/cupy_cache\nmkdir -p /tmp/via/triton-cache\nexport TRITON_CACHE_DIR=/tmp/via/triton-cache\ncd /tmp/via\nln -s /opt/nvidia/via/via-engine via-engine\nln -s /opt/nvidia/via/config config\n\nif [ -z \"$${LLM_MODEL}\" ]; then\n    export LLM_MODEL=\"$${LLM_MODEL}\"\nfi\n\nCONFIG_FILE=\"/tmp/via/default_config.yaml\"\ncontent=$(cat \"$CONFIG_FILE\")\nwhile IFS= read -r var; do\n    [[ -z \"$var\" ]] && continue\n    [[ \"$var\" == egress.* ]] && continue\n    if [[ -n \"$${!var:-}\" ]]; then\n        value=\"$${!var}\"\n        escaped_value=$(printf '%s\\n' \"$value\" | sed -e 's/[\\/&]/\\\\&/g')\n        if echo \"$content\" | grep -q \"port:.*\\$${$var}\"; then\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/\\\"$escaped_value\\\"/g\")\n        else\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/$escaped_value/g\")\n        fi\n    else\n        echo \"Warning: Environment variable '$var' is not set\" >&2\n    fi\ndone < <(grep -oE '\\$\\{[^}]+\\}' \"$CONFIG_FILE\" | sed 's/\\$${\\([^}]*\\)}/\\1/' | sort -u)\necho \"$content\" > \"$CONFIG_FILE\"\n\nsed -i 's|^FILE_NAME_PATTERN = .*|FILE_NAME_PATTERN = r\"^[A-Za-z0-9_.\\\\-/ ]*$\"|' /opt/nvidia/via/via-engine/vss_api_models.py\n/opt/nvidia/via/start_via.sh\n"
                  }
                  name           = "scripts"
                  default_mode   = 493
                  mount_location = "/opt/scripts"
                },
                {
                  data = {
                    "ca_rag_config.yaml"             = "context_manager:\n  functions:\n  - summarization\n  - ingestion_function\n  - retriever_function\n  - notification\nfunctions:\n  ingestion_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_ingestion\n  notification:\n    params:\n      events: []\n    tools:\n      llm: notification_llm\n      notification_tool: notification_tool\n    type: notification\n  retriever_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_retrieval\n  summarization:\n    params:\n      batch_max_concurrency: 20\n      batch_size: 5\n      prompts:\n        caption: Write a concise and clear dense caption for the provided warehouse video, focusing on irregular or hazardous events such as boxes falling, workers not wearing PPE, workers falling, workers taking photographs, workers chitchatting, forklift stuck, etc. Start and end each sentence with a time stamp.\n        caption_summarization: 'You should summarize the following events of a warehouse in the format start_time:end_time:caption. For start_time and end_time use . to seperate seconds, minutes, hours. If during a time segment only regular activities happen, then ignore them, else note any irregular activities in detail. The output should be bullet points in the format start_time:end_time: detailed_event_description. Don''t return anything else except the bullet points.'\n        summary_aggregation: 'You are a warehouse monitoring system. Given the caption in the form start_time:end_time: caption, Aggregate the following captions in the format start_time:end_time:event_description. If the event_description is the same as another event_description, aggregate the captions in the format start_time1:end_time1,...,start_timek:end_timek:event_description. If any two adjacent end_time1 and start_time2 is within a few tenths of a second, merge the captions in the format start_time1:end_time2. The output should only contain bullet points. Cluster the output into Unsafe Behavior, Operational Inefficiencies, Potential Equipment Damage and Unauthorized Personnel'\n    tools:\n      db: graph_db\n      llm: summarization_llm\n    type: batch_summarization\ntools:\n  chat_llm:\n    params:\n      api_key: $${OPENAI_API_KEY}\n      base_url: $${LLM_BASE_URL}\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  graph_db:\n    params:\n      host: $${GRAPH_DB_HOST}\n      password: $${GRAPH_DB_PASSWORD}\n      port: $${GRAPH_DB_PORT}\n      username: $${GRAPH_DB_USERNAME}\n    tools:\n      embedding: nvidia_embedding\n    type: neo4j\n  notification_llm:\n    params:\n      api_key: $${OPENAI_API_KEY}\n      base_url: $${LLM_BASE_URL}\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  notification_tool:\n    params:\n      endpoint: http://127.0.0.1:60000/via-alert-callback\n    type: alert_sse_notifier\n  nvidia_embedding:\n    params:\n      base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n      model: nvidia/llama-3.2-nv-embedqa-1b-v2\n    type: embedding\n  nvidia_reranker:\n    params:\n      base_url: http://$${RERANK_HOST}:$${RERANK_PORT}/v1\n      model: nvidia/llama-3.2-nv-rerankqa-1b-v2\n    type: reranker\n  summarization_llm:\n    params:\n      api_key: $${OPENAI_API_KEY}\n      base_url: $${LLM_BASE_URL}\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  vector_db:\n    params:\n      host: $${MILVUS_DB_HOST}\n      port: $${MILVUS_DB_PORT}\n    tools:\n      embedding: nvidia_embedding\n    type: milvus\n"
                    "guardrails_config.yaml"         = "instructions:\n- content: |\n    Below is a conversation between a bot and a user about the image or video.\n    The bot is factual and concise. If the bot does not know the answer to a\n    question, it truthfully says it does not know.\n  type: general\nmodels:\n- engine: nim\n  model: $${LLM_MODEL}\n  parameters:\n    base_url: $${LLM_BASE_URL}\n  type: main\n- engine: nim\n  model: nvidia/llama-3.2-nv-embedqa-1b-v2\n  parameters:\n    base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n  type: embeddings\nsample_conversation: |\n  user \"Hello there!\"\n    express greeting\n  bot express greeting\n    \"Hello! How can I assist you today?\"\n  user \"What can you do for me?\"\n    ask about capabilities\n  bot respond about capabilities\n    \"I am an AI assistant here to answer questions about the image or video.\"\n"
                    "cv_pipeline_tracker_config.yml" = "BaseConfig:\n  minDetectorConfidence: 0.1630084739998828\nDataAssociator:\n  associationMatcherType: 1\n  checkClassMatch: 1\n  dataAssociatorType: 0\n  matchingScoreWeight4Iou: 0.46547889321000563\n  matchingScoreWeight4SizeSimilarity: 0.4463422634549605\n  matchingScoreWeight4VisualSimilarity: 0.7092410997389017\n  minMatchingScore4Iou: 0.29413058985254187\n  minMatchingScore4Overall: 0.06843005365443096\n  minMatchingScore4SizeSimilarity: 0.2929323932012989\n  minMatchingScore4TentativeIou: 0.45510391462097216\n  minMatchingScore4VisualSimilarity: 0.42453250143328114\n  tentativeDetectorConfidence: 0.1721247313806944\nReID:\n  addFeatureNormalization: 1\n  batchSize: 100\n  colorFormat: 0\n  inferDims: [3, 256, 128]\n  inputOrder: 0\n  keepAspc: 1\n  modelEngineFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx.engine\n  netScaleFactor: 0.01735207\n  networkMode: 1\n  offsets: [123.675, 116.28, 103.53]\n  onnxFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx\n  outputReidTensor: 0\n  reidFeatureSize: 256\n  reidHistorySize: 100\n  reidType: 2\n  tltModelKey: nvidia_tao\n  useVPICropScaler: 1\n  workspaceSize: 1000\nStateEstimator:\n  measurementNoiseVar4Detector: 100.00000584166246\n  measurementNoiseVar4Tracker: 4988.392688178733\n  processNoiseVar4Loc: 6533.099736052837\n  processNoiseVar4Size: 6415.121729390737\n  processNoiseVar4Vel: 2798.795011988113\n  stateEstimatorType: 1\nTargetManagement:\n  earlyTerminationAge: 1\n  enableBboxUnClipping: 0\n  maxShadowTrackingAge: 39\n  maxTargetsPerStream: 150\n  minIouDiff4NewTarget: 0.8176422840795657\n  minTrackerConfidence: 0.19878939278068558\n  preserveStreamUpdateOrder: 0\n  probationAge: 6\nTrajectoryManagement:\n  enableReAssoc: 1\n  matchingScoreWeight4ReidSimilarity: 0.7200658660519842\n  matchingScoreWeight4TrackletSimilarity: 0.23836654600118312\n  maxAngle4TrackletMatching: 142\n  maxTrackletMatchingTimeSearchRange: 20\n  minBboxSizeSimilarity4TrackletMatching: 0.18214484831006444\n  minMatchingScore4Overall: 0.23583585666333318\n  minMatchingScore4ReidSimilarity: 0.24582563724796622\n  minSpeedSimilarity4TrackletMatching: 0.0023058182326161298\n  minTrackletMatchingScore: 0.09979720773093673\n  minTrajectoryLength4Projection: 37\n  prepLength4TrajectoryProjection: 50\n  reidExtractionInterval: 19\n  trackletSpacialSearchRegionScale: 0.2598\n  trajectoryProjectionLength: 43\n  trajectoryProjectionMeasurementNoiseScale: 100\n  trajectoryProjectionProcessNoiseScale: 0.01\n  useUniqueID: 0\nVisualTracker:\n  featureFocusOffsetFactor_y: -0.15647586556568632\n  featureImgSizeLevel: 3\n  filterChannelWeightsLr: 0.07701879646606641\n  filterLr: 0.13560657062953396\n  gaussianSigma: 1.497826153095461\n  useColorNames: 1\n  useHog: 1\n  visualTrackerType: 2\n"
                  }
                  name           = "configs"
                  default_mode   = 420
                  mount_location = "/opt/configs"
                }
              ]
              recipe_additional_ingress_ports = [
                { port_name = "api", port = 8000, path = "/vss(/|$)(.*)", path_type = "ImplementationSpecific", rewrite_target = "/$2" }
              ]
              recipe_node_shape       = local.starter_pack_config.worker_node_shape
              recipe_nvidia_gpu_count = 1
              recipe_container_env = [
                { key = "VLM_MODEL_TO_USE", value = "openai-compat" },
                { key = "VIA_VLM_ENDPOINT", value = "http://$${llamastack.service_name}/v1/" },
                { key = "VIA_VLM_OPENAI_MODEL_DEPLOYMENT_NAME", value = "oci/openai.gpt-4o" },
                { key = "DISABLE_GUARDRAILS", value = "true" },
                { key = "OPENAI_API_KEY", value = "not-needed" },
                { key = "OPENAI_API_KEY_NAME", value = "OPENAI_API_KEY" },
                { key = "NVIDIA_API_KEY_NAME", value = "VSS_NVIDIA_API_KEY" },
                { key = "NGC_API_KEY_NAME", value = "VSS_NGC_API_KEY" },
                { key = "TRT_LLM_MODE", value = "int4_awq" },
                { key = "DISABLE_CV_PIPELINE", value = "false" },
                { key = "GDINO_INFERENCE_INTERVAL", value = "1" },
                { key = "NUM_CV_CHUNKS_PER_GPU", value = "1" },
                { key = "ENABLE_AUDIO", value = "true" },
                { key = "LLM_BASE_URL", value = "http://$${llamastack.service_name}/v1/" },
                { key = "LLM_MODEL", value = "oci/openai.gpt-5.2" },
                { key = "EMBED_HOST", value = "$${embedding.internal_dns_name}" },
                { key = "EMBED_PORT", value = "8000" },
                { key = "RERANK_HOST", value = "$${rerank.internal_dns_name}" },
                { key = "RERANK_PORT", value = "8000" },
                { key = "RIVA_ASR_SERVER_URI", value = "$${riva.internal_dns_name}" },
                { key = "RIVA_ASR_GRPC_PORT", value = "50051" },
                { key = "RIVA_ASR_HTTP_PORT", value = "9000" },
                { key = "ENABLE_RIVA_SERVER_READINESS_CHECK", value = "true" },
                { key = "RIVA_ASR_SERVER_IS_NIM", value = "true" },
                { key = "RIVA_ASR_SERVER_USE_SSL", value = "false" },
                { key = "INSTALL_PROPRIETARY_CODECS", value = "false" },
                { key = "VLLM_GPU_MEMORY_UTILIZATION", value = "0.7" },
                { key = "FRONTEND_PORT", value = "9000" },
                { key = "BACKEND_PORT", value = "8000" },
                { key = "GRAPH_DB_HOST", value = "$${neo4j.internal_dns_name}" },
                { key = "GRAPH_DB_PORT", value = "7687" },
                { key = "MILVUS_DB_HOST", value = "milvus" },
                { key = "MILVUS_DB_PORT", value = "19530" },
                { key = "MINIO_HOST", value = "milvus-minio" },
                { key = "MINIO_PORT", value = "9000" },
                { key = "MINIO_WEBUI_PORT", value = "9001" },
                { key = "ARANGO_DB_HOST", value = "arango-db-arango-db-deployment-arango-db-service" },
                { key = "ARANGO_DB_PORT", value = "8529" },
                { key = "APP_VECTORSTORE_URL", value = "http://milvus.milvus:19530" },
                { key = "ES_HOST", value = "$${elasticsearch.internal_dns_name}" },
                { key = "ES_PORT", value = "9200" },
                { key = "ES_TRANSPORT_PORT", value = "9300" },
                { key = "NEO4J_AUTH", value = "neo4j/password" }
              ]
              recipe_replica_count     = 1
              recipe_container_port    = "9000"
              recipe_storage_group_id  = 1000
              recipe_container_command = ["bash", "/opt/scripts/start.sh"]
              recipe_environment_secrets = [
                { secret_key = "NGC_API_KEY", envvar_name = "NVIDIA_API_KEY", secret_name = "ngc-api-secret" },
                { secret_key = "NGC_API_KEY", envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret" },
                { secret_key = "username", envvar_name = "GRAPH_DB_USERNAME", secret_name = "neo4j-creds" },
                { secret_key = "password", envvar_name = "GRAPH_DB_PASSWORD", secret_name = "neo4j-creds" },
                { secret_key = "access-key", envvar_name = "MINIO_USERNAME", secret_name = "minio-creds-secret" },
                { secret_key = "secret-key", envvar_name = "MINIO_PASSWORD", secret_name = "minio-creds-secret" },
                { secret_key = "username", envvar_name = "ARANGO_DB_USERNAME", secret_name = "arango-db-creds-secret" },
                { secret_key = "password", envvar_name = "ARANGO_DB_PASSWORD", secret_name = "arango-db-creds-secret" }
              ]
              recipe_startup_probe_params = {
                port              = 8000
                endpoint_path     = "/health/ready"
                period_seconds    = 10
                timeout_seconds   = 1
                failure_threshold = 360
              }
              recipe_use_shared_node_pool = true
              recipe_liveness_probe_params = {
                port              = 8000
                endpoint_path     = "/health/live"
                period_seconds    = 10
                timeout_seconds   = 1
                failure_threshold = 3
              }
              recipe_readiness_probe_params = {
                port                  = 8000
                endpoint_path         = "/health/ready"
                period_seconds        = 5
                timeout_seconds       = 1
                failure_threshold     = 3
                initial_delay_seconds = 5
              }
              recipe_shared_memory_volume_size_limit_in_mb = 16384
            }
          )
        }
        ],
        local.vss_postgres_recipe,
        local.vss_download_service_recipe,
        local.vss_oracle_ux_recipes,
        local.auth_service_recipe
      )
    }
  })

  _vss_small_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat([
        {
          name = "elasticsearch"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "elasticsearch-standalone"
            deployment_name                       = "elasticsearch-deployment-group"
            recipe_mode                           = "service"
            recipe_node_shape                     = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape
            recipe_node_pool_size                 = 1
            recipe_use_shared_node_pool           = true
            recipe_replica_count                  = 1
            recipe_image_uri                      = "docker.io/elasticsearch:9.1.2"
            recipe_container_env = [
              { key = "discovery.type", value = "single-node" },
              { key = "xpack.security.enabled", value = "false" },
              { key = "ES_JAVA_OPTS", value = "-Xms6g -Xmx6g" }
            ]
            recipe_container_port = "9200"
            recipe_host_port      = "9200"
            recipe_additional_ingress_ports = [
              { port_name = "transport", port = 9300, path = "/" }
            ]
          }
          exports = ["internal_dns_name"]
        },
        {
          name = "neo4j"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            deployment_name                       = "neo4j-deployment-group"
            recipe_mode                           = "service"
            recipe_image_uri                      = "docker.io/neo4j:5.26.4"
            recipe_replica_count                  = 1
            recipe_node_shape                     = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool           = true
            recipe_container_port                 = "7687"
            recipe_host_port                      = "7687"
            recipe_additional_ingress_ports = [
              { port_name = "http", port = 7474, path = "/" }
            ]
            recipe_container_command = ["bash", "/opt/scripts/start.sh"]
            recipe_configmaps = [
              {
                name           = "configs"
                mount_location = "/opt/configs"
                default_mode   = 420
                data = {
                  "config.yaml" = "SampleConfig:\n  sampleValue: 0\n"
                }
              },
              {
                name           = "scripts"
                mount_location = "/opt/scripts"
                default_mode   = 493
                data = {
                  "script.sh" = "#The scripts can be used as commands in the Initcontainers or as container commands.\n#Size of script file can not exceed 1 MiB\n"
                  "start.sh"  = "#!/bin/bash\nexport NEO4J_AUTH=\"$${DB_USERNAME}/$${DB_PASSWORD}\"\nexport NEO4JLABS_PLUGINS='[\"apoc\"]'\n\ntini -g -- /startup/docker-entrypoint.sh neo4j\n"
                }
              },
              {
                name           = "workload"
                mount_location = "/opt/workload-config"
                default_mode   = 420
                data = {
                  ".placeholder" = ""
                }
              }
            ]
            recipe_environment_secrets = [
              { envvar_name = "DB_USERNAME", secret_name = "neo4j-creds", secret_key = "username" },
              { envvar_name = "DB_PASSWORD", secret_name = "neo4j-creds", secret_key = "password" }
            ]
            recipe_startup_probe_params = {
              failure_threshold = 30
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
            }
            recipe_liveness_probe_params = {
              failure_threshold = 3
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
            }
            recipe_readiness_probe_params = {
              failure_threshold     = 3
              port                  = 7687
              scheme                = "TCP"
              initial_delay_seconds = 5
              period_seconds        = 5
              timeout_seconds       = 1
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["elasticsearch"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "embedding"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nemo-embedding-nim"
            deployment_name                       = "nemo-embedding-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 1
            recipe_image_uri                      = "nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0"
            recipe_container_secret_name          = "ngc-secret"
            recipe_container_port                 = "8000"
            recipe_host_port                      = "8000"
            recipe_storage_group_id               = 1000
            recipe_container_env = [
              { key = "NIM_TRT_ENGINE_HOST_CODE_ALLOWED", value = "1" },
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nemo-embed-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
            }
            recipe_liveness_probe_params = {
              endpoint_path         = "/v1/health/ready"
              port                  = 8000
              scheme                = "HTTP"
              initial_delay_seconds = 10
              period_seconds        = 30
              failure_threshold     = 3
              timeout_seconds       = 20
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["neo4j"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "rerank"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nemo-rerank-nim"
            deployment_name                       = "nemo-rerank-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 1
            recipe_image_uri                      = "nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0"
            recipe_container_secret_name          = "ngc-secret"
            recipe_container_port                 = "8000"
            recipe_host_port                      = "8000"
            recipe_storage_group_id               = 1000
            recipe_container_env = [
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nemo-rerank-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
            }
            recipe_liveness_probe_params = {
              endpoint_path         = "/v1/health/ready"
              port                  = 8000
              scheme                = "HTTP"
              initial_delay_seconds = 10
              period_seconds        = 10
              failure_threshold     = 100
              timeout_seconds       = 20
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["embedding"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "nim-llm"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nim-llm-llama3-8b"
            deployment_name                       = "nim-llm-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_node_pool_size                 = 1
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 4
            recipe_image_uri                      = "nvcr.io/nim/meta/llama-3.1-8b-instruct:1.13.1"
            recipe_container_env = [
              { key = "NIM_CACHE_PATH", value = "/model-store" },
              { key = "OUTLINES_CACHE_DIR", value = "/tmp/outlines" },
              { key = "NIM_SERVER_PORT", value = "8000" },
              { key = "NIM_JSONL_LOGGING", value = "1" },
              { key = "NIM_LOG_LEVEL", value = "INFO" },
              { key = "NIM_MAX_MODEL_LEN", value = "32768" },
              { key = "TRTLLM_KVCACHE_FREE_GPU_MEM_FRACTION", value = "0.7" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            recipe_container_port                        = "8000"
            recipe_host_port                             = "8000"
            recipe_container_secret_name                 = "ngc-secret"
            recipe_shared_memory_volume_size_limit_in_mb = 65536
            recipe_storage_group_id                      = 1000
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nim-model-store", mount_location = "/model-store", volume_size_in_gbs = 1000 }
              ]
            }
            recipe_liveness_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/live"
              initial_delay_seconds = 15
              period_seconds        = 10
              failure_threshold     = 3
              timeout_seconds       = 1
            }
            recipe_readiness_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/ready"
              initial_delay_seconds = 15
              period_seconds        = 10
              failure_threshold     = 3
              timeout_seconds       = 1
            }
            recipe_startup_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/ready"
              initial_delay_seconds = 120
              period_seconds        = 30
              failure_threshold     = 360
              timeout_seconds       = 10
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["rerank"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "vss"
          recipe = merge(
            {
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              deployment_name                       = "vss-deployment-group"
              recipe_mode                           = "service"
              recipe_image_uri                      = "nvcr.io/nvidia/blueprint/vss-engine:2.4.0"
              recipe_container_secret_name          = "ngc-secret"
              recipe_replica_count                  = 1
              recipe_node_shape                     = local.starter_pack_config.worker_node_shape
              recipe_use_shared_node_pool           = true
              recipe_nvidia_gpu_count               = 2
              recipe_storage_group_id               = 1000
              recipe_container_port                 = "9000"
              recipe_host_port                      = "9000"
              recipe_additional_ingress_ports = [
                { port_name = "api", port = 8000, path = "/" }
              ]
              recipe_container_command                     = ["bash", "/opt/scripts/start.sh"]
              recipe_shared_memory_volume_size_limit_in_mb = 16384

              pvcs = {
                retain_after_undeploy = false
                volumes = [
                  { name = "vss-ngc-model-cache", mount_location = "/tmp/via-ngc-model-cache", volume_size_in_gbs = 1000 }
                ]
              }

              input_file_system = local.deploy_app_vss ? [
                {
                  file_system_ocid   = oci_file_storage_file_system.vss_fss[0].id
                  mount_target_ocid  = oci_file_storage_mount_target.vss_mount_target[0].id
                  mount_location     = "/mnt/fss"
                  volume_size_in_gbs = 1000
                }
              ] : []

              recipe_configmaps = [
                {
                  name           = "scripts"
                  mount_location = "/opt/scripts"
                  default_mode   = 493
                  data = {
                    "start.sh" = "#!/bin/bash\nset -e\n\n# Pre-create the shared FSS cache dir that vss-download-service (uid 1001)\n# writes into. vss runs with recipe_storage_group_id=1000 so it has write\n# access to /mnt/fss; chmod 0777 lets the downloader's uid use the same\n# dir without remounting or shifting gids.\nmkdir -p /mnt/fss/cache\nchmod 0777 /mnt/fss/cache\n\n# Check Riva specific environment variables and set them if not set.\nif [ -z \"$${RIVA_ASR_SERVER_URI}\" ]; then\n    export RIVA_ASR_SERVER_URI=\"riva-service\"\n    echo \"RIVA_ASR_SERVER_URI was not set. Using default value: $RIVA_ASR_SERVER_URI\"\nfi\n\nif [ -z \"$${RIVA_ASR_GRPC_PORT}\" ]; then\n    export RIVA_ASR_GRPC_PORT=\"50051\"\n    echo \"RIVA_ASR_GRPC_PORT was not set. Using default value: $RIVA_ASR_GRPC_PORT\"\nfi\n\nif [ -z \"$${RIVA_ASR_HTTP_PORT}\" ]; then\n    export RIVA_ASR_HTTP_PORT=\"9000\"\n    echo \"RIVA_ASR_HTTP_PORT was not set. Using default value: $RIVA_ASR_HTTP_PORT\"\nfi\n\nif [ -z \"$${ENABLE_RIVA_SERVER_READINESS_CHECK}\" ]; then\n    export ENABLE_RIVA_SERVER_READINESS_CHECK=\"false\"\n    echo \"ENABLE_RIVA_SERVER_READINESS_CHECK was not set. Using default value: $ENABLE_RIVA_SERVER_READINESS_CHECK\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_IS_NIM}\" ]; then\n    export RIVA_ASR_SERVER_IS_NIM=\"true\"\n    echo \"RIVA_ASR_SERVER_IS_NIM was not set. Using default value: $RIVA_ASR_SERVER_IS_NIM\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_USE_SSL}\" ]; then\n    export RIVA_ASR_SERVER_USE_SSL=\"false\"\n    echo \"RIVA_ASR_SERVER_USE_SSL was not set. Using default value: $RIVA_ASR_SERVER_USE_SSL\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_API_KEY}\" ]; then\n    export RIVA_ASR_SERVER_API_KEY=\"\"\n    echo \"RIVA_ASR_SERVER_API_KEY was not set. Using default value: $RIVA_ASR_SERVER_API_KEY\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_FUNC_ID}\" ]; then\n    export RIVA_ASR_SERVER_FUNC_ID=\"\"\n    echo \"RIVA_ASR_SERVER_FUNC_ID was not set. Using default value: $RIVA_ASR_SERVER_FUNC_ID\"\nfi\n\nif [ -z \"$${INSTALL_PROPRIETARY_CODECS}\" ]; then\n    export INSTALL_PROPRIETARY_CODECS=\"false\"\n    echo \"INSTALL_PROPRIETARY_CODECS was not set. Using default value: $INSTALL_PROPRIETARY_CODECS\"\nfi\n\n# Check and set environment variables with default values if not set\nif [ -z \"$${OPENAI_API_KEY_NAME}\" ]; then\n    export OPENAI_API_KEY_NAME=\"openai-api-key\"\n    echo \"OPENAI_API_KEY_NAME was not set. Using default value: $OPENAI_API_KEY_NAME\"\nelse\n    echo \"OPENAI_API_KEY_NAME is already set to: $OPENAI_API_KEY_NAME\"\nfi\n\nif [ -z \"$${NVIDIA_API_KEY_NAME}\" ]; then\n    export NVIDIA_API_KEY_NAME=\"nvidia-api-key\"\n    echo \"NVIDIA_API_KEY_NAME was not set. Using default value: $NVIDIA_API_KEY_NAME\"\nelse\n    echo \"NVIDIA_API_KEY_NAME is already set to: $NVIDIA_API_KEY_NAME\"\nfi\n\nif [ -z \"$${NGC_API_KEY_NAME}\" ]; then\n    export NGC_API_KEY_NAME=\"ngc-api-key\"\n    echo \"NGC_API_KEY_NAME was not set. Using default value: $NGC_API_KEY_NAME\"\nelse\n    echo \"NGC_API_KEY_NAME is already set to: $NGC_API_KEY_NAME\"\nfi\n\n# NVCF will mount secrets to /var/secrets/secrets.json, check and update accordingly\nif [ -f \"/var/secrets/secrets.json\" ]; then\n    echo \"Contents of /var/secrets/secrets.json:\"\n    jq -r 'keys[]' /var/secrets/secrets.json\n\n    if grep -q \"$OPENAI_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$OPENAI_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$OPENAI_API_KEY\n        export OPENAI_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$OPENAI_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$OPENAI_API_KEY\" ]; then\n            echo \"OPENAI_API_KEY updated from secrets.json\"\n        else\n            echo \"OPENAI_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$OPENAI_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\n\n    if grep -q \"$NVIDIA_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$NVIDIA_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$NVIDIA_API_KEY\n        export NVIDIA_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$NVIDIA_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$NVIDIA_API_KEY\" ]; then\n            echo \"NVIDIA_API_KEY updated from secrets.json\"\n        else\n            echo \"NVIDIA_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$NVIDIA_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\n\n    if grep -q \"$NGC_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$NGC_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$NGC_API_KEY\n        export NGC_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$NGC_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$NGC_API_KEY\" ]; then\n            echo \"NGC_API_KEY updated from secrets.json\"\n        else\n            echo \"NGC_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$NGC_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\nelse\n    echo \"/var/secrets/secrets.json file does not exist\"\nfi\n\n# Overwrite default CA RAG in container:\nmkdir -p /tmp/via\ncp /opt/configs/guardrails_config.yaml /opt/nvidia/via/guardrails_config/config.yml\ncp /opt/configs/ca_rag_config.yaml /tmp/via/default_config.yaml\nexport CA_RAG_CONFIG=\"/tmp/via/default_config.yaml\"\ncp /opt/configs/cv_pipeline_tracker_config.yml /tmp/default_tracker_config.yml\nexport CV_PIPELINE_TRACKER_CONFIG=\"/tmp/default_tracker_config.yml\"\n\nmkdir -p /tmp/huggingface-via\nexport HF_HOME=/tmp/huggingface-via\n\nexport NGC_MODEL_CACHE=/tmp/via-ngc-model-cache\n\nexport CUPY_CACHE_DIR=/tmp/cupy_cache\n\nmkdir -p /tmp/via/triton-cache\nexport TRITON_CACHE_DIR=/tmp/via/triton-cache\n\ncd /tmp/via\nln -s /opt/nvidia/via/via-engine via-engine\nln -s /opt/nvidia/via/config config\n\nif [ -z \"$${LLM_MODEL}\" ]; then\n    export LLM_MODEL=\"meta/llama-3.1-70b-instruct\"\n    echo \"LLM_MODEL was not set. Using default value: $LLM_MODEL\"\nfi\n\nCONFIG_FILE=\"/tmp/via/default_config.yaml\"\n\ncontent=$(cat \"$CONFIG_FILE\")\n\nwhile IFS= read -r var; do\n    [[ -z \"$var\" ]] && continue\n    [[ \"$var\" == egress.* ]] && continue\n    \n    if [[ -n \"$${!var:-}\" ]]; then\n        value=\"$${!var}\"\n        escaped_value=$(printf '%s\\n' \"$value\" | sed -e 's/[\\/&]/\\\\&/g')\n\n        if echo \"$content\" | grep -q \"port:.*\\$${$var}\"; then\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/\\\"$escaped_value\\\"/g\")\n        else\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/$escaped_value/g\")\n        fi\n    else\n        echo \"Warning: Environment variable '$var' is not set\" >&2\n    fi\ndone < <(grep -oE '\\$\\{[^}]+\\}' \"$CONFIG_FILE\" | sed 's/\\$${\\([^}]*\\)}/\\1/' | sort -u)\n\necho \"$content\" > \"$CONFIG_FILE\"\n\n/opt/nvidia/via/start_via.sh\n"
                  }
                },
                {
                  name           = "configs"
                  mount_location = "/opt/configs"
                  default_mode   = 420
                  data = {
                    "guardrails_config.yaml"         = "instructions:\n- content: |\n    Below is a conversation between a bot and a user about the image or video.\n    The bot is factual and concise. If the bot does not know the answer to a\n    question, it truthfully says it does not know.\n  type: general\nmodels:\n- engine: nim\n  model: $${LLM_MODEL}\n  parameters:\n    base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n  type: main\n- engine: nim\n  model: nvidia/llama-3.2-nv-embedqa-1b-v2\n  parameters:\n    base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n  type: embeddings\nsample_conversation: |\n  user \"Hello there!\"\n    express greeting\n  bot express greeting\n    \"Hello! How can I assist you today?\"\n  user \"What can you do for me?\"\n    ask about capabilities\n  bot respond about capabilities\n    \"I am an AI assistant here to answer questions about the image or video.\"\n"
                    "cv_pipeline_tracker_config.yml" = "BaseConfig:\n  minDetectorConfidence: 0.1630084739998828\nDataAssociator:\n  associationMatcherType: 1\n  checkClassMatch: 1\n  dataAssociatorType: 0\n  matchingScoreWeight4Iou: 0.46547889321000563\n  matchingScoreWeight4SizeSimilarity: 0.4463422634549605\n  matchingScoreWeight4VisualSimilarity: 0.7092410997389017\n  minMatchingScore4Iou: 0.29413058985254187\n  minMatchingScore4Overall: 0.06843005365443096\n  minMatchingScore4SizeSimilarity: 0.2929323932012989\n  minMatchingScore4TentativeIou: 0.45510391462097216\n  minMatchingScore4VisualSimilarity: 0.42453250143328114\n  tentativeDetectorConfidence: 0.1721247313806944\nReID:\n  addFeatureNormalization: 1\n  batchSize: 100\n  colorFormat: 0\n  inferDims: [3, 256, 128]\n  inputOrder: 0\n  keepAspc: 1\n  modelEngineFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx.engine\n  netScaleFactor: 0.01735207\n  networkMode: 1\n  offsets: [123.675, 116.28, 103.53]\n  onnxFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx\n  outputReidTensor: 0\n  reidFeatureSize: 256\n  reidHistorySize: 100\n  reidType: 2\n  tltModelKey: nvidia_tao\n  useVPICropScaler: 1\n  workspaceSize: 1000\nStateEstimator:\n  measurementNoiseVar4Detector: 100.00000584166246\n  measurementNoiseVar4Tracker: 4988.392688178733\n  processNoiseVar4Loc: 6533.099736052837\n  processNoiseVar4Size: 6415.121729390737\n  processNoiseVar4Vel: 2798.795011988113\n  stateEstimatorType: 1\nTargetManagement:\n  earlyTerminationAge: 1\n  enableBboxUnClipping: 0\n  maxShadowTrackingAge: 39\n  maxTargetsPerStream: 150\n  minIouDiff4NewTarget: 0.8176422840795657\n  minTrackerConfidence: 0.19878939278068558\n  preserveStreamUpdateOrder: 0\n  probationAge: 6\nTrajectoryManagement:\n  enableReAssoc: 1\n  matchingScoreWeight4ReidSimilarity: 0.7200658660519842\n  matchingScoreWeight4TrackletSimilarity: 0.23836654600118312\n  maxAngle4TrackletMatching: 142\n  maxTrackletMatchingTimeSearchRange: 20\n  minBboxSizeSimilarity4TrackletMatching: 0.18214484831006444\n  minMatchingScore4Overall: 0.23583585666333318\n  minMatchingScore4ReidSimilarity: 0.24582563724796622\n  minSpeedSimilarity4TrackletMatching: 0.0023058182326161298\n  minTrackletMatchingScore: 0.09979720773093673\n  minTrajectoryLength4Projection: 37\n  prepLength4TrajectoryProjection: 50\n  reidExtractionInterval: 19\n  trackletSpacialSearchRegionScale: 0.2598\n  trajectoryProjectionLength: 43\n  trajectoryProjectionMeasurementNoiseScale: 100\n  trajectoryProjectionProcessNoiseScale: 0.01\n  useUniqueID: 0\nVisualTracker:\n  featureFocusOffsetFactor_y: -0.15647586556568632\n  featureImgSizeLevel: 3\n  filterChannelWeightsLr: 0.07701879646606641\n  filterLr: 0.13560657062953396\n  gaussianSigma: 1.497826153095461\n  useColorNames: 1\n  useHog: 1\n  visualTrackerType: 2\n"
                    "ca_rag_config.yaml"             = "context_manager:\n  functions:\n  - summarization\n  - ingestion_function\n  - retriever_function\n  - notification\nfunctions:\n  ingestion_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_ingestion\n  notification:\n    params:\n      events: []\n    tools:\n      llm: notification_llm\n      notification_tool: notification_tool\n    type: notification\n  retriever_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_retrieval\n  summarization:\n    params:\n      batch_max_concurrency: 20\n      batch_size: 5\n      prompts:\n        caption: Write a concise and clear dense caption for the provided warehouse video, focusing on irregular or hazardous events such as boxes falling, workers not wearing PPE, workers falling, workers taking photographs, workers chitchatting, forklift stuck, etc. Start and end each sentence with a time stamp.\n        caption_summarization: 'You should summarize the following events of a warehouse in the format start_time:end_time:caption. For start_time and end_time use . to seperate seconds, minutes, hours. If during a time segment only regular activities happen, then ignore them, else note any irregular activities in detail. The output should be bullet points in the format start_time:end_time: detailed_event_description. Don''t return anything else except the bullet points.'\n        summary_aggregation: 'You are a warehouse monitoring system. Given the caption in the form start_time:end_time: caption, Aggregate the following captions in the format start_time:end_time:event_description. If the event_description is the same as another event_description, aggregate the captions in the format start_time1:end_time1,...,start_timek:end_timek:event_description. If any two adjacent end_time1 and start_time2 is within a few tenths of a second, merge the captions in the format start_time1:end_time2. The output should only contain bullet points. Cluster the output into Unsafe Behavior, Operational Inefficiencies, Potential Equipment Damage and Unauthorized Personnel'\n    tools:\n      db: graph_db\n      llm: summarization_llm\n    type: batch_summarization\ntools:\n  chat_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  graph_db:\n    params:\n      host: $${GRAPH_DB_HOST}\n      password: $${GRAPH_DB_PASSWORD}\n      port: $${GRAPH_DB_PORT}\n      username: $${GRAPH_DB_USERNAME}\n    tools:\n      embedding: nvidia_embedding\n    type: neo4j\n  notification_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  notification_tool:\n    params:\n      endpoint: http://127.0.0.1:60000/via-alert-callback\n    type: alert_sse_notifier\n  nvidia_embedding:\n    params:\n      base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n      model: nvidia/llama-3.2-nv-embedqa-1b-v2\n    type: embedding\n  nvidia_reranker:\n    params:\n      base_url: http://$${RERANK_HOST}:$${RERANK_PORT}/v1\n      model: nvidia/llama-3.2-nv-rerankqa-1b-v2\n    type: reranker\n  summarization_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  vector_db:\n    params:\n      host: $${MILVUS_DB_HOST}\n      port: $${MILVUS_DB_PORT}\n    tools:\n      embedding: nvidia_embedding\n    type: milvus\n"
                  }
                }
              ]

              recipe_container_env = [
                { key = "VLM_MODEL_TO_USE", value = "cosmos-reason1" },
                { key = "MODEL_PATH", value = "ngc:nim/nvidia/cosmos-reason1-7b:1.1-fp8-dynamic" },
                { key = "DISABLE_GUARDRAILS", value = "true" },
                { key = "NVIDIA_API_KEY_NAME", value = "VSS_NVIDIA_API_KEY" },
                { key = "NGC_API_KEY_NAME", value = "VSS_NGC_API_KEY" },
                { key = "TRT_LLM_MODE", value = "int4_awq" },
                { key = "ENABLE_AUDIO", value = "false" },
                { key = "LLM_MODEL", value = "meta-llama/llama-3.1-8b-instruct" },
                { key = "LLM_HOST", value = "$${nim-llm.internal_dns_name}" },
                { key = "LLM_PORT", value = "8000" },
                { key = "EMBED_HOST", value = "$${embedding.internal_dns_name}" },
                { key = "EMBED_PORT", value = "8000" },
                { key = "RERANK_HOST", value = "$${rerank.internal_dns_name}" },
                { key = "RERANK_PORT", value = "8000" },
                { key = "RIVA_ASR_SERVER_URI", value = "riva-service" },
                { key = "RIVA_ASR_GRPC_PORT", value = "50051" },
                { key = "RIVA_ASR_HTTP_PORT", value = "9000" },
                { key = "ENABLE_RIVA_SERVER_READINESS_CHECK", value = "false" },
                { key = "RIVA_ASR_SERVER_IS_NIM", value = "false" },
                { key = "RIVA_ASR_SERVER_USE_SSL", value = "false" },
                { key = "INSTALL_PROPRIETARY_CODECS", value = "false" },
                { key = "VLLM_GPU_MEMORY_UTILIZATION", value = "0.4" },
                { key = "FRONTEND_PORT", value = "9000" },
                { key = "BACKEND_PORT", value = "8000" },
                { key = "GRAPH_DB_HOST", value = "$${neo4j.internal_dns_name}" },
                { key = "GRAPH_DB_PORT", value = "7687" },
                { key = "MILVUS_DB_HOST", value = "my-release-milvus" },
                { key = "MILVUS_DB_PORT", value = "19530" },
                { key = "MINIO_HOST", value = "my-release-minio" },
                { key = "MINIO_PORT", value = "9000" },
                { key = "MINIO_WEBUI_PORT", value = "9001" },
                { key = "ARANGO_DB_HOST", value = "arango-db-arango-db-deployment-arango-db-service" },
                { key = "ARANGO_DB_PORT", value = "8529" },
                { key = "APP_VECTORSTORE_URL", value = "http://my-release-milvus:19530" },
                { key = "ES_HOST", value = "$${elasticsearch.internal_dns_name}" },
                { key = "ES_PORT", value = "9200" },
                { key = "ES_TRANSPORT_PORT", value = "9300" },
                { key = "NEO4J_AUTH", value = "neo4j/password" }
              ]

              recipe_environment_secrets = [
                { envvar_name = "NVIDIA_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" },
                { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" },
                { envvar_name = "GRAPH_DB_USERNAME", secret_name = "neo4j-creds", secret_key = "username" },
                { envvar_name = "GRAPH_DB_PASSWORD", secret_name = "neo4j-creds", secret_key = "password" },
                { envvar_name = "MINIO_USERNAME", secret_name = "minio-creds-secret", secret_key = "access-key" },
                { envvar_name = "MINIO_PASSWORD", secret_name = "minio-creds-secret", secret_key = "secret-key" },
                { envvar_name = "ARANGO_DB_USERNAME", secret_name = "arango-db-creds-secret", secret_key = "username" },
                { envvar_name = "ARANGO_DB_PASSWORD", secret_name = "arango-db-creds-secret", secret_key = "password" }
              ]

              recipe_liveness_probe_params = {
                failure_threshold = 3
                endpoint_path     = "/health/live"
                port              = 8000
                period_seconds    = 10
                timeout_seconds   = 1
              }

              recipe_startup_probe_params = {
                failure_threshold = 180
                endpoint_path     = "/health/ready"
                port              = 8000
                period_seconds    = 10
                timeout_seconds   = 1
              }

              recipe_readiness_probe_params = {
                failure_threshold     = 3
                endpoint_path         = "/health/ready"
                port                  = 8000
                initial_delay_seconds = 5
                period_seconds        = 5
                timeout_seconds       = 1
              }
            }
          )
          depends_on = concat([
            "elasticsearch",
            "neo4j",
            "embedding",
            "rerank",
            "nim-llm"
          ], var.enable_auth_service ? ["auth-service"] : [])
        }
        ],
        local.vss_postgres_recipe,
        local.vss_download_service_recipe,
        local.vss_oracle_ux_recipes,
        local.auth_service_recipe
      )
    }
  })

  _vss_medium_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat([
        {
          name = "elasticsearch"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "elasticsearch-standalone"
            deployment_name                       = "elasticsearch-deployment-group"
            recipe_mode                           = "service"
            recipe_node_shape                     = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape
            recipe_node_pool_size                 = 1
            recipe_use_shared_node_pool           = true
            recipe_replica_count                  = 1
            recipe_image_uri                      = "docker.io/elasticsearch:9.1.2"
            recipe_container_env = [
              { key = "discovery.type", value = "single-node" },
              { key = "xpack.security.enabled", value = "false" },
              { key = "ES_JAVA_OPTS", value = "-Xms6g -Xmx6g" }
            ]
            recipe_container_port = "9200"
            recipe_host_port      = "9200"
            recipe_additional_ingress_ports = [
              { port_name = "transport", port = 9300, path = "/" }
            ]
          }
          exports = ["internal_dns_name"]
        },
        {
          name = "neo4j"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            deployment_name                       = "neo4j-deployment-group"
            recipe_mode                           = "service"
            recipe_image_uri                      = "docker.io/neo4j:5.26.4"
            recipe_replica_count                  = 1
            recipe_node_shape                     = local.starter_pack_config.control_plane_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool           = true
            recipe_container_port                 = "7687"
            recipe_host_port                      = "7687"
            recipe_additional_ingress_ports = [
              { port_name = "http", port = 7474, path = "/" }
            ]
            recipe_container_command = ["bash", "/opt/scripts/start.sh"]
            recipe_configmaps = [
              {
                name           = "configs"
                mount_location = "/opt/configs"
                default_mode   = 420
                data = {
                  "config.yaml" = "SampleConfig:\n  sampleValue: 0\n"
                }
              },
              {
                name           = "scripts"
                mount_location = "/opt/scripts"
                default_mode   = 493
                data = {
                  "script.sh" = "#The scripts can be used as commands in the Initcontainers or as container commands.\n#Size of script file can not exceed 1 MiB\n"
                  "start.sh"  = "#!/bin/bash\nexport NEO4J_AUTH=\"$${DB_USERNAME}/$${DB_PASSWORD}\"\nexport NEO4JLABS_PLUGINS='[\"apoc\"]'\n\ntini -g -- /startup/docker-entrypoint.sh neo4j\n"
                }
              },
              {
                name           = "workload"
                mount_location = "/opt/workload-config"
                default_mode   = 420
                data = {
                  ".placeholder" = ""
                }
              }
            ]
            recipe_environment_secrets = [
              { envvar_name = "DB_USERNAME", secret_name = "neo4j-creds", secret_key = "username" },
              { envvar_name = "DB_PASSWORD", secret_name = "neo4j-creds", secret_key = "password" }
            ]
            recipe_startup_probe_params = {
              failure_threshold = 30
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
            }
            recipe_liveness_probe_params = {
              failure_threshold = 3
              port              = 7687
              scheme            = "TCP"
              period_seconds    = 10
              timeout_seconds   = 1
            }
            recipe_readiness_probe_params = {
              failure_threshold     = 3
              port                  = 7687
              scheme                = "TCP"
              initial_delay_seconds = 5
              period_seconds        = 5
              timeout_seconds       = 1
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["elasticsearch"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "embedding"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nemo-embedding-nim"
            deployment_name                       = "nemo-embedding-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 1
            recipe_image_uri                      = "nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0"
            recipe_container_secret_name          = "ngc-secret"
            recipe_container_port                 = "8000"
            recipe_host_port                      = "8000"
            recipe_storage_group_id               = 1000
            recipe_container_env = [
              { key = "NIM_TRT_ENGINE_HOST_CODE_ALLOWED", value = "1" },
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nemo-embed-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
            }
            recipe_liveness_probe_params = {
              endpoint_path         = "/v1/health/ready"
              port                  = 8000
              scheme                = "HTTP"
              initial_delay_seconds = 10
              period_seconds        = 30
              failure_threshold     = 3
              timeout_seconds       = 20
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["nim-llm"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "rerank"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nemo-rerank-nim"
            deployment_name                       = "nemo-rerank-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 1
            recipe_image_uri                      = "nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0"
            recipe_container_secret_name          = "ngc-secret"
            recipe_container_port                 = "8000"
            recipe_host_port                      = "8000"
            recipe_storage_group_id               = 1000
            recipe_container_env = [
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nemo-rerank-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 50 }
              ]
            }
            recipe_liveness_probe_params = {
              endpoint_path         = "/v1/health/ready"
              port                  = 8000
              scheme                = "HTTP"
              initial_delay_seconds = 10
              period_seconds        = 10
              failure_threshold     = 100
              timeout_seconds       = 20
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["embedding"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "riva"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "riva-nim"
            deployment_name                       = "riva-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 1
            recipe_image_uri                      = "nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us:2.0.0"
            recipe_container_secret_name          = "ngc-secret"
            recipe_container_port                 = "9000"
            recipe_host_port                      = "9000"
            recipe_storage_group_id               = 1000
            recipe_container_env = [
              { key = "NIM_HTTP_API_PORT", value = "9000" },
              { key = "NIM_GRPC_API_PORT", value = "50051" },
              { key = "NIM_CACHE_PATH", value = "/mnt/nim-cache" },
              { key = "NIM_TAGS_SELECTOR", value = "name=parakeet-0-6b-ctc-riva-en-us,mode=all" }
            ]
            recipe_additional_ingress_ports = [
              { port_name = "grpc", port = 50051, path = "/" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "riva-cache", mount_location = "/mnt/nim-cache", volume_size_in_gbs = 100 }
              ]
            }
            recipe_liveness_probe_params = {
              endpoint_path         = "/v1/health/ready"
              port                  = 9000
              scheme                = "HTTP"
              initial_delay_seconds = 10
              period_seconds        = 30
              failure_threshold     = 3
              timeout_seconds       = 20
            }
          }
          exports    = ["internal_dns_name"],
          depends_on = concat(["rerank"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "nim-llm"
          recipe = {
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_id                             = "nim-llm-llama3-8b"
            deployment_name                       = "nim-llm-deployment-group"
            recipe_mode                           = "service"
            recipe_use_shared_node_pool           = true
            recipe_node_shape                     = local.starter_pack_config.worker_node_shape
            recipe_node_pool_size                 = 1
            recipe_replica_count                  = 1
            recipe_nvidia_gpu_count               = 3
            recipe_image_uri                      = "nvcr.io/nim/meta/llama-3.1-8b-instruct:1.13.1"
            recipe_container_env = [
              { key = "NIM_CACHE_PATH", value = "/model-store" },
              { key = "OUTLINES_CACHE_DIR", value = "/tmp/outlines" },
              { key = "NIM_SERVER_PORT", value = "8000" },
              { key = "NIM_JSONL_LOGGING", value = "1" },
              { key = "NIM_LOG_LEVEL", value = "INFO" },
              { key = "NIM_MAX_MODEL_LEN", value = "32768" },
              { key = "TRTLLM_KVCACHE_FREE_GPU_MEM_FRACTION", value = "0.7" }
            ]
            recipe_environment_secrets = [
              { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" }
            ]
            recipe_container_port                        = "8000"
            recipe_host_port                             = "8000"
            recipe_container_secret_name                 = "ngc-secret"
            recipe_shared_memory_volume_size_limit_in_mb = 65536
            recipe_storage_group_id                      = 1000
            pvcs = {
              retain_after_undeploy = false
              volumes = [
                { name = "nim-model-store", mount_location = "/model-store", volume_size_in_gbs = 1000 }
              ]
            }
            recipe_liveness_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/live"
              initial_delay_seconds = 15
              period_seconds        = 10
              failure_threshold     = 3
              timeout_seconds       = 1
            }
            recipe_readiness_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/ready"
              initial_delay_seconds = 15
              period_seconds        = 10
              failure_threshold     = 3
              timeout_seconds       = 1
            }
            recipe_startup_probe_params = {
              scheme                = "HTTP"
              port                  = 8000
              endpoint_path         = "/v1/health/ready"
              initial_delay_seconds = 120
              period_seconds        = 30
              failure_threshold     = 360
              timeout_seconds       = 10
            }
          }
          exports    = ["internal_dns_name"]
          depends_on = concat(["neo4j"], var.enable_auth_service ? ["auth-service"] : [])
        },
        {
          name = "vss"
          recipe = merge(
            {
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              deployment_name                       = "vss-deployment-group"
              recipe_mode                           = "service"
              recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/vss-engine:2.4.0-custom"
              recipe_replica_count                  = 1
              recipe_node_shape                     = local.starter_pack_config.worker_node_shape
              recipe_use_shared_node_pool           = true
              recipe_nvidia_gpu_count               = 2
              recipe_storage_group_id               = 1000
              recipe_container_port                 = "9000"
              recipe_host_port                      = "9000"
              recipe_additional_ingress_ports = [
                { port_name = "api", port = 8000, path = "/" }
              ]
              recipe_container_command                     = ["bash", "/opt/scripts/start.sh"]
              recipe_shared_memory_volume_size_limit_in_mb = 16384

              pvcs = {
                retain_after_undeploy = false
                volumes = [
                  { name = "vss-ngc-model-cache", mount_location = "/tmp/via-ngc-model-cache", volume_size_in_gbs = 1000 }
                ]
              }

              input_file_system = local.deploy_app_vss ? [
                {
                  file_system_ocid   = oci_file_storage_file_system.vss_fss[0].id
                  mount_target_ocid  = oci_file_storage_mount_target.vss_mount_target[0].id
                  mount_location     = "/mnt/fss"
                  volume_size_in_gbs = 1000
                }
              ] : []

              recipe_configmaps = [
                {
                  name           = "scripts"
                  mount_location = "/opt/scripts"
                  default_mode   = 493
                  data = {
                    "start.sh" = "#!/bin/bash\nset -e\n\n# Pre-create the shared FSS cache dir that vss-download-service (uid 1001)\n# writes into. vss runs with recipe_storage_group_id=1000 so it has write\n# access to /mnt/fss; chmod 0777 lets the downloader's uid use the same\n# dir without remounting or shifting gids.\nmkdir -p /mnt/fss/cache\nchmod 0777 /mnt/fss/cache\n\n# Check Riva specific environment variables and set them if not set.\nif [ -z \"$${RIVA_ASR_SERVER_URI}\" ]; then\n    export RIVA_ASR_SERVER_URI=\"riva-service\"\n    echo \"RIVA_ASR_SERVER_URI was not set. Using default value: $RIVA_ASR_SERVER_URI\"\nfi\n\nif [ -z \"$${RIVA_ASR_GRPC_PORT}\" ]; then\n    export RIVA_ASR_GRPC_PORT=\"50051\"\n    echo \"RIVA_ASR_GRPC_PORT was not set. Using default value: $RIVA_ASR_GRPC_PORT\"\nfi\n\nif [ -z \"$${RIVA_ASR_HTTP_PORT}\" ]; then\n    export RIVA_ASR_HTTP_PORT=\"9000\"\n    echo \"RIVA_ASR_HTTP_PORT was not set. Using default value: $RIVA_ASR_HTTP_PORT\"\nfi\n\nif [ -z \"$${ENABLE_RIVA_SERVER_READINESS_CHECK}\" ]; then\n    export ENABLE_RIVA_SERVER_READINESS_CHECK=\"false\"\n    echo \"ENABLE_RIVA_SERVER_READINESS_CHECK was not set. Using default value: $ENABLE_RIVA_SERVER_READINESS_CHECK\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_IS_NIM}\" ]; then\n    export RIVA_ASR_SERVER_IS_NIM=\"true\"\n    echo \"RIVA_ASR_SERVER_IS_NIM was not set. Using default value: $RIVA_ASR_SERVER_IS_NIM\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_USE_SSL}\" ]; then\n    export RIVA_ASR_SERVER_USE_SSL=\"false\"\n    echo \"RIVA_ASR_SERVER_USE_SSL was not set. Using default value: $RIVA_ASR_SERVER_USE_SSL\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_API_KEY}\" ]; then\n    export RIVA_ASR_SERVER_API_KEY=\"\"\n    echo \"RIVA_ASR_SERVER_API_KEY was not set. Using default value: $RIVA_ASR_SERVER_API_KEY\"\nfi\n\nif [ -z \"$${RIVA_ASR_SERVER_FUNC_ID}\" ]; then\n    export RIVA_ASR_SERVER_FUNC_ID=\"\"\n    echo \"RIVA_ASR_SERVER_FUNC_ID was not set. Using default value: $RIVA_ASR_SERVER_FUNC_ID\"\nfi\n\nif [ -z \"$${INSTALL_PROPRIETARY_CODECS}\" ]; then\n    export INSTALL_PROPRIETARY_CODECS=\"false\"\n    echo \"INSTALL_PROPRIETARY_CODECS was not set. Using default value: $INSTALL_PROPRIETARY_CODECS\"\nfi\n\n# Check and set environment variables with default values if not set\nif [ -z \"$${OPENAI_API_KEY_NAME}\" ]; then\n    export OPENAI_API_KEY_NAME=\"openai-api-key\"\n    echo \"OPENAI_API_KEY_NAME was not set. Using default value: $OPENAI_API_KEY_NAME\"\nelse\n    echo \"OPENAI_API_KEY_NAME is already set to: $OPENAI_API_KEY_NAME\"\nfi\n\nif [ -z \"$${NVIDIA_API_KEY_NAME}\" ]; then\n    export NVIDIA_API_KEY_NAME=\"nvidia-api-key\"\n    echo \"NVIDIA_API_KEY_NAME was not set. Using default value: $NVIDIA_API_KEY_NAME\"\nelse\n    echo \"NVIDIA_API_KEY_NAME is already set to: $NVIDIA_API_KEY_NAME\"\nfi\n\nif [ -z \"$${NGC_API_KEY_NAME}\" ]; then\n    export NGC_API_KEY_NAME=\"ngc-api-key\"\n    echo \"NGC_API_KEY_NAME was not set. Using default value: $NGC_API_KEY_NAME\"\nelse\n    echo \"NGC_API_KEY_NAME is already set to: $NGC_API_KEY_NAME\"\nfi\n\n# NVCF will mount secrets to /var/secrets/secrets.json, check and update accordingly\nif [ -f \"/var/secrets/secrets.json\" ]; then\n    echo \"Contents of /var/secrets/secrets.json:\"\n    jq -r 'keys[]' /var/secrets/secrets.json\n\n    if grep -q \"$OPENAI_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$OPENAI_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$OPENAI_API_KEY\n        export OPENAI_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$OPENAI_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$OPENAI_API_KEY\" ]; then\n            echo \"OPENAI_API_KEY updated from secrets.json\"\n        else\n            echo \"OPENAI_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$OPENAI_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\n\n    if grep -q \"$NVIDIA_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$NVIDIA_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$NVIDIA_API_KEY\n        export NVIDIA_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$NVIDIA_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$NVIDIA_API_KEY\" ]; then\n            echo \"NVIDIA_API_KEY updated from secrets.json\"\n        else\n            echo \"NVIDIA_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$NVIDIA_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\n\n    if grep -q \"$NGC_API_KEY_NAME\" \"/var/secrets/secrets.json\"; then\n        echo \"$NGC_API_KEY_NAME is present in /var/secrets/secrets.json\"\n        old_key=$NGC_API_KEY\n        export NGC_API_KEY=$(cat \"/var/secrets/secrets.json\" | jq \".[\\\"$NGC_API_KEY_NAME\\\"]\" -r)\n        if [ \"$old_key\" != \"$NGC_API_KEY\" ]; then\n            echo \"NGC_API_KEY updated from secrets.json\"\n        else\n            echo \"NGC_API_KEY remains unchanged from Kubernetes secret\"\n        fi\n    else\n        echo \"$NGC_API_KEY_NAME is not present in /var/secrets/secrets.json\"\n    fi\nelse\n    echo \"/var/secrets/secrets.json file does not exist\"\nfi\n\n# Overwrite default CA RAG in container:\nmkdir -p /tmp/via\ncp /opt/configs/guardrails_config.yaml /opt/nvidia/via/guardrails_config/config.yml\ncp /opt/configs/ca_rag_config.yaml /tmp/via/default_config.yaml\nexport CA_RAG_CONFIG=\"/tmp/via/default_config.yaml\"\ncp /opt/configs/cv_pipeline_tracker_config.yml /tmp/default_tracker_config.yml\nexport CV_PIPELINE_TRACKER_CONFIG=\"/tmp/default_tracker_config.yml\"\n\nmkdir -p /tmp/huggingface-via\nexport HF_HOME=/tmp/huggingface-via\n\nexport NGC_MODEL_CACHE=/tmp/via-ngc-model-cache\n\nexport CUPY_CACHE_DIR=/tmp/cupy_cache\n\nmkdir -p /tmp/via/triton-cache\nexport TRITON_CACHE_DIR=/tmp/via/triton-cache\n\ncd /tmp/via\nln -s /opt/nvidia/via/via-engine via-engine\nln -s /opt/nvidia/via/config config\n\nif [ -z \"$${LLM_MODEL}\" ]; then\n    export LLM_MODEL=\"meta/llama-3.1-70b-instruct\"\n    echo \"LLM_MODEL was not set. Using default value: $LLM_MODEL\"\nfi\n\nCONFIG_FILE=\"/tmp/via/default_config.yaml\"\n\ncontent=$(cat \"$CONFIG_FILE\")\n\nwhile IFS= read -r var; do\n    [[ -z \"$var\" ]] && continue\n    [[ \"$var\" == egress.* ]] && continue\n    \n    if [[ -n \"$${!var:-}\" ]]; then\n        value=\"$${!var}\"\n        escaped_value=$(printf '%s\\n' \"$value\" | sed -e 's/[\\/&]/\\\\&/g')\n\n        if echo \"$content\" | grep -q \"port:.*\\$${$var}\"; then\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/\\\"$escaped_value\\\"/g\")\n        else\n            content=$(echo \"$content\" | sed \"s/\\$${$var}/$escaped_value/g\")\n        fi\n    else\n        echo \"Warning: Environment variable '$var' is not set\" >&2\n    fi\ndone < <(grep -oE '\\$\\{[^}]+\\}' \"$CONFIG_FILE\" | sed 's/\\$${\\([^}]*\\)}/\\1/' | sort -u)\n\necho \"$content\" > \"$CONFIG_FILE\"\n\n/opt/nvidia/via/start_via.sh\n"
                  }
                },
                {
                  name           = "configs"
                  mount_location = "/opt/configs"
                  default_mode   = 420
                  data = {
                    "guardrails_config.yaml"         = "instructions:\n- content: |\n    Below is a conversation between a bot and a user about the image or video.\n    The bot is factual and concise. If the bot does not know the answer to a\n    question, it truthfully says it does not know.\n  type: general\nmodels:\n- engine: nim\n  model: $${LLM_MODEL}\n  parameters:\n    base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n  type: main\n- engine: nim\n  model: nvidia/llama-3.2-nv-embedqa-1b-v2\n  parameters:\n    base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n  type: embeddings\nsample_conversation: |\n  user \"Hello there!\"\n    express greeting\n  bot express greeting\n    \"Hello! How can I assist you today?\"\n  user \"What can you do for me?\"\n    ask about capabilities\n  bot respond about capabilities\n    \"I am an AI assistant here to answer questions about the image or video.\"\n"
                    "cv_pipeline_tracker_config.yml" = "BaseConfig:\n  minDetectorConfidence: 0.1630084739998828\nDataAssociator:\n  associationMatcherType: 1\n  checkClassMatch: 1\n  dataAssociatorType: 0\n  matchingScoreWeight4Iou: 0.46547889321000563\n  matchingScoreWeight4SizeSimilarity: 0.4463422634549605\n  matchingScoreWeight4VisualSimilarity: 0.7092410997389017\n  minMatchingScore4Iou: 0.29413058985254187\n  minMatchingScore4Overall: 0.06843005365443096\n  minMatchingScore4SizeSimilarity: 0.2929323932012989\n  minMatchingScore4TentativeIou: 0.45510391462097216\n  minMatchingScore4VisualSimilarity: 0.42453250143328114\n  tentativeDetectorConfidence: 0.1721247313806944\nReID:\n  addFeatureNormalization: 1\n  batchSize: 100\n  colorFormat: 0\n  inferDims: [3, 256, 128]\n  inputOrder: 0\n  keepAspc: 1\n  modelEngineFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx.engine\n  netScaleFactor: 0.01735207\n  networkMode: 1\n  offsets: [123.675, 116.28, 103.53]\n  onnxFile: /tmp/via/data/models/gdino-sam/resnet50_market1501_aicity156.onnx\n  outputReidTensor: 0\n  reidFeatureSize: 256\n  reidHistorySize: 100\n  reidType: 2\n  tltModelKey: nvidia_tao\n  useVPICropScaler: 1\n  workspaceSize: 1000\nStateEstimator:\n  measurementNoiseVar4Detector: 100.00000584166246\n  measurementNoiseVar4Tracker: 4988.392688178733\n  processNoiseVar4Loc: 6533.099736052837\n  processNoiseVar4Size: 6415.121729390737\n  processNoiseVar4Vel: 2798.795011988113\n  stateEstimatorType: 1\nTargetManagement:\n  earlyTerminationAge: 1\n  enableBboxUnClipping: 0\n  maxShadowTrackingAge: 39\n  maxTargetsPerStream: 150\n  minIouDiff4NewTarget: 0.8176422840795657\n  minTrackerConfidence: 0.19878939278068558\n  preserveStreamUpdateOrder: 0\n  probationAge: 6\nTrajectoryManagement:\n  enableReAssoc: 1\n  matchingScoreWeight4ReidSimilarity: 0.7200658660519842\n  matchingScoreWeight4TrackletSimilarity: 0.23836654600118312\n  maxAngle4TrackletMatching: 142\n  maxTrackletMatchingTimeSearchRange: 20\n  minBboxSizeSimilarity4TrackletMatching: 0.18214484831006444\n  minMatchingScore4Overall: 0.23583585666333318\n  minMatchingScore4ReidSimilarity: 0.24582563724796622\n  minSpeedSimilarity4TrackletMatching: 0.0023058182326161298\n  minTrackletMatchingScore: 0.09979720773093673\n  minTrajectoryLength4Projection: 37\n  prepLength4TrajectoryProjection: 50\n  reidExtractionInterval: 19\n  trackletSpacialSearchRegionScale: 0.2598\n  trajectoryProjectionLength: 43\n  trajectoryProjectionMeasurementNoiseScale: 100\n  trajectoryProjectionProcessNoiseScale: 0.01\n  useUniqueID: 0\nVisualTracker:\n  featureFocusOffsetFactor_y: -0.15647586556568632\n  featureImgSizeLevel: 3\n  filterChannelWeightsLr: 0.07701879646606641\n  filterLr: 0.13560657062953396\n  gaussianSigma: 1.497826153095461\n  useColorNames: 1\n  useHog: 1\n  visualTrackerType: 2\n"
                    "ca_rag_config.yaml"             = "context_manager:\n  functions:\n  - summarization\n  - ingestion_function\n  - retriever_function\n  - notification\nfunctions:\n  ingestion_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_ingestion\n  notification:\n    params:\n      events: []\n    tools:\n      llm: notification_llm\n      notification_tool: notification_tool\n    type: notification\n  retriever_function:\n    params:\n      batch_size: 1\n      cot: false\n      image: false\n      top_k: 5\n    tools:\n      db: graph_db\n      llm: chat_llm\n    type: graph_retrieval\n  summarization:\n    params:\n      batch_max_concurrency: 20\n      batch_size: 5\n      prompts:\n        caption: Write a concise and clear dense caption for the provided warehouse video, focusing on irregular or hazardous events such as boxes falling, workers not wearing PPE, workers falling, workers taking photographs, workers chitchatting, forklift stuck, etc. Start and end each sentence with a time stamp.\n        caption_summarization: 'You should summarize the following events of a warehouse in the format start_time:end_time:caption. For start_time and end_time use . to seperate seconds, minutes, hours. If during a time segment only regular activities happen, then ignore them, else note any irregular activities in detail. The output should be bullet points in the format start_time:end_time: detailed_event_description. Don''t return anything else except the bullet points.'\n        summary_aggregation: 'You are a warehouse monitoring system. Given the caption in the form start_time:end_time: caption, Aggregate the following captions in the format start_time:end_time:event_description. If the event_description is the same as another event_description, aggregate the captions in the format start_time1:end_time1,...,start_timek:end_timek:event_description. If any two adjacent end_time1 and start_time2 is within a few tenths of a second, merge the captions in the format start_time1:end_time2. The output should only contain bullet points. Cluster the output into Unsafe Behavior, Operational Inefficiencies, Potential Equipment Damage and Unauthorized Personnel'\n    tools:\n      db: graph_db\n      llm: summarization_llm\n    type: batch_summarization\ntools:\n  chat_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  graph_db:\n    params:\n      host: $${GRAPH_DB_HOST}\n      password: $${GRAPH_DB_PASSWORD}\n      port: $${GRAPH_DB_PORT}\n      username: $${GRAPH_DB_USERNAME}\n    tools:\n      embedding: nvidia_embedding\n    type: neo4j\n  notification_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  notification_tool:\n    params:\n      endpoint: http://127.0.0.1:60000/via-alert-callback\n    type: alert_sse_notifier\n  nvidia_embedding:\n    params:\n      base_url: http://$${EMBED_HOST}:$${EMBED_PORT}/v1\n      model: nvidia/llama-3.2-nv-embedqa-1b-v2\n    type: embedding\n  nvidia_reranker:\n    params:\n      base_url: http://$${RERANK_HOST}:$${RERANK_PORT}/v1\n      model: nvidia/llama-3.2-nv-rerankqa-1b-v2\n    type: reranker\n  summarization_llm:\n    params:\n      base_url: http://$${LLM_HOST}:$${LLM_PORT}/v1\n      max_tokens: 2048\n      model: $${LLM_MODEL}\n      temperature: 0.2\n      top_p: 0.7\n    type: llm\n  vector_db:\n    params:\n      host: $${MILVUS_DB_HOST}\n      port: $${MILVUS_DB_PORT}\n    tools:\n      embedding: nvidia_embedding\n    type: milvus\n"
                  }
                }
              ]

              recipe_container_env = [
                { key = "VLM_MODEL_TO_USE", value = "cosmos-reason1" },
                { key = "MODEL_PATH", value = "git:https://huggingface.co/nvidia/Cosmos-Reason1-7B" },
                { key = "DISABLE_GUARDRAILS", value = "true" },
                { key = "OPENAI_API_KEY_NAME", value = "VSS_OPENAI_API_KEY" },
                { key = "NVIDIA_API_KEY_NAME", value = "VSS_NVIDIA_API_KEY" },
                { key = "NGC_API_KEY_NAME", value = "VSS_NGC_API_KEY" },
                { key = "TRT_LLM_MODE", value = "int4_awq" },
                { key = "DISABLE_CV_PIPELINE", value = "false" },
                { key = "GDINO_INFERENCE_INTERVAL", value = "1" },
                { key = "NUM_CV_CHUNKS_PER_GPU", value = "1" },
                { key = "ENABLE_AUDIO", value = "true" },
                { key = "LLM_MODEL", value = "meta-llama/llama-3.1-8b-instruct" },
                { key = "LLM_HOST", value = "$${nim-llm.internal_dns_name}" },
                { key = "LLM_PORT", value = "8000" },
                { key = "EMBED_HOST", value = "$${embedding.internal_dns_name}" },
                { key = "EMBED_PORT", value = "8000" },
                { key = "RERANK_HOST", value = "$${rerank.internal_dns_name}" },
                { key = "RERANK_PORT", value = "8000" },
                { key = "RIVA_ASR_SERVER_URI", value = "$${riva.internal_dns_name}" },
                { key = "RIVA_ASR_GRPC_PORT", value = "50051" },
                { key = "RIVA_ASR_HTTP_PORT", value = "9000" },
                { key = "ENABLE_RIVA_SERVER_READINESS_CHECK", value = "true" },
                { key = "RIVA_ASR_SERVER_IS_NIM", value = "true" },
                { key = "RIVA_ASR_SERVER_USE_SSL", value = "false" },
                { key = "INSTALL_PROPRIETARY_CODECS", value = "false" },
                { key = "VLLM_GPU_MEMORY_UTILIZATION", value = "0.7" },
                { key = "FRONTEND_PORT", value = "9000" },
                { key = "BACKEND_PORT", value = "8000" },
                { key = "GRAPH_DB_HOST", value = "$${neo4j.internal_dns_name}" },
                { key = "GRAPH_DB_PORT", value = "7687" },
                { key = "MILVUS_DB_HOST", value = "my-release-milvus" },
                { key = "MILVUS_DB_PORT", value = "19530" },
                { key = "MINIO_HOST", value = "my-release-minio" },
                { key = "MINIO_PORT", value = "9000" },
                { key = "MINIO_WEBUI_PORT", value = "9001" },
                { key = "ARANGO_DB_HOST", value = "arango-db-arango-db-deployment-arango-db-service" },
                { key = "ARANGO_DB_PORT", value = "8529" },
                { key = "APP_VECTORSTORE_URL", value = "http://my-release-milvus:19530" },
                { key = "ES_HOST", value = "$${elasticsearch.internal_dns_name}" },
                { key = "ES_PORT", value = "9200" },
                { key = "ES_TRANSPORT_PORT", value = "9300" },
                { key = "NEO4J_AUTH", value = "neo4j/password" }
              ]

              recipe_environment_secrets = [
                { envvar_name = "NVIDIA_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" },
                { envvar_name = "NGC_API_KEY", secret_name = "ngc-api-secret", secret_key = "NGC_API_KEY" },
                { envvar_name = "GRAPH_DB_USERNAME", secret_name = "neo4j-creds", secret_key = "username" },
                { envvar_name = "GRAPH_DB_PASSWORD", secret_name = "neo4j-creds", secret_key = "password" },
                { envvar_name = "MINIO_USERNAME", secret_name = "minio-creds-secret", secret_key = "access-key" },
                { envvar_name = "MINIO_PASSWORD", secret_name = "minio-creds-secret", secret_key = "secret-key" },
                { envvar_name = "ARANGO_DB_USERNAME", secret_name = "arango-db-creds-secret", secret_key = "username" },
                { envvar_name = "ARANGO_DB_PASSWORD", secret_name = "arango-db-creds-secret", secret_key = "password" }
              ]

              recipe_liveness_probe_params = {
                failure_threshold = 3
                endpoint_path     = "/health/live"
                port              = 8000
                period_seconds    = 10
                timeout_seconds   = 1
              }

              recipe_startup_probe_params = {
                failure_threshold = 360
                endpoint_path     = "/health/ready"
                port              = 8000
                period_seconds    = 10
                timeout_seconds   = 1
              }

              recipe_readiness_probe_params = {
                failure_threshold     = 3
                endpoint_path         = "/health/ready"
                port                  = 8000
                initial_delay_seconds = 5
                period_seconds        = 5
                timeout_seconds       = 1
              }
            }
          )
          depends_on = concat([
            "nim-llm",
            "embedding",
            "rerank",
            "riva",
            "elasticsearch",
            "neo4j"
          ], var.enable_auth_service ? ["auth-service"] : [])
        }
        ],
        local.vss_postgres_recipe,
        local.vss_download_service_recipe,
        local.vss_oracle_ux_recipes,
        local.auth_service_recipe
      )
    }
  })
  _wpp_frontend_deployments = [
    for skin in local.enabled_frontend_skins : {
      name       = skin.variable_name
      depends_on = ["backend"]
      recipe = merge(
        {
          recipe_id                            = replace(skin.variable_name, "_", "-")
          deployment_name                      = replace(skin.variable_name, "_", "-")
          recipe_mode                          = "service"
          recipe_image_uri                     = skin.image_uri
          recipe_replica_count                 = 1
          recipe_flex_shape_ocpu_count         = 2
          recipe_flex_shape_memory_size_in_gbs = 16
          recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
          recipe_use_shared_node_pool          = true
          recipe_container_port                = skin.container_port
          service_endpoint_subdomain           = skin.subdomain
          recipe_additional_ingress_ports = [
            {
              port_name    = "api"
              service_name = "$${backend.service_name}"
              port         = 8000
              path         = "/api"
              path_type    = "Prefix"
            }
          ]
        },
        var.use_custom_dns ? { service_endpoint_domain = local.public_endpoint.starter_pack } : {}
      )
    }
    if try(skin.variable_name, "") != ""
  ]

  _warehouse_pick_path_small_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat(
        [
          {
            name    = "backend"
            exports = ["service_name"]
            recipe = {
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              recipe_id                             = "wpp-backend"
              recipe_mode                           = "service"
              deployment_name                       = "wpp-backend"
              recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/warehouse-pick-path-optimizer-be:2d2a008"
              recipe_replica_count                  = 1
              recipe_node_shape                     = local.starter_pack_config.worker_node_shape
              recipe_nvidia_gpu_count               = 1
              recipe_use_shared_node_pool           = true
              recipe_container_port                 = "8000"
              recipe_container_env = [
                { key = "OCI26AI_CONNECTION_STRING", value = local.oracle26ai_high_connection_string },
                { key = "OCI26AI_USER", value = var.db_username },
                { key = "OCI26AI_PASSWORD", value = var.db_password },
              ]
              recipe_liveness_probe_params = {
                port                  = 8000
                scheme                = "HTTP"
                endpoint_path         = "/healthz"
                period_seconds        = 30
                timeout_seconds       = 10
                failure_threshold     = 3
                success_threshold     = 1
                initial_delay_seconds = 60
              }
              recipe_readiness_probe_params = {
                port                  = 8000
                scheme                = "HTTP"
                endpoint_path         = "/readyz"
                period_seconds        = 15
                timeout_seconds       = 10
                success_threshold     = 1
                initial_delay_seconds = 30
              }
            }
          },
        ],
        local._wpp_frontend_deployments
      )
    }
  })
  _paas_rag_frontend_deployments = [
    for skin in local.enabled_frontend_skins : {
      name       = skin.variable_name
      depends_on = ["llamastack"]
      recipe = {
        recipe_id                            = replace(skin.variable_name, "_", "-")
        deployment_name                      = replace(skin.variable_name, "_", "-")
        recipe_mode                          = "service"
        recipe_image_uri                     = skin.image_uri
        recipe_replica_count                 = 1
        recipe_flex_shape_ocpu_count         = 4
        recipe_flex_shape_memory_size_in_gbs = 32
        recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
        recipe_use_shared_node_pool          = true
        recipe_container_port                = skin.container_port
        service_endpoint_subdomain           = skin.subdomain
        recipe_additional_ingress_ports = [
          { port_name = "models", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1/models", path_type = "Prefix" },
          { port_name = "health", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1/health", path_type = "Prefix" },
          { port_name = "responses", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1/responses", path_type = "Prefix" },
          { port_name = "vectorstores", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1/vector_stores", path_type = "Prefix" },
          { port_name = "files", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1/files", path_type = "Prefix" },
          { port_name = "base", service_name = "$${llamastack.service_name}", port = 8321, path = "/v1", path_type = "Prefix" },
        ]
      }
    }
    if try(skin.variable_name, "") != ""
  ]

  _paas_rag_small_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = [
        {
          name       = "llamastack"
          exports    = ["service_name"]
          depends_on = ["auth-service"]
          recipe = merge(
            {
              recipe_id                   = "llamastack"
              recipe_mode                 = "service"
              deployment_name             = "llamastack"
              recipe_node_shape           = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
              recipe_node_pool_size       = local.starter_pack_config.cpu_worker_node_pool_size
              recipe_use_shared_node_pool = true
              recipe_replica_count        = 1
              recipe_image_uri            = "ord.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.1.3"
              recipe_container_env = [
                { "key" = "RUN_CONFIG_PATH", value = "/config/config.yaml" },
                { "key" = "OCI26AI_CONNECTION_STRING", value = local.oracle26ai_high_connection_string },
                { "key" = "OCI26AI_USER", value = var.db_username },
                { "key" = "OCI26AI_PASSWORD", value = var.db_password },
                { "key" = "OCI_COMPARTMENT_OCID", value = var.compartment_ocid },
                { "key" = "OCI_REGION", value = var.genai_region },
                { "key" = "OCI_AUTH_TYPE", value = "instance_principal" },
                { "key" = "SQLITE_STORE_DIR", value = "/sqlite-store" },
                { "key" = "S3_BUCKET_NAME", value = local.bucket_name },
                { "key" = "AWS_REGION", value = var.region },
                { "key" = "AWS_ACCESS_KEY_ID", value = local.aws_compat_access_key_id },
                { "key" = "AWS_SECRET_ACCESS_KEY", value = local.aws_compat_access_key_key },
                { "key" = "S3_ENDPOINT_URL", value = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oci.customer-oci.com" },
                { "key" = "AWS_REQUEST_CHECKSUM_CALCULATION", value = "when_required" },
                { "key" = "AWS_RESPONSE_CHECKSUM_VALIDATION", value = "when_required" },
                { "key" = "AUTH_VALIDATE_ENDPOINT", value = "http://$${auth-service.service_name}/auth/validate" }
              ],
              pvcs = {
                retain_after_undeploy = true
                volumes = [
                  { name = "ls-sqlite", mount_location = "/sqlite-store", volume_size_in_gbs = 500 }
                ]
              },
              recipe_container_port                = "8321"
              recipe_flex_shape_ocpu_count         = 8
              recipe_flex_shape_memory_size_in_gbs = 64
              recipe_secret_mounts = [
                { "name" = "llamastack-paas-config", "mount_location" = "/config" }
              ]
            },
            var.use_custom_dns ? { service_endpoint_domain = local.public_endpoint.starter_pack } : {}
          )
        },
        {
          name       = "frontend",
          depends_on = ["llamastack", "auth-service"],
          recipe = {
            recipe_id                            = "frontend",
            deployment_name                      = "frontend",
            recipe_mode                          = "service",
            recipe_image_uri                     = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend:v0.4.3-arbi",
            recipe_replica_count                 = 1,
            recipe_flex_shape_ocpu_count         = 4,
            recipe_flex_shape_memory_size_in_gbs = 32,
            recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape,
            recipe_use_shared_node_pool          = true,
            recipe_container_port                = "3000",
            # try() default keeps this local evaluable for non-paas_rag categories
            # (the blueprint map is always materialized); main dropped frontend_url
            # from the vss/cuopt configs when those frontends moved to skins.
            service_endpoint_subdomain = try(local.starter_pack_config.frontend_url, "frontend-paas")
            recipe_additional_ingress_ports = [
              {
                port_name    = "models"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1/models"
                path_type    = "Prefix"
              },
              {
                port_name    = "health"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1/health"
                path_type    = "Prefix"
              },
              {
                port_name    = "responses"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1/responses"
                path_type    = "Prefix"
              },
              {
                port_name    = "vectorstores"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1/vector_stores"
                path_type    = "Prefix"
              },
              {
                port_name    = "files"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1/files"
                path_type    = "Prefix"
              },
              {
                port_name    = "base"
                service_name = "$${llamastack.service_name}"
                port         = 8321
                path         = "/v1"
                path_type    = "Prefix"
              },
              {
                port_name    = "auth"
                service_name = "$${auth-service.service_name}"
                port         = 8080
                path         = "/auth"
                path_type    = "Prefix"
              }
            ]
          }
        },
        {
          name       = "auth-service",
          exports    = ["service_name"],
          depends_on = [],
          recipe = {
            recipe_id                            = "auth-service",
            deployment_name                      = "auth-service",
            recipe_mode                          = "service",
            recipe_image_uri                     = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service:v1.0.0",
            recipe_replica_count                 = 1,
            recipe_flex_shape_ocpu_count         = 2,
            recipe_flex_shape_memory_size_in_gbs = 8,
            recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape,
            recipe_use_shared_node_pool          = true,
            recipe_container_port                = "8080",
            recipe_container_env = [
              { key = "AUTH_JWT_SECRET", value = "arbi-demo-secret-rbr-2026" },
              { key = "AUTH_DATABASE_TYPE", value = "oracle" },
              { key = "AUTH_ORACLE_CONNECTION_STRING", value = local.oracle26ai_high_connection_string },
              { key = "AUTH_ORACLE_USER", value = var.db_username },
              { key = "AUTH_ORACLE_PASSWORD", value = var.db_password },
              { key = "AUTH_AUTO_ADMIN_FIRST_USER", value = "true" },
              { key = "AUTH_BCRYPT_ROUNDS", value = "12" },
              { key = "AUTH_ACCESS_TOKEN_EXPIRE_MINUTES", value = "15" },
              { key = "AUTH_REFRESH_TOKEN_EXPIRE_DAYS", value = "7" }
            ]
          }
        },
        {
          name       = "rag-ingestor-migrate",
          depends_on = ["auth-service"],
          recipe = {
            recipe_id                            = "rag-ingestor-migrate",
            deployment_name                      = "rag-ingestor-migrate",
            recipe_mode                          = "job",
            recipe_image_uri                     = local.rag_ingestor_image_uri,
            recipe_flex_shape_ocpu_count         = 2,
            recipe_flex_shape_memory_size_in_gbs = 8,
            recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape,
            recipe_use_shared_node_pool          = true,
            recipe_container_command             = ["python", "-m", "etl.admin"],
            recipe_container_command_args        = ["db", "migrate", "--ini", "/app/alembic.ini"],
            recipe_container_env = [
              { key = "LOG_LEVEL", value = "INFO" },
              { key = "LLAMA_STACK_USERNAME", value = "robert.riley@oracle.com" },
              { key = "AUTH_SERVICE_URL", value = "http://$${auth-service.service_name}" }
            ],
            recipe_environment_secrets = [
              { envvar_name = "DATABASE_URL", secret_name = "etl-secrets", secret_key = "DATABASE_URL" },
              { envvar_name = "OCI_AUTH_METHOD", secret_name = "etl-secrets", secret_key = "OCI_AUTH_METHOD" },
              { envvar_name = "LLAMA_STACK_PASSWORD", secret_name = "etl-secrets", secret_key = "LLAMA_STACK_PASSWORD" }
            ]
          }
        },
        {
          name       = "rag-ingestor",
          exports    = ["service_name"],
          depends_on = ["rag-ingestor-migrate", "llamastack", "auth-service"],
          recipe = {
            recipe_id                            = "rag-ingestor",
            deployment_name                      = "rag-ingestor",
            recipe_mode                          = "service",
            recipe_image_uri                     = local.rag_ingestor_image_uri,
            recipe_replica_count                 = 1,
            recipe_flex_shape_ocpu_count         = 2,
            recipe_flex_shape_memory_size_in_gbs = 8,
            recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape,
            recipe_use_shared_node_pool          = true,
            recipe_container_port                = "8080",
            recipe_container_command             = ["python", "-m", "etl.api"],
            recipe_container_env = [
              { key = "LOG_LEVEL", value = "INFO" },
              { key = "MAX_OBJECT_BYTES", value = "104857600" },
              { key = "K8S_NAMESPACE", value = local.starter_pack_config.app_namespace },
              { key = "WORKER_IMAGE", value = local.rag_ingestor_image_uri },
              { key = "LLAMA_STACK_URL", value = "http://$${llamastack.service_name}" },
              { key = "LLAMA_STACK_USERNAME", value = "robert.riley@oracle.com" },
              { key = "AUTH_SERVICE_URL", value = "http://$${auth-service.service_name}" },
              { key = "ETL_API_HOST", value = "0.0.0.0" },
              { key = "ETL_API_PORT", value = "8080" }
            ],
            recipe_environment_secrets = [
              { envvar_name = "DATABASE_URL", secret_name = "etl-secrets", secret_key = "DATABASE_URL" },
              { envvar_name = "OCI_AUTH_METHOD", secret_name = "etl-secrets", secret_key = "OCI_AUTH_METHOD" },
              { envvar_name = "LLAMA_STACK_PASSWORD", secret_name = "etl-secrets", secret_key = "LLAMA_STACK_PASSWORD" }
            ]
          }
        }
      ]
    }
  })

  # -----------------------------------
  # Document Extractor Blueprint
  # Inherits paas_rag deployments (LlamaStack), removes OracleNet frontend,
  # adds dox-backend and dox-frontend + DAC.
  # Shares one 26ai database across all services.
  # -----------------------------------

  # Take paas_rag's LlamaStack deployment only. dox_pack has its own
  # contract backend and frontend wiring.
  _dox_pack_base_deployment_names = ["llamastack"]

  # Category guard inline in the if-clause keeps the result type consistent
  # (always a list of deployment objects, just empty when dox_pack isn't
  # the selected category). Pairs with the gated _dox_pack_small_blueprint
  # below so the frontend_url lookup never evaluates for other packs.
  # Override the inherited llamastack's OCI_REGION so it reads the model
  # catalog from llamastack_region (Chicago by default — where Llama-4 lives)
  # while the DAC stays in genai_region (where H100 capacity is).
  _paas_rag_base_for_dox_pack = [
    for d in jsondecode(local._paas_rag_small_blueprint).deployment_group.deployments :
    d.name == "llamastack" ? merge(d, {
      recipe = merge(d.recipe, {
        recipe_container_env = [
          for e in d.recipe.recipe_container_env :
          e.key == "OCI_REGION" ? { key = "OCI_REGION", value = var.llamastack_region } : e
        ]
      })
    }) : d
    if contains(local._dox_pack_base_deployment_names, d.name) && var.starter_pack_category == "dox_pack"
  ]

  _dox_pack_backend_env = [
    { "key" = "DB_MODE", value = "oracle" },
    { "key" = "DB_USER", value = var.db_username },
    { "key" = "DB_PASSWORD", value = var.db_password },
    { "key" = "DB_DSN", value = local.oracle26ai_high_connection_string },
    { "key" = "ORACLE_USER", value = var.db_username },
    { "key" = "ORACLE_PASSWORD", value = var.db_password },
    { "key" = "ORACLE_DSN", value = local.oracle26ai_high_connection_string },
    { "key" = "GENAI_INFERENCE_ENDPOINT", value = local.dac_inference_url },
    { "key" = "GENAI_MODEL", value = "/models/${var.dac_model_id}" },
    { "key" = "LLAMASTACK_URL", value = "http://$${llamastack.service_name}:80" },
    { "key" = "LLAMASTACK_CHAT_MODEL", value = "oci/meta.llama-4-maverick-17b-128e-instruct-fp8" },
    { "key" = "LLAMASTACK_EMBEDDING_MODEL", value = "oci/cohere.embed-english-v3.0" },
    { "key" = "LLAMASTACK_EMBEDDING_DIMENSION", value = "1024" },
    { "key" = "DOX_VECTOR_STORE_NAME", value = "dox-documents" },
    { "key" = "PYTHONUNBUFFERED", value = "1" },
  ]

  _dox_pack_small_blueprint = var.starter_pack_category == "dox_pack" ? jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = concat(local._paas_rag_base_for_dox_pack, [
        {
          name       = "dox-backend"
          exports    = ["service_name"]
          depends_on = ["llamastack"]
          recipe = {
            recipe_id                             = "dox-backend"
            recipe_mode                           = "service"
            deployment_name                       = "contract-backend"
            recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/contract-analysis/contract-analysis-backend:v1.0.3"
            recipe_replica_count                  = 1
            recipe_flex_shape_ocpu_count          = 4
            recipe_flex_shape_memory_size_in_gbs  = 32
            recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool           = true
            recipe_container_port                 = "8000"
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_container_env                  = local._dox_pack_backend_env
          }
        },
        {
          name       = "dox-frontend"
          depends_on = ["dox-backend"]
          recipe = {
            recipe_id                             = "dox-frontend"
            recipe_mode                           = "service"
            deployment_name                       = "dox-frontend"
            recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/contract-analysis/contract-analysis-frontend:v1.0.1"
            recipe_replica_count                  = 1
            recipe_flex_shape_ocpu_count          = 4
            recipe_flex_shape_memory_size_in_gbs  = 32
            recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool           = true
            recipe_container_port                 = "80"
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            service_endpoint_subdomain            = local.starter_pack_config.frontend_url
            recipe_container_env = [
              { "key" = "BACKEND_SVC", value = "$${dox-backend.service_name}" },
            ]
          }
        }
      ])
    }
  }) : ""
}
