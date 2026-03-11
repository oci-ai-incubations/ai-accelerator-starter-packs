# Variable validation tests -- each run block overrides exactly one variable
# with an invalid value and asserts the validation catches it via expect_failures.

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

  override_data {
    target = data.oci_generative_ai_models.genai_models
    values = {
      model_collection = [{
        items = [{
          id           = "ocid1.generativeaimodel.oc1..test"
          display_name = "meta.llama-4-maverick-17b-128e-instruct-fp8"
        }]
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
  starter_pack_category           = "enterprise_rag"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}

# --- Network configuration mode ---

# Test: invalid network_configuration_mode values are rejected by input validation
run "rejects_invalid_network_mode" {
  command = plan

  variables {
    network_configuration_mode = "invalid"
  }

  expect_failures = [var.network_configuration_mode]
}

# --- Cluster visibility ---

# Test: invalid cluster_workers_visibility values are rejected by input validation
run "rejects_invalid_cluster_workers_visibility" {
  command = plan

  variables {
    cluster_workers_visibility = "invalid"
  }

  expect_failures = [var.cluster_workers_visibility]
}

# Test: invalid cluster endpoint visibility for new VCN is rejected by input validation
run "rejects_invalid_cluster_endpoint_visibility_new_vcn" {
  command = plan

  variables {
    cluster_endpoint_visibility_new_vcn = "invalid"
  }

  expect_failures = [var.cluster_endpoint_visibility_new_vcn]
}

# Test: invalid cluster endpoint visibility for existing VCN is rejected by input validation
run "rejects_invalid_cluster_endpoint_visibility_existing_vcn" {
  command = plan

  variables {
    cluster_endpoint_visibility_existing_vcn = "invalid"
  }

  expect_failures = [var.cluster_endpoint_visibility_existing_vcn]
}

# --- Endpoint visibility ---

# Test: invalid blueprints_endpoint_visibility values are rejected by input validation
run "rejects_invalid_blueprints_endpoint_visibility" {
  command = plan

  variables {
    blueprints_endpoint_visibility = "invalid"
  }

  expect_failures = [var.blueprints_endpoint_visibility]
}

# Test: invalid apps_endpoint_visibility values are rejected by input validation
run "rejects_invalid_apps_endpoint_visibility" {
  command = plan

  variables {
    apps_endpoint_visibility = "invalid"
  }

  expect_failures = [var.apps_endpoint_visibility]
}

# --- Starter pack category and size ---

# Test: invalid starter_pack_category values are rejected by input validation
run "rejects_invalid_starter_pack_category" {
  command = plan

  variables {
    starter_pack_category = "invalid"
  }

  expect_failures = [var.starter_pack_category]
}

# Test: invalid starter_pack_size values are rejected by input validation
run "rejects_invalid_starter_pack_size" {
  command = plan

  variables {
    starter_pack_size = "invalid"
  }

  expect_failures = [var.starter_pack_size]
}

# --- Database password validations ---

# Test: database passwords shorter than the minimum length are rejected
run "rejects_short_db_password" {
  command = plan

  variables {
    db_password = "Short1!"
  }

  expect_failures = [var.db_password]
}

# Test: database passwords without an uppercase letter are rejected
run "rejects_db_password_without_uppercase" {
  command = plan

  variables {
    db_password = "alllowercase1!"
  }

  expect_failures = [var.db_password]
}

# Test: database passwords without a special character are rejected
run "rejects_db_password_without_special_char" {
  command = plan

  variables {
    db_password = "NoSpecialChar123"
  }

  expect_failures = [var.db_password]
}
