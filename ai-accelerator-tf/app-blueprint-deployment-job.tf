# ConfigMap to hold the blueprint JSON file
resource "kubernetes_config_map_v1" "cuopt_blueprint_config" {
  metadata {
    name = "cuopt-blueprint-config"
  }
  data = {
    "cuopt-blueprint.json" = local.cuopt_small_blueprint
  }
}

resource "kubernetes_job_v1" "blueprint_deployment_job" {
  metadata {
    name = "blueprint-deployment-job"
  }
  spec {
    template {
      metadata {}
      spec {

        container {
          name              = "blueprint-deployment-job"
          image             = local.app.deploy_blueprint_image_uri
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c"]
          args = [
            "python3 /app/corrino_api_client.py -y -a ${local.public_endpoint.api_origin_secure} -d /blueprints/cuopt-blueprint.json"
          ]

          env {
            name  = "CORRINO_USERNAME"
            value = var.corrino_admin_username
          }
          
          env {
            name  = "CORRINO_PASSWORD"
            value = var.corrino_admin_password
          }

          volume_mount {
            name       = "blueprint-volume"
            mount_path = "/blueprints"
            read_only  = true
          }
        }

        volume {
          name = "blueprint-volume"
          config_map {
            name = kubernetes_config_map_v1.cuopt_blueprint_config.metadata[0].name
          }
        }

        restart_policy = "Never"
      }
    }
    backoff_limit              = 0
    ttl_seconds_after_finished = 120
  }
  wait_for_completion = true
  timeouts {
    create = "20m"
    update = "20m"
  }

  depends_on = [
    kubernetes_deployment_v1.corrino_cp_deployment,
    kubernetes_config_map_v1.cuopt_blueprint_config,
    kubernetes_service_v1.postgres,
  ]
  count = 1
}