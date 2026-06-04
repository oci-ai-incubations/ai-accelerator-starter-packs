# Auth-service integration (per-user JWT) — RS256 + JWKS.
#
# When enable_auth_service is true:
#   - The auth-service pod generates its own RSA-2048 signing keypair on first
#     start and publishes the public half at
#     https://<pack-fqdn>/auth/.well-known/jwks.json. Pack BEs fetch that JWKS,
#     cache it for var.auth_service_jwks_cache_ttl_seconds, and verify token
#     signatures locally. No shared secret crosses pod boundaries.
#   - local.auth_service_recipe contains a single deployment to splat into a
#     pack's blueprint deployments list via concat().
#   - local.auth_service_ingress_route contains the /auth ingress entry to
#     splat into the pack frontend's recipe_additional_ingress_ports via concat().
#   - local.cuopt_backend_auth_env contains the CUOPT_AUTH_* env vars consumed
#     by the cuopt-backend recipe (defined in cuopt-locals.tf) — auth.py
#     verifies incoming JWTs against the trusted-issuers JWKS.
#
# OIDC providers are NOT auto-seeded — auth-service has no env-driven provider
# bootstrap. After deploy, an operator (or a follow-up null_resource hook) must
# call POST /auth/providers with the credentials below. The OIDC env vars are
# still passed into the container so future versions or external seed scripts
# can read them.

