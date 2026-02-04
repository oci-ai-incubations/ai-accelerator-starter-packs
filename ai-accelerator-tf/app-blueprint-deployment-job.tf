# ConfigMap to hold the blueprint JSON file
# Not created for enterprise_rag since it's deployed via Helm, not OCI AI Blueprints
resource "kubernetes_config_map_v1" "blueprint_config_map" {
  count = var.starter_pack_category != "enterprise_rag" ? 1 : 0
  metadata {
    name = "blueprint-config"
  }
  data = {
    "${local.starter_pack_config.blueprint_file}" = local.starter_pack_blueprint_content
  }
}

resource "kubernetes_job_v1" "configure_oke_for_blueprint_deployment_job" {
  metadata {
    name = "configure-oke-for-blueprint-deployment-job"
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name              = "configure-oke"
          image             = local.app.deploy_blueprint_image_uri
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c"]
          args = [
            "python3 /app/configure_oke.py -n ${local.starter_pack_config.app_namespace}"
          ]
        }
      }
    }
    backoff_limit              = 0
    ttl_seconds_after_finished = 3600 # 1 hour instead of 2 minutes
  }
  wait_for_completion = true
  timeouts {
    create = "20m"
    update = "20m"
  }
  depends_on = [
    kubernetes_deployment_v1.corrino_cp_deployment,
  ]
  count = var.is_nvaie_enabled && var.starter_pack_category != "enterprise_rag" ? 1 : 0
}

# DNS Configuration Warning - outputs the required DNS setup when custom_dns is enabled
# This runs BEFORE the blueprint deployment job so users see the message even if deployment fails
resource "null_resource" "custom_dns_configuration_warning" {
  count = var.use_custom_dns ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "=============================================================================="
      echo "                    CUSTOM DNS CONFIGURATION REQUIRED"
      echo "=============================================================================="
      echo ""
      echo "You have enabled custom DNS for your deployment."
      echo ""
      echo "To complete the setup, you must add a wildcard A record in your DNS registrar:"
      echo ""
      echo "    Domain:       *.${var.fqdn_custom_domain}"
      echo "    Record Type:  A"
      echo "    Value:        ${local.network.external_ip}"
      echo ""
      echo "Point the wildcard domain to the load balancer IP address shown above."
      echo ""
      echo "If DNS is not configured, the deployment will fail when attempting to"
      echo "reach the API at: ${local.public_endpoint.api_origin_secure}"
      echo ""
      echo "=============================================================================="
      echo ""
    EOT
  }

  depends_on = [
    helm_release.ingress_nginx,
    data.kubernetes_service_v1.ingress,
  ]
}

# Blueprint deployment job - not used for enterprise_rag since it's deployed via Helm
resource "kubernetes_job_v1" "blueprint_deployment_job" {
  count = var.starter_pack_category != "enterprise_rag" ? 1 : 0
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
          args = [<<-EOT
            python3 /app/corrino_api_client.py -y -a ${local.public_endpoint.api_origin_secure} -d /blueprints/${local.starter_pack_config.blueprint_file}
            EXIT_CODE=$?
            if [ $EXIT_CODE -ne 0 ] && [ "$USE_CUSTOM_DNS" = "true" ]; then
              echo ""
              echo "=============================================================================="
              echo "         DEPLOYMENT FAILED - CUSTOM DNS CONFIGURATION MAY BE REQUIRED"
              echo "=============================================================================="
              echo ""
              echo "You have enabled custom DNS. Ensure you have added a wildcard A record:"
              echo ""
              echo "    Domain:       *.$CUSTOM_DNS_DOMAIN"
              echo "    Record Type:  A"
              echo "    Value:        $CUSTOM_DNS_IP"
              echo ""
              echo "Point the wildcard domain to the load balancer IP address shown above."
              echo ""
              echo "=============================================================================="
              echo ""
            fi
            exit $EXIT_CODE
          EOT
          ]

          env {
            name  = "CORRINO_USERNAME"
            value = var.corrino_admin_username
          }

          env {
            name  = "CORRINO_PASSWORD"
            value = var.corrino_admin_password
          }

          env {
            name  = "USE_CUSTOM_DNS"
            value = var.use_custom_dns ? "true" : "false"
          }

          env {
            name  = "CUSTOM_DNS_DOMAIN"
            value = var.fqdn_custom_domain
          }

          env {
            name  = "CUSTOM_DNS_IP"
            value = local.network.external_ip
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
            name = kubernetes_config_map_v1.blueprint_config_map[0].metadata[0].name
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
    kubernetes_job_v1.configure_oke_for_blueprint_deployment_job,
    kubernetes_config_map_v1.blueprint_config_map,
    kubernetes_service_v1.postgres,
    kubernetes_job_v1.wallet_extractor_job,
    oci_objectstorage_bucket.paas_rag_bucket,
    oci_identity_customer_secret_key.aws_compat_access_key,
    null_resource.custom_dns_configuration_warning,
  ]
}