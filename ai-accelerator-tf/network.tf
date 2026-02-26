# Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# VCN
resource "oci_core_virtual_network" "oke_vcn" {
  cidr_block     = var.network_cidrs["VCN-CIDR"]
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-VCN-${random_string.deploy_id.result}"
  dns_label      = "vcn${random_string.deploy_id.result}"
  count          = local.create_network_resources ? 1 : 0

  # Ensure capacity is validated before starting network provisioning
  depends_on = [terraform_data.capacity_validated]
}

# Subnets
resource "oci_core_subnet" "oke_k8s_endpoint_subnet" {
  cidr_block                 = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-ENDPOINT-SUBNET-${random_string.deploy_id.result}"
  dns_label                  = "endpoint${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = (local.cluster_endpoint_visibility == "Private") ? true : false
  route_table_id             = (local.cluster_endpoint_visibility == "Private") ? (local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null) : (local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null)
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_endpoint_security_list[0].id] : []
  count                      = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_nodes_subnet" {
  cidr_block                 = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-NODES-SUBNET-${random_string.deploy_id.result}"
  dns_label                  = "nodes${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = true
  route_table_id             = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_nodes_security_list[0].id] : []
  count                      = local.create_network_resources ? 1 : 0
}

resource "oci_core_subnet" "oke_lb_subnet" {
  cidr_block                 = var.network_cidrs["LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-LB-SUBNET-BP-CP-${random_string.deploy_id.result}"
  dns_label                  = "lbcp${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = (var.blueprints_endpoint_visibility == "Private") ? true : false
  route_table_id             = (var.blueprints_endpoint_visibility == "Private") ? (local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null) : (local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null)
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_lb_security_list[0].id] : []
  count                      = local.create_network_resources ? 1 : 0
}


# Route Tables
resource "oci_core_route_table" "oke_private_route_table" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-PRIVATE-ROUTE-TABLE-${random_string.deploy_id.result}"

  route_rules {
    description       = "Traffic to internet"
    destination       = var.network_cidrs["ALL-CIDR"]
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.oke_nat_gateway[0].id
  }

  dynamic "route_rules" {
    for_each = length(data.oci_core_services.all_services.services) > 0 ? [1] : []
    content {
      description       = "Traffic to OCI services"
      destination       = data.oci_core_services.all_services.services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.oke_service_gateway[0].id
    }
  }

  count = local.create_network_resources ? 1 : 0
}

resource "oci_core_route_table" "oke_public_route_table" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-PUBLIC-ROUTE-TABLE-${random_string.deploy_id.result}"

  route_rules {
    description       = "Traffic to/from internet"
    destination       = var.network_cidrs["ALL-CIDR"]
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.oke_internet_gateway[0].id
  }

  count = local.create_network_resources ? 1 : 0
}

# Gateways
resource "oci_core_nat_gateway" "oke_nat_gateway" {
  compartment_id = var.compartment_ocid
  block_traffic  = false
  display_name   = "AI-Accel-NAT-GATEWAY-${random_string.deploy_id.result}"
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  count          = local.create_network_resources ? 1 : 0
}

resource "oci_core_internet_gateway" "oke_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-INTERNET-GATEWAY-${random_string.deploy_id.result}"
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  enabled        = true

  count = local.create_network_resources ? 1 : 0
}

resource "oci_core_service_gateway" "oke_service_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-SERVICE-GATEWAY-${random_string.deploy_id.result}"
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }

  count = local.create_network_resources && length(data.oci_core_services.all_services.services) > 0 ? 1 : 0
}

# Security Lists

