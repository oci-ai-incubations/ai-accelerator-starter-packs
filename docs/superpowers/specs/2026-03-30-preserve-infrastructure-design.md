# Preserve Infrastructure on Teardown

## Problem

GPU A100 nodes take ~6 hours to recycle after termination. The current integration pipeline destroys all infrastructure (OKE cluster, node pools, networking) alongside the application layer after each test run. This makes iterative testing prohibitively slow.

## Goal

Allow users to tear down the application layer (Corrino, blueprints, Helm charts, databases) while preserving the underlying infrastructure (OKE cluster, node pools, VCN) so that subsequent test runs deploy onto warm nodes without waiting for GPU provisioning.

## Constraints

- `terraform destroy` is all-or-nothing -- there is no native Terraform mechanism to selectively skip resources based on a variable during destroy.
- `prevent_destroy` must be a literal boolean in HashiCorp Terraform (all versions through 1.15.x) -- it cannot accept variables.
- OCI Resource Manager destroy jobs have no `-target` support.
- `prevent_destroy = true` fails the entire destroy plan, not just the protected resource.

## Approach: Apply-Based Teardown + Bring Your Own Cluster

Two complementary features that together enable fast iterative testing:

1. **Apply-based teardown**: Toggle `deploy_application = false` + Apply to destroy the app layer while preserving infrastructure. The infra stack becomes a "warm node pool" waiting for the next deployment.
2. **Bring your own cluster**: Subsequent test runs create a NEW ORM stack that references the existing cluster by ID, skipping all infrastructure creation and deploying only the app layer. This new stack can be fully destroyed via ORM's Destroy button since it contains only app resources.

### Variables

- `preserve_infrastructure` (bool, default `false`) -- set once at stack creation. Signals intent to reuse infrastructure across test runs. When true, infra resources are protected with `prevent_destroy = true` as a safety net.
- `deploy_application` (bool, default `true`) -- toggled to `false` + Apply to tear down the app layer.
- `existing_cluster_id` (string, default `""`) -- when provided, skips OKE cluster/node pool/network creation and deploys the app layer onto the specified existing cluster.

## ORM Workflow

### First Test Run (Infrastructure + App)

1. **Create stack**: Set `preserve_infrastructure = true`. Leave `deploy_application = true` (default). Leave `existing_cluster_id` empty.
2. **Apply**: Everything created -- VCN, OKE cluster, node pools, Corrino, blueprints, Helm charts.
3. **Test**.
4. **Tear down app**: Update `deploy_application = false` in ORM UI -> Apply. App resources destroyed. Infrastructure stays. Stack outputs `cluster_id`, `cluster_endpoint`, and `cluster_ca_certificate`.

### Subsequent Test Runs (App Only, on Warm Nodes)

5. **Create NEW stack**: Set `existing_cluster_id = <cluster_id from step 4>`. Leave `preserve_infrastructure = false` (irrelevant -- no infra to preserve). Leave `deploy_application = true`.
6. **Apply**: App deploys on existing warm nodes. No GPU provisioning wait.
7. **Test**.
8. **Destroy**: Click Destroy in ORM. Works naturally -- this stack only contains app resources. Nodes are untouched (they belong to the infra stack from step 1).
9. **Repeat from step 5** for next test iteration.

### Final Cleanup

10. Go back to the original infra stack. Set `preserve_infrastructure = false`. Destroy.

## Resource Boundary

### Infrastructure (always present in infra stack, skipped in "bring your own cluster" stacks)

These resources are NOT conditional on `deploy_application`. When `preserve_infrastructure = true`, critical resources are protected with `prevent_destroy = true` (literal). When `existing_cluster_id` is provided, these resources are not created at all.

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

### Application (conditional on `local.deploy_application`)

These resources get `count = local.deploy_application ? <original_count> : 0`. In "bring your own cluster" stacks, these are the ONLY resources that exist.

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
| `app-blueprint-deployment-job.tf` | Blueprint configmap, deployment job, configure OKE job, random_id |
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
variable "preserve_infrastructure" {
  description = "When true, infrastructure (VCN, OKE cluster, node pools) is protected from accidental destroy via prevent_destroy. Set once at stack creation for integration pipeline reuse."
  type        = bool
  default     = false
}

