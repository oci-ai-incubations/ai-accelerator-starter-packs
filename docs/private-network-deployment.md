# Private Network Deployment

This guide covers deploying the AI Accelerator stack into a private network — either an isolated private VCN or a VCN peered to another network (such as on-premises infrastructure or a second OCI VCN).

---

## Overview

By default, the stack creates a new VCN with a public Kubernetes API endpoint and public load balancers, making the deployment accessible from the internet. For environments requiring network isolation, you can deploy into a VCN you already control, enabling peering, FastConnect, or VPN connectivity.

> **Note:** Creating a new private VCN from scratch via the stack is not yet supported. See [Coming Soon](#coming-soon--new-private-vcn) for details.

---

## Network Architecture

### Public Cluster (Default)

```
Internet
    │
    ▼
┌──────────────────────────────────┐
│  VCN                             │
│                                  │
│  ┌─────────────────┐             │
│  │ Public Subnet   │             │
│  │ (Load Balancer) │ ◄── HTTPS ──┤
│  └────────┬────────┘             │
│           │                      │
│  ┌────────▼────────┐             │
│  │ Private Subnet  │             │
│  │ (Worker Nodes)  │             │
│  └─────────────────┘             │
│                                  │
│  ┌─────────────────┐             │
│  │ Public Subnet   │             │
│  │ (OKE Endpoint)  │ ◄── kubectl ┤
│  └─────────────────┘             │
└──────────────────────────────────┘
```

### Private Cluster with Bastion

```
Your Machine / On-Premises
    │
    │ SSH tunnel through bastion
    ▼
┌──────────────────────────────────┐
│  VCN                             │
│                                  │
│  ┌─────────────────┐             │
│  │ Public Subnet   │             │
│  │ (Bastion)       │             │
│  └────────┬────────┘             │
│           │ private              │
│  ┌────────▼────────┐             │
│  │ Private Subnet  │             │
│  │ (OKE Endpoint)  │             │
│  └────────┬────────┘             │
│           │                      │
│  ┌────────▼────────┐             │
│  │ Private Subnet  │             │
│  │ (Worker Nodes)  │             │
│  └─────────────────┘             │
└──────────────────────────────────┘
```

### Private Cluster with VCN Peering

```
On-Premises / Second OCI VCN          AI Accelerator VCN
    │                                      │
    │  FastConnect / VPN / Local Peering   │
    └──────────────────────────────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │  Private Subnets        │
                              │  - OKE Endpoint         │
                              │  - Worker Nodes         │
                              │  - Load Balancers       │
                              └─────────────────────────┘
```

---

## Bring Your Own VCN

Use this option when you need to integrate the AI Accelerator with an existing network — for example, when peering with an on-premises network or a second OCI VCN that hosts other workloads.

### Step 1: Create the AI Accelerator VCN

Create a VCN in OCI with the following subnets. The CIDR ranges below are suggestions — adjust them to avoid overlap with your peered networks.

| Subnet | Purpose | Type | Suggested CIDR |
|--------|---------|------|---------------|
| Endpoint subnet | OKE Kubernetes API endpoint | Private | `10.1.80.0/20` |
| Nodes subnet | OKE worker node compute instances | Private | `10.1.96.0/20` |
| Load balancer subnet (Blueprints) | OCI AI Blueprints platform load balancer | Public or Private | `10.1.112.0/20` |
| Load balancer subnet (Apps) | Starter pack application load balancer | Public or Private | `10.1.128.0/20` |
| Pods subnet | OKE pod networking (VCN-native CNI) | Private | `172.16.0.0/16` |
| Services subnet | OKE Kubernetes services (ClusterIP) | Private | `172.17.0.0/16` |

> **Note:** Pods and services subnets can use RFC 1918 ranges that are not routable externally (172.16/16 and 172.17/16 are suitable defaults). Do not peer these subnets with your external network unless you specifically route pod traffic externally.

**Required security list / NSG rules:**

- Endpoint subnet: Allow ingress on TCP 6443 from the nodes subnet and from any host that runs kubectl.
- Nodes subnet: Allow all ingress/egress within the VCN; allow HTTPS outbound to 0.0.0.0/0 (for pulling container images).
- Load balancer subnets: Allow HTTP/HTTPS ingress from your intended clients (internet, peered VCN, or on-premises CIDR).
- Pods subnet: Allow all traffic within the pods and nodes subnets.

### Step 2: Set Up VCN Peering (If Needed)

If you want to access the AI Accelerator from another OCI VCN or on-premises, configure peering before deploying.

#### Local VCN Peering (Same Region)

Use [Local VCN Peering](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/VCNpeering.htm) when both VCNs are in the same OCI region.

```
VCN A (AI Accelerator)         VCN B (Your Workloads)
  10.1.0.0/16         ◄────►   10.2.0.0/16
       │                              │
  Local Peering GW            Local Peering GW
```

1. In VCN A, create a **Local Peering Gateway (LPG)**.
2. In VCN B, create a **Local Peering Gateway (LPG)**.
3. Connect the two LPGs (from either VCN's console, click the LPG and select **Establish Peering Connection**).
4. Add route rules in each VCN's route tables pointing the other VCN's CIDR to its LPG.
5. Add security list rules permitting traffic between the two CIDRs.

#### Remote VCN Peering (Cross-Region)

Use [Remote VCN Peering](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/remoteVCNpeering.htm) when VCNs are in different OCI regions. This uses Dynamic Routing Gateways (DRGs).

#### On-Premises Connectivity

For on-premises access, connect via:
- [Site-to-Site VPN](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingIPsec.htm) — IPSec VPN over the internet
- [FastConnect](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/fastconnect.htm) — dedicated private circuit

In both cases, attach a **Dynamic Routing Gateway (DRG)** to the AI Accelerator VCN and advertise the VCN CIDR to your on-premises router.

### Step 3: Deploy with bring_your_own

Once your VCN is set up and peering is established, deploy the stack using `bring_your_own` mode:

```hcl
network_configuration_mode = "bring_your_own"

# Provide OCIDs of the pre-created subnets
existing_vcn_id             = "ocid1.vcn.oc1..aaaaaaaa..."
existing_endpoint_subnet_id = "ocid1.subnet.oc1..aaaaaaaa..."  # Endpoint subnet
existing_node_subnet_id     = "ocid1.subnet.oc1..aaaaaaaa..."  # Nodes subnet
existing_lb_subnet_id       = "ocid1.subnet.oc1..aaaaaaaa..."  # Load balancer subnet (Blueprints)
existing_pods_subnet_id     = "ocid1.subnet.oc1..aaaaaaaa..."  # Pods subnet
existing_services_subnet_id = "ocid1.subnet.oc1..aaaaaaaa..."  # Services subnet

# Endpoint visibility when using your own VCN
cluster_endpoint_visibility_existing_vcn = "Private"   # or "Public"

# Endpoint visibility for load balancers
blueprints_endpoint_visibility = "Private"  # or "Public"
apps_endpoint_visibility       = "Private"  # or "Public"
```

### Step 4: IAM Policy Adjustments

When using `bring_your_own`, the IAM policies needed for the network are read-only (not `manage`). See [docs/iam-policies.md — Bring Your Own VCN](./iam-policies.md#oke-cluster--bring-your-own-vcn).

---

## Accessing Services After Deployment

### OCI AI Blueprints UI

If `blueprints_endpoint_visibility = "Private"`, the Blueprints UI is only accessible from within the VCN or from a peered network. Use an SSH tunnel or a jump host in the VCN:

```bash
# Example: SSH tunnel from local machine to bastion, forwarding port 8443
ssh -L 8443:<blueprints-private-ip>:443 opc@<bastion-public-ip>

# Then open https://localhost:8443 in your browser
```

### Starter Pack Application

Same approach as above. If `apps_endpoint_visibility = "Private"`, access via the peered network or an SSH tunnel.

### kubectl Access

Configure your local kubeconfig to connect through the bastion:

```bash
# Get the kubeconfig for the private cluster
oci ce cluster create-kubeconfig \
  --cluster-id <cluster-ocid> \
  --file ~/.kube/ai-accelerator-config \
  --region <region> \
  --kube-endpoint PRIVATE_ENDPOINT

# Set up the SSH proxy
BASTION_IP=$(terraform output -raw bastion_public_ip)
export HTTPS_PROXY=socks5://localhost:1080
ssh -D 1080 -N opc@${BASTION_IP} &

# Use kubectl
KUBECONFIG=~/.kube/ai-accelerator-config kubectl get pods -A
```

---

## Checklist

- [ ] Non-overlapping CIDRs between AI Accelerator VCN and peered networks
- [ ] Route tables updated in both VCNs (or VPN/FastConnect routes propagated)
- [ ] Security lists / NSGs allow traffic between peered CIDRs
- [ ] Pods subnet (`172.16.0.0/16`) and services subnet (`172.17.0.0/16`) are **not** advertised to peered networks unless intentional
- [ ] `bring_your_own` subnet OCIDs entered correctly in `terraform.tfvars`
- [ ] If using a private OKE endpoint: bastion or operator instance is available for kubectl access
- [ ] IAM policies use "bring_your_own" variants (read-only network permissions)

---

## Coming Soon — New Private VCN

> **Not currently supported.** Deploying a fully private network from scratch using `network_configuration_mode = "create_new"` with a private OKE endpoint is not yet functional.

The root cause is a bootstrapping problem: when Terraform creates a new VCN and sets the OKE API endpoint to private, the machine running `terraform apply` (whether a local workstation or an OCI Resource Manager runner) is not included in the security rules that allow access to the newly created private endpoint. As a result, the Kubernetes and Helm providers — which must connect to the OKE API to deploy cluster resources — cannot reach it, and the apply fails.

Resolving this requires one of:
- Automatically adding the deployer's IP to the endpoint subnet security list during apply.
- Running the apply from within the same VCN (e.g., from an operator instance bootstrapped in a first pass).
- A two-phase deployment (network + OKE in one apply, cluster resources in a second apply from inside the VCN).

Until this is implemented, **private network deployments require `bring_your_own`** with a pre-existing VCN whose security rules already permit access from the deploying machine or ORM runner.

When this feature ships, the configuration will look like:

```hcl
# Coming soon — not yet functional
network_configuration_mode          = "create_new"
cluster_endpoint_visibility_new_vcn = "Private"
blueprints_endpoint_visibility      = "Private"
apps_endpoint_visibility            = "Private"
create_bastion                      = true
ssh_public_key                      = "ssh-rsa AAAAB3NzaC1yc2EAAAA..."
```
