# Multi-skin frontend resolution tests.

mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = { regions = [{ name = "us-ashburn-1", key = "IAD" }] }
  }
  override_data {
    target = data.oci_identity_availability_domains.ads
    values = { availability_domains = [{ name = "US-ASHBURN-AD-1" }] }
  }
  override_data {
    target = data.oci_core_images.oracle_linux
    values = { images = [{ id = "ocid1.image.oc1..test" }] }
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
}

# ===================== cuopt ==========================================

run "cuopt_default_skin_resolves" {
  command = plan
  # LiveLabs default: partner skin on, core skin off.
  assert {
    condition     = local.primary_skin.variable_name == "skin_cuopt_partner"
    error_message = "cuopt default primary should be the partner skin"
  }
  assert {
    condition     = length(local.enabled_frontend_skins) == 1
    error_message = "cuopt default should have 1 enabled skin (partner)"
  }
  assert {
    condition     = length(output.frontend_skin_urls) == 1
    error_message = "frontend_skin_urls should have 1 entry"
  }
}

run "cuopt_multi_skin" {
  command = plan
  variables {
    skin_cuopt_core    = true
    skin_cuopt_partner = true
  }
  assert {
    condition     = length(local.enabled_frontend_skins) == 2
    error_message = "cuopt multi should have 2 skins"
  }
  assert {
    condition     = local.primary_skin.key == "Vehicle Route Optimizer Frontend (Core App)"
    error_message = "primary = first enabled = Core"
  }
  assert {
    condition     = local.enabled_frontend_skins[0].container_port == "80"
    error_message = "cuopt core skin nginx image listens on 80"
  }
  assert {
    condition     = local.enabled_frontend_skins[1].container_port == "80"
    error_message = "cuopt partner skin should expose nginx on 80"
  }
  assert {
    condition = alltrue([
      for deployment in local._cuopt_frontend_deployments :
      !contains([for env_pair in deployment.recipe.recipe_container_env : env_pair.key], "PORT")
    ])
    error_message = "cuopt frontend deployments must not inject PORT; image-local defaults control internal listeners"
  }
  assert {
    condition     = length(output.frontend_skin_urls) == 2
    error_message = "frontend_skin_urls should have 2 entries"
  }
}

run "cuopt_partner_only" {
  command = plan
  variables {
    skin_cuopt_core    = false
    skin_cuopt_partner = true
  }
  assert {
    condition     = length(local.enabled_frontend_skins) == 1
    error_message = "1 skin enabled"
  }
  assert {
    condition     = local.primary_skin.variable_name == "skin_cuopt_partner"
    error_message = "primary = partner"
  }
}

run "cuopt_zero_skins_fails" {
  command = plan
  variables {
    skin_cuopt_core    = false
    skin_cuopt_partner = false
  }
  expect_failures = [resource.terraform_data.skin_validation]
}


# ===================== deploy_application=false =======================

run "infra_only_skips_precondition" {
  command = plan
  variables {
    deploy_application = false
    skin_cuopt_core    = false
    skin_cuopt_partner = false
  }
  # Precondition resource has count = 0; no failure even with zero skins.
  assert {
    condition     = length(output.frontend_skin_urls) == 0
    error_message = "infra-only frontend_skin_urls must be {}"
  }
  assert {
    condition     = output.starter_pack_url == null
    error_message = "infra-only starter_pack_url must be null (matches existing starter_pack_infra_only behavior)"
  }
}
