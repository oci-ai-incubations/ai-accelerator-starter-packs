# Preserve Infrastructure on Teardown

## Problem

GPU A100 nodes take ~6 hours to recycle after termination. The current integration pipeline destroys all infrastructure (OKE cluster, node pools, networking) alongside the application layer after each test run. This makes iterative testing prohibitively slow.

## Goal

Allow users to tear down the application layer (Corrino, blueprints, Helm charts, databases) while preserving the underlying infrastructure (OKE cluster, node pools, VCN) so that subsequent test runs deploy onto warm nodes without waiting for GPU provisioning.

## Constraints

- `terraform destroy` is all-or-nothing -- no native Terraform mechanism to selectively skip resources based on a variable during destroy.
- `prevent_destroy` must be a literal boolean in HashiCorp Terraform (all versions) -- cannot accept variables.
- OCI Resource Manager destroy jobs have no `-target` support.
- During `terraform destroy`, resources are destroyed in reverse creation order (inverse dependency graph). This ordering IS deterministic and can be relied upon.

## Approach: Infrastructure-Only Stacks + Bring Your Own Cluster

Two complementary features implemented via simple count gating:

1. **`deploy_application` boolean**: When `false`, all app resources have `count = 0`. Creates an infrastructure-only stack (VCN, OKE cluster, node pools, GPU instances).
2. **`existing_cluster_id` string**: When provided, all infra resources have `count = 0`. Creates an app-only stack that deploys onto an existing cluster. This stack can be fully destroyed via ORM's Destroy button since it only contains app resources.
3. **Blueprint undeploy on destroy**: A `terraform_data` resource with a destroy-time `local-exec` provisioner calls the Corrino undeploy API before Corrino is torn down, preventing orphaned blueprint workloads.

## ORM Workflow

### Step 1: Create Infrastructure Stack

1. **Create stack**: Set `deploy_application = false`. Leave `existing_cluster_id` empty.
2. **Apply**: Infrastructure created -- VCN, OKE cluster, node pools, GPU instance pools. No app resources.
3. Stack outputs `cluster_id` (visible in ORM UI).

### Step 2: Create App Stack (Repeatable)

4. **Create NEW stack**: Set `existing_cluster_id = <cluster_id from step 3>`. Leave `deploy_application = true` (default).
5. **Apply**: App deploys on existing warm nodes. No GPU provisioning wait.
6. **Test**.
7. **Destroy**: Click Destroy in ORM. Blueprint workloads are undeployed via Corrino API (destroy-time provisioner), then all app resources are destroyed. Nodes are untouched (they belong to the infra stack).
8. **Repeat from step 4** for next test iteration.

### Final Cleanup

9. Destroy the infrastructure stack from step 1.

## Resource Boundary

### Infrastructure (gated on `local.create_infrastructure`)

These resources are only created when `existing_cluster_id` is empty. They are NOT conditional on `deploy_application`.

| File | Resources |
|------|-----------|
| `network.tf` | VCN, subnets, gateways, security lists, route tables (18 resources) |
| `oke.tf` | OKE cluster (both variants), control plane node pool, CPU worker pool, SSH key, NVIDIA GPU addon |
| `instance_pools.tf` | Instance configuration, instance pool, cluster network |
| `capacity_check.tf` | Capacity reports, capacity_validated |
| `compute.tf` | Bastion, operator instances |
| `custom_image_import.tf` | NVIDIA/AMD GPU images |
| `orm-private-endpoint.tf` | ORM private endpoint |
| `rbac.tf` | Cluster role, cluster role binding |
| `kubernetes.tf` | Namespaces (cluster_tools, milvus) |

### Application (gated on `local.deploy_application`)

These resources get `count = local.deploy_application ? <original_count> : 0`. In app-only stacks (`existing_cluster_id` provided), these are the ONLY resources that exist.

