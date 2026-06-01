# cuOpt-specific Oracle-owned backend (cuopt-ev-routing-backend).
#
# This service is the FastAPI port of the Express server previously embedded in
# the cuopt-ev-routing-frontend container. After this migration, the frontend
# container serves only static files via `serve`; all /api/* traffic is routed
# by the frontend ingress to this backend pod.
#
# The recipe is unconditional for the cuopt category — there is no flag to turn
# it off. The shape is a single-element list to match the splat pattern used by
# auth_service_recipe (consumers concat() into the deployments array).

locals {
  cuopt_backend_image_uri = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/cuopt-ev-routing-backend:${var.cuopt_backend_image_version}"

  # Base env vars the backend needs to talk to upstream services and serve
  # config to the frontend. Mirrors what the legacy Express server read from
  # process.env. Auth env (CUOPT_AUTH_*) is appended via concat below from
  # local.cuopt_backend_auth_env (see auth-locals.tf).
  # Settings fields use Pydantic env_prefix="CUOPT_", so each app-level env var
  # must be prefixed with CUOPT_ (e.g. field cuopt_endpoint → CUOPT_CUOPT_ENDPOINT).
  # Container-level PORT stays unprefixed (uvicorn / health probes read it
  # directly, not via Settings).
  cuopt_backend_base_env = [
    { key = "CUOPT_CUOPT_ENDPOINT", value = "http://$${cuopt.service_name}:80" },
    { key = "CUOPT_LLAMASTACK_ENDPOINT", value = "http://$${llamastack.service_name}:80" },
    { key = "CUOPT_LLAMASTACK_MODEL", value = "" },
    { key = "CUOPT_GOOGLE_MAPS_API_KEY", value = var.google_maps_api_key },
    { key = "CUOPT_OPENWEATHERMAP_API_KEY", value = var.cuopt_openweathermap_api_key },
    { key = "PORT", value = "8080" },
    # TLS verify for httpx calls to in-cluster cuopt + llamastack. Default
    # true; flip via var.cuopt_tls_verify=false when those services present
    # self-signed certs (common in dev / first deploy). See
    # cuopt-ev-routing-backend services/_client.py for the consumer.
    { key = "CUOPT_TLS_VERIFY", value = tostring(var.cuopt_tls_verify) },
  ]

  # depends_on includes auth-service when enable_auth_service=true so Corrino's
  # placeholder resolver has its exports available when this recipe activates —
  # we reference $${auth-service.service_name} in the auth-url annotation
  # injected by local.backend_ingress_annotations_corrino.
  cuopt_backend_recipe = [{
    name       = "cuopt-backend"
    exports    = ["service_name"]
    depends_on = concat(["cuopt", "llamastack"], var.enable_auth_service ? ["auth-service"] : [])
    recipe = {
      recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino
      recipe_id                             = "cuopt-backend"
      deployment_name                       = "cuopt-backend"
      recipe_mode                           = "service"
      recipe_image_uri                      = local.cuopt_backend_image_uri
      recipe_replica_count                  = 1
      recipe_flex_shape_ocpu_count          = 2
      recipe_flex_shape_memory_size_in_gbs  = 4
      recipe_node_shape                     = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
      recipe_use_shared_node_pool           = true
      recipe_container_port                 = "8080"
      recipe_container_env = concat(
        local.cuopt_backend_base_env,
        local.cuopt_backend_auth_env
      )
      recipe_liveness_probe_params = {
        port                  = 8080
        scheme                = "HTTP"
        endpoint_path         = "/healthz"
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3
        success_threshold     = 1
        initial_delay_seconds = 30
      }
      recipe_readiness_probe_params = {
        port                  = 8080
        scheme                = "HTTP"
        endpoint_path         = "/readyz"
        period_seconds        = 10
        timeout_seconds       = 5
        success_threshold     = 1
        initial_delay_seconds = 10
      }
    }
  }]

  # Ingress route for the frontend to expose /api/* through the backend.
  cuopt_backend_ingress_route = [
    { port_name = "cuopt-backend", service_name = "$${cuopt-backend.service_name}", port = 8080, path = "/api", path_type = "Prefix" },
  ]
}