variable "deploy_application" {
  description = "When false, all application-layer resources are removed while infrastructure remains. Toggle to false + Apply to tear down the app layer."
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

### Core Locals

```hcl
locals {
  deploy_application    = var.deploy_application
  use_existing_cluster  = var.existing_cluster_id != ""
  create_infrastructure = !local.use_existing_cluster
}
```

### Bring Your Own Cluster: Provider Configuration

When `existing_cluster_id` is provided, the kubernetes and helm providers must connect to the existing cluster. This requires fetching the cluster endpoint and CA certificate via a data source:

```hcl
data "oci_containerengine_cluster" "existing" {
  count      = local.use_existing_cluster ? 1 : 0
  cluster_id = var.existing_cluster_id
}

locals {
  # Unified cluster reference -- works for both created and existing clusters
  effective_cluster_endpoint       = local.use_existing_cluster ? data.oci_containerengine_cluster.existing[0].endpoints[0].public_endpoint : oci_containerengine_cluster.oke_cluster[0].endpoints[0].public_endpoint
  effective_cluster_ca_certificate = local.use_existing_cluster ? base64decode(data.oci_containerengine_cluster.existing[0].endpoints[0].certificate_authority) : base64decode(oci_containerengine_cluster.oke_cluster[0].endpoints[0].certificate_authority)
}
```

The kubernetes/helm providers reference `local.effective_cluster_endpoint` and `local.effective_cluster_ca_certificate` instead of directly referencing the cluster resource.

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

When `existing_cluster_id` is provided, `create_infrastructure = false`, so all infra resources have count=0 and are never created.

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

### Safety Net: `prevent_destroy` on Critical Infrastructure

Since `prevent_destroy` must be a literal, use dual resource blocks for critical GPU-related resources:

```hcl
# Unprotected (default)
resource "oci_containerengine_cluster" "oke_cluster" {
  count = local.create_infrastructure && !var.preserve_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
  # ... config ...
}

# Protected
resource "oci_containerengine_cluster" "oke_cluster_protected" {
  count = local.create_infrastructure && var.preserve_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
  # ... same config ...
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # Unified reference
  oke_cluster = var.preserve_infrastructure ? (
    length(oci_containerengine_cluster.oke_cluster_protected) > 0 ? oci_containerengine_cluster.oke_cluster_protected[0] : null
  ) : (
    length(oci_containerengine_cluster.oke_cluster) > 0 ? oci_containerengine_cluster.oke_cluster[0] : null
  )
}
```

**Critical resources to protect (dual-block pattern):**
- `oci_containerengine_cluster.oke_cluster` (both create_new and bring_your_own variants)
- `oci_containerengine_node_pool.oke_node_pool` (control plane)
- `oci_containerengine_node_pool.worker_cpu_pool`
- `oci_core_instance_pool.worker_nodes_pool`
- `oci_core_instance_configuration.worker_nodes_configuration`

Other infra resources (networking, bastion, images) don't need `prevent_destroy` since they provision quickly.

### Blueprint Undeploy Job

A dedicated Kubernetes Job that undeploys running blueprints via the Corrino API before Corrino itself is torn down.

```hcl
resource "kubernetes_job_v1" "blueprint_undeploy_job" {
  count = !local.deploy_application ? 1 : 0

  depends_on = [
    kubernetes_deployment_v1.corrino_cp_deployment,
    kubernetes_service_v1.corrino_cp_service
  ]

  # wait_for_completion = true
  # Runs undeploy-only script:
  #   1. Check if Corrino is reachable (exit 0 if not -- graceful no-op)
  #   2. Log into Corrino API
  #   3. Fetch workspace recipes
  #   4. Find all deployments and undeploy them
  #   5. Poll until workspace is clear (up to 10 minutes)
}
```

**Ordering via Terraform's dependency graph:**

When `deploy_application` goes `true` -> `false`:
1. CREATE `blueprint_undeploy_job` (Corrino is still running, job calls API, waits for completion)
2. DESTROY `corrino_cp_deployment` and other app resources (blueprints already cleaned up)

**Graceful handling:** The undeploy script checks if Corrino is reachable before attempting undeploy. If Corrino is not running (e.g., `deploy_application` was never `true`), the job exits 0.

### Outputs

The infra stack must output everything needed for subsequent "bring your own cluster" stacks:

```hcl
output "cluster_id" {
  description = "OKE cluster OCID -- pass this as existing_cluster_id to subsequent app-only stacks"
  value       = local.use_existing_cluster ? var.existing_cluster_id : try(local.oke_cluster.id, null)
}

output "cluster_endpoint" {
  description = "OKE cluster API endpoint"
  value       = try(local.effective_cluster_endpoint, null)
}
```

These outputs are visible in the ORM UI after Apply, making it easy to copy the cluster ID into a new stack.

### Schema Changes

Add variables to `common_schema.yaml` for the ORM UI:

- New variable group: **"Infrastructure Lifecycle"**
  - `preserve_infrastructure` -- checkbox, default false
  - `deploy_application` -- checkbox, default true
  - `existing_cluster_id` -- text input, default empty, with description explaining the bring-your-own-cluster workflow

### Reference Updates

All `[0]` index references to resources that gain a `count` must be updated throughout the codebase:
- `kubernetes_deployment_v1.corrino_cp_deployment.metadata[0].name` becomes `kubernetes_deployment_v1.corrino_cp_deployment[0].metadata[0].name`
- Outputs referencing app resources need `try()` or conditional expressions to handle count=0
- All references to `oci_containerengine_cluster.oke_cluster[0]` must go through `local.oke_cluster` or `local.effective_cluster_*` to support both created and existing cluster modes
- Provider configurations must reference the unified `local.effective_cluster_*` locals

### Test Changes

- New test file `tests/starter_pack_preserve_infra.tftest.hcl`:
  - `deploy_application = false` results in no app resources planned
  - `preserve_infrastructure = true` with `deploy_application = true` creates everything
  - Infrastructure resources are always planned regardless of `deploy_application`
- New test file `tests/starter_pack_existing_cluster.tftest.hcl`:
  - `existing_cluster_id = <mock_ocid>` results in no infra resources planned
  - App resources are planned when `existing_cluster_id` is provided and `deploy_application = true`
  - Kubernetes/helm providers configured from existing cluster data source
- Existing tests pass without changes (all new variables have defaults that preserve current behavior)

## Out of Scope

- Splitting into two entirely separate Terraform root modules (the "bring your own cluster" feature achieves the same effect within a single codebase)
- Skill/workflow changes to automate the toggle (skills can be updated later to orchestrate the teardown + new-stack flow)
- Data persistence across teardown cycles (PVCs are destroyed with the app layer; fresh data on redeploy is expected)
- Bringing your own VCN + cluster simultaneously (can be combined with existing `network_configuration_mode = "bring_your_own"` in a future iteration)
