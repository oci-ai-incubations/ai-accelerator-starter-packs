# Ingress API key validator.
# A minimal nginx pod that ingress-nginx calls via auth-url on protected backend
# ingresses. Returns 200 when the request carries `Authorization: Bearer <key>`,
# 401 otherwise. Only deployed when add_api_key_to_ingress is true.

# Ingress classification when add_api_key_to_ingress is true:
#   frontends (stay open):  grafana, prometheus, corrino_cp, oci_ai_blueprints_portal,
#                           enterprise_rag_frontend, enterprise_rag_aiq_frontend,
#                           plus the `demo` and `frontend` recipes in _cuopt_with_frontend
#                           and _paas_rag_small blueprints.
#   backends (protected):   every other blueprint recipe (llamastack, cuopt, elasticsearch,
#                           neo4j, embedding, rerank, riva, vss, nim-llm). Annotations are
#                           threaded per-recipe in blueprint_files.tf.

locals {
  # Effective API key: user-provided if non-empty, otherwise auto-generated.
  # Empty string when the feature is disabled.
  ingress_api_key_effective = var.add_api_key_to_ingress ? (
    var.ingress_api_key != "" ? var.ingress_api_key : try(random_password.ingress_api_key[0].result, "")
  ) : ""

  # Service address for the static-key validator pod (deployed by this file).
  ingress_api_key_validator_url = "http://ingress-api-key-validator.cluster-tools.svc.cluster.local/auth"

  # Annotation maps for the two backend-ingress gates. Both target nginx-ingress's
  # auth-url mechanism but point at different validators:
  #   add_api_key_to_ingress  → static-shared-bearer-token nginx validator pod
  #   enable_auth_service     → auth-service /auth/me (RS256 JWT)
  # auth-service takes precedence on the auth-url key when both flags are on
  # (merge order = last wins). The auth-service URL uses Corrino's templating
  # $${auth-service.service_name} so it resolves to the deployment-suffixed
  # k8s service name at blueprint-apply time.
  _backend_annotations_ingress_api_key = var.add_api_key_to_ingress ? {
    "nginx.ingress.kubernetes.io/auth-url"    = local.ingress_api_key_validator_url
    "nginx.ingress.kubernetes.io/auth-method" = "GET"
  } : {}

  # Corrino's resolve_recipe_placeholders walks the recipe and substitutes
  # $${...} from the resolved_exports map of the deployment group at activation
  # time. The key wrinkle: a recipe's placeholders only resolve cleanly if the
  # referenced deployment has been activated and its exports collected first.
  # Cuopt-blueprint backends (cuopt, llamastack, cuopt-backend) all reference
  # $${auth-service.service_name} here, so each of them lists "auth-service"
  # in its depends_on — see blueprint_files.tf (cuopt + llamastack) and
  # cuopt-locals.tf (cuopt-backend).
  _backend_annotations_auth_service = var.enable_auth_service ? {
    # FQDN required — ingress-nginx runs in the ingress-nginx namespace and
    # has no default search domain for `default`; short service names fail to
    # resolve from there and nginx returns 500 on the auth subrequest.
    "nginx.ingress.kubernetes.io/auth-url"    = "http://$${auth-service.service_name}.default.svc.cluster.local/auth/me"
    "nginx.ingress.kubernetes.io/auth-method" = "GET"
  } : {}

  # Merged map consumed by every backend recipe via
  # recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino.
  backend_ingress_annotations = merge(
    local._backend_annotations_ingress_api_key,
    local._backend_annotations_auth_service,
  )

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
