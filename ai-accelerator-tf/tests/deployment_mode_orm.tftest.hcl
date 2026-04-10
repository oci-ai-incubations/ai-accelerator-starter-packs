# Deployment mode tests -- validates ORM deployment mode configuration
# Tests that deploy_private_k8s_and_loadbalancer=true with various endpoint configurations plans successfully.

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
  db_password                     = "TestDBP@ssw0rd1"
}

# Test: deploy_private_k8s_and_loadbalancer=true with public endpoint plans successfully (no ORM PE needed)
run "plan_orm_public_endpoint" {
  command = plan

  variables {
    deploy_private_k8s_and_loadbalancer = true
    cluster_endpoint_visibility_new_vcn = "Public"
    blueprints_endpoint_visibility      = "Public"
  }

  assert {
    condition     = output.cluster_endpoint_visibility == "Public"
    error_message = "Endpoint visibility should be Public"
  }
}

# Test: deploy_private_k8s_and_loadbalancer=true with private K8s endpoint forces bastion/operator creation
run "plan_orm_private_endpoint" {
  command = plan

  variables {
    deploy_private_k8s_and_loadbalancer = true
    cluster_endpoint_visibility_new_vcn = "Private"
    blueprints_endpoint_visibility      = "Private"
  }

  assert {
    condition     = output.cluster_endpoint_visibility == "Private"
    error_message = "Endpoint visibility should be Private"
  }

  # Bastion and operator should be planned when ORM + private endpoint
  assert {
    condition     = length(oci_core_instance.bastion) == 1
    error_message = "Bastion should be created when deploy_private_k8s_and_loadbalancer=true and endpoint is Private"
  }

  assert {
    condition     = length(oci_core_instance.operator) == 1
    error_message = "Operator should be created when deploy_private_k8s_and_loadbalancer=true and endpoint is Private"
  }

  # ORM Private Endpoint should be planned
  assert {
    condition     = length(oci_resourcemanager_private_endpoint.oke) == 1
    error_message = "ORM Private Endpoint should be created when deploy_private_k8s_and_loadbalancer=true and endpoint is Private"
  }
}

# Test: deploy_private_k8s_and_loadbalancer=true with private LB but public K8s endpoint forces bastion for readiness
run "plan_orm_private_lb" {
  command = plan

  variables {
    deploy_private_k8s_and_loadbalancer = true
    cluster_endpoint_visibility_new_vcn = "Public"
    blueprints_endpoint_visibility      = "Private"
  }

  assert {
    condition     = output.cluster_endpoint_visibility == "Public"
    error_message = "Endpoint visibility should be Public"
  }

  # Bastion should be created for readiness via operator even with public K8s endpoint
  assert {
    condition     = length(oci_core_instance.bastion) == 1
    error_message = "Bastion should be created when deploy_private_k8s_and_loadbalancer=true and LB is Private"
  }

  assert {
    condition     = length(oci_core_instance.operator) == 1
    error_message = "Operator should be created when deploy_private_k8s_and_loadbalancer=true and LB is Private"
  }

  # ORM PE should NOT be created since K8s endpoint is public
  assert {
    condition     = length(oci_resourcemanager_private_endpoint.oke) == 0
    error_message = "ORM Private Endpoint should NOT be created when K8s endpoint is Public"
  }
}

# Test: deploy_private_k8s_and_loadbalancer=false keeps current behavior (no bastion unless explicitly requested)
run "plan_no_orm_no_bastion" {
  command = plan

  variables {
    deploy_private_k8s_and_loadbalancer = false
    create_bastion                      = false
  }

  assert {
    condition     = length(oci_core_instance.bastion) == 0
    error_message = "Bastion should not be created when deploy_private_k8s_and_loadbalancer=false and create_bastion=false"
  }

  assert {
    condition     = length(oci_core_instance.operator) == 0
    error_message = "Operator should not be created when deploy_private_k8s_and_loadbalancer=false and create_bastion=false"
  }

  assert {
    condition     = length(oci_resourcemanager_private_endpoint.oke) == 0
    error_message = "ORM Private Endpoint should not be created when deploy_private_k8s_and_loadbalancer=false"
  }
}
