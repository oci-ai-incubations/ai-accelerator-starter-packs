resource "kubernetes_service_v1" "oci_ai_blueprints_portal_service" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "oci-ai-blueprints-portal"
    annotations = {
      "oci.oraclecloud.com/load-balancer-type"             = "lb"
      "service.beta.kubernetes.io/oci-load-balancer-shape" = "flexible"
    }
  }
  spec {
    selector = {
      app = "oci-ai-blueprints-portal"
    }
    port {
      port        = 80
      target_port = 3000
    }
  }
  depends_on = [kubernetes_deployment_v1.oci_ai_blueprints_portal_deployment]
}

resource "kubernetes_deployment_v1" "oci_ai_blueprints_portal_deployment" {
  count = local.deploy_application ? 1 : 0
  metadata {
    name = "oci-ai-blueprints-portal"
    labels = {
      app = "oci-ai-blueprints-portal"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "oci-ai-blueprints-portal"
      }
    }
    template {
      metadata {
        labels = {
          app = "oci-ai-blueprints-portal"
        }
      }
      spec {
        container {
          name              = "oci-ai-blueprints-portal"
          image             = local.app.blueprint_portal_image_uri
          image_pull_policy = "Always"

          dynamic "env" {
            for_each = local.env_universal
            content {
              name  = env.value.name
              value = env.value.value
            }
          }

          dynamic "env" {
            for_each = local.env_app_configmap
            content {
              name = env.value.name
              value_from {
                config_map_key_ref {
                  name = env.value.config_map_name
                  key  = env.value.config_map_key
                }
              }
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_deployment_v1.corrino_cp_deployment]
}

