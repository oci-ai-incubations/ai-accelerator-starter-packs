# =============================================================================
# VSS File Storage Service (FSS) - Shared cache for VSS components
# Only created when starter_pack_category = "vss"
# =============================================================================

# Get availability domain for FSS
data "oci_identity_availability_domain" "vss_ad" {
  count          = var.starter_pack_category == "vss" ? 1 : 0
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

# Look up node subnet CIDR for production-safe FSS export (allow only OKE nodes)
data "oci_core_subnet" "vss_fss_node_subnet" {
  count     = var.starter_pack_category == "vss" ? 1 : 0
  subnet_id = local.network.oke_node_subnet_id
}

# File System
resource "oci_file_storage_file_system" "vss_fss" {
  count               = var.starter_pack_category == "vss" ? 1 : 0
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.vss_ad[0].name
  display_name        = "vss-cache-${local.deploy_id}"
}

# Mount Target (NFS endpoint)
resource "oci_file_storage_mount_target" "vss_mount_target" {
  count               = var.starter_pack_category == "vss" ? 1 : 0
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.vss_ad[0].name
  subnet_id           = local.network.oke_node_subnet_id
  display_name        = "vss-mount-target-${local.deploy_id}"
}

# Export (links FSS to mount target)
resource "oci_file_storage_export" "vss_export" {
  count          = var.starter_pack_category == "vss" ? 1 : 0
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

# Kubernetes PersistentVolume
resource "kubernetes_persistent_volume_v1" "vss_fss_pv" {
  count = var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-fss-pv-${lower(local.deploy_id)}"
  }

  spec {
    capacity = {
      storage = "1Ti" # FSS is elastic, this is nominal
    }

    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""

    persistent_volume_source {
      nfs {
        server = oci_file_storage_mount_target.vss_mount_target[0].ip_address
        path   = oci_file_storage_export.vss_export[0].path
      }
    }

    persistent_volume_reclaim_policy = "Retain"
  }

  depends_on = [oci_file_storage_export.vss_export]
}

# Kubernetes PersistentVolumeClaim
resource "kubernetes_persistent_volume_claim_v1" "vss_fss_pvc" {
  count = var.starter_pack_category == "vss" ? 1 : 0

  metadata {
    name = "vss-fss-pvc"
    annotations = {
      "volume.beta.kubernetes.io/storage-class" = ""
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""

    resources {
      requests = {
        storage = "1Ti"
      }
    }

    volume_name = kubernetes_persistent_volume_v1.vss_fss_pv[0].metadata[0].name
  }

  depends_on = [kubernetes_persistent_volume_v1.vss_fss_pv]
}
