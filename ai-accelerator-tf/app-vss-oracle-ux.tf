# =============================================================================
# VSS Oracle UX - Web UI for Video Search & Summarization
# Only deployed when starter_pack_category = "vss"
# =============================================================================

# =============================================================================
# Dynamic VSS Backend Service Discovery
# Queries Corrino workspace API to get the actual VSS service name
# =============================================================================
locals {
  # Extract VSS recipe info from workspace data (reuses data from blueprint-readiness.tf)
  vss_recipe_info = var.starter_pack_category == "vss" ? [
    for name, info in local.recipes :
    {
      name           = name
      canonical_name = try(info["canonical-name"], name)
      service_name   = "recipe-${try(info["canonical-name"], name)}"
    }
    if startswith(name, "vss-deployment-group-")
  ] : []

  # Get the first matching VSS recipe
  vss_backend_recipe = length(local.vss_recipe_info) > 0 ? local.vss_recipe_info[0] : null

  # The actual VSS backend service name from Corrino
  vss_backend_service_name = local.vss_backend_recipe != null ? local.vss_backend_recipe.service_name : "vss-backend-not-found"

  # VSS Oracle UX configuration (only used when starter_pack_category = "vss")
  vss_oracle_ux = {
    download_service_image_uri = "${local.ocir.base_uri}:vss-download-service-prod-0.0.4"
    # vss_backend_service is dynamically fetched from Corrino workspace API in app-vss-oracle-ux.tf
    vss_backend_deployment = "recipe-vss-deployment"
  }

  _enabled_vss_skins = local.deploy_app_vss ? {
    for skin in local.enabled_frontend_skins : skin.variable_name => skin
  } : {}

  # Name suffix: empty for the catalog default skin, hyphenated for non-default.
  _vss_k8s_name_suffix = {
    for key, skin in local._enabled_vss_skins :
    key => key == local.default_skin_variable_name
    ? ""
    : "-${replace(key, "_", "-")}"
  }
}

# ConfigMap for VSS Oracle UX specific configuration
resource "kubernetes_config_map_v1" "vss_oracle_ux_config" {
  for_each = local._enabled_vss_skins

  metadata { name = "vss-oracle-ux-config${local._vss_k8s_name_suffix[each.key]}" }

  data = {
    VSS_API_BASE_URL       = "http://${local.vss_backend_service_name}:8000/"
    FILE_STORAGE_PATH      = "/mnt/fss/cache"
    DOWNLOAD_SERVICE_URL   = "http://vss-download-service:8080"
    VSS_BACKEND_DEPLOYMENT = local.vss_oracle_ux.vss_backend_deployment
  }

  depends_on = [null_resource.wait_for_deployment]
}

# Service for VSS Oracle UX
resource "kubernetes_service_v1" "vss_oracle_ux_service" {
  for_each = local._enabled_vss_skins

  metadata { name = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}" }

  spec {
    selector = { app = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}" }
    port {
      port        = 80
      target_port = tonumber(each.value.container_port)
      protocol    = "TCP"
      name        = "http"
    }
    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment_v1.vss_oracle_ux_deployment]
}

