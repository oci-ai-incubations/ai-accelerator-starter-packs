# Warehouse Pick Path Optimizer starter pack test
# Hybrid GPU + CPU + 26ai path (use_dynamic_url = true).
# Supplies db_password to satisfy the 26ai.tf lifecycle precondition.

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
  starter_pack_category           = "warehouse_pick_path"
  db_password                     = "TestDBP@ssw0rd123!"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}

# Test: warehouse_pick_path starter pack plans successfully with correct deployment name, DB defaults, and registration triggers
run "plan_warehouse_pick_path_small" {
  command = plan

  # Deployment name should start with the short form of the starter pack category (suffixed with random_id hex)
  assert {
    condition     = startswith(output.starter_pack_deployment_name, "wpp-")
    error_message = "warehouse_pick_path deployment name should start with 'wpp-'"
  }

  # Database username should default to ADMIN when not explicitly set
  assert {
    condition     = output.db_username == "ADMIN"
    error_message = "DB username should use default value"
  }

  # Postflight registration trigger should record the selected starter pack category
  assert {
    condition     = null_resource.postflight_registration.triggers.starter_pack_category == "warehouse_pick_path"
    error_message = "postflight trigger should capture starter pack category"
  }

  # Postflight registration trigger should record the deployment region
  assert {
    condition     = null_resource.postflight_registration.triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }
}
