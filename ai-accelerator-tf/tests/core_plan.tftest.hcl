# Core plan test -- validates the default configuration plans successfully
# and deterministic outputs resolve to expected values.

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
  starter_pack_category           = "enterprise_rag"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  db_password                     = "TestDBP@ssw0rd123!"
}

# Test: default configuration plans successfully and deterministic outputs resolve to expected values
run "plan_succeeds_with_defaults" {
  command = plan

  # Default VCN CIDR should match the standard network range
  assert {
    condition     = output.vcn_cidr == "10.0.0.0/16"
    error_message = "VCN CIDR should match default network_cidrs"
  }

  # New VCN deployments should default to a public cluster endpoint
  assert {
    condition     = output.cluster_endpoint_visibility == "Public"
    error_message = "Default endpoint visibility should be Public for new VCN"
  }

  # Admin username should pass through from the input variable unchanged
  assert {
    condition     = output.corrino_admin_username == "testadmin"
    error_message = "Admin username output should pass through variable"
  }

  # Admin email should pass through from the input variable unchanged
  assert {
    condition     = output.corrino_admin_email == "test@example.com"
    error_message = "Admin email output should pass through variable"
  }

  # Database username should default to ADMIN when not explicitly set
  assert {
    condition     = output.db_username == "ADMIN"
    error_message = "DB username should use default value"
  }
}

# Test: create_policies=false skips policy resource creation
run "plan_succeeds_with_create_policies_false" {
  command = plan

  variables {
    create_policies = false
  }

  assert {
    condition     = length(oci_identity_dynamic_group.dyn_group) == 0
    error_message = "dyn_group should not be created when create_policies is false"
  }

  assert {
    condition     = length(oci_identity_policy.oke_instances_tenancy_policy) == 0
    error_message = "oke_instances_tenancy_policy should not be created when create_policies is false"
  }
}
