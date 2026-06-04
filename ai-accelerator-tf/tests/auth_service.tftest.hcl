# Tests for the optional accelerator-pack-auth-service integration.
# Validates var plumbing, RS256/JWKS env wiring, and that the auth-service
# deployment + /auth ingress route are conditionally injected into the cuopt
# blueprint when enable_auth_service is true.

mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = {
      regions = [{
        name = "us-ashburn-1"
        key  = "IAD"
      }]
    }
  }

  override_data {
    target = data.oci_identity_availability_domains.ads
    values = {
      availability_domains = [{
        name = "US-ASHBURN-AD-1"
      }]
    }
  }

  override_data {
    target = data.oci_core_images.oracle_linux
    values = {
      images = [{
        id = "ocid1.image.oc1..test"
      }]
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}
mock_provider "random" {}
mock_provider "http" {}

variables {
  tenancy_ocid                    = "ocid1.tenancy.oc1..test"
  compartment_ocid                = "ocid1.compartment.oc1..test"
  region                          = "us-ashburn-1"
  current_user_ocid               = "ocid1.user.oc1..test"
  corrino_admin_username          = "testadmin"
  corrino_admin_password          = "TestP@ssw0rd123!"
  corrino_admin_email             = "test@example.com"
  starter_pack_category           = "cuopt"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  db_password                     = "TestDBP@ssw0rd123!"
}

# Auth is MANDATORY for this workshop pack — hard-coded on via
# local.enable_auth_service = true (livelabs.tf). It is not a toggle: even
# setting var.enable_auth_service = false must NOT disable it. The
# auth-service deployment, its /auth ingress route, and the cuopt-backend auth
# env are always present. There is no supported "auth off" mode.
#
# Plan-time-safe assertions only — values that depend on apply-time resources
# (the 26ai connection string baked into the jsonencoded blueprint) cannot be
# evaluated here. The "auth-service always on" guarantee comes from the three
# list-length checks below.
run "plan_auth_forced_on_ignores_var_false" {
  command = plan

  # Try to turn auth off — the hard-coded local must ignore this.
  variables {
    enable_auth_service = false
  }

  assert {
    condition     = length(local.auth_service_recipe) == 1
    error_message = "auth is hard-coded on: auth_service_recipe must be present even when var.enable_auth_service=false"
  }

  assert {
    condition     = length(local.auth_service_ingress_route) == 1
    error_message = "auth is hard-coded on: auth_service_ingress_route must be present even when var.enable_auth_service=false"
  }

  assert {
    condition     = length(local.cuopt_backend_auth_env) > 0
    error_message = "auth is hard-coded on: cuopt_backend_auth_env must be populated even when var.enable_auth_service=false"
  }
}

# Flag on: cuopt blueprint contains the auth-service deployment, /auth ingress
# route is present on the frontend, AUTH_ISSUER_URL is non-empty.
# With both OIDC toggles off (default), no AUTH_OIDC_* envs.
run "plan_enabled_emits_issuer_url" {
  command = plan

  variables {
    enable_auth_service = true
  }

  assert {
    condition     = length(local.auth_service_recipe) == 1
    error_message = "auth_service_recipe should have one element when enable_auth_service is true"
  }

  assert {
    condition     = local.auth_service_recipe[0].name == "auth-service"
    error_message = "auth_service_recipe deployment name should be 'auth-service'"
  }

  assert {
    condition     = length(local.auth_service_ingress_route) == 1
    error_message = "auth_service_ingress_route should have one element when enable_auth_service is true"
  }

  assert {
    condition     = local.auth_service_ingress_route[0].path == "/auth"
    error_message = "auth_service_ingress_route path should be '/auth'"
  }

  assert {
    condition     = length(local.cuopt_backend_auth_env) == 6
    error_message = "cuopt_backend_auth_env should have CUOPT_AUTH_TRUSTED_ISSUERS, CUOPT_AUTH_JWKS_CACHE_TTL, CUOPT_AUTH_TOKEN_AUDIENCE, CUOPT_AUTH_REQUIRE_AUTH, CUOPT_AUTH_LOCAL_ISSUER_URL, CUOPT_AUTH_LOCAL_JWKS_URL"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_LOCAL_ISSUER_URL"
    ]) == 1
    error_message = "cuopt_backend_auth_env must include CUOPT_AUTH_LOCAL_ISSUER_URL"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_LOCAL_JWKS_URL"
    ]) == 1
    error_message = "cuopt_backend_auth_env must include CUOPT_AUTH_LOCAL_JWKS_URL"
  }

  # JWKS cache TTL env var is wired through from var.auth_service_jwks_cache_ttl_seconds
  # (default 3600). Only key presence is plan-time-evaluable here — env.value is
  # apply-time-unknown when any field on cuopt_backend_auth_env touches the
  # public_endpoint (which carries through to CUOPT_AUTH_TRUSTED_ISSUERS); the
  # default-value contract is locked by the JWKS-TTL validation tests below.
  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_JWKS_CACHE_TTL"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_JWKS_CACHE_TTL"
  }

  # Audience claim wiring: pack BE validates iss + aud + exp + signature, so TF
  # must pin the expected audience to the active pack category. Key presence
  # only (env.value is apply-time-unknown, see comment above).
  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_TOKEN_AUDIENCE"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_TOKEN_AUDIENCE"
  }

  # Auth-service env block contains AUTH_ISSUER_URL and not AUTH_JWT_SECRET.
  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_ISSUER_URL"
    ]) == 1
    error_message = "auth_service_recipe must include AUTH_ISSUER_URL in recipe_container_env"
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_JWT_SECRET"
    ]) == 0
    error_message = "auth_service_recipe must NOT include the legacy AUTH_JWT_SECRET env var"
  }

  # cuopt backend env contains CUOPT_AUTH_TRUSTED_ISSUERS, not CUOPT_AUTH_JWT_SECRET.
  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_TRUSTED_ISSUERS"
    ]) == 1
    error_message = "cuopt_backend_auth_env must include CUOPT_AUTH_TRUSTED_ISSUERS"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_JWT_SECRET"
    ]) == 0
    error_message = "cuopt_backend_auth_env must NOT include the legacy CUOPT_AUTH_JWT_SECRET env var"
  }

  # No OIDC env vars when both provider toggles are off.
  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if startswith(env.key, "AUTH_OIDC_")
    ]) == 0
    error_message = "auth_service_recipe must NOT include AUTH_OIDC_* env vars when both provider toggles are off"
  }

  # Total env count locks the auth-service recipe surface — accidental
  # additions/removals to recipe_container_env fail this assertion. Mirrors
  # the length() check on cuopt_backend_auth_env above. 14 base entries with
  # both OIDC toggles off: AUTH_ISSUER_URL, AUTH_DATABASE_TYPE,
  # AUTH_ORACLE_CONNECTION_STRING, AUTH_ORACLE_USER, AUTH_ORACLE_PASSWORD,
  # AUTH_AUTO_ADMIN_FIRST_USER, AUTH_PACK, AUTH_BCRYPT_ROUNDS,
  # AUTH_ACCESS_TOKEN_EXPIRE_MINUTES, AUTH_REFRESH_TOKEN_EXPIRE_DAYS,
  # AUTH_CLIENT_CREDENTIALS_ENABLED, AUTH_CLIENT_TOKEN_EXPIRE_MINUTES,
  # AUTH_CLIENT_MAX_PER_OWNER, AUTH_STRICT_SCOPES, AUTH_CORS_ORIGINS,
  # AUTH_DEBUG, AUTH_SSO_REDIRECT_BASE_URL.
  assert {
    condition     = length(local.auth_service_recipe[0].recipe.recipe_container_env) == 17
    error_message = "auth_service_recipe.recipe_container_env must have exactly 17 entries when both OIDC toggles are off"
  }

  # Spec 002: OAuth2 client_credentials env vars are emitted on every enabled
  # deploy. Key presence + value pinning — three exact keys, default values
  # match the auth-service Pydantic defaults.
  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_CLIENT_CREDENTIALS_ENABLED"
    ]) == 1
    error_message = "auth_service_recipe must include AUTH_CLIENT_CREDENTIALS_ENABLED"
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_CLIENT_TOKEN_EXPIRE_MINUTES"
    ]) == 1
    error_message = "auth_service_recipe must include AUTH_CLIENT_TOKEN_EXPIRE_MINUTES"
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_CLIENT_MAX_PER_OWNER"
    ]) == 1
    error_message = "auth_service_recipe must include AUTH_CLIENT_MAX_PER_OWNER"
  }

  assert {
    condition = [
      for env in local.auth_service_recipe[0].recipe.recipe_container_env :
      env.value
      if env.key == "AUTH_CLIENT_CREDENTIALS_ENABLED"
    ][0] == "true"
    error_message = "AUTH_CLIENT_CREDENTIALS_ENABLED must default to 'true'"
  }

  assert {
    condition = [
      for env in local.auth_service_recipe[0].recipe.recipe_container_env :
      env.value
      if env.key == "AUTH_CLIENT_TOKEN_EXPIRE_MINUTES"
    ][0] == "60"
    error_message = "AUTH_CLIENT_TOKEN_EXPIRE_MINUTES must default to '60'"
  }

  assert {
    condition = [
      for env in local.auth_service_recipe[0].recipe.recipe_container_env :
      env.value
      if env.key == "AUTH_CLIENT_MAX_PER_OWNER"
    ][0] == "20"
    error_message = "AUTH_CLIENT_MAX_PER_OWNER must default to '20'"
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if env.key == "AUTH_STRICT_SCOPES"
    ]) == 1
    error_message = "auth_service_recipe must include AUTH_STRICT_SCOPES"
  }

  assert {
    condition = [
      for env in local.auth_service_recipe[0].recipe.recipe_container_env :
      env.value
      if env.key == "AUTH_STRICT_SCOPES"
    ][0] == "false"
    error_message = "AUTH_STRICT_SCOPES must default to 'false'"
  }
}

