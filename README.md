# OCI AI Accelerator Starter Packs

[![License: UPL-1.0](https://img.shields.io/badge/license-UPL--1.0-blue.svg)](LICENSE.md)
[![Terraform CI](https://github.com/oracle-devrel/oci-ai-accelerator/actions/workflows/terraform-test.yml/badge.svg)](https://github.com/oracle-devrel/oci-ai-accelerator/actions/workflows/terraform-test.yml)
[![Lint](https://github.com/oracle-devrel/oci-ai-accelerator/actions/workflows/terraform-lint.yml/badge.svg)](https://github.com/oracle-devrel/oci-ai-accelerator/actions/workflows/terraform-lint.yml)

Terraform-based infrastructure-as-code that deploys production-ready AI workloads on [Oracle Cloud Infrastructure (OCI)](https://www.oracle.com/cloud/) using [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/). It provisions networking, compute, a Kubernetes cluster, Helm-managed platform services, and deploys an AI application stack (the OCI AI Blueprints platform) — all from a single `terraform apply`.

---

## Starter Packs

Each starter pack is a pre-configured AI workload that deploys onto the OKE cluster via [OCI AI Blueprints](https://docs.oracle.com/en-us/iaas/ai-blueprints/).

| Pack | Category Key | Description | GPU Required |
|------|-------------|-------------|--------------|
| **cuOpt** | `cuopt` | NVIDIA cuOpt route optimization with a LlamaStack-powered chat interface | Yes |
| **VSS** | `vss` | NVIDIA Video Summary Service — ingest, analyze, and query video content | Yes |
| **PaaS RAG** | `paas_rag` | Retrieval-Augmented Generation backed by Oracle Autonomous Database 23ai | No |
| **Enterprise RAG** | `enterprise_rag` | Full-stack RAG pipeline with NVIDIA NIMs, Milvus, NeMo microservices, and a React frontend | Yes |
| **Enterprise RAG + AIQ** | `enterprise_rag_aiq` | Enterprise RAG extended with an NVIDIA AIQ research assistant and Tavily web search | Yes |

Each pack comes in **small** and **medium** sizes. See [`SOFTWARE_VERSIONS.md`](SOFTWARE_VERSIONS.md) for the complete list of container images and versions deployed by each pack.

---

## Prerequisites

- An **OCI tenancy** with sufficient [service limits](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/servicelimits.htm) for GPU shapes (for GPU packs) and OKE clusters.
- An **NVIDIA NGC API key** — sign up at [ngc.nvidia.com](https://ngc.nvidia.com) and generate an API key under your organization settings. Required for pulling NVIDIA NIM and Blueprint container images.
- **Terraform >= 1.5** installed locally (only for CLI deployments).
- **OCI CLI** configured with API key credentials, or an OCI Resource Manager stack (no local tooling needed for console deployments).

---

## Deploy via OCI Console (Recommended)

The fastest way to deploy is through **OCI Resource Manager**, which provides a guided UI form.

1. Download the latest stack zip for your chosen starter pack from the [Releases page](https://github.com/oracle-devrel/oci-ai-accelerator/releases).
2. In the OCI Console, navigate to **Developer Services → Resource Manager → Stacks**.
3. Click **Create Stack**, select **Upload a .zip**, and upload the downloaded zip.
4. Fill in the form:
   - Choose your **compartment** and **region**.
   - Enter your **NVIDIA NGC API key**.
   - Set your OCI AI Blueprints **admin username**, **password**, and **email**.
   - Accept the defaults or customize networking, node shapes, and visibility settings.
5. Click **Next → Next → Create**.
6. Click **Apply** on the stack detail page and confirm.

Deployment takes approximately **20–40 minutes** depending on the starter pack. When complete, the **Outputs** tab shows the URL to access your deployed application.

> For GPU starter packs, ensure you select an **availability domain** that has GPU capacity for your chosen shape. The stack includes a capacity pre-check that will fail fast if the selected AD has no capacity.

---

## Deploy via Terraform CLI

### 1. Clone and configure

```bash
git clone https://github.com/oracle-devrel/oci-ai-accelerator.git
cd oci-ai-accelerator/ai-accelerator-tf
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# OCI identity
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaa..."
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaa..."
region           = "us-ashburn-1"
current_user_ocid = "ocid1.user.oc1..aaaaaaaa..."
fingerprint      = "aa:bb:cc:..."
private_key_path = "~/.oci/oci_api_key.pem"

# NVIDIA NGC credentials
ngc_secret     = "nvapi-..."
ngc_api_secret = "nvapi-..."

# OCI AI Blueprints admin user
corrino_admin_username = "admin"
corrino_admin_password = "YourSecurePassword1!"
corrino_admin_email    = "you@example.com"
```

Set the starter pack category (required — this is not in `terraform.tfvars`):

```bash
echo 'starter_pack_category = "cuopt"' > starter_pack_category.auto.tfvars
```

### 2. Initialize and deploy

```bash
terraform init
terraform plan    # review what will be created
terraform apply
```

### 3. Access your deployment

After apply completes, retrieve the application URL from outputs:

```bash
terraform output corrino_endpoint   # OCI AI Blueprints UI
terraform output starter_pack_url   # Starter pack application URL
```

### 4. Tear down

```bash
terraform destroy
```

> **Note:** If `terraform destroy` fails on the Kubernetes provider, retry with `--refresh=false`:
> `terraform destroy --refresh=false`

---

## Configuration Reference

### Required Variables

| Variable | Description |
|----------|-------------|
| `tenancy_ocid` | OCID of your OCI tenancy |
| `compartment_ocid` | OCID of the compartment to deploy into |
| `region` | OCI region (e.g., `us-ashburn-1`) |
| `current_user_ocid` | OCID of the OCI user running the deployment |
| `ngc_secret` | NVIDIA NGC API key (for image pulls from `nvcr.io`) |
| `ngc_api_secret` | NVIDIA NGC API key (for NGC API access) |
| `corrino_admin_username` | Admin username for the OCI AI Blueprints portal |
| `corrino_admin_password` | Admin password (min 8 chars, 1 uppercase, 1 special char) |
| `corrino_admin_email` | Admin email address |
| `starter_pack_category` | One of: `cuopt`, `vss`, `paas_rag`, `enterprise_rag`, `enterprise_rag_aiq` |

### Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `starter_pack_size` | `small` | Size tier: `small` or `medium` |
| `worker_node_availability_domain` | `""` | AD for GPU worker nodes. Required for GPU packs when capacity check is enabled |
| `network_configuration_mode` | `create_new` | `create_new` or `bring_your_own` (see [Networking Options](#networking-options)) |
| `cluster_endpoint_visibility_new_vcn` | `Public` | API endpoint visibility for new VCN: `Public` or `Private` |
| `cluster_workers_visibility` | `Private` | Worker node subnet visibility: `Private` or `Public` |
| `blueprints_endpoint_visibility` | `Public` | OCI AI Blueprints UI visibility: `Public` or `Private` |
| `apps_endpoint_visibility` | `Private` | Starter pack app endpoint visibility: `Public` or `Private` |
| `create_bastion` | `false` | Create a bastion + operator instance for private cluster access |
| `create_policies` | `true` | Auto-create required IAM policies. Disable if policies are pre-created |
| `skip_capacity_check` | `false` | Skip GPU capacity pre-validation |
| `k8s_version` | `v1.34.1` | Kubernetes version for the OKE cluster |
| `db_password` | `null` | Autonomous Database password. Required for `paas_rag` |
| `tavily_api_key` | `""` | Tavily web search API key. Optional; only used by `enterprise_rag_aiq` |
| `use_custom_dns` | `false` | Use a custom domain instead of the automatic `nip.io` domain |
| `fqdn_custom_domain` | `""` | Your custom FQDN (requires DNS A-record pointing to the load balancer IP) |

### Node Pool Shape

```hcl
node_pool_instance_shape = {
  instanceShape = "VM.Standard.E5.Flex"
  ocpus         = 6
  memory        = 64
}
```

GPU starter packs deploy additional GPU worker node pools automatically based on the selected pack and size. The control plane node pool uses the `node_pool_instance_shape` above.

### Network CIDRs

Default CIDRs work for most deployments. Override only if they conflict with your existing network:

```hcl
network_cidrs = {
  VCN-CIDR                                 = "10.0.0.0/16"
  ENDPOINT-SUBNET-REGIONAL-CIDR            = "10.0.80.0/20"
  NODES-SUBNET-REGIONAL-CIDR               = "10.0.96.0/20"
  LB-SUBNET-BP-CONTROL-PLANE-REGIONAL-CIDR = "10.0.112.0/20"
  LB-SUBNET-APPS-REGIONAL-CIDR             = "10.0.128.0/20"
  PODS-SUBNET-REGIONAL-CIDR                = "172.16.0.0/16"
  SERVICES-SUBNET-REGIONAL-CIDR            = "172.17.0.0/16"
  BASTION-SUBNET-REGIONAL-CIDR             = "10.0.192.0/20"
  OPERATOR-SUBNET-REGIONAL-CIDR            = "10.0.208.0/20"
}
```

---

## Networking Options

### Create a New VCN (Default)

```hcl
network_configuration_mode = "create_new"
```

Terraform creates a complete VCN with all required subnets, route tables, security lists, and gateways. This is the simplest option and recommended for new deployments.

### Bring Your Own VCN

```hcl
network_configuration_mode          = "bring_your_own"
existing_vcn_id                     = "ocid1.vcn.oc1..aaaaaaaa..."
existing_endpoint_subnet_id         = "ocid1.subnet.oc1..aaaaaaaa..."
existing_node_subnet_id             = "ocid1.subnet.oc1..aaaaaaaa..."
existing_lb_subnet_id               = "ocid1.subnet.oc1..aaaaaaaa..."
existing_pods_subnet_id             = "ocid1.subnet.oc1..aaaaaaaa..."
existing_services_subnet_id         = "ocid1.subnet.oc1..aaaaaaaa..."
```

Use your own pre-existing VCN and subnets. This is required when deploying into a private network, connecting to on-premises infrastructure, or peering with another VCN. See [Private Network Deployment](docs/private-network-deployment.md) for full setup instructions.

---

## IAM Policies

The stack can automatically create the required IAM policies (`create_policies = true`, which is the default). If your user lacks permission to create policies, a tenancy administrator must create them in advance. Set `create_policies = false` once they exist.

See [docs/iam-policies.md](docs/iam-policies.md) for the full policy reference with per-feature breakdowns.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  OCI Compartment                                │
│                                                 │
│  ┌──────────── VCN ──────────────────────────┐  │
│  │                                           │  │
│  │  ┌─────────────────┐  ┌────────────────┐  │  │
│  │  │  OKE Cluster    │  │  Bastion /     │  │  │
│  │  │                 │  │  Operator      │  │  │
│  │  │  ┌───────────┐  │  │  (optional)    │  │  │
│  │  │  │ Helm Stack │  │  └────────────────┘  │  │
│  │  │  │ - nginx    │  │                      │  │
│  │  │  │ - cert-mgr │  │  ┌────────────────┐  │  │
│  │  │  │ - prometheus│  │  │  Autonomous DB │  │  │
│  │  │  │ - grafana  │  │  │  (paas_rag)    │  │  │
│  │  │  └───────────┘  │  └────────────────┘  │  │
│  │  │                 │                       │  │
│  │  │  ┌───────────┐  │                       │  │
│  │  │  │ AI Blpts  │  │                       │  │
│  │  │  │ Platform  │  │                       │  │
│  │  │  │ + Pack    │  │                       │  │
│  │  │  └───────────┘  │                       │  │
│  │  └─────────────────┘                       │  │
│  │         ↑ Load Balancers ↑                 │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

**Key components provisioned:**

- **VCN** — Virtual Cloud Network with regional subnets for endpoint, nodes, load balancers, pods, services, bastion, and operator
- **OKE Cluster** — Managed Kubernetes cluster with a control-plane node pool and per-pack GPU node pools
- **Helm Stack** — ingress-nginx, cert-manager (Let's Encrypt TLS), Prometheus, Grafana, NVIDIA DCGM exporter
- **OCI AI Blueprints** — The Corrino platform that manages AI workload deployments on the cluster
- **Starter Pack** — The AI workload deployed as a blueprint onto the cluster

---

## Software Versions

See [`SOFTWARE_VERSIONS.md`](SOFTWARE_VERSIONS.md) for the complete list of container images and versions deployed by each starter pack configuration.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/iam-policies.md](docs/iam-policies.md) | Full IAM policy reference — stack creation and feature policies |
| [docs/private-network-deployment.md](docs/private-network-deployment.md) | How to deploy into a private network with VCN peering |
| [docs/VERSIONING.md](docs/VERSIONING.md) | Version management and release process |
| [docs/BLUEPRINT_LIFECYCLE.md](docs/BLUEPRINT_LIFECYCLE.md) | How blueprint deployments are managed (immutability, hashing, lifecycle) |
| [docs/TESTING.md](docs/TESTING.md) | Unit test, schema test, and integration test guides |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute — OCA, PR process, code of conduct |
| [SECURITY.md](SECURITY.md) | Responsible disclosure policy |

---

## Contributing

Contributions are welcome. Before submitting a pull request, please read [CONTRIBUTING.md](CONTRIBUTING.md) — all contributors must sign the [Oracle Contributor Agreement (OCA)](https://oca.opensource.oracle.com) and include a `Signed-off-by` line in their commits.

For bugs and feature requests, [open a GitHub issue](https://github.com/oracle-devrel/oci-ai-accelerator/issues) first.

---

## License

Copyright (c) 2024 Oracle and/or its affiliates.

Released under the [Universal Permissive License v 1.0](LICENSE.md).
