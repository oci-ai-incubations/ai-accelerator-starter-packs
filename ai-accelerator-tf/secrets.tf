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

  count      = var.starter_pack_category == "vss" ? 1 : 0
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

  count      = var.starter_pack_category == "vss" ? 1 : 0
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

  count      = var.starter_pack_category == "vss" ? 1 : 0
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

  count = var.starter_pack_category == "enterprise_rag" ? 1 : 0
  depends_on = [
    kubernetes_namespace_v1.app_namespace,
    kubernetes_secret_v1.oadb_high_connection,
  ]
}
