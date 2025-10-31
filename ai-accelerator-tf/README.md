# AI Accelerator OKE Terraform Configuration

This Terraform configuration creates an Oracle Kubernetes Engine (OKE) cluster with a Virtual Cloud Network (VCN) in Oracle Cloud Infrastructure (OCI). It supports both public and private cluster configurations with optional bastion and operator instances for secure access.

## Features

- **Flexible Network Configuration**: Create new VCN or use existing one
- **Public/Private Endpoints**: Configure cluster API endpoint visibility
- **Public/Private Load Balancers**: Control load balancer subnet visibility
- **Bastion & Operator Setup**: Secure access to private clusters via bastion host and operator instance
- **Auto-configured Security**: Comprehensive security lists for all components
- **SSH Key Management**: Auto-generate SSH keys or use provided ones

## Architecture

### Public Configuration
- OKE cluster with public API endpoint
- Public load balancer subnets
- Direct kubectl access from internet

### Private Configuration
- OKE cluster with private API endpoint
- Private load balancer subnets
- Bastion host in public subnet for SSH access
- Operator instance in private subnet with kubectl and OCI CLI pre-installed
- Secure SSH tunneling: Internet → Bastion → Operator → Cluster

## Prerequisites

1. **OCI Account**: Active Oracle Cloud Infrastructure account
2. **Terraform**: Version 1.0 or later
3. **OCI CLI**: Configured with appropriate credentials
4. **Required Permissions**: 
   - Manage VCNs, subnets, and security lists
   - Manage compute instances
   - Manage OKE clusters and node pools
   - Manage load balancers

## Quick Start

### 1. Clone and Configure

```bash
cd ai-accelerator-tf
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit terraform.tfvars

```hcl
# Required Variables
tenancy_ocid     = "ocid1.tenancy.oc1..your-tenancy-id"
compartment_ocid = "ocid1.compartment.oc1..your-compartment-id"
region          = "us-ashburn-1"
user_ocid       = "ocid1.user.oc1..your-user-id"
fingerprint     = "your-api-key-fingerprint"
private_key_path = "~/.oci/oci_api_key.pem"

# Optional: Provide SSH public key (if not provided, one will be generated)
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... your-public-key"

# Network Configuration
network_configuration_mode = "create_new"  # or "bring_your_own"

# Cluster Configuration
cluster_endpoint_visibility_new_vcn = "Public"  # Only "Public" supported for new VCN
cluster_workers_visibility = "Private"

# Bastion Configuration (for private access)
create_bastion = true
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Configuration Options

### Network Configuration

#### Create New VCN (Recommended)
```hcl
network_configuration_mode = "create_new"
cluster_endpoint_visibility_new_vcn = "Public"  # Only option for new VCN
```

#### Use Existing VCN
```hcl
network_configuration_mode = "bring_your_own"
existing_vcn_id = "ocid1.vcn.oc1..your-vcn-id"
existing_endpoint_subnet_id = "ocid1.subnet.oc1..your-endpoint-subnet-id"
existing_node_subnet_id = "ocid1.subnet.oc1..your-node-subnet-id"
existing_lb_subnet_id = "ocid1.subnet.oc1..your-lb-subnet-id"
cluster_endpoint_visibility_existing_vcn = "Private"  # or "Public"
```

### Instance Shapes

#### Node Pool Configuration
```hcl
node_pool_instance_shape = {
  instanceShape = "VM.Standard.E5.Flex"
  ocpus         = 6
  memory        = 64
}
num_pool_workers = 3
```

#### Bastion Configuration
```hcl
bastion_instance_shape = {
  instanceShape = "VM.Standard.E5.Flex"
  ocpus         = 1
  memory        = 8
}
```

#### Operator Configuration
```hcl
operator_instance_shape = {
  instanceShape = "VM.Standard.E5.Flex"
  ocpus         = 2
  memory        = 16
}
```

### Load Balancer Visibility
```hcl
blueprints_endpoint_visibility = "Public"   # or "Private"
apps_endpoint_visibility = "Public"         # or "Private"
```

