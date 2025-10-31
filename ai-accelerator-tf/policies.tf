
# Operator DG and Policy for Cluster Access
resource "oci_identity_dynamic_group" "operator_dg" {
    provider = oci.home_region
    name = "operator_dg-${random_string.deploy_id.result}"
    description = "DG For operator to access the cluster"
    compartment_id = var.tenancy_ocid
    matching_rule = "ALL {instance.id = '${oci_core_instance.operator[0].id}'}"
    count = local.create_network_resources && var.create_bastion ? 1 : 0
}

resource "oci_identity_policy" "operator_policy" {
    provider = oci.home_region
    name = "operator_policy-${random_string.deploy_id.result}"
    description = "Policy For operator to access the cluster"
    compartment_id = var.tenancy_ocid
    statements = [
        "Allow dynamic-group 'operator_dg-${random_string.deploy_id.result}' to manage cluster-family in compartment id ${var.compartment_ocid}"
    ]
    count = local.create_network_resources && var.create_bastion ? 1 : 0
    depends_on = [
        oci_identity_dynamic_group.operator_dg
    ]
}