# Both OIDC toggles on: all 6 AUTH_OIDC_* env vars are emitted.
run "plan_enabled_with_both_oidc_providers" {
  command = plan

  variables {
    enable_auth_service         = true
    enable_oracle_oidc_idcs     = true
    enable_microsoft_entra_oidc = true
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if startswith(env.key, "AUTH_OIDC_")
    ]) == 6
    error_message = "auth_service_recipe must include 6 AUTH_OIDC_* env vars (3 Oracle IDCS + 3 Microsoft Entra) when both toggles are on"
  }

  # Total env count: 17 base + 3 IDCS + 3 Entra = 23. Regression net for
  # accidental env additions/removals in either OIDC branch.
  assert {
    condition     = length(local.auth_service_recipe[0].recipe.recipe_container_env) == 23
    error_message = "auth_service_recipe.recipe_container_env must have exactly 23 entries when both OIDC toggles are on (17 base + 3 IDCS + 3 Entra)"
  }
}

# Oracle IDCS toggle only: 3 IDCS env vars, no Entra envs.
run "plan_enabled_with_oracle_oidc_only" {
  command = plan

  variables {
    enable_auth_service     = true
    enable_oracle_oidc_idcs = true
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if startswith(env.key, "AUTH_OIDC_ORACLE_IDCS_")
    ]) == 3
    error_message = "auth_service_recipe must include 3 AUTH_OIDC_ORACLE_IDCS_* env vars when enable_oracle_oidc_idcs=true"
  }

  assert {
    condition = length([
      for env in local.auth_service_recipe[0].recipe.recipe_container_env : env
      if startswith(env.key, "AUTH_OIDC_MICROSOFT_ENTRA_")
    ]) == 0
    error_message = "auth_service_recipe must NOT include AUTH_OIDC_MICROSOFT_ENTRA_* env vars when enable_microsoft_entra_oidc=false"
  }

  # Total env count: 17 base + 3 IDCS = 20. Regression net for accidental
  # env additions/removals in the single-OIDC branch.
  assert {
    condition     = length(local.auth_service_recipe[0].recipe.recipe_container_env) == 20
    error_message = "auth_service_recipe.recipe_container_env must have exactly 20 entries when only enable_oracle_oidc_idcs=true (17 base + 3 IDCS)"
  }
}