locals {
  # Image URI for the auth-service container.
  auth_service_image_uri = "iad.ocir.io/iduyx1qnmway/corrino-devops-repository/accelerator-pack-auth-service:${var.auth_service_image_version}"

  # Issuer URL stamped into every minted token's `iss` claim and exposed via
  # /auth/.well-known/openid-configuration. Pack BEs accept tokens whose `iss`
  # is in this list and fetch JWKS from `{iss}/.well-known/jwks.json`.
  auth_service_issuer_url = local.enable_auth_service ? "https://${local.public_endpoint.starter_pack}/auth" : ""

  # Sanitized list of user-supplied extra trusted issuer URLs. Extras are split
  # on commas, whitespace-trimmed, and empty entries dropped so a trailing
  # comma or stray whitespace in the input never produces an empty or
  # whitespace-padded entry in the final list. Exposed as its own local so
  # plan-time tests can assert on it directly without the apply-time-unknown
  # auth_service_issuer_url contaminating the value.
  auth_service_trusted_issuers_extras_list = [
    for s in split(",", var.auth_service_extra_trusted_issuers) : trimspace(s) if trimspace(s) != ""
  ]

  # Comma-separated allowlist of trusted token issuers for pack BEs. In
  # standalone mode that's just this auth-service; integration deployments
  # add customer-controlled IdPs (Oracle IDCS, Microsoft Entra, etc.) via
  # var.auth_service_extra_trusted_issuers.
  auth_service_trusted_issuers = local.enable_auth_service ? join(",", concat(
    [local.auth_service_issuer_url],
    local.auth_service_trusted_issuers_extras_list
  )) : ""

  # OIDC env vars passed into the auth-service container. Each provider's
  # env is only emitted when (a) auth-service is on AND (b) that provider's
  # enable toggle is true. Empty omission is intentional — auth-service treats
  # an absent issuer_url / tenant_id as "provider disabled" without further
  # configuration.
  auth_service_oidc_env = local.enable_auth_service ? concat(
    var.enable_oracle_oidc_idcs ? [
      { key = "AUTH_OIDC_ORACLE_IDCS_ISSUER_URL", value = var.auth_oidc_oracle_idcs_issuer_url },
      { key = "AUTH_OIDC_ORACLE_IDCS_CLIENT_ID", value = var.auth_oidc_oracle_idcs_client_id },
      { key = "AUTH_OIDC_ORACLE_IDCS_CLIENT_SECRET", value = var.auth_oidc_oracle_idcs_client_secret },
    ] : [],
    var.enable_microsoft_entra_oidc ? [
      { key = "AUTH_OIDC_MICROSOFT_ENTRA_TENANT_ID", value = var.auth_oidc_microsoft_entra_tenant_id },
      { key = "AUTH_OIDC_MICROSOFT_ENTRA_CLIENT_ID", value = var.auth_oidc_microsoft_entra_client_id },
      { key = "AUTH_OIDC_MICROSOFT_ENTRA_CLIENT_SECRET", value = var.auth_oidc_microsoft_entra_client_secret },
    ] : []
  ) : []

  # Single auth-service deployment ready to splat into a pack's blueprint.
  # List shape (empty when disabled, single element when enabled) lets callers
  # `concat(existing_deployments, local.auth_service_recipe)` without ternary.
  auth_service_recipe = local.enable_auth_service ? [{
    name       = "auth-service"
    exports    = ["service_name"]
    depends_on = []
    recipe = {
      recipe_id                            = "auth-service"
      deployment_name                      = "auth-service"
      recipe_mode                          = "service"
      recipe_image_uri                     = local.auth_service_image_uri
      recipe_replica_count                 = 1
      recipe_flex_shape_ocpu_count         = 2
      recipe_flex_shape_memory_size_in_gbs = 8
      recipe_node_shape                    = local.starter_pack_config.cpu_worker_node_pool_instance_shape.instanceShape
      recipe_use_shared_node_pool          = true
      recipe_container_port                = "8080"
      # Suppress the auto-created Ingress for this recipe. The auth-service is
      # reached from browsers via the pack frontend's ingress (the /auth/* route
      # spliced into recipe_additional_ingress_ports) and from in-cluster
      # callers (pack BE JWKS fetches, JWT validation) via the cluster Service.
      # The dedicated auth-service ingress was a public surface for the admin
      # endpoints (/auth/users, /auth/audit, etc.) that does not need to exist;
      # per-route role checks in FastAPI are still in place as the primary
      # control.
      recipe_disable_ingress = true
      recipe_container_env = concat(
        [
          { key = "AUTH_ISSUER_URL", value = local.auth_service_issuer_url },
          { key = "AUTH_DATABASE_TYPE", value = "oracle" },
          { key = "AUTH_ORACLE_CONNECTION_STRING", value = local.oracle26ai_high_connection_string },
          { key = "AUTH_ORACLE_USER", value = var.db_username },
          { key = "AUTH_ORACLE_PASSWORD", value = local.db_password },
          { key = "AUTH_AUTO_ADMIN_FIRST_USER", value = "true" },
          # Pack-extensible RBAC selector (per accelerator-pack-auth-service
          # pack_models/). Default in the auth-service is "base"; we
          # explicitly pass the pack category here so each pack's RBAC
          # (admin/user/reader for cuopt; collection-RBAC for paas_rag, etc.)
          # seeds on first deploy.
          { key = "AUTH_PACK", value = var.starter_pack_category },
          { key = "AUTH_BCRYPT_ROUNDS", value = "12" },
          { key = "AUTH_ACCESS_TOKEN_EXPIRE_MINUTES", value = "15" },
          { key = "AUTH_REFRESH_TOKEN_EXPIRE_DAYS", value = "7" },
          # OAuth2 client_credentials grant (spec 002). Master switch on by
          # default; flip via var.enable_client_credentials_grant in tfvars to
          # disable issuance of new service-account tokens cluster-wide as an
          # incident-response containment lever. Token TTL and per-owner cap
          # follow the defaults documented in accelerator-pack-auth-service/CLAUDE.md.
          { key = "AUTH_CLIENT_CREDENTIALS_ENABLED", value = tostring(var.enable_client_credentials_grant) },
          { key = "AUTH_CLIENT_TOKEN_EXPIRE_MINUTES", value = "60" },
          { key = "AUTH_CLIENT_MAX_PER_OWNER", value = "20" },
          # Lenient (RFC 6749 §3.3) is the default — silent narrowing of mismatched
          # scope requests. To switch to strict mode (return 400 invalid_scope on any
          # unallowed scope), edit this literal to "true" and re-apply. Not a tfvars
          # knob — strict vs lenient is a behavioral preference, not an incident-
          # response containment lever like AUTH_CLIENT_CREDENTIALS_ENABLED.
          { key = "AUTH_STRICT_SCOPES", value = "false" },
          # CORS pin: only the pack frontend origin may make credentialed
          # cross-origin calls to /auth. AUTH_CORS_ORIGINS=="" (the default
          # in config.py) fails closed; we explicitly enumerate the FE origin
          # here. allow_credentials is auto-disabled by the middleware when
          # a wildcard is present in the list.
          { key = "AUTH_CORS_ORIGINS", value = "https://${local.public_endpoint.starter_pack}" },
          # Production mode: emit HSTS, disable OpenAPI docs surfaces. Set to
          # "true" only for in-cluster integration testing against a
          # self-signed cert where HSTS would lock the operator's browser
          # into refusing the host on the next visit.
          { key = "AUTH_DEBUG", value = "false" },
          # SSO redirect-URI allowlist base. /authorize requires the caller
          # to present redirect_uri == AUTH_SSO_REDIRECT_BASE_URL/sso/callback/{slug}.
          # Defense in depth on top of the IdP's own Redirect URL allowlist.
          { key = "AUTH_SSO_REDIRECT_BASE_URL", value = "https://${local.public_endpoint.starter_pack}" },
        ],
        local.auth_service_oidc_env
      )
    }
  }] : []

  # /auth ingress entry to splat into a pack frontend's recipe_additional_ingress_ports.
  auth_service_ingress_route = local.enable_auth_service ? [
    { port_name = "auth", service_name = "$${auth-service.service_name}", port = 8080, path = "/auth", path_type = "Prefix" },
  ] : []

  # Per-backend-ingress annotations that gate non-frontend recipes behind the
  # auth-service /auth/me check. Corrino's resolve_recipe_placeholders walks
  # the recipe and substitutes $${...} from the resolved_exports map of the
  # deployment group at activation time, so each recipe that references
  # $${auth-service.service_name} here lists "auth-service" in its depends_on
  # — see blueprint_files.tf (cuopt + llamastack) and cuopt-locals.tf
  # (cuopt-backend). The FQDN form is required: ingress-nginx runs in its own
  # namespace and short service names fail to resolve from there (nginx
  # returns 500 on the auth subrequest).
  backend_ingress_annotations = local.enable_auth_service ? {
    "nginx.ingress.kubernetes.io/auth-url"    = "http://$${auth-service.service_name}.default.svc.cluster.local/auth/me"
    "nginx.ingress.kubernetes.io/auth-method" = "GET"
  } : {}

  # Same map shaped for corrino's recipe_additional_ingress_annotations
  # (list of {key, value}).
  backend_ingress_annotations_corrino = [
    for k, v in local.backend_ingress_annotations : { key = k, value = v }
  ]

  # In-cluster JWKS fetch URL for the cuopt backend. The auth-service has no
  # ingress (recipe_disable_ingress=true above); pack BEs reach it via the
  # corrino-managed cluster Service. Going through the public ingress would
  # mean an extra hop and (in dev) a self-signed-cert TLS failure on JWKS
  # fetch. The token's `iss` claim still carries the public issuer URL —
  # only the fetch URL changes. Empty when auth is off.
  # Service port is 80 (corrino maps it to the container's 8080).
  auth_service_local_jwks_url = local.enable_auth_service ? "http://$${auth-service.service_name}/auth/.well-known/jwks.json" : ""

  # Env vars for the cuopt backend recipe. Splat into recipe_container_env via
  # concat. The CUOPT_AUTH_TRUSTED_ISSUERS list directs the backend at the
  # JWKS endpoints it should trust for token verification. CUOPT_AUTH_TOKEN_AUDIENCE
  # pins the expected `aud` claim — the auth-service stamps the active starter
  # pack category onto every minted token, so audience scoping is per-pack.
  # CUOPT_AUTH_LOCAL_{ISSUER,JWKS}_URL together short-circuit the public-ingress
  # JWKS fetch when the issuer is this co-located auth-service.
  cuopt_backend_auth_env = local.enable_auth_service ? [
    { key = "CUOPT_AUTH_TRUSTED_ISSUERS", value = local.auth_service_trusted_issuers },
    { key = "CUOPT_AUTH_JWKS_CACHE_TTL", value = tostring(var.auth_service_jwks_cache_ttl_seconds) },
    { key = "CUOPT_AUTH_TOKEN_AUDIENCE", value = var.starter_pack_category },
    { key = "CUOPT_AUTH_REQUIRE_AUTH", value = "true" },
    { key = "CUOPT_AUTH_LOCAL_ISSUER_URL", value = local.auth_service_issuer_url },
    { key = "CUOPT_AUTH_LOCAL_JWKS_URL", value = local.auth_service_local_jwks_url },
  ] : []
}
