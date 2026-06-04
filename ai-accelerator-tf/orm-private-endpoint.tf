# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#
# ORM Private Endpoint for private K8s API access from Resource Manager

resource "oci_resourcemanager_private_endpoint" "oke" {
  count          = local.create_orm_private_endpoint ? 1 : 0
  compartment_id = local.compartment_ocid
  display_name   = "AI-Accel-ORM-PE-${random_string.deploy_id.result}"
  vcn_id         = local.vcn_id
  subnet_id      = local.endpoint_subnet_id

  lifecycle {
    ignore_changes = [defined_tags]
  }

  depends_on = [
    oci_core_subnet.oke_k8s_endpoint_subnet,
    oci_containerengine_cluster.oke_cluster,
    oci_containerengine_cluster.oke_cluster_existing_vcn,
  ]
}

data "oci_resourcemanager_private_endpoint_reachable_ip" "oke" {
  count               = local.create_orm_private_endpoint ? 1 : 0
  private_endpoint_id = oci_resourcemanager_private_endpoint.oke[0].id
  private_ip          = local.cluster_endpoint_private
}
