# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# VCN
resource "oci_core_virtual_network" "oke_vcn" {
  cidr_block     = lookup(var.network_cidrs, "VCN-CIDR")
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-VCN-${random_string.deploy_id.result}"
  dns_label      = "ai-accel-vcn-${random_string.deploy_id.result}"
  count          = local.create_network_resources ? 1 : 0
}

# Subnets
resource "oci_core_subnet" "oke_endpoint_subnet" {
    cidr_block                 = lookup(var.network_cidrs, "ENDPOINT-SUBNET-REGIONAL-CIDR")
    compartment_id             = var.compartment_ocid
    display_name               = "AI-Accel-ENDPOINT-SUBNET-${random_string.deploy_id.result}"
    dns_label                  = "ai-accel-endpoint-subnet-${random_string.deploy_id.result}"
    vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = (local.cluster_endpoint_visibility == "Private") ? true : false
    route_table_id             = (local.cluster_endpoint_visibility == "Private") ? (local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null) : (local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null)
    dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_endpoint_security_list[0].id] : []
    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_nodes_subnet" {
    cidr_block                 = lookup(var.network_cidrs, "NODES-SUBNET-REGIONAL-CIDR")
    compartment_id             = var.compartment_ocid
    display_name               = "AI-Accel-NODES-SUBNET-${random_string.deploy_id.result}"
    dns_label                  = "ai-accel-nodes-subnet-${random_string.deploy_id.result}"
    vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = true
    route_table_id             = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
    dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_nodes_security_list[0].id] : []
    count                      = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_lb_subnet_bp_control_plane" {
    cidr_block = lookup(var.network_cidrs, "LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR")
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-LB-SUBNET-BP-CP-${random_string.deploy_id.result}"
    dns_label = "ai-accel-lb-subnet-bp-cp-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = (var.blueprints_endpoint_visibility == "Private") ? true : false
    route_table_id = (var.blueprints_endpoint_visibility == "Private") ? (local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null) : (local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null)
    dhcp_options_id = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids = local.create_network_resources ? [oci_core_security_list.oke_lb_security_list[0].id] : []
    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_lb_subnet_apps" {
    cidr_block = lookup(var.network_cidrs, "LB-SUBNET-APPS-REGIONAL-CIDR")
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-LB-SUBNET-APPS-${random_string.deploy_id.result}"
    dns_label = "ai-accel-lb-subnet-apps-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = (var.apps_endpoint_visibility == "Private") ? true : false
    route_table_id = (var.apps_endpoint_visibility == "Private") ? (local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null) : (local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null)
    dhcp_options_id = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids = local.create_network_resources ? [oci_core_security_list.oke_lb_security_list[0].id] : []
    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_pods_subnet" {
    cidr_block = lookup(var.network_cidrs, "PODS-SUBNET-REGIONAL-CIDR")
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-PODS-SUBNET-${random_string.deploy_id.result}"
    dns_label = "ai-accel-pods-subnet-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = true
    route_table_id = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
    dhcp_options_id = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids = local.create_network_resources ? [oci_core_security_list.oke_pods_security_list[0].id] : []
    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_services_subnet" {
    cidr_block = lookup(var.network_cidrs, "SERVICES-SUBNET-REGIONAL-CIDR")
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-SERVICES-SUBNET-${random_string.deploy_id.result}"
    dns_label = "ai-accel-services-subnet-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    prohibit_public_ip_on_vnic = true
    route_table_id = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
    dhcp_options_id = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
    security_list_ids = local.create_network_resources ? [oci_core_security_list.oke_services_security_list[0].id] : []
    count = local.create_network_resources ? 1 : 0
}

# Route Tables
resource "oci_core_route_table" "oke_private_route_table" {
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-PRIVATE-ROUTE-TABLE-${random_string.deploy_id.result}"

    route_rules {
        description = "Traffic to internet"
        destination = lookup(var.network_cidrs, "ALL-CIDR")
        destination_type = "CIDR_BLOCK"
        network_entity_id = oci_core_nat_gateway.oke_nat_gateway[0].id
    }

    route_rules {
        description = "Traffic to OCI services"
        destination = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
        destination_type = "SERVICE_CIDR_BLOCK"
        network_entity_id = oci_core_service_gateway.oke_service_gateway[0].id
    }

    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_route_table" "oke_public_route_table" {
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-PUBLIC-ROUTE-TABLE-${random_string.deploy_id.result}"

    route_rules {
        description = "Traffic to/from internet"
        destination = lookup(var.network_cidrs, "ALL-CIDR")
        destination_type = "CIDR_BLOCK"
        network_entity_id = oci_core_internet_gateway.oke_internet_gateway[0].id
    }

    count = local.create_network_resources ? 1 : 0
}

# Gateways
resource "oci_core_nat_gateway" "oke_nat_gateway" {
    compartment_id = var.compartment_ocid
    block_traffic = false
    display_name = "AI-Accel-NAT-GATEWAY-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_internet_gateway" "oke_internet_gateway" {
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-INTERNET-GATEWAY-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    enabled = true

    count = local.create_network_resources ? 1 : 0
}

resource "oci_core_service_gateway" "oke_service_gateway" {
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-SERVICE-GATEWAY-${random_string.deploy_id.result}"
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    services {
        service_id = lookup(data.oci_core_services.all_services.services[0], "id")
    }

    count = local.create_network_resources ? 1 : 0
}

# Security Lists

resource "oci_core_security_list" "oke_nodes_security_list" {
    vcn_id = oci_core_virtual_network.oke_vcn[0].id
    compartment_id = var.compartment_ocid
    display_name = "AI-Accel-NODES-SECURITY-LIST-${random_string.deploy_id.result}"
    

    count = local.create_network_resources ? 1 : 0
}


locals {
    http_port = 80
    https_port = 443
    k8s_api_port = 6443
    ssh_port = 22
    k8s_worker_to_cp_port = 12250

}