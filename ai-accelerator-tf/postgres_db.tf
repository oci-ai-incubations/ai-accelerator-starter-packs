# PostgreSQL Database Resources
# Deployed to support the Corrino Control Plane

# ConfigMap for PostgreSQL configuration
resource "kubernetes_config_map_v1" "postgres_secret" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "bp-postgres-secret"
    labels = {
      app = "bp-postgres"
    }
  }

  data = {
    POSTGRES_DB       = local.postgres_db.db_name
    POSTGRES_USER     = local.postgres_db.user
    POSTGRES_PASSWORD = local.postgres_db.password
  }
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# PersistentVolumeClaim for PostgreSQL data
resource "kubernetes_persistent_volume_claim_v1" "postgresql_pv_claim" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "bp-postgresql-pv-claim"
  }

  spec {
    storage_class_name = "oci-bv"
    access_modes       = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }

  wait_until_bound = false

  timeouts {
    create = "5m"
  }
  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# PostgreSQL Deployment
resource "kubernetes_deployment_v1" "postgres" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "bp-postgres"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "bp-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "bp-postgres"
        }
      }

      spec {
        # Init container to prepare data directory
        init_container {
          name  = "init-pgdata-dir"
          image = "docker.io/library/busybox:1.34"

          command = [
            "sh",
            "-c",
            "mkdir -p /var/lib/postgresql/data/pgdata && chown -R 999:999 /var/lib/postgresql/data"
          ]

          volume_mount {
            name       = "bp-postgresdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        # PostgreSQL container
        container {
          name              = "bp-postgres"
          image             = "docker.io/library/postgres:14"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.postgres_secret[0].metadata[0].name
            }
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "bp-postgresdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "bp-postgresdata"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.postgresql_pv_claim[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.postgres_secret,
    kubernetes_persistent_volume_claim_v1.postgresql_pv_claim,
    oci_containerengine_node_pool.oke_node_pool
  ]
}

# PostgreSQL Service (ClusterIP - cluster-internal access)
# Creates cluster-internal DNS name: postgres.default.svc.cluster.local
resource "kubernetes_service_v1" "postgres" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "bp-postgres"
    labels = {
      app = "bp-postgres"
    }
  }

  spec {
    # type = "ClusterIP"  # Default type, can be omitted

    selector = {
      app = "bp-postgres"
    }

    port {
      name        = "postgres"
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
  }

  depends_on = [kubernetes_deployment_v1.postgres, oci_containerengine_node_pool.oke_node_pool]
}

# tflint-ignore: terraform_unused_declarations
data "kubernetes_service_v1" "postgres_service" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = kubernetes_service_v1.postgres[0].metadata[0].name
  }

  depends_on = [kubernetes_service_v1.postgres]
}
