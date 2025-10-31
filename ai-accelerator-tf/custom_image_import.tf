locals {
    nvidia_image_url = "https://objectstorage.ca-montreal-1.oraclecloud.com/p/ts6fjAuj7hY4io5x_jfX3fyC70HRCG8-9gOFqAjuF0KE0s-6tgDZkbRRZIbMZmoN/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2025.05.20-0-OFED-24.10-1.1.4.0-GPU-570-OPEN-CUDA-12.8-2025.07.22-0"
    amd_image_url = "https://objectstorage.ca-montreal-1.oraclecloud.com/p/ts6fjAuj7hY4io5x_jfX3fyC70HRCG8-9gOFqAjuF0KE0s-6tgDZkbRRZIbMZmoN/n/hpc_limited_availability/b/images/o/Canonical-Ubuntu-22.04-2025.07.23-0-DOCA-OFED-3.1.0-AMD-ROCM-643-2025.09.25-0"
}

resource "oci_core_image" "nvidia_image" {
    compartment_id = var.compartment_ocid
    display_name = "NVIDIA_Ubuntu_22.04_Driver_570_CUDA_12.8_HPC"
    image_source_details {
        operating_system = "Ubuntu"
        operating_system_version = "22.04"
        source_type = "objectStorageUri"
        source_uri = local.nvidia_image_url
    }
}

resource "oci_core_image" "amd_image" {
    compartment_id = var.compartment_ocid
    display_name = "AMD_Ubuntu_22.04_Driver_643_ROCM_HPC"
    image_source_details {
        operating_system = "Ubuntu"
        operating_system_version = "22.04"
        source_type = "objectStorageUri"
        source_uri = local.amd_image_url
    }
}