# Ingress API key validator.
# A minimal nginx pod that ingress-nginx calls via auth-url on protected backend
# ingresses. Returns 200 when the request carries `Authorization: Bearer <key>`,
# 401 otherwise. Only deployed when add_api_key_to_ingress is true.

locals {
  # Single source of truth for which ingresses require API key auth when
  # add_api_key_to_ingress is true. kind=frontend ingresses stay open; kind=backend
  # ingresses (blueprint-injected cuopt/llamastack/vss, plus future TF-managed backend
  # ingresses) get the auth-url annotation merged in.
  ingress_classification = {
    # Terraform-managed (ingress.tf)
    grafana                     = { kind = "frontend" }
    prometheus                  = { kind = "frontend" }
    corrino_cp                  = { kind = "frontend" }
    oci_ai_blueprints_portal    = { kind = "frontend" }
    enterprise_rag_frontend     = { kind = "frontend" }
    enterprise_rag_aiq_frontend = { kind = "frontend" }
    # Blueprint-injected (blueprint_files.tf via recipe_additional_ingress_annotations)
    cuopt      = { kind = "backend" }
    llamastack = { kind = "backend" }
    vss        = { kind = "backend" }
  }

  # Effective API key: user-provided if non-empty, otherwise auto-generated.
  # Empty string when the feature is disabled.
  ingress_api_key_effective = var.add_api_key_to_ingress ? (
    var.ingress_api_key != "" ? var.ingress_api_key : try(random_password.ingress_api_key[0].result, "")
  ) : ""

  # Service address for the validator — referenced from the auth-url annotation
  # on every backend ingress.
  ingress_api_key_validator_url = "http://ingress-api-key-validator.cluster-tools.svc.cluster.local/auth"

  # Annotation map merged into backend ingresses when the feature is enabled.
  # Applied via `merge(existing_annotations, local.backend_ingress_annotations)` on
  # kubernetes_ingress_v1 resources.
  backend_ingress_annotations = var.add_api_key_to_ingress ? {
    "nginx.ingress.kubernetes.io/auth-url"    = local.ingress_api_key_validator_url
    "nginx.ingress.kubernetes.io/auth-method" = "GET"
  } : {}

  # Same map, shaped for corrino's recipe_additional_ingress_annotations (list of {key,value}).
  backend_ingress_annotations_corrino = [
    for k, v in local.backend_ingress_annotations : { key = k, value = v }
  ]

  # Rendered nginx config for the validator pod. The key is baked in at plan time;
  # rotation re-renders this and triggers a rolling restart via checksum/config.
  ingress_api_key_validator_config = var.add_api_key_to_ingress ? templatefile(
    "${path.module}/files/ingress-auth-nginx.conf.tpl",
    { api_key = local.ingress_api_key_effective }
  ) : ""
}

resource "kubernetes_config_map_v1" "ingress_api_key_validator" {
  count = local.deploy_application && var.add_api_key_to_ingress ? 1 : 0

  metadata {
    name      = "ingress-api-key-validator"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
  }

  data = {
    "default.conf" = local.ingress_api_key_validator_config
  }
}

resource "kubernetes_deployment_v1" "ingress_api_key_validator" {
  count = local.deploy_application && var.add_api_key_to_ingress ? 1 : 0

  metadata {
    name      = "ingress-api-key-validator"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
    labels = {
      app = "ingress-api-key-validator"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ingress-api-key-validator"
      }
    }

    template {
      metadata {
        labels = {
          app = "ingress-api-key-validator"
        }
        annotations = {
          # Rolls the pod whenever the rendered config (which embeds the key) changes,
          # so rotating var.ingress_api_key propagates without an explicit restart.
          "checksum/config" = sha256(local.ingress_api_key_validator_config)
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "docker.io/nginxinc/nginx-unprivileged:1.27.3-alpine"

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/conf.d"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
            initial_delay_seconds = 2
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds    = 20
            timeout_seconds   = 2
            failure_threshold = 3
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.ingress_api_key_validator[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ingress_api_key_validator" {
  count = local.deploy_application && var.add_api_key_to_ingress ? 1 : 0

  metadata {
    name      = "ingress-api-key-validator"
    namespace = kubernetes_namespace_v1.cluster_tools[0].id
  }

  spec {
    selector = {
      app = "ingress-api-key-validator"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
