# Frontend skins resolution tests
# Validates that each starter pack category resolves to the correct default skin,
# and that explicit skin overrides work correctly.

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
}

# Test: cuopt default skin resolves to Core App
run "cuopt_default_skin_resolves" {
  command = plan

  assert {
    condition     = local.frontend_skin_name == "Vehicle Route Optimizer Frontend (Core App)"
    error_message = "cuopt default skin name should be 'Vehicle Route Optimizer Frontend (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "cuopt default skin image_uri should not be empty"
  }

  assert {
    condition     = local.frontend_skin_provider == "Oracle"
    error_message = "cuopt default skin provider should be 'Oracle'"
  }
}

# Test: cuopt explicit Partner Contributed skin override resolves correctly
run "cuopt_explicit_partner_skin" {
  command = plan

  variables {
    frontend_skin = "Oracle Interactive - Route visualization (Partner Contributed)"
  }

  assert {
    condition     = local.frontend_skin_name == "Oracle Interactive - Route visualization (Partner Contributed)"
    error_message = "cuopt partner skin name should match selection"
  }

  assert {
    condition     = local.frontend_skin_provider == "Oracle"
    error_message = "cuopt partner skin provider should be 'Oracle'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "cuopt partner skin image_uri should not be empty"
  }
}

# Test: vss default skin resolves to Oracle Custom
run "vss_default_skin_resolves" {
  command = plan

  variables {
    starter_pack_category = "vss"
  }

  assert {
    condition     = local.frontend_skin_name == "Oracle Custom - Enhanced search (Core App)"
    error_message = "vss default skin name should be 'Oracle Custom - Enhanced search (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "vss default skin image_uri should not be empty"
  }

  assert {
    condition     = local.frontend_skin_provider == "Oracle"
    error_message = "vss default skin provider should be 'Oracle'"
  }
}

# Test: paas_rag default skin resolves to Oracle Net
run "paas_rag_default_skin_resolves" {
  command = plan

  variables {
    starter_pack_category = "paas_rag"
    db_password           = "TestDBP@ssw0rd123!"
  }

  assert {
    condition     = local.frontend_skin_name == "Oracle Net - Chat interface (Core App)"
    error_message = "paas_rag default skin name should be 'Oracle Net - Chat interface (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "paas_rag default skin image_uri should not be empty"
  }
}

# Test: enterprise_rag default skin resolves to Oracle RAG
run "enterprise_rag_default_skin_resolves" {
  command = plan

  variables {
    starter_pack_category = "enterprise_rag"
    db_password           = "TestDBP@ssw0rd123!"
  }

  assert {
    condition     = local.frontend_skin_name == "Oracle RAG - Document chat (Core App)"
    error_message = "enterprise_rag default skin name should be 'Oracle RAG - Document chat (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "enterprise_rag default skin image_uri should not be empty"
  }
}

# Test: enterprise_rag_aiq default skin resolves to NVIDIA AIRA
run "enterprise_rag_aiq_default_skin_resolves" {
  command = plan

  variables {
    starter_pack_category = "enterprise_rag_aiq"
    tavily_api_key        = ""
  }

  assert {
    condition     = local.frontend_skin_name == "NVIDIA AIRA - Agentic workflows (Core App)"
    error_message = "enterprise_rag_aiq default skin name should be 'NVIDIA AIRA - Agentic workflows (Core App)'"
  }

  assert {
    condition     = local.frontend_skin_image_uri != ""
    error_message = "enterprise_rag_aiq default skin image_uri should not be empty"
  }

  assert {
    condition     = local.frontend_skin_provider == "NVIDIA"
    error_message = "enterprise_rag_aiq default skin provider should be 'NVIDIA'"
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

# Test: skin outputs are populated when deploy_application is true (default)
run "skin_outputs_populated" {
  command = plan

  assert {
    condition     = output.frontend_skin_name != null
    error_message = "frontend_skin_name output should not be null"
  }

  assert {
    condition     = output.frontend_skin_image_uri != null
    error_message = "frontend_skin_image_uri output should not be null"
  }

  assert {
    condition     = output.frontend_skin_provider != null
    error_message = "frontend_skin_provider output should not be null"
  }

  assert {
    condition     = output.frontend_skins_learn_more != ""
    error_message = "frontend_skins_learn_more output should not be empty"
  }
}