| File | Resources |
|------|-----------|
| `helm.tf` | ingress-nginx, cert-manager, cert-manager-issuers, prometheus, grafana, grafana PVC, vllm dashboard configmap, NVIDIA GPU operator, milvus, rag, aiq, node labeling, NIM patching, AIQ restart |
| `ingress.tf` | All ingress rules (grafana, prometheus, corrino, portal, enterprise_rag frontends) |
| `app-api.tf` | Corrino CP service + deployment |
| `app-background.tf` | Corrino CP background deployment |
| `app-configmap.tf` | Corrino configmap |
| `app-migration.tf` | Corrino migration job |
| `app-user.tf` | Corrino user job |
| `app-blueprint-portal.tf` | Blueprint portal service + deployment |
| `app-blueprint-deployment-job.tf` | Blueprint configmap, deployment job, configure OKE job, random_id, blueprint undeploy trigger |
| `postgres_db.tf` | PostgreSQL configmap, PVC, deployment, service |
| `26ai.tf` | Oracle 26AI database, k8s secrets |
| `app-vss-fss.tf` | VSS file storage, mount target, export, PV, PVC |
| `app-vss-download-service.tf` | VSS download service + deployment |
| `app-vss-oracle-ux.tf` | VSS Oracle UX configmap, service, deployment, ingress |
| `vss_postgres_db.tf` | VSS PostgreSQL configmap, PVC, deployment, service, secret |
| `object_storage.tf` | PaaS RAG bucket, customer secret key |
| `app-registration.tf` | Registration file + null_resource |
| `app-registration-capacity.tf` | Capacity registration file + null_resource |
| `app-registration-preflight.tf` | Preflight/postflight registration |
| `app-aiq-data-ingestion.tf` | AIQ data ingestion job |
| `data-starter-pack-url.tf` | Deployment readiness checks (if applicable) |

## Implementation Details

### Variables

```hcl
variable "deploy_application" {
  description = "When false, all application-layer resources are skipped. Use this to create an infrastructure-only stack."
  type        = bool
  default     = true
}

variable "existing_cluster_id" {
  description = "OCID of an existing OKE cluster to deploy onto. When provided, all infrastructure creation (VCN, OKE cluster, node pools) is skipped and the app layer deploys directly onto the existing cluster."
  type        = string
  default     = ""
  validation {
    condition     = var.existing_cluster_id == "" || can(regex("^ocid1\\.cluster\\.", var.existing_cluster_id))
    error_message = "existing_cluster_id must be empty or a valid OKE cluster OCID."
  }
}
```

Note: `preserve_infrastructure` has been removed. The two-stack model makes it unnecessary -- the infra stack is simply never destroyed until final cleanup, and the app stack can be freely destroyed.

### Core Locals

```hcl
locals {
  deploy_application    = var.deploy_application
  use_existing_cluster  = var.existing_cluster_id != ""
  create_infrastructure = !local.use_existing_cluster
}
```

### Bring Your Own Cluster: Provider Configuration

When `existing_cluster_id` is provided, the kubernetes and helm providers connect to the existing cluster. The existing `data.oci_containerengine_cluster_kube_config` data source is extended to support both modes:

```hcl
data "oci_containerengine_cluster_kube_config" "oke" {
  cluster_id = local.use_existing_cluster ? var.existing_cluster_id : local.oke_cluster.id
  # ... existing config ...
}
```

The existing locals in `kubernetes.tf` (`local.provider_host`, `local.cluster_ca_certificate`, `local.cluster_id`) continue to derive from this kubeconfig data source -- no changes needed to their derivation logic. The only change is the `cluster_id` input to the data source.

For the `local.oke_cluster` reference used by the kubeconfig data source: when `existing_cluster_id` is provided, infra resources have count=0 so `local.oke_cluster` would be null. The conditional on the data source's `cluster_id` handles this by using `var.existing_cluster_id` directly instead of going through `local.oke_cluster`.

### Infrastructure Resource Gating

All infrastructure resources gain a `local.create_infrastructure` condition:

```hcl
# Before
resource "oci_containerengine_cluster" "oke_cluster" {
  count = var.network_configuration_mode == "create_new" ? 1 : 0
  ...
}

# After
resource "oci_containerengine_cluster" "oke_cluster" {
  count = local.create_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
  ...
}
```

