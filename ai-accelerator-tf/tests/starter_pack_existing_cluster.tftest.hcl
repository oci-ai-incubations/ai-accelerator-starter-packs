# Existing cluster mode tests -- validates that providing existing_cluster_id
# skips infrastructure creation and validates OCID format.

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
    target = data.oci_containerengine_cluster_kube_config.oke_kube_config
    values = {
      content = "mock-kubeconfig-content"
    }
  }

  override_data {
    target = data.oci_containerengine_cluster_kube_config.oke
    values = {
      content = "mock-kubeconfig-content"
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
  tenancy_ocid                     = "ocid1.tenancy.oc1..test"
  compartment_ocid                 = "ocid1.compartment.oc1..test"
  region                           = "us-ashburn-1"
  current_user_ocid                = "ocid1.user.oc1..test"
  corrino_admin_username           = "testadmin"
  corrino_admin_password           = "TestP@ssw0rd123!"
  corrino_admin_email              = "test@example.com"
  starter_pack_category            = "cuopt"
  worker_node_availability_domain  = "US-ASHBURN-AD-1"
  skip_capacity_check              = true
  existing_cluster_id              = "ocid1.cluster.oc1.us-ashburn-1.testcluster"
  db_password                      = "TestDbP@ssw0rd123!"
  existing_autonomous_db_subnet_id = "ocid1.subnet.oc1..testdbsubnet"
}

# Test: existing cluster mode should not output a node_pool_id
run "existing_cluster_skips_node_pool" {
  command = plan

  assert {
    condition     = output.node_pool_id == null
    error_message = "Existing cluster mode should not output node_pool_id"
  }
}

# Test: invalid existing_cluster_id OCID format is rejected by input validation
run "rejects_invalid_cluster_ocid" {
  command = plan

  variables {
    existing_cluster_id = "not-a-valid-ocid"
  }

  expect_failures = [var.existing_cluster_id]
}

# Test: existing cluster with private endpoints correctly disables readiness_via_operator
# (operator instance doesn't exist when deploy_infrastructure=false)
run "existing_cluster_private_disables_operator_readiness" {
  command = plan

  variables {
    deploy_private_k8s_and_loadbalancer = true
    blueprints_endpoint_visibility      = "Private"
  }

  assert {
    condition     = !local.deploy_infrastructure
    error_message = "deploy_infrastructure should be false when existing_cluster_id is set"
  }

  assert {
    condition     = !local.readiness_via_operator
    error_message = "readiness_via_operator should be false when deploy_infrastructure is false (no operator instance exists)"
  }
}

# Test: existing cluster resolves autonomous_db_subnet_id from the existing variable
run "existing_cluster_uses_existing_autonomous_db_subnet" {
  command = plan

  assert {
    condition     = output.autonomous_db_subnet_id == "ocid1.subnet.oc1..testdbsubnet"
    error_message = "autonomous_db_subnet_id should resolve to existing_autonomous_db_subnet_id for existing clusters"
  }
}
