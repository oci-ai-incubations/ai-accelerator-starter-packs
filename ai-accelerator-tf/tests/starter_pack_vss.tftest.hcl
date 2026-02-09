# VSS starter pack test
# Dynamic URL path (use_dynamic_url = true).

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
  starter_pack_category           = "vss"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}

run "plan_vss_small" {
  command = plan

  assert {
    condition     = output.starter_pack_deployment_name == "vss"
    error_message = "vss deployment name should be 'vss'"
  }

  # Registration trigger assertions
  assert {
    condition     = null_resource.postflight_registration.triggers.starter_pack_category == "vss"
    error_message = "postflight trigger should capture starter pack category"
  }

  assert {
    condition     = null_resource.postflight_registration.triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }


}
