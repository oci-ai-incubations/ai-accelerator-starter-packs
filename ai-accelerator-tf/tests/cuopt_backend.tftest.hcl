# Tests for the cuopt-ev-routing-backend deployment recipe and its /api ingress
# route on the cuopt frontend. Recipe is unconditional for the cuopt category.

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

# Recipe is unconditional: present whether auth is on or off.
run "plan_default_includes_cuopt_backend" {
  command = plan

  assert {
    condition     = length(local.cuopt_backend_recipe) == 1
    error_message = "cuopt_backend_recipe should always have one element for the cuopt category"
  }

  assert {
    condition     = local.cuopt_backend_recipe[0].name == "cuopt-backend"
    error_message = "cuopt_backend_recipe deployment name should be 'cuopt-backend'"
  }

  assert {
    condition     = local.cuopt_backend_recipe[0].recipe.recipe_container_port == "8080"
    error_message = "cuopt-backend container port should be 8080"
  }

  assert {
    condition     = !strcontains(local.cuopt_backend_recipe[0].recipe.recipe_image_uri, ":latest")
    error_message = "cuopt-backend image URI must NEVER use :latest tag"
  }

  assert {
    condition     = strcontains(local.cuopt_backend_recipe[0].recipe.recipe_image_uri, "cuopt-ev-routing-backend:")
    error_message = "cuopt-backend image URI should reference cuopt-ev-routing-backend"
  }

  assert {
    condition     = length(local.cuopt_backend_ingress_route) == 1
    error_message = "cuopt_backend_ingress_route should have one element"
  }

  assert {
    condition     = local.cuopt_backend_ingress_route[0].path == "/api"
    error_message = "cuopt_backend_ingress_route path should be '/api'"
  }

  assert {
    condition     = local.cuopt_backend_ingress_route[0].port == 8080
    error_message = "cuopt_backend_ingress_route port should be 8080"
  }

  # Base env: CUOPT_CUOPT_ENDPOINT, CUOPT_LLAMASTACK_ENDPOINT,
  # CUOPT_LLAMASTACK_MODEL, CUOPT_GOOGLE_MAPS_API_KEY,
  # CUOPT_OPENWEATHERMAP_API_KEY, PORT, CUOPT_TLS_VERIFY = 7 entries;
  # auth env adds 0 when off.
  assert {
    condition     = length(local.cuopt_backend_base_env) == 7
    error_message = "cuopt_backend_base_env should have 7 entries when auth is off"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_CUOPT_ENDPOINT"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_CUOPT_ENDPOINT (env_prefix CUOPT_ + field cuopt_endpoint)"
  }

  # Structural assertions (don't evaluate the jsonencoded blueprint string —
  # it depends on the 26ai connection string which is unknown until apply
  # now that cuopt is in needs_26ai).
  assert {
    condition     = local.cuopt_backend_recipe[0].name == "cuopt-backend"
    error_message = "cuopt-backend recipe must be present and named correctly"
  }

  assert {
    condition     = local.cuopt_backend_ingress_route[0].path == "/api"
    error_message = "cuopt-backend ingress route must be /api"
  }
}

# When auth is on, the cuopt-backend recipe gains the CUOPT_AUTH_* env vars.
run "plan_auth_on_adds_cuopt_auth_envs" {
  command = plan

  variables {
    enable_auth_service = true
  }

  # base 7 + auth 6 = 13
  assert {
    condition     = length(local.cuopt_backend_recipe[0].recipe.recipe_container_env) == 13
    error_message = "cuopt-backend container env should have base 7 + auth 6 = 13 entries when auth is on"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_TRUSTED_ISSUERS"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_TRUSTED_ISSUERS when auth is on"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_TOKEN_AUDIENCE"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_TOKEN_AUDIENCE when auth is on"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_LOCAL_ISSUER_URL"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_LOCAL_ISSUER_URL when auth is on"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_LOCAL_JWKS_URL"
    ]) == 1
    error_message = "cuopt-backend env must include CUOPT_AUTH_LOCAL_JWKS_URL when auth is on"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_JWT_SECRET"
    ]) == 0
    error_message = "cuopt-backend env must NOT include the legacy CUOPT_AUTH_JWT_SECRET env var"
  }
}

# Auth is hard-coded on for this pack (local.enable_auth_service = true in
# livelabs.tf). Setting var.enable_auth_service = false must NOT disable it —
# the local-override env vars are still present. There is no "auth off" mode.
run "plan_auth_forced_on_ignores_var_false" {
  command = plan

  variables {
    enable_auth_service = false
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_LOCAL_ISSUER_URL"
    ]) == 1
    error_message = "auth is hard-coded on: cuopt-backend env must still include CUOPT_AUTH_LOCAL_ISSUER_URL even when var.enable_auth_service=false"
  }

  assert {
    condition = length([
      for env in local.cuopt_backend_recipe[0].recipe.recipe_container_env : env
      if env.key == "CUOPT_AUTH_LOCAL_JWKS_URL"
    ]) == 1
    error_message = "auth is hard-coded on: cuopt-backend env must still include CUOPT_AUTH_LOCAL_JWKS_URL even when var.enable_auth_service=false"
  }
}

# Image tag validation: 'latest' is rejected.
run "rejects_latest_image_tag" {
  command = plan

  variables {
    cuopt_backend_image_version = "latest"
  }

  expect_failures = [var.cuopt_backend_image_version]
}

# Image tag validation: empty is rejected.
run "rejects_empty_image_tag" {
  command = plan

  variables {
    cuopt_backend_image_version = ""
  }

  expect_failures = [var.cuopt_backend_image_version]
}