Resources that currently have no count (e.g., `oci_containerengine_node_pool.oke_node_pool`) gain `count = local.create_infrastructure ? 1 : 0`. This is a breaking reference change -- all unindexed references to these resources must be updated to `[0]` throughout the codebase. See "Reference Updates" section.

The `nvidia_gpu_plugin` addon and `oke_kube_config` data source in `oke.tf` currently hardcode `oci_containerengine_cluster.oke_cluster[0].id`. These must be updated to use the unified cluster ID reference:

```hcl
resource "oci_containerengine_addon" "nvidia_gpu_plugin" {
  cluster_id = local.effective_cluster_id
  count      = local.create_infrastructure ? 1 : 0
  ...
}
```

### App Resource Gating

App resources gain a `local.deploy_application` condition:

```hcl
# Resources with no existing count
resource "kubernetes_deployment_v1" "corrino_cp_deployment" {
  count = local.deploy_application ? 1 : 0
  ...
}

# Resources with existing count conditions
# Before
count = var.starter_pack_category == "vss" ? 1 : 0
# After
count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0
```

### Blueprint Undeploy on Destroy

A `terraform_data` resource with a destroy-time `local-exec` provisioner that calls the Corrino API to undeploy all blueprint workloads before the app stack is torn down.

```hcl
resource "terraform_data" "blueprint_undeploy" {
  count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0

  # Capture values at creation time -- destroy provisioner can only reference self
  input = {
    api_url  = local.public_endpoint.api_origin_secure
    username = var.corrino_admin_username
    password = var.corrino_admin_password
  }

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${path.module}/scripts/undeploy_blueprints.py '${self.output.api_url}' '${self.output.username}' '${self.output.password}'"
  }

  depends_on = [
    kubernetes_job_v1.blueprint_deployment_job,
    helm_release.ingress_nginx,
  ]
}
```

**`scripts/undeploy_blueprints.py`**: A new script extracted from the existing undeploy logic in `app-blueprint-deployment-job.tf` (lines 130-171). Contains the same logic:
1. Check if Corrino API is reachable (exit 0 if not -- graceful no-op)
2. Log in and get auth token
3. Fetch workspace recipes
4. Find all Ingress-type deployments and undeploy them
5. Poll until workspace is clear (up to 10 minutes)

This script is shared between the deploy job (which calls it before deploying) and the destroy provisioner (which calls it during teardown).

**Destroy ordering (deterministic -- inverse of creation order):**
1. `blueprint_undeploy` destroyed first -- provisioner calls Corrino API to undeploy all blueprints. At this point, Corrino CP, the ingress, and the load balancer are all still alive.
2. `blueprint_deployment_job` destroyed -- Job object removed from Kubernetes.
3. `corrino_cp_deployment` destroyed -- Corrino pods killed. No orphaned workloads remain because step 1 already cleaned them up.
4. `helm_release.ingress_nginx` destroyed -- ingress controller removed.
5. Remaining app resources destroyed.

**Graceful handling:** If the Corrino API is not reachable (e.g., infrastructure-only stack where `deploy_application = false` was set from the start), the script exits 0. This also handles the case where the cluster is unreachable or Corrino never started.

### Helm Release Node Readiness

Helm releases currently `depends_on = [oci_containerengine_node_pool.oke_node_pool]` to ensure nodes are ready before deploying charts. In app-only stacks (`existing_cluster_id` provided), this resource has count=0.

When the infra resource has count=0, `depends_on` resolves to an empty set -- Terraform treats it as a no-op. Since the existing cluster already has running nodes, Helm charts can deploy immediately without a readiness gate. No replacement mechanism is needed.

If node readiness verification is desired for app-only stacks in the future, a `terraform_data` resource with a `kubectl get nodes` check could be added. This is out of scope for the initial implementation.

### Outputs

The infra stack must output everything needed for subsequent app-only stacks:

