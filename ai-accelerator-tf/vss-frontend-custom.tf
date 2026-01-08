# =============================================================================
# VSS Oracle UX - Kubernetes Resources
# Deploy to default namespace alongside VSS API
# Only created when starter_pack_choice is "vss_medium"
# =============================================================================

locals {
  vss_oracle_ux_count = var.starter_pack_choice == "vss_medium" ? 1 : 0

  # Dynamic host based on ingress controller IP
  vss_oracle_ux_host = var.starter_pack_choice == "vss_medium" ? "vss-oracle-ux.${replace(local.ingress_controller_load_balancer_ip, ".", "-")}.nip.io" : ""
}

# -----------------------------------------------------------------------------
# ConfigMap for non-sensitive configuration
# -----------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "vss_oracle_ux_config" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-oracle-ux-config"
    namespace = "default"
  }

  data = {
    # OCI Configuration
    LOCAL              = "false" # Use Instance Principals in production
    OCI_CONFIG_PROFILE = "aiincubations"
    REGION_NAME        = var.region

    # Object Storage Configuration
    FILE_UPLOAD_BUCKET_NAME = "vss-file-uploads"

    # VSS API Configuration (internal cluster URL for faster access)
    # This uses the dynamically discovered VSS deployment endpoint
    API_BASE_URL = "http://recipe-vss-deployment-group-vs-523e518d:8000/v1/"

    # File Storage Path (must match volume mount)
    FILE_STORAGE_PATH = "/data/vss-files"
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# -----------------------------------------------------------------------------
# Secret for sensitive configuration (OCIDs)
# -----------------------------------------------------------------------------
resource "kubernetes_secret_v1" "vss_oracle_ux_secrets" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-oracle-ux-secrets"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    # OCI Compartment and Tenancy OCIDs - use terraform variables
    COMPARTMENT_ID = var.compartment_ocid
    TENANCY_ID     = var.tenancy_ocid
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# -----------------------------------------------------------------------------
# OCIR Image Pull Secret (docker-registry type)
# Required to pull images from Oracle Container Image Registry
# -----------------------------------------------------------------------------
resource "kubernetes_secret_v1" "vss_oracle_ux_ocir_secret" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-oracle-ux-ocir-secret"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    # Note: You'll need to provide valid OCIR credentials
    # Format: { "auths": { "<region>.ocir.io": { "username": "<tenancy>/<username>", "password": "<auth_token>" }}}
    ".dockerconfigjson" = jsonencode({
      auths = {
        "sjc.ocir.io" = {
          username = "${local.oci.tenancy_namespace}/oracleidentitycloudservice/${var.corrino_admin_email}"
          password = var.corrino_admin_password # Replace with actual OCIR auth token if different
          auth     = base64encode("${local.oci.tenancy_namespace}/oracleidentitycloudservice/${var.corrino_admin_email}:${var.corrino_admin_password}")
        }
      }
    })
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# -----------------------------------------------------------------------------
# PersistentVolumeClaim for file storage (OCI Block Volume)
# -----------------------------------------------------------------------------
resource "kubernetes_persistent_volume_claim_v1" "vss_file_storage_pvc" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-file-storage-pvc"
    namespace = "default"
  }

  spec {
    storage_class_name = "oci-bv"
    access_modes       = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }

  wait_until_bound = false

  timeouts {
    create = "5m"
  }

  depends_on = [oci_containerengine_node_pool.oke_node_pool]
}

# -----------------------------------------------------------------------------
# Deployment
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "vss_oracle_ux" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-oracle-ux"
    namespace = "default"
    labels = {
      app = "vss-oracle-ux"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vss-oracle-ux"
      }
    }

    template {
      metadata {
        labels = {
          app = "vss-oracle-ux"
        }
      }

      spec {
        # Security context for the pod - fsGroup ensures volume is writable
        security_context {
          fs_group = 1001
        }

        container {
          name              = "vss-oracle-ux"
          image             = "iad.ocir.io/iduyx1qnmway/vss-oracle-ux:latest"
          image_pull_policy = "Always"

          port {
            container_port = 3000
            name           = "http"
          }

          # Environment variables from ConfigMap
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.vss_oracle_ux_config[0].metadata[0].name
            }
          }

          # Environment variables from Secret
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.vss_oracle_ux_secrets[0].metadata[0].name
            }
          }

          # Volume mounts
          volume_mount {
            name       = "file-storage"
            mount_path = "/data/vss-files"
          }

          # Resource limits (increased for large video downloads)
          resources {
            requests = {
              memory = "512Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "4Gi"
              cpu    = "1000m"
            }
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        # Volumes
        volume {
          name = "file-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vss_file_storage_pvc[0].metadata[0].name
          }
        }

        # Image pull secrets for OCIR
        image_pull_secrets {
          name = kubernetes_secret_v1.vss_oracle_ux_ocir_secret[0].metadata[0].name
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.vss_oracle_ux_config,
    kubernetes_secret_v1.vss_oracle_ux_secrets,
    kubernetes_persistent_volume_claim_v1.vss_file_storage_pvc,
    kubernetes_secret_v1.vss_oracle_ux_ocir_secret,
    kubernetes_deployment_v1.corrino_cp_deployment
  ]
}

# -----------------------------------------------------------------------------
# Service (ClusterIP)
# -----------------------------------------------------------------------------
resource "kubernetes_service_v1" "vss_oracle_ux" {
  count = local.vss_oracle_ux_count

  metadata {
    name      = "vss-oracle-ux"
    namespace = "default"
    labels = {
      app = "vss-oracle-ux"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "vss-oracle-ux"
    }

    port {
      port        = 3000
      target_port = 3000
      protocol    = "TCP"
      name        = "http"
    }
  }

  depends_on = [kubernetes_deployment_v1.vss_oracle_ux]
}

# -----------------------------------------------------------------------------
# Ingress (matching VSS API ingress configuration)
# -----------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "vss_oracle_ux_ingress" {
  count                  = local.vss_oracle_ux_count
  wait_for_load_balancer = true

  metadata {
    name      = "vss-oracle-ux-ingress"
    namespace = "default"
    annotations = {
      "cert-manager.io/cluster-issuer"              = "letsencrypt-prod"
      "kubernetes.io/ingress.class"                 = "nginx"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "2000m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.vss_oracle_ux_host]
      secret_name = "vss-oracle-ux-tls"
    }

    rule {
      host = local.vss_oracle_ux_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.vss_oracle_ux[0].metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_service_v1.vss_oracle_ux
  ]
}

# -----------------------------------------------------------------------------
# Output the VSS Oracle UX URL
# -----------------------------------------------------------------------------
output "vss_oracle_ux_url" {
  description = "URL for the VSS Oracle UX frontend"
  value       = var.starter_pack_choice == "vss_medium" ? "https://${local.vss_oracle_ux_host}" : ""
}

