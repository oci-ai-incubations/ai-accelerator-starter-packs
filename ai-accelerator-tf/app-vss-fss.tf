# =============================================================================
# VSS File Storage Service (FSS) - Shared cache for VSS components
# Only created when starter_pack_category = "vss"
# =============================================================================

# Get availability domain for FSS
data "oci_identity_availability_domain" "vss_ad" {
  count          = local.deploy_app_vss ? 1 : 0
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

# Look up node subnet CIDR for production-safe FSS export (allow only OKE nodes)
data "oci_core_subnet" "vss_fss_node_subnet" {
  count     = local.deploy_app_vss ? 1 : 0
  subnet_id = local.network.oke_node_subnet_id
}

# File System
resource "oci_file_storage_file_system" "vss_fss" {
  count               = local.deploy_app_vss ? 1 : 0
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.vss_ad[0].name
  display_name        = "vss-cache-${local.deploy_id}"
}

# Mount Target (NFS endpoint)
resource "oci_file_storage_mount_target" "vss_mount_target" {
  count               = local.deploy_app_vss ? 1 : 0
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.vss_ad[0].name
  subnet_id           = local.network.oke_node_subnet_id
  display_name        = "vss-mount-target-${local.deploy_id}"
}

# Export (links FSS to mount target)
resource "oci_file_storage_export" "vss_export" {
  count          = local.deploy_app_vss ? 1 : 0
  file_system_id = oci_file_storage_file_system.vss_fss[0].id
  export_set_id  = oci_file_storage_mount_target.vss_mount_target[0].export_set_id
  path           = "/vss-cache-${local.deploy_id}"

  # Restrict source to OKE node subnet only
  export_options {
    source                         = data.oci_core_subnet.vss_fss_node_subnet[0].cidr_block
    access                         = "READ_WRITE"
    identity_squash                = "NONE"
    require_privileged_source_port = false
  }
}

# NOTE: the Kubernetes PersistentVolume + PersistentVolumeClaim that used to
# bridge the OCI FSS into the cluster were removed when vss-oracle-ux,
# vss-download-service, and the vss engine itself moved under Corrino. Each
# recipe now references the FSS directly via `input_file_system = [{
# file_system_ocid, mount_target_ocid, mount_location, volume_size_in_gbs }]`
# — Corrino provisions its own per-recipe PV/PVC pair under the hood, so the
# native-TF objects became redundant.
