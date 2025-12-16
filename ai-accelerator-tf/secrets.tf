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

  count      = local.starter_pack_config.starter_pack_choice == "vss_medium" ? 1 : 0
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

  count      = local.starter_pack_config.starter_pack_choice == "vss_medium" ? 1 : 0
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

  count      = local.starter_pack_config.starter_pack_choice == "vss_medium" ? 1 : 0
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}
