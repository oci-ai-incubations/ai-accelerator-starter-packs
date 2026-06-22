# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# Deploy-time generated secrets for the Langfuse (agent_observability) pack.
# All sensitive material is generated in Terraform and injected into the Corrino
# blueprint via the langfuse-secrets Kubernetes secret (recipe_environment_secrets).
# No secrets are ever written into the blueprint JSON in plaintext.

# OCI PSQL admin password — complexity-safe and URL-safe (no @ : / # ?).
resource "random_password" "langfuse_pg_password" {
  count            = local.deploy_app_agent_obs ? 1 : 0
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "_-*."
}

# ClickHouse password — alphanumeric to keep the connection URL simple.
resource "random_password" "langfuse_clickhouse_password" {
  count   = local.deploy_app_agent_obs ? 1 : 0
  length  = 24
  special = false
}

# NextAuth session-cookie signing secret.
resource "random_password" "langfuse_nextauth_secret" {
  count   = local.deploy_app_agent_obs ? 1 : 0
  length  = 32
  special = false
}

# API-key salt.
resource "random_password" "langfuse_salt" {
  count   = local.deploy_app_agent_obs ? 1 : 0
  length  = 32
  special = false
}

# ENCRYPTION_KEY must be exactly 256 bits = 64 hex characters.
resource "random_id" "langfuse_encryption_key" {
  count       = local.deploy_app_agent_obs ? 1 : 0
  byte_length = 32
}

locals {
  langfuse_s3_endpoint = local.deploy_app_agent_obs ? format(
    "https://%s.compat.objectstorage.%s.oci.customer-oci.com",
    data.oci_objectstorage_namespace.ns.namespace,
    var.region,
  ) : ""

  langfuse_secret_name = "langfuse-secrets"
}

resource "kubernetes_secret_v1" "langfuse_secrets" {
  count = local.deploy_app_agent_obs ? 1 : 0
  metadata {
    name      = local.langfuse_secret_name
    namespace = local.starter_pack_config.app_namespace
  }

  data = {
    DATABASE_URL                = local.langfuse_database_url
    REDIS_CONNECTION_STRING     = local.langfuse_redis_connection_string
    CLICKHOUSE_URL              = local.langfuse_clickhouse_url
    CLICKHOUSE_MIGRATION_URL    = local.langfuse_clickhouse_migration_url
    CLICKHOUSE_USER             = local.langfuse_clickhouse_user
    CLICKHOUSE_PASSWORD         = random_password.langfuse_clickhouse_password[0].result
    S3_ACCESS_KEY_ID            = local.aws_compat_access_key_id
    S3_SECRET_ACCESS_KEY        = local.aws_compat_access_key_key
    NEXTAUTH_SECRET             = random_password.langfuse_nextauth_secret[0].result
    SALT                        = random_password.langfuse_salt[0].result
    ENCRYPTION_KEY              = random_id.langfuse_encryption_key[0].hex
    AUTH_CUSTOM_CLIENT_SECRET   = var.agent_obs_oidc_client_secret
    LANGFUSE_INIT_USER_PASSWORD = var.corrino_admin_password
  }

  type = "Opaque"

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}