```hcl
output "cluster_id" {
  description = "OKE cluster OCID -- pass this as existing_cluster_id to subsequent app-only stacks"
  value       = local.use_existing_cluster ? var.existing_cluster_id : try(local.oke_cluster.id, null)
}

output "cluster_endpoint" {
  description = "OKE cluster API endpoint"
  value       = try(local.effective_cluster_endpoint, null)
}

output "cluster_ca_certificate" {
  description = "OKE cluster CA certificate (base64 encoded)"
  value       = try(local.cluster_ca_certificate, null)
  sensitive   = true
}
```

These outputs are visible in the ORM UI after Apply, making it easy to copy the cluster ID into a new stack.

### Schema Changes

Add variables to `common_schema.yaml` for the ORM UI:

- New variable group: **"Infrastructure Lifecycle"**
  - `deploy_application` -- checkbox, default true
  - `existing_cluster_id` -- text input, default empty, with description explaining the bring-your-own-cluster workflow

### Reference Updates

All `[0]` index references to resources that gain a `count` must be updated throughout the codebase. This is the largest surface area of the change.

**Infra resources gaining count for the first time** (currently no count):
- `oci_containerengine_node_pool.oke_node_pool` -- referenced in `depends_on` across `helm.tf`, `postgres_db.tf`, `26ai.tf`, `secrets.tf`, `vss_postgres_db.tf`, `app-registration.tf`, and others. All `depends_on` references become `oci_containerengine_node_pool.oke_node_pool[0]` when infra is created, or the `depends_on` entries are wrapped in conditionals.
- `oci_containerengine_addon.nvidia_gpu_plugin` -- hardcoded `oke_cluster[0]`, must use unified cluster reference.
- `data.oci_containerengine_cluster_kube_config.oke` -- hardcoded `local.oke_cluster.id`, must support existing cluster path.

**App resources gaining count for the first time** (currently no count):
- `kubernetes_deployment_v1.corrino_cp_deployment` -- referenced in `app-api.tf`, `app-background.tf`, `app-blueprint-deployment-job.tf`
- `kubernetes_service_v1.corrino_cp_service` -- referenced in `ingress.tf`
- `kubernetes_service_v1.postgres` -- referenced in `app-blueprint-deployment-job.tf`
- `kubernetes_config_map_v1.corrino-configmap` -- referenced across app files
- All other app resources listed in the Application boundary table

**Outputs** referencing app resources need `try()` or conditional expressions to handle count=0.

### `local.oke_cluster` Unified Reference

The existing `local.oke_cluster` handles `{create_new, bring_your_own_vcn}`. It must be extended for the `existing_cluster_id` case:

```hcl
locals {
  oke_cluster = local.use_existing_cluster ? null : (
    var.network_configuration_mode == "create_new"
      ? oci_containerengine_cluster.oke_cluster[0]
      : oci_containerengine_cluster.oke_cluster_existing_vcn[0]
  )

  effective_cluster_id = local.use_existing_cluster ? var.existing_cluster_id : local.oke_cluster.id
}
```

All downstream references that need the cluster ID use `local.effective_cluster_id` instead of `local.oke_cluster.id`.

### Test Changes

- New test file `tests/starter_pack_infra_only.tftest.hcl`:
  - `deploy_application = false` results in no app resources planned
  - Infrastructure resources are planned normally
- New test file `tests/starter_pack_existing_cluster.tftest.hcl`:
  - `existing_cluster_id = <mock_ocid>` results in no infra resources planned
  - App resources are planned when `existing_cluster_id` is provided and `deploy_application = true`
  - Kubernetes/helm providers configured from existing cluster data source
- Existing tests pass without changes (all new variables have defaults that preserve current behavior)

## Out of Scope

- Splitting into two entirely separate Terraform root modules (the single codebase with count gating achieves the same effect)
- Skill/workflow changes to automate the two-stack flow (skills can be updated later)
- Data persistence across teardown cycles (PVCs are destroyed with the app layer; fresh data on redeploy is expected)
- Bringing your own VCN + cluster simultaneously (can be combined with existing `network_configuration_mode = "bring_your_own"` in a future iteration)
- Node readiness verification for app-only stacks (nodes are assumed ready since the infra stack created them)