resource "oci_core_security_list" "oke_nodes_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-NODES-SECURITY-LIST-${random_string.deploy_id.result}"
  ingress_security_rules {
    description = "Allow pods on one worker node to communicate with pods on another worker node"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.all_protocols
    stateless   = false
  }
  ingress_security_rules {
    description = "Inbound SSH traffic from bastion subnet"
    source      = var.network_cidrs["BASTION-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }
  ingress_security_rules {
    description = "Path discovery"
    source      = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.icmp_protocol
    stateless   = false
    icmp_options {
      type = 3
      code = 4
    }
  }
  ingress_security_rules {
    description = "Allow pods to communicate with OKE"
    source      = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
  }
  ingress_security_rules {
    description = "Inbound traffic to worker nodes from pods"
    source      = var.network_cidrs["PODS-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.all_protocols
    stateless   = false
  }
  ingress_security_rules {
    description = "Inbound traffic to worker nodes from load balancer"
    source      = var.network_cidrs["LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.all_protocols
    stateless   = false
  }

  egress_security_rules {
    description      = "Allow nodes to communicate with OKE"
    destination      = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.k8s_worker_to_cp_port
      max = local.k8s_worker_to_cp_port
    }
  }
  egress_security_rules {
    description      = "Path discovery"
    destination      = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.icmp_protocol
    stateless        = false
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    description      = "Allow nodes to communicate with internet"
    destination      = var.network_cidrs["ALL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }
  egress_security_rules {
    description      = "Allow nodes to communicate with pods"
    destination      = var.network_cidrs["PODS-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }
  egress_security_rules {
    description      = "Allow nodes to communicate with database subnet - SQL*Net"
    destination      = var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = 1521
      max = 1521
    }
  }
  egress_security_rules {
    description      = "Allow nodes to communicate with database subnet - SQL*Net"
    destination      = var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = 1522
      max = 1522
    }
  }
  egress_security_rules {
    description      = "Allow nodes to communicate with database subnet - HTTPS"
    destination      = var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.https_port
      max = local.https_port
    }
  }

  count = local.create_network_resources ? 1 : 0
}

# Endpoint Security List
resource "oci_core_security_list" "oke_endpoint_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-ENDPOINT-SECURITY-LIST-${random_string.deploy_id.result}"

  dynamic "ingress_security_rules" {
    for_each = local.api_endpoint_allowed_cidrs
    content {
      description = "External access to Kubernetes API endpoint from ${ingress_security_rules.value}"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = local.tcp_protocol
      stateless   = false
      tcp_options {
        min = local.k8s_api_port
        max = local.k8s_api_port
      }
    }
  }
  ingress_security_rules {
    description = "Kubernetes worker to Kubernetes API endpoint communication"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.k8s_api_port
      max = local.k8s_api_port
    }
  }
  ingress_security_rules {
    description = "Kubernetes worker to control plane communication"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.k8s_worker_to_cp_port
      max = local.k8s_worker_to_cp_port
    }
  }
  ingress_security_rules {
    description = "Path discovery"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.icmp_protocol
    stateless   = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    description      = "Allow Kubernetes API endpoint to communicate with worker nodes"
    destination      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
  }
  egress_security_rules {
    description      = "All traffic to internet"
    destination      = var.network_cidrs["ALL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }
  egress_security_rules {
    description      = "Path discovery"
    destination      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.icmp_protocol
    stateless        = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  count = local.create_network_resources ? 1 : 0
}

# Load Balancer Security List
resource "oci_core_security_list" "oke_lb_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-LB-SECURITY-LIST-${random_string.deploy_id.result}"

  dynamic "ingress_security_rules" {
    for_each = local.lb_allowed_cidrs
    content {
      description = "Allow HTTP from ${ingress_security_rules.value}"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = local.tcp_protocol
      stateless   = false
      tcp_options {
        min = local.http_port
        max = local.http_port
      }
    }
  }
  dynamic "ingress_security_rules" {
    for_each = local.lb_allowed_cidrs
    content {
      description = "Allow HTTPS from ${ingress_security_rules.value}"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = local.tcp_protocol
      stateless   = false
      tcp_options {
        min = local.https_port
        max = local.https_port
      }
    }
  }

  egress_security_rules {
    description      = "All traffic to worker nodes"
    destination      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
  }

  count = local.create_network_resources ? 1 : 0
}

# Autonomous Database Security List
resource "oci_core_security_list" "oke_db_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-DB-SECURITY-LIST-${random_string.deploy_id.result}"

  ingress_security_rules {
    description = "Allow SQL*Net from nodes subnet"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = 1521
      max = 1521
    }
  }
  ingress_security_rules {
    description = "Allow SQL*Net from nodes subnet"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = 1522
      max = 1522
    }
  }
  ingress_security_rules {
    description = "Allow HTTPS from nodes subnet"
    source      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.https_port
      max = local.https_port
    }
  }

  egress_security_rules {
    description      = "All traffic to internet"
    destination      = var.network_cidrs["ALL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }

  count = local.create_network_resources ? 1 : 0
}



# Bastion Subnet and Security List
resource "oci_core_subnet" "oke_bastion_subnet" {
  cidr_block                 = var.network_cidrs["BASTION-SUBNET-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-BASTION-SUBNET-${random_string.deploy_id.result}"
  dns_label                  = "bastion${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = false
  route_table_id             = local.create_network_resources ? oci_core_route_table.oke_public_route_table[0].id : null
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_bastion_security_list[0].id] : []
  count                      = local.create_network_resources && var.create_bastion ? 1 : 0
}

resource "oci_core_security_list" "oke_bastion_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-BASTION-SECURITY-LIST-${random_string.deploy_id.result}"

  ingress_security_rules {
    description = "SSH access from internet"
    source      = var.network_cidrs["ALL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }

  egress_security_rules {
    description      = "SSH access to operator subnet"
    destination      = var.network_cidrs["OPERATOR-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }
  egress_security_rules {
    description      = "SSH access to worker nodes"
    destination      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }
  egress_security_rules {
    description      = "All traffic to internet"
    destination      = var.network_cidrs["ALL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }

  count = local.create_network_resources && var.create_bastion ? 1 : 0
}

# Operator Subnet and Security List
resource "oci_core_subnet" "oke_operator_subnet" {
  cidr_block                 = var.network_cidrs["OPERATOR-SUBNET-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-OPERATOR-SUBNET-${random_string.deploy_id.result}"
  dns_label                  = "operator${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = true
  route_table_id             = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_operator_security_list[0].id] : []
  count                      = local.create_network_resources && var.create_bastion ? 1 : 0
}

resource "oci_core_security_list" "oke_operator_security_list" {
  vcn_id         = oci_core_virtual_network.oke_vcn[0].id
  compartment_id = var.compartment_ocid
  display_name   = "AI-Accel-OPERATOR-SECURITY-LIST-${random_string.deploy_id.result}"

  ingress_security_rules {
    description = "SSH access from bastion"
    source      = var.network_cidrs["BASTION-SUBNET-REGIONAL-CIDR"]
    source_type = "CIDR_BLOCK"
    protocol    = local.tcp_protocol
    stateless   = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }

  egress_security_rules {
    description      = "Kubernetes API access"
    destination      = var.network_cidrs["ENDPOINT-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.k8s_api_port
      max = local.k8s_api_port
    }
  }
  egress_security_rules {
    description      = "SSH access to worker nodes"
    destination      = var.network_cidrs["NODES-SUBNET-REGIONAL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.tcp_protocol
    stateless        = false
    tcp_options {
      min = local.ssh_port
      max = local.ssh_port
    }
  }
  egress_security_rules {
    description      = "All traffic to internet"
    destination      = var.network_cidrs["ALL-CIDR"]
    destination_type = "CIDR_BLOCK"
    protocol         = local.all_protocols
    stateless        = false
  }

  count = local.create_network_resources && var.create_bastion ? 1 : 0
}

# Autonomous Database Subnet
resource "oci_core_subnet" "oke_db_subnet" {
  cidr_block                 = var.network_cidrs["DB-SUBNET-REGIONAL-CIDR"]
  compartment_id             = var.compartment_ocid
  display_name               = "AI-Accel-DB-SUBNET-${random_string.deploy_id.result}"
  dns_label                  = "db${random_string.deploy_id.result}"
  vcn_id                     = oci_core_virtual_network.oke_vcn[0].id
  prohibit_public_ip_on_vnic = true
  route_table_id             = local.create_network_resources ? oci_core_route_table.oke_private_route_table[0].id : null
  dhcp_options_id            = local.create_network_resources ? oci_core_virtual_network.oke_vcn[0].default_dhcp_options_id : null
  security_list_ids          = local.create_network_resources ? [oci_core_security_list.oke_db_security_list[0].id] : []
  count                      = local.create_network_resources ? 1 : 0
}

locals {
  http_port             = 80
  https_port            = 443
  k8s_api_port          = 6443
  ssh_port              = 22
  k8s_worker_to_cp_port = 12250
  all_protocols         = "all"
  tcp_protocol          = "6"
  icmp_protocol         = "1"
}