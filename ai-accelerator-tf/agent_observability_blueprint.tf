# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Corrino deployment-group blueprint for the Agent Observability (Langfuse) pack.
# Backing services (Postgres, Redis, ClickHouse, Object Storage, GenAI) live
# outside the blueprint and are injected via env + the langfuse-secrets secret.

locals {
  # Secret references shared by langfuse-web and langfuse-worker.
  _langfuse_base_secret_refs = [
    { envvar_name = "DATABASE_URL", secret_name = local.langfuse_secret_name, secret_key = "DATABASE_URL" },
    { envvar_name = "REDIS_CONNECTION_STRING", secret_name = local.langfuse_secret_name, secret_key = "REDIS_CONNECTION_STRING" },
    { envvar_name = "CLICKHOUSE_URL", secret_name = local.langfuse_secret_name, secret_key = "CLICKHOUSE_URL" },
    { envvar_name = "CLICKHOUSE_MIGRATION_URL", secret_name = local.langfuse_secret_name, secret_key = "CLICKHOUSE_MIGRATION_URL" },
    { envvar_name = "CLICKHOUSE_USER", secret_name = local.langfuse_secret_name, secret_key = "CLICKHOUSE_USER" },
    { envvar_name = "CLICKHOUSE_PASSWORD", secret_name = local.langfuse_secret_name, secret_key = "CLICKHOUSE_PASSWORD" },
    { envvar_name = "SALT", secret_name = local.langfuse_secret_name, secret_key = "SALT" },
    { envvar_name = "ENCRYPTION_KEY", secret_name = local.langfuse_secret_name, secret_key = "ENCRYPTION_KEY" },
    { envvar_name = "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID", secret_name = local.langfuse_secret_name, secret_key = "S3_ACCESS_KEY_ID" },
    { envvar_name = "LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY", secret_name = local.langfuse_secret_name, secret_key = "S3_SECRET_ACCESS_KEY" },
    { envvar_name = "LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID", secret_name = local.langfuse_secret_name, secret_key = "S3_ACCESS_KEY_ID" },
    { envvar_name = "LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY", secret_name = local.langfuse_secret_name, secret_key = "S3_SECRET_ACCESS_KEY" },
  ]

  # OIDC enabled only when an issuer is provided.
  _langfuse_oidc_enabled = var.agent_obs_oidc_issuer != ""

  _langfuse_web_secret_refs = concat(
    local._langfuse_base_secret_refs,
    [
      { envvar_name = "NEXTAUTH_SECRET", secret_name = local.langfuse_secret_name, secret_key = "NEXTAUTH_SECRET" },
      { envvar_name = "LANGFUSE_INIT_USER_PASSWORD", secret_name = local.langfuse_secret_name, secret_key = "LANGFUSE_INIT_USER_PASSWORD" },
    ],
    local._langfuse_oidc_enabled ? [
      { envvar_name = "AUTH_CUSTOM_CLIENT_SECRET", secret_name = local.langfuse_secret_name, secret_key = "AUTH_CUSTOM_CLIENT_SECRET" },
    ] : [],
  )

  # Non-secret S3 + ClickHouse config shared by web and worker.
  _langfuse_shared_env = [
    { key = "CLICKHOUSE_CLUSTER_ENABLED", value = local.langfuse_clickhouse_cluster_enabled },
    { key = "REDIS_TLS_ENABLED", value = "true" },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_ENABLED", value = "true" },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET", value = local.bucket_name },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_PREFIX", value = "events/" },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_REGION", value = var.region },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT", value = local.langfuse_s3_endpoint },
    { key = "LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE", value = "true" },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_ENABLED", value = "true" },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_BUCKET", value = local.bucket_name },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_PREFIX", value = "media/" },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_REGION", value = var.region },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT", value = local.langfuse_s3_endpoint },
    { key = "LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE", value = "true" },
    { key = "TELEMETRY_ENABLED", value = "false" },
  ]

  _langfuse_web_env = concat(
    local._langfuse_shared_env,
    [
      { key = "HOSTNAME", value = "0.0.0.0" },
      { key = "PORT", value = "3000" },
      { key = "NEXTAUTH_URL", value = "https://${local.public_endpoint.starter_pack}" },
      { key = "AUTH_DISABLE_SIGNUP", value = "true" },
      { key = "LANGFUSE_INIT_ORG_ID", value = "oracle" },
      { key = "LANGFUSE_INIT_ORG_NAME", value = "Oracle" },
      { key = "LANGFUSE_INIT_PROJECT_ID", value = "agent-observability" },
      { key = "LANGFUSE_INIT_PROJECT_NAME", value = "Agent Observability" },
      { key = "LANGFUSE_INIT_USER_EMAIL", value = var.corrino_admin_email },
      { key = "LANGFUSE_INIT_USER_NAME", value = var.corrino_admin_username },
    ],
    local._langfuse_oidc_enabled ? [
      { key = "AUTH_CUSTOM_ISSUER", value = var.agent_obs_oidc_issuer },
      { key = "AUTH_CUSTOM_CLIENT_ID", value = var.agent_obs_oidc_client_id },
      { key = "AUTH_CUSTOM_NAME", value = var.agent_obs_oidc_name },
      { key = "AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING", value = "true" },
    ] : [],
  )

  _agent_observability_blueprint = jsonencode({
    deployment_group = {
      name = "DEPLOY_NAME"
      deployments = [
        {
          name    = "langfuse-web"
          exports = ["service_name", "internal_dns_name", "service_url"]
          recipe = merge(
            {
              recipe_id                             = "langfuse-web"
              deployment_name                       = "langfuse-web"
              recipe_mode                           = "service"
              recipe_image_uri                      = "docker.io/langfuse/langfuse:3"
              recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
              recipe_use_shared_node_pool           = true
              recipe_replica_count                  = local.agent_obs_size.langfuse_web_replicas
              recipe_flex_shape_ocpu_count          = 2
              recipe_flex_shape_memory_size_in_gbs  = 8
              recipe_container_port                 = "3000"
              service_endpoint_subdomain            = "langfuse"
              recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
              recipe_container_env                  = local._langfuse_web_env
              recipe_environment_secrets            = local._langfuse_web_secret_refs
              recipe_readiness_probe_params = {
                endpoint_path         = "/api/public/health"
                port                  = 3000
                scheme                = "HTTP"
                initial_delay_seconds = 30
                period_seconds        = 15
                timeout_seconds       = 10
                failure_threshold     = 30
              }
              recipe_liveness_probe_params = {
                endpoint_path         = "/api/public/health"
                port                  = 3000
                scheme                = "HTTP"
                initial_delay_seconds = 300
                period_seconds        = 30
                timeout_seconds       = 10
                failure_threshold     = 6
              }
            },
            var.use_custom_dns ? { service_endpoint_domain = local.public_endpoint.starter_pack } : {},
          )
        },
        {
          name       = "langfuse-worker"
          exports    = ["service_name", "internal_dns_name"]
          depends_on = ["langfuse-web"]
          recipe = {
            recipe_id                            = "langfuse-worker"
            deployment_name                      = "langfuse-worker"
            recipe_mode                          = "service"
            recipe_image_uri                     = "docker.io/langfuse/langfuse-worker:3"
            recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool          = true
            recipe_replica_count                 = 1
            recipe_flex_shape_ocpu_count         = 2
            recipe_flex_shape_memory_size_in_gbs = 8
            recipe_container_port                = "3030"
            recipe_disable_ingress               = true
            recipe_container_env                 = local._langfuse_shared_env
            recipe_environment_secrets           = local._langfuse_base_secret_refs
            recipe_readiness_probe_params = {
              endpoint_path         = "/api/health"
              port                  = 3030
              scheme                = "HTTP"
              initial_delay_seconds = 30
              period_seconds        = 15
              timeout_seconds       = 10
              failure_threshold     = 30
            }
          }
        },
        {
          name       = "llamastack"
          exports    = ["service_name", "internal_dns_name", "service_url"]
          depends_on = ["langfuse-web"]
          recipe = {
            recipe_id                             = "llamastack"
            deployment_name                       = "llamastack"
            recipe_mode                           = "service"
            recipe_image_uri                      = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3"
            recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
            recipe_use_shared_node_pool           = true
            recipe_replica_count                  = 1
            recipe_flex_shape_ocpu_count          = 1
            recipe_flex_shape_memory_size_in_gbs  = 8
            recipe_container_port                 = "8321"
            service_endpoint_subdomain            = "llamastack"
            recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
            recipe_container_command_args         = ["/config/config.yaml"]
            recipe_container_env = [
              { key = "OCI_COMPARTMENT_OCID", value = var.compartment_ocid },
              { key = "OCI_REGION", value = var.genai_region },
              { key = "OCI_AUTH_TYPE", value = "instance_principal" },
              { key = "AGENT_MODEL_ENDPOINT", value = local.agent_obs_inference_url },
            ]
            recipe_secret_mounts = [
              { name = "llamastack-inference-config", mount_location = "/config" },
            ]
          }
        },
      ]
    }
  })
}