## Access Patterns

### Public Cluster Access

1. **Get kubeconfig**:
   ```bash
   oci ce cluster create-kubeconfig --cluster-id <cluster-id> --file ~/.kube/config --region <region>
   ```

2. **Test access**:
   ```bash
   kubectl get nodes
   ```

### Private Cluster Access (via Bastion)

1. **SSH to bastion**:
   ```bash
   ssh -i <private-key> opc@<bastion-public-ip>
   ```

2. **SSH to operator** (from bastion):
   ```bash
   ssh operator  # Pre-configured alias
   ```

3. **Configure kubectl** (on operator):
   ```bash
   ./configure_oke.sh
   ```

4. **Test cluster access**:
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

### SSH Tunneling (Alternative)

Direct SSH tunnel to operator:
```bash
ssh -i <private-key> -J opc@<bastion-public-ip> opc@<operator-private-ip>
```

## Network Architecture

### CIDR Blocks (Default)
- **VCN**: 10.0.0.0/16
- **Endpoint Subnet**: 10.0.80.0/20
- **Node Subnet**: 10.0.96.0/20
- **LB Subnet (BP)**: 10.0.112.0/20
- **LB Subnet (Apps)**: 10.0.128.0/20
- **Pods Subnet**: 10.0.160.0/20
- **Services Subnet**: 10.0.176.0/20
- **Bastion Subnet**: 10.0.192.0/20
- **Operator Subnet**: 10.0.208.0/20

### Security Groups

#### Node Security List
- Inbound: SSH from bastion, pod communication, API endpoint communication
- Outbound: Internet access, pod communication, API endpoint communication

#### Endpoint Security List
- Inbound: API access (port 6443), worker communication
- Outbound: Worker communication, internet access

#### Load Balancer Security List
- Inbound: HTTP (80), HTTPS (443)
- Outbound: Worker node communication

#### Bastion Security List
- Inbound: SSH from internet (port 22)
- Outbound: SSH to operator and worker nodes, internet access

#### Operator Security List
- Inbound: SSH from bastion
- Outbound: Kubernetes API access, SSH to workers, internet access

## Outputs

After successful deployment, you'll get:

```bash
cluster_id = "ocid1.cluster.oc1..your-cluster-id"
cluster_endpoint = "https://your-cluster-endpoint:6443"
bastion_public_ip = "xxx.xxx.xxx.xxx"
operator_private_ip = "10.0.208.x"
connection_instructions = {
  bastion_ssh = "ssh -i <private_key_file> opc@xxx.xxx.xxx.xxx"
  operator_ssh_via_bastion = "ssh -i <private_key_file> -J opc@xxx.xxx.xxx.xxx opc@10.0.208.x"
  kubectl_setup = "After connecting to operator instance, run: ./configure_oke.sh"
}
```

## Troubleshooting

### Common Issues

1. **SSH Key Issues**:
   - Ensure SSH public key is correctly formatted
   - Check private key permissions (600)

2. **Network Connectivity**:
   - Verify security list rules
   - Check route table configurations
   - Ensure NAT gateway is working for private subnets

3. **Cluster Access**:
   - Verify OCI CLI configuration on operator instance
   - Check cluster endpoint visibility settings
   - Ensure proper IAM permissions

### Debugging Commands

```bash
# Check cluster status
oci ce cluster get --cluster-id <cluster-id>

# Check node pool status
oci ce node-pool get --node-pool-id <node-pool-id>

# Test network connectivity
ping <target-ip>
telnet <target-ip> <port>

# Check security lists
oci network security-list get --security-list-id <security-list-id>
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including the VCN, subnets, instances, and OKE cluster. Make sure to backup any important data first.

## Support

For issues and questions:
1. Check the [Oracle OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
2. Review the [OCI Terraform Provider Documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs)
3. Consult the [Oracle Cloud Infrastructure Documentation](https://docs.oracle.com/en-us/iaas/Content/home.htm)

## License

Copyright (c) 2025 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
