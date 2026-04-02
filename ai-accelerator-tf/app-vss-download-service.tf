# =============================================================================
# VSS Download Service - Handles async downloads from Object Storage to FSS
# Only deployed when starter_pack_category = "vss"
# =============================================================================

# Service for VSS Download Service
resource "kubernetes_service_v1" "vss_download_service" {
  count = local.deploy_app_vss ? 1 : 0

  metadata {
    name = "vss-download-service"
  }

  spec {
    selector = {
      app = "vss-download-service"
    }

    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment_v1.vss_download_service_deployment]
}

# Deployment for VSS Download Service
resource "kubernetes_deployment_v1" "vss_download_service_deployment" {
  count = local.deploy_app_vss ? 1 : 0

  metadata {
    name = "vss-download-service"
    labels = {
      app = "vss-download-service"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vss-download-service"
      }
    }

    template {
      metadata {
        labels = {
          app = "vss-download-service"
        }
      }

      spec {
        # FSS volume for shared cache
        volume {
          name = "fss-cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vss_fss_pvc[0].metadata[0].name
          }
        }

        # Init container to ensure cache directory exists
        init_container {
          name    = "init-cache-dir"
          image   = "busybox:1.36"
          command = ["sh", "-c", "mkdir -p /mnt/fss/cache && chmod 777 /mnt/fss/cache"]

          volume_mount {
            name       = "fss-cache"
            mount_path = "/mnt/fss"
          }
        }

        container {
          name              = "vss-download-service"
          image             = local.vss_oracle_ux.download_service_image_uri
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          # Environment variables
          env {
            name  = "FILE_STORAGE_PATH"
            value = "/mnt/fss/cache"
          }

          env {
            name  = "MAX_CONCURRENT_DOWNLOADS"
            value = "3"
          }

          env {
            name = "REGION_NAME"
            value_from {
              config_map_key_ref {
                name = "corrino-configmap"
                key  = "REGION_NAME"
              }
            }
          }

          env {
            name  = "VSS_ORACLE_UX_URL"
            value = "http://vss-oracle-ux"
          }

          # Volume mount for FSS cache
          volume_mount {
            name       = "fss-cache"
            mount_path = "/mnt/fss"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "2Gi"
              cpu    = "1000m"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.corrino-configmap,
    kubernetes_persistent_volume_claim_v1.vss_fss_pvc
  ]
}
