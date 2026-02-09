resource "kubernetes_job_v1" "corrino_migration_job" {
  metadata {
    name = "corrino-migration-job"
  }
  spec {
    template {
      metadata {}
      spec {

        container {
          name              = "corrino-migration-job"
          image             = local.app.backend_image_uri
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c"]
          args = [
            "pwd; ls -al; uname -a; whoami; python3 manage.py print_settings; python3 manage.py makemigrations; python3 manage.py migrate"
          ]

          dynamic "env" {
            for_each = local.env_universal
            content {
              name  = env.value.name
              value = env.value.value
            }
          }

          dynamic "env" {
            for_each = local.env_app_jobs
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

          dynamic "env" {
            for_each = local.env_psql_configmap
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
    kubernetes_config_map_v1.corrino-configmap,
    kubernetes_service_v1.postgres,
  ]
  count = 1
}