# Flag on with extra trusted issuers: cuopt_backend_auth_env carries
# CUOPT_AUTH_TRUSTED_ISSUERS exactly once; the bundled auth-service issuer
# concat()s with the user-supplied extras via local.auth_service_trusted_issuers.
# The full string value depends on local.public_endpoint.starter_pack (an
# apply-time computation), so we test structural shape instead of exact text.
run "plan_enabled_with_extra_trusted_issuers" {
  command = plan

  variables {
    enable_auth_service                = true
    auth_service_extra_trusted_issuers = "https://idcs.example.oraclecloud.com,https://login.microsoftonline.com/tenant"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_auth_env : env
      if env.key == "CUOPT_AUTH_TRUSTED_ISSUERS"
    ]) == 1
    error_message = "cuopt_backend_auth_env must include exactly one CUOPT_AUTH_TRUSTED_ISSUERS entry"
  }

  # Composition: each user-supplied extra issuer ends up in the sanitized
  # extras list. The fully-joined CUOPT_AUTH_TRUSTED_ISSUERS env value is
  # apply-time-unknown (the bundled auth-service issuer URL depends on
  # local.public_endpoint.starter_pack), but the extras list itself is
  # pure-input, so we assert on it directly.
  assert {
    condition     = length(local.auth_service_trusted_issuers_extras_list) == 2
    error_message = "auth_service_trusted_issuers_extras_list must contain both supplied issuers (got != 2)"
  }

  assert {
    condition     = local.auth_service_trusted_issuers_extras_list[0] == "https://idcs.example.oraclecloud.com"
    error_message = "first extras list entry must be the IDCS issuer URL verbatim"
  }

  assert {
    condition     = local.auth_service_trusted_issuers_extras_list[1] == "https://login.microsoftonline.com/tenant"
    error_message = "second extras list entry must be the Entra issuer URL verbatim"
  }
}

