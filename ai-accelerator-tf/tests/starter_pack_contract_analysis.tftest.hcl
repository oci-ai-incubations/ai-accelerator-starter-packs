# Contract Analysis starter pack test
# Dynamic URL path (blueprint_file != "").
# Supplies db_password for 26ai.tf and dac_billing_acknowledgement for GenAI DAC.

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
  starter_pack_category           = "contract_analysis"
  db_password                     = "TestDBP@ssw0rd123!"
  dac_billing_acknowledgement     = true
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}

# Test: contract_analysis starter pack plans successfully with correct deployment name, DB defaults, and registration triggers
run "plan_contract_analysis_small" {
  command = plan

  # Config deployment name should be the base name (output includes random_id hex suffix, unknown at plan time)
  assert {
    condition     = local.starter_pack_config.deployment_name == "contract-analysis"
    error_message = "contract_analysis config deployment name should be 'contract-analysis'"
  }

  # Database username should default to ADMIN when not explicitly set
  assert {
    condition     = output.db_username == "ADMIN"
    error_message = "DB username should use default value"
  }

  # Postflight registration trigger should record the selected starter pack category
  assert {
    condition     = null_resource.postflight_registration[0].triggers.starter_pack_category == "contract_analysis"
    error_message = "postflight trigger should capture starter pack category"
  }

  # Postflight registration trigger should record the deployment region
  assert {
    condition     = null_resource.postflight_registration[0].triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }
}
