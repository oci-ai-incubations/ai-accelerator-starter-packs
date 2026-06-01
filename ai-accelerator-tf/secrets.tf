# Kubernetes Secrets

resource "kubernetes_secret_v1" "neo4j_creds" {
  metadata {
    name      = "neo4j-creds"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    username = "neo4j"
    password = "password"
  }

  count      = local.deploy_app_vss ? 1 : 0
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

resource "kubernetes_secret_v1" "minio_creds" {
  metadata {
    name      = "minio-creds-secret"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    "access-key" = "minioadmin"
    "secret-key" = "minioadmin"
  }

  count      = local.deploy_app_vss ? 1 : 0
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

resource "kubernetes_secret_v1" "arango_db_creds" {
  metadata {
    name      = "arango-db-creds-secret"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    username = "root"
    password = "password"
  }

  count      = local.deploy_app_vss ? 1 : 0
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

resource "kubernetes_secret_v1" "oci_config_secret" {
  metadata {
    name      = "oci-config-secret"
    namespace = local.starter_pack_config.app_namespace
  }

  type = "Opaque"

  data = {
    "oracle-user"     = var.db_username
    "oracle-password" = var.db_password
  }

  count = local.deploy_application && var.starter_pack_category == "enterprise_rag" ? 1 : 0
  depends_on = [
    kubernetes_namespace_v1.app_namespace,
    kubernetes_secret_v1.oadb_high_connection,
  ]
}

# =============================================================================
# etl-secrets — credentials consumed by rag-ingestor + rag-ingestor-migrate
# via recipe_environment_secrets, and by per-feed worker CronJobs (envFrom)
# the etl-api renders in-cluster. LLAMA_STACK_URL stays in
# recipe_container_env (blueprint_files.tf) because it depends on a
# Corrino-runtime-resolved template variable that terraform can't compute at
# plan time.
# =============================================================================
resource "kubernetes_secret_v1" "etl_secrets" {
  metadata {
    name      = "etl-secrets"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    DATABASE_URL         = local.oracle26ai_sqlalchemy_url
    OCI_AUTH_METHOD      = "instance_principal"
    LLAMA_STACK_PASSWORD = "Testing123!"
  }

  count = var.starter_pack_category == "paas_rag" && local.needs_26ai ? 1 : 0
  depends_on = [
    oci_database_autonomous_database.oracle_26ai,
    oci_containerengine_node_pool.oke_node_pool,
  ]
}
