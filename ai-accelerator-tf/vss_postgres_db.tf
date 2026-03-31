# =============================================================================
# VSS Oracle UX dedicated PostgreSQL
# Only deployed when starter_pack_category = "vss"
# =============================================================================

locals {
  vss_postgres_db = {
    host     = "vss-postgres"
    port     = "5432"
    db_name  = try(format("%s_db", random_string.vss_postgres_db_name[0].result), "")
    user     = try(format("%s_user", random_string.vss_postgres_db_username[0].result), "")
    password = try(random_string.vss_postgres_db_password[0].result, "")
  }
}

# ConfigMap for VSS Postgres credentials (used by the Postgres container)
resource "kubernetes_config_map_v1" "vss_postgres_config" {
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-postgres-config"
    labels = {
      app = "vss-postgres"
    }
  }

  data = {
    POSTGRES_DB       = local.vss_postgres_db.db_name
    POSTGRES_USER     = local.vss_postgres_db.user
    POSTGRES_PASSWORD = local.vss_postgres_db.password
  }
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# PersistentVolumeClaim for VSS Postgres data
resource "kubernetes_persistent_volume_claim_v1" "vss_postgresql_pv_claim" {
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-postgresql-pv-claim"
  }

  spec {
    storage_class_name = "oci-bv"
    access_modes       = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }

  wait_until_bound = false

  timeouts {
    create = "5m"
  }
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# VSS PostgreSQL Deployment
resource "kubernetes_deployment_v1" "vss_postgres" {
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-postgres"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vss-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "vss-postgres"
        }
      }

      spec {
        init_container {
          name  = "init-pgdata-dir"
          image = "docker.io/library/busybox:1.34"

          command = [
            "sh",
            "-c",
            "mkdir -p /var/lib/postgresql/data/pgdata && chown -R 999:999 /var/lib/postgresql/data"
          ]

          volume_mount {
            name       = "vss-postgresdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        container {
          name              = "vss-postgres"
          image             = "docker.io/library/postgres:14"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.vss_postgres_config[0].metadata[0].name
            }
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "vss-postgresdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "vss-postgresdata"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vss_postgresql_pv_claim[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.vss_postgres_config,
    kubernetes_persistent_volume_claim_v1.vss_postgresql_pv_claim,
    oci_containerengine_node_pool.oke_node_pool
  ]
}

# VSS PostgreSQL Service (ClusterIP)
resource "kubernetes_service_v1" "vss_postgres" {
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-postgres"
    labels = {
      app = "vss-postgres"
    }
  }

  spec {
    selector = {
      app = "vss-postgres"
    }

    port {
      name        = "postgres"
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
  }

  depends_on = [
    kubernetes_deployment_v1.vss_postgres,
    oci_containerengine_node_pool.oke_node_pool
  ]
}

# Secret containing DATABASE_URL for VSS Oracle UX (Prisma)
resource "kubernetes_secret_v1" "vss_db_url" {
  count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-db-url"
  }

  data = {
    DATABASE_URL = "postgresql://${local.vss_postgres_db.user}:${local.vss_postgres_db.password}@${local.vss_postgres_db.host}:${local.vss_postgres_db.port}/${local.vss_postgres_db.db_name}?schema=public"
  }

  depends_on = [kubernetes_service_v1.vss_postgres]
}