# Deployment for VSS Oracle UX
resource "kubernetes_deployment_v1" "vss_oracle_ux_deployment" {
  for_each = local._enabled_vss_skins

  metadata {
    name   = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}"
    labels = { app = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}" }
    }

    template {
      metadata {
        labels = { app = "vss-oracle-ux${local._vss_k8s_name_suffix[each.key]}" }
        annotations = {
          "checksum/config" = sha256(jsonencode({
            config    = kubernetes_config_map_v1.vss_oracle_ux_config[each.key].data
            blueprint = local.starter_pack_blueprints[var.starter_pack_category][var.starter_pack_size]
          }))
        }
      }

      spec {
        volume {
          name = "fss-cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vss_fss_pvc[0].metadata[0].name
          }
        }

        container {
          name              = "vss-oracle-ux"
          image             = each.value.image_uri
          image_pull_policy = "Always"

          port {
            container_port = tonumber(each.value.container_port)
            name           = "http"
          }

          # Static environment variables
          env {
            name  = "LOCAL"
            value = "false"
          }

          env {
            name  = "NEXT_DEPLOYMENT_ID"
            value = sha256(local.canonical_blueprint_content)
          }

          # OCI Configuration from corrino-configmap (unchanged — corrino-configmap is shared)
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
            name = "COMPARTMENT_ID"
            value_from {
              config_map_key_ref {
                name = "corrino-configmap"
                key  = "COMPARTMENT_ID"
              }
            }
          }

          env {
            name = "TENANCY_ID"
            value_from {
              config_map_key_ref {
                name     = "corrino-configmap"
                key      = "TENANCY_ID"
                optional = true
              }
            }
          }

          env {
            name = "TENANCY_NAMESPACE"
            value_from {
              config_map_key_ref {
                name     = "corrino-configmap"
                key      = "TENANCY_NAMESPACE"
                optional = true
              }
            }
          }

          # VSS Configuration from the per-skin configmap (name is now dynamic)
          env {
            name = "VSS_API_BASE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.vss_oracle_ux_config[each.key].metadata[0].name
                key  = "VSS_API_BASE_URL"
              }
            }
          }

          env {
            name = "FILE_STORAGE_PATH"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.vss_oracle_ux_config[each.key].metadata[0].name
                key  = "FILE_STORAGE_PATH"
              }
            }
          }

          env {
            name = "DOWNLOAD_SERVICE_URL"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.vss_oracle_ux_config[each.key].metadata[0].name
                key  = "DOWNLOAD_SERVICE_URL"
              }
            }
          }

          env {
            name = "VSS_BACKEND_DEPLOYMENT"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.vss_oracle_ux_config[each.key].metadata[0].name
                key  = "VSS_BACKEND_DEPLOYMENT"
              }
            }
          }

          # Database URL for Prisma (unchanged — secret, not configmap-backed)
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.vss_db_url[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          volume_mount {
            name       = "fss-cache"
            mount_path = "/mnt/fss"
          }

          resources {
            requests = {
              memory = "1Gi"
              cpu    = "200m"
            }
            limits = {
              memory = "4Gi"
              cpu    = "2000m"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = tonumber(each.value.container_port)
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = tonumber(each.value.container_port)
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.vss_oracle_ux_config,
    kubernetes_deployment_v1.vss_download_service_deployment,
    kubernetes_persistent_volume_claim_v1.vss_fss_pvc,
    kubernetes_secret_v1.vss_db_url,
  ]
}

# =============================================================================
# Ingress for VSS Oracle UX - Exposes the frontend at starter_pack_url
# =============================================================================
resource "kubernetes_ingress_v1" "vss_oracle_ux_ingress" {
  for_each               = local._enabled_vss_skins
  wait_for_load_balancer = true

  metadata {
    name = "vss-oracle-ux-ingress${local._vss_k8s_name_suffix[each.key]}"
    annotations = {
      "cert-manager.io/cluster-issuer"                 = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target"     = "/"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "1800"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "1800"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["${each.value.subdomain}.${local.fqdn.name}"]
      secret_name = "vss-oracle-ux-tls${local._vss_k8s_name_suffix[each.key]}"
    }

    rule {
      host = "${each.value.subdomain}.${local.fqdn.name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vss_oracle_ux_service[each.key].metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx, kubernetes_service_v1.vss_oracle_ux_service]
}

# State migration: count-gated → for_each-keyed. Only needed the first time a
# stack is upgraded from single-skin to multi-skin. The default skin keeps
# the original metadata.name, so the underlying K8s resources are not
# renamed or recreated — this is a pure Terraform-state address change.
moved {
  from = kubernetes_deployment_v1.vss_oracle_ux_deployment[0]
  to   = kubernetes_deployment_v1.vss_oracle_ux_deployment["skin_vss_core"]
}
moved {
  from = kubernetes_service_v1.vss_oracle_ux_service[0]
  to   = kubernetes_service_v1.vss_oracle_ux_service["skin_vss_core"]
}
moved {
  from = kubernetes_ingress_v1.vss_oracle_ux_ingress[0]
  to   = kubernetes_ingress_v1.vss_oracle_ux_ingress["skin_vss_core"]
}
moved {
  from = kubernetes_config_map_v1.vss_oracle_ux_config[0]
  to   = kubernetes_config_map_v1.vss_oracle_ux_config["skin_vss_core"]
}