# Whitespace + trailing-comma sanitization: extras with stray surrounding
# whitespace and a trailing comma yield a clean list — no empty entries,
# no whitespace-padded entries. Trims happen before the join.
run "plan_enabled_extras_sanitize_whitespace_and_trailing_comma" {
  command = plan

  variables {
    enable_auth_service                = true
    auth_service_extra_trusted_issuers = "  https://idcs.example.oraclecloud.com  ,https://login.microsoftonline.com/tenant,"
  }

  # Trailing comma + surrounding whitespace must still yield exactly two
  # entries (the empty third element from the trailing comma is dropped).
  assert {
    condition     = length(local.auth_service_trusted_issuers_extras_list) == 2
    error_message = "Trailing comma must not produce an empty extras-list entry"
  }

  # Surrounding whitespace must be stripped before list inclusion.
  assert {
    condition     = local.auth_service_trusted_issuers_extras_list[0] == "https://idcs.example.oraclecloud.com"
    error_message = "Surrounding whitespace must be stripped from each extras entry"
  }
}

# Validation: http:// scheme is rejected — an http:// JWKS URL would be a
# silent MITM hazard.
run "rejects_http_trusted_issuer" {
  command = plan

  variables {
    auth_service_extra_trusted_issuers = "http://insecure.example.com"
  }

  expect_failures = [var.auth_service_extra_trusted_issuers]
}

# Validation: malformed (no scheme) issuer is rejected.
run "rejects_malformed_trusted_issuer" {
  command = plan

  variables {
    auth_service_extra_trusted_issuers = "idcs.example.com"
  }

  expect_failures = [var.auth_service_extra_trusted_issuers]
}

# Validation: an issuer URL with embedded whitespace is rejected even when
# the trimmed leading characters spell `https://`.
run "rejects_trusted_issuer_with_internal_whitespace" {
  command = plan

  variables {
    auth_service_extra_trusted_issuers = "https://example.com /trailing"
  }

  expect_failures = [var.auth_service_extra_trusted_issuers]
}

# Validation: empty string is the default and must remain valid.
run "accepts_empty_extra_trusted_issuers" {
  command = plan

  variables {
    auth_service_extra_trusted_issuers = ""
  }

  assert {
    condition     = var.auth_service_extra_trusted_issuers == ""
    error_message = "Empty string must remain a valid value for auth_service_extra_trusted_issuers"
  }
}

# JWKS cache TTL validation: rejects too-low values (< 60s).
run "rejects_jwks_cache_ttl_below_minimum" {
  command = plan

  variables {
    auth_service_jwks_cache_ttl_seconds = 30
  }

  expect_failures = [var.auth_service_jwks_cache_ttl_seconds]
}

# JWKS cache TTL validation: rejects too-high values (> 86400s = 24h).
run "rejects_jwks_cache_ttl_above_maximum" {
  command = plan

  variables {
    auth_service_jwks_cache_ttl_seconds = 100000
  }

  expect_failures = [var.auth_service_jwks_cache_ttl_seconds]
}

# Spec 002 master switch: when enable_client_credentials_grant=false (the
# incident-response containment lever), AUTH_CLIENT_CREDENTIALS_ENABLED is
# emitted as "false" so the auth-service refuses to mint new service-account
# tokens. Default-true path is covered by the value assertion in
# plan_enabled_emits_issuer_url above.
run "plan_enabled_client_credentials_disabled" {
  command = plan

  variables {
    enable_auth_service             = true
    enable_client_credentials_grant = false
  }

  assert {
    condition = [
      for env in local.auth_service_recipe[0].recipe.recipe_container_env :
      env.value
      if env.key == "AUTH_CLIENT_CREDENTIALS_ENABLED"
    ][0] == "false"
    error_message = "AUTH_CLIENT_CREDENTIALS_ENABLED must be 'false' when enable_client_credentials_grant=false"
  }
}

# Image tag validation: 'latest' is rejected.
run "rejects_latest_auth_service_image" {
  command = plan

  variables {
    auth_service_image_version = "latest"
  }

  expect_failures = [var.auth_service_image_version]
}

# Image tag validation: empty is rejected.
run "rejects_empty_auth_service_image" {
  command = plan

  variables {
    auth_service_image_version = ""
  }

  expect_failures = [var.auth_service_image_version]
}
