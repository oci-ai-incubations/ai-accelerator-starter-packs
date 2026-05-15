# Red Bull demo — paas_rag-only resources, additive to the standard
# accelerator pack and gated on `var.starter_pack_category == "paas_rag"`.

locals {
  # Single source of truth for the rag-ingestor image. Referenced by the
  # rag-ingestor recipes in blueprint_files.tf (recipe_image_uri +
  # WORKER_IMAGE env) and by the etl-config ConfigMap below (WORKER_IMAGE
  # the etl-api uses when rendering per-feed worker CronJobs).
  rag_ingestor_image_uri = "ord.ocir.io/iduyx1qnmway/corrino-devops-repository/paas-rag-ingestor:pr-41f28f2"

  # Recipe canonical names discovered from Corrino workspace data (populated
  # via blueprint-readiness.tf). Empty during plan; consumers in this file
  # depend on null_resource.wait_for_deployment so workspace data is
  # available at apply time.
  llamastack_recipe_canonical = var.starter_pack_category == "paas_rag" ? try([
    for name, info in local.recipes : try(info["canonical-name"], name)
    if startswith(name, "llamastack-paas-")
  ][0], "") : ""

  rag_ingestor_recipe_canonical = var.starter_pack_category == "paas_rag" ? try([
    for name, info in local.recipes : try(info["canonical-name"], name)
    if startswith(name, "rag-ingestor-paas-")
  ][0], "") : ""

  frontend_recipe_canonical = var.starter_pack_category == "paas_rag" ? try([
    for name, info in local.recipes : try(info["canonical-name"], name)
    if startswith(name, "frontend-paas-")
  ][0], "") : ""

  auth_service_recipe_canonical = var.starter_pack_category == "paas_rag" ? try([
    for name, info in local.recipes : try(info["canonical-name"], name)
    if startswith(name, "auth-service-paas-")
  ][0], "") : ""
}

# =============================================================================
# etl-secrets — credentials consumed by rag-ingestor + rag-ingestor-migrate
# via recipe_environment_secrets, and by per-feed worker CronJobs (envFrom)
# the etl-api renders in-cluster. LLAMA_STACK_URL stays in
# recipe_container_env (blueprint_files.tf) because it depends on a
# Corrino-runtime-resolved template variable that terraform can't compute at
# plan time.
# =============================================================================
resource "kubernetes_secret_v1" "etl_secrets" {
  metadata {
    name      = "etl-secrets"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    DATABASE_URL         = local.oracle26ai_sqlalchemy_url
    OCI_AUTH_METHOD      = "instance_principal"
    LLAMA_STACK_PASSWORD = "Testing123!"
  }

  count = var.starter_pack_category == "paas_rag" && local.needs_26ai ? 1 : 0
  depends_on = [
    oci_database_autonomous_database.oracle_26ai,
    oci_containerengine_node_pool.oke_node_pool,
  ]
}

# =============================================================================
# etl-config — non-secret runtime knobs the etl-api injects into per-feed
# worker CronJobs via envFrom. Mirrors blueprints-etl-worker/k8s/base/
# configmap.yaml from the application repo; provisioned from terraform
# because this deploy doesn't run kustomize.
# =============================================================================
resource "kubernetes_config_map_v1" "etl_config" {
  metadata {
    name      = "etl-config"
    namespace = "default"
  }

  data = {
    LOG_LEVEL        = "INFO"
    MAX_OBJECT_BYTES = "104857600"
    K8S_NAMESPACE    = local.starter_pack_config.app_namespace
    WORKER_IMAGE     = local.rag_ingestor_image_uri
    # Service exposes port 80 → targetPort 8321; hit the Service on :80, not :8321.
    LLAMA_STACK_URL      = "http://recipe-${local.llamastack_recipe_canonical}"
    LLAMA_STACK_USERNAME = "robert.riley@oracle.com"
    AUTH_SERVICE_URL     = "http://recipe-${local.auth_service_recipe_canonical}"
  }

  count = var.starter_pack_category == "paas_rag" ? 1 : 0
  depends_on = [
    oci_containerengine_node_pool.oke_node_pool,
    null_resource.wait_for_deployment,
  ]
}

# =============================================================================
# rag-ingestor /api/etl/* Ingress — separate Ingress so the SPA at
# frontend-paas can call the ETL API at /api/etl/<path> without CORS. Can't
# reuse the frontend ingress because nginx's rewrite-target annotation is
# ingress-scoped — adding it there would break the other paths (/v1/models,
# /v1/health) that proxy unchanged to llamastack. rewrite-target /$2 strips
# the /api/etl prefix so /api/etl/v1/feeds reaches the rag-ingestor pod as
# /v1/feeds.
# =============================================================================
resource "kubernetes_ingress_v1" "rag_ingestor_etl_ingress" {
  # count uses only var (plan-time known) so terraform test can evaluate it;
  # workspace-data-derived locals tolerate empty values during plan.
  count = var.starter_pack_category == "paas_rag" ? 1 : 0

  metadata {
    name      = "rag-ingestor-etl-ingress"
    namespace = local.starter_pack_config.app_namespace
    annotations = {
      "cert-manager.io/cluster-issuer"              = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/use-regex"       = "true"
      "nginx.ingress.kubernetes.io/rewrite-target"  = "/$2"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "2000m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.public_endpoint.starter_pack]
      secret_name = "recipe-${local.frontend_recipe_canonical}-tls"
    }

    rule {
      host = local.public_endpoint.starter_pack
      http {
        path {
          path      = "/api/etl(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "recipe-${local.rag_ingestor_recipe_canonical}"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [null_resource.wait_for_deployment]
}

