
# Operator DG and Policy for Cluster Access
resource "oci_identity_dynamic_group" "operator_dg" {
  provider       = oci.home_region
  name           = "operator_dg-${random_string.deploy_id.result}"
  description    = "DG For operator to access the cluster"
  compartment_id = var.tenancy_ocid
  matching_rule  = "ALL {instance.id = '${oci_core_instance.operator[0].id}'}"
  count          = local.create_network_resources && local.create_bastion_effective && var.create_policies ? 1 : 0
}

resource "oci_identity_policy" "operator_policy" {
  provider       = oci.home_region
  name           = "operator_policy-${random_string.deploy_id.result}"
  description    = "Policy For operator to access the cluster"
  compartment_id = var.tenancy_ocid
  statements = [
    "Allow dynamic-group 'operator_dg-${random_string.deploy_id.result}' to manage cluster-family in compartment id ${var.compartment_ocid}"
  ]
  count = local.create_network_resources && local.create_bastion_effective && var.create_policies ? 1 : 0
  depends_on = [
    oci_identity_dynamic_group.operator_dg
  ]
}

# tflint-ignore: terraform_unused_declarations
data "oci_identity_compartment" "oci_compartment" {
  id = var.compartment_ocid
}

# Define the dynamic group
resource "oci_identity_dynamic_group" "dyn_group" {
  provider       = oci.home_region
  name           = "${local.app_name}-instance-dg"
  description    = "Dynamic group for OKE instances across the tenancy"
  compartment_id = var.tenancy_ocid
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
  freeform_tags  = local.corrino_tags
  count          = local.deploy_infrastructure && var.create_policies ? 1 : 0

  # Ensure capacity is validated before creating IAM resources
  depends_on = [terraform_data.capacity_validated]
}

# Define the IAM policy
resource "oci_identity_policy" "oke_instances_tenancy_policy" {
  provider       = oci.home_region
  name           = "${local.app_name}-dg-inst-policy"
  description    = "Tenancy-level policy to grant needed permissions to the dynamic group"
  compartment_id = var.tenancy_ocid

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to manage all-resources in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to use all-resources in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to manage cluster-node-pools in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to manage cluster-work-requests in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to manage volume-attachments in tenancy where request.principal.type = 'cluster'",
    "Allow dynamic-group ${oci_identity_dynamic_group.dyn_group[0].name} to manage volumes in tenancy where request.principal.type = 'cluster'"
  ]
  freeform_tags = local.corrino_tags
  depends_on    = [oci_identity_dynamic_group.dyn_group]
  count         = local.deploy_infrastructure && var.create_policies ? 1 : 0
}