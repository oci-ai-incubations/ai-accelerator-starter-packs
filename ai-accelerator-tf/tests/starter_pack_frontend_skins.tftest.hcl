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
  assert {
    condition     = local.primary_skin.key == "Vehicle Route Optimizer Frontend (Core App)"
    error_message = "cuopt primary should be Core App"
  }
  assert {
    condition     = length(local.enabled_frontend_skins) == 1
    error_message = "cuopt default should have 1 enabled skin"
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

# ===================== vss ============================================

run "vss_default_skin_resolves" {
  command = plan
  variables {
    starter_pack_category = "vss"
  }
  assert {
    condition     = local.primary_skin.variable_name == "skin_vss_core"
    error_message = "vss primary = Core"
  }
  assert {
    condition     = length(local.enabled_frontend_skins) == 1
    error_message = "vss has 1 enabled skin"
  }
}

run "vss_zero_skins_fails" {
  command = plan
  variables {
    starter_pack_category = "vss"
    skin_vss_core         = false
  }
  expect_failures = [resource.terraform_data.skin_validation]
}

# ===================== paas_rag =======================================

run "paas_rag_default_skin_resolves" {
  command = plan
  variables {
    starter_pack_category = "paas_rag"
    db_password           = "TestDBP@ssw0rd123!"
  }
  assert {
    condition     = local.primary_skin.variable_name == "skin_paas_rag_core"
    error_message = "paas_rag primary = Core"
  }
}

run "paas_rag_zero_skins_fails" {
  command = plan
  variables {
    starter_pack_category = "paas_rag"
    skin_paas_rag_core    = false
    db_password           = "TestDBP@ssw0rd123!"
  }
  expect_failures = [resource.terraform_data.skin_validation]
}

# ===================== Helm packs =====================================

run "enterprise_rag_helm_pack_unaffected" {
  command = plan
  variables {
    starter_pack_category = "enterprise_rag"
    db_password           = "TestDBP@ssw0rd123!"
  }
  # primary_skin is null for Helm packs; back-compat locals fall back to catalog default
  assert {
    condition     = local.primary_skin == null
    error_message = "Helm pack primary_skin must be null"
  }
  assert {
    condition     = local.frontend_skin_image_uri != null
    error_message = "back-compat image_uri must be set via catalog default"
  }
  assert {
    condition     = local.frontend_skin_name == "Oracle RAG - Document chat (Core App)"
    error_message = "back-compat frontend_skin_name must resolve from catalog default"
  }
  assert {
    condition     = length(output.frontend_skin_urls) == 0
    error_message = "Helm pack frontend_skin_urls must be {}"
  }
  assert {
    condition     = output.starter_pack_url != null
    error_message = "Helm pack starter_pack_url must be set"
  }
  assert {
    condition     = can(regex("^frontend-erag\\.", output.starter_pack_url))
    error_message = "enterprise_rag starter_pack_url should begin with frontend-erag."
  }
}

run "enterprise_rag_aiq_helm_pack_unaffected" {
  command = plan
  variables {
    starter_pack_category = "enterprise_rag_aiq"
    tavily_api_key        = ""
    db_password           = "TestDBP@ssw0rd123!"
  }
  assert {
    condition     = local.primary_skin == null
    error_message = "Helm pack primary_skin must be null"
  }
  assert {
    condition     = local.frontend_skin_image_uri != null
    error_message = "back-compat image_uri must be set"
  }
  assert {
    condition     = local.frontend_skin_name == "NVIDIA AIRA - Agentic workflows (Core App)"
    error_message = "back-compat frontend_skin_name must resolve from catalog default"
  }
  assert {
    condition     = length(output.frontend_skin_urls) == 0
    error_message = "aiq frontend_skin_urls must be {}"
  }
  assert {
    condition     = can(regex("^aiq\\.", output.starter_pack_url))
    error_message = "aiq starter_pack_url should begin with aiq."
  }
}

# Test: warehouse_pick_path default skin resolves to Core App
run "warehouse_pick_path_default_skin_resolves" {
  command = plan

  variables {
    starter_pack_category = "warehouse_pick_path"
    db_password           = "TestDBP@ssw0rd123!"
  }

  assert {
    condition     = local.frontend_skin_name == "Warehouse Pick Path Optimizer Frontend (Core App)"
    error_message = "warehouse_pick_path default skin name should be 'Warehouse Pick Path Optimizer Frontend (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "warehouse_pick_path default skin image_uri should not be empty"
  }

  assert {
    condition     = local.frontend_skin_provider == "Oracle"
    error_message = "warehouse_pick_path default skin provider should be 'Oracle'"
  }
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
