data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.tenancy_ocid
}

data "oci_identity_regions" "home_region" {
  filter {
    name   = "key"
    values = [data.oci_identity_tenancy.tenancy.home_region_key]
  }
}

data "oci_identity_tenancy" "tenancy" {
  tenancy_id = local.tenancy_ocid
}

# Get the latest Oracle Linux image
data "oci_core_images" "oracle_linux" {
  compartment_id           = local.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.bastion_instance_shape.instanceShape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Get cluster kube config for provider configuration
data "oci_containerengine_cluster_kube_config" "oke" {
  cluster_id    = local.effective_cluster_id
  token_version = "2.0.0"
}

# Get Object Storage namespace
data "oci_objectstorage_namespace" "ns" {
  compartment_id = local.compartment_ocid
}
