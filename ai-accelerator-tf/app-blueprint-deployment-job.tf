# ConfigMap to hold the blueprint JSON file
# Not created for enterprise_rag since it's deployed via Helm, not OCI AI Blueprints
resource "kubernetes_config_map_v1" "blueprint_config_map" {
  count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
  metadata {
    name = "blueprint-config"
  }
  data = {
    (local.starter_pack_config.blueprint_file) = local.starter_pack_blueprint_content
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
  count = local.deploy_application && local.starter_pack_config.create_ngc_secrets_in_cluster ? 1 : 0
}

# Configure OKE secrets in the AIQ namespace (enterprise_rag_aiq only).
# The main configure_oke job creates secrets in app_namespace ("rag"), but the AIQ
# helm chart deploys to a separate namespace and needs its own copy of the secrets.
resource "kubernetes_job_v1" "configure_oke_for_aiq_namespace" {
  metadata {
    name = "configure-oke-for-aiq-namespace"
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name              = "configure-oke-aiq"
          image             = local.app.deploy_blueprint_image_uri
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c"]
          args = [
            "python3 /app/configure_oke.py -n ${coalesce(local.starter_pack_config.aiq_namespace, "aiq")}"
          ]
        }
      }
    }
    backoff_limit              = 0
    ttl_seconds_after_finished = 3600
  }
  wait_for_completion = true
  timeouts {
    create = "20m"
    update = "20m"
  }
  depends_on = [
    kubernetes_deployment_v1.corrino_cp_deployment,
  ]
  count = var.starter_pack_category == "enterprise_rag_aiq" ? 1 : 0
}

# =============================================================================
# Blueprint lifecycle: Job runs only when canonical blueprint content changes.
# random_id keepers use a hash of the canonical blueprint so the job is re-run
# only when the blueprint (or its inputs) actually change, not on every apply.
# =============================================================================

# Unique suffix for deployment names - changes only when the canonical blueprint content changes,
# so the blueprint deployment job is not re-run on every apply.
resource "random_id" "blueprint_deploy_id" {
  count       = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
  byte_length = 4

  keepers = {
    blueprint_hash = !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? sha256(local.canonical_blueprint_content) : "enterprise_rag"
  }
}

# DNS Configuration Warning - outputs the required DNS setup when custom_dns is enabled
# This runs BEFORE the blueprint deployment job so users see the message even if deployment fails
resource "null_resource" "custom_dns_configuration_warning" {
  count = local.deploy_application && var.use_custom_dns ? 1 : 0

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
  count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
  metadata {
    name = "blueprint-deployment-job-${random_id.blueprint_deploy_id[0].hex}"
  }

  lifecycle {
    replace_triggered_by = [random_id.blueprint_deploy_id]
  }
  spec {
    template {
      metadata {}
      spec {

        # the undeploy logic in the python script is:
        # 1. login and get the workspace
        # 2. get the deployment uuids for the Ingress recipes which correspond to the recipes in the blueprint file
        # 3. undeploy the deployments (if any exist)
        # 4. Ensure they are undeployed by polling until they are all cleared
        # 5. When they are all gone, deploy the new blueprint
        container {
          name              = "blueprint-deployment-job"
          image             = local.app.deploy_blueprint_image_uri
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -e
            API_URL="${local.public_endpoint.api_origin_secure}"
            echo "Blueprint lifecycle: undeploying existing Ingress deployments before deploy..."
            python3 - "$API_URL" "$CORRINO_USERNAME" "$CORRINO_PASSWORD" << 'PYTHON_UNDEPLOY'
            import json, ssl, sys, time, urllib.request
            from urllib.error import HTTPError
            from urllib.parse import urlencode
            api_url = sys.argv[1].rstrip('/')
            username, password = sys.argv[2], sys.argv[3]
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
            try:
              login = urllib.request.urlopen(urllib.request.Request(api_url + '/login/', data=urlencode({'username': username, 'password': password}).encode(), headers={'Content-Type': 'application/x-www-form-urlencoded'}, method='POST'), context=ctx)
              token = json.load(login).get('token') if login else None
            except Exception as e:
              print('API not reachable, skipping undeploy:', e); sys.exit(0)
            if not token:
              print('No token, skipping undeploy.'); sys.exit(0)
            try:
              req = urllib.request.Request(api_url + '/workspace/', headers={'Authorization': 'Token %s' % token}, method='GET')
              ws = json.load(urllib.request.urlopen(req, context=ctx))
              recipes = ws.get('recipes') or {}
            except Exception as e:
              print('No workspace, skipping undeploy:', e); sys.exit(0)
            uuids = [r.get('deployment-uuid', '') for r in recipes.values() if r.get('type') == 'Ingress' and r.get('deployment-uuid')]
            for uuid in uuids:
              try:
                r = urllib.request.urlopen(urllib.request.Request(api_url + '/undeploy/', data=json.dumps({'deployment_uuid': uuid}).encode(), headers={'Authorization': 'Token %s' % token, 'Content-Type': 'application/json'}, method='POST'), context=ctx)
                print('Undeploy %s succeeded' % uuid)
              except HTTPError as e:
                if e.code == 404: print('Deployment %s not found (already undeployed)' % uuid)
                else: print('Undeploy %s failed: %s' % (uuid, e)); sys.exit(1)
              except Exception as e: print('Undeploy %s failed: %s' % (uuid, e)); sys.exit(1)
            if uuids:
              print('Waiting for workspace recipes to clear...')
              for attempt in range(60):
                try:
                  ws = json.load(urllib.request.urlopen(urllib.request.Request(api_url + '/workspace/', headers={'Authorization': 'Token %s' % token}, method='GET'), context=ctx))
                  recipes = ws.get('recipes') or {}
                  if not recipes:
                    print('Workspace recipes cleared after %ds.' % (attempt * 10)); break
                  print('  Attempt %d: %d recipe(s) remaining, waiting 10s...' % (attempt + 1, len(recipes)))
                except Exception as e: print('  Poll failed:', e)
                time.sleep(10)
              else:
                print('Timeout waiting for workspace to clear.'); sys.exit(1)
            print('Undeploy complete.')
            PYTHON_UNDEPLOY
            python3 /app/corrino_api_client.py -y -a "$API_URL" -d /blueprints/${local.starter_pack_config.blueprint_file}
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
    ttl_seconds_after_finished = 31536000 # 1 year — Job must persist so Terraform doesn't recreate it on subsequent applies
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
    oci_objectstorage_bucket.paas_rag_bucket,
    oci_identity_customer_secret_key.aws_compat_access_key,
    null_resource.custom_dns_configuration_warning,
  ]
}

# Destroy-time provisioner: undeploys all blueprints via Corrino API before app teardown.
# During terraform destroy, this resource is destroyed FIRST (inverse dependency order),
# so Corrino and the ingress are still alive when the undeploy script runs.
resource "terraform_data" "blueprint_undeploy" {
  count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0

  input = {
    api_url  = local.public_endpoint.api_origin_secure
    username = var.corrino_admin_username
    password = var.corrino_admin_password
  }

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${path.module}/scripts/undeploy_blueprints.py '${self.output.api_url}' '${self.output.username}' '${self.output.password}'"
  }

  depends_on = [
    kubernetes_job_v1.blueprint_deployment_job,
    helm_release.ingress_nginx,
  ]
}
