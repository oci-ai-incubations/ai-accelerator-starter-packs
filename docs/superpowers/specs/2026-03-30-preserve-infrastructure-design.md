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

## Approach: Apply-Based Teardown

Instead of using `terraform destroy` for partial teardown, use `terraform apply` with a variable toggle:

- `preserve_infrastructure` (bool, default `false`) -- set once at stack creation. Signals intent to reuse infrastructure across test runs.
- `deploy_application` (bool, default `true`) -- toggled to `false` + Apply to tear down the app layer. Toggled back to `true` + Apply to redeploy.

When `preserve_infrastructure = true`, the ORM "Destroy" button should be blocked by `prevent_destroy = true` (literal) on infrastructure resources as a safety net. Full destroy requires `preserve_infrastructure = false`.

## ORM Workflow

1. **Create stack**: Set `preserve_infrastructure = true` in ORM UI. `deploy_application = true` (default).
2. **First deploy**: Apply -- everything created (infra + app).
3. **Test**.
4. **Tear down app**: Update `deploy_application = false` in ORM UI -- Apply. App resources destroyed, nodes stay.
5. **Redeploy app**: Update `deploy_application = true` -- Apply. App deploys on warm nodes.
6. **Full destroy** (when done for real): Set `preserve_infrastructure = false`, ensure `deploy_application = false` -- Destroy.

## Resource Boundary

### Infrastructure (always present)

These resources are NOT conditional on `deploy_application`. When `preserve_infrastructure = true`, they are protected with `prevent_destroy = true` (literal).

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

These resources get `count = local.deploy_application ? <original_count> : 0`.

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
| `data-starter-pack-url.tf` | Deployment readiness checks (if any resources exist here) |

## Implementation Details

### Variables

```hcl
variable "preserve_infrastructure" {
  description = "When true, infrastructure (VCN, OKE cluster, node pools) is protected from accidental destroy. Use deploy_application to control the app layer lifecycle."
  type        = bool
  default     = false
}

variable "deploy_application" {
  description = "When false, all application-layer resources are removed while infrastructure remains. Toggle to false + Apply to tear down the app, toggle to true + Apply to redeploy."
  type        = bool
  default     = true
}
```

### Convenience Local

```hcl
locals {
  deploy_application = var.deploy_application
}
```

### Conditional Pattern for App Resources

Resources with no existing count:
```hcl
# Before
resource "kubernetes_deployment_v1" "corrino_cp_deployment" { ... }

# After
resource "kubernetes_deployment_v1" "corrino_cp_deployment" {
  count = local.deploy_application ? 1 : 0
  ...
}
```

Resources with existing count conditions:
```hcl
# Before
count = var.starter_pack_category == "vss" ? 1 : 0

# After
count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0
```

### Safety Net: `prevent_destroy` on Infrastructure

When `preserve_infrastructure = true`, infrastructure resources are protected. Since `prevent_destroy` must be a literal, use two resource blocks:

```hcl
# Unprotected (default)
resource "oci_containerengine_cluster" "oke_cluster" {
  count = !var.preserve_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
  # ... config ...
}

# Protected
resource "oci_containerengine_cluster" "oke_cluster_protected" {
  count = var.preserve_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
  # ... same config ...
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  oke_cluster = var.preserve_infrastructure ? oci_containerengine_cluster.oke_cluster_protected[0] : oci_containerengine_cluster.oke_cluster[0]
}
```

**Note:** This dual-resource pattern is only needed for the critical GPU-related resources where accidental destroy is catastrophic (OKE cluster, GPU node pool, GPU instance pool). Networking and other infra resources don't need `prevent_destroy` since they provision quickly.

**Critical resources to protect:**
- `oci_containerengine_cluster.oke_cluster` (both variants)
- `oci_containerengine_node_pool.oke_node_pool` (control plane)
- `oci_containerengine_node_pool.worker_cpu_pool`
- `oci_core_instance_pool.worker_nodes_pool`
- `oci_core_instance_configuration.worker_nodes_configuration`

### Blueprint Undeploy Job

A dedicated Kubernetes Job that undeploys running blueprints via the Corrino API before Corrino itself is torn down.

```hcl
resource "kubernetes_job_v1" "blueprint_undeploy_job" {
  count = !var.deploy_application ? 1 : 0

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

When `deploy_application` goes `false` -> `true`:
1. DESTROY `blueprint_undeploy_job` (just deletes completed K8s Job object)
2. CREATE Corrino CP, then blueprint deployment job (deploys on clean cluster)

**Graceful handling:** The undeploy script checks if Corrino is reachable before attempting undeploy. If Corrino is not running (e.g., first deploy with `deploy_application = false`), the job exits 0.

### Schema Changes

Add both variables to `common_schema.yaml` so they appear in the ORM UI:

- `preserve_infrastructure` -- checkbox, default false, in a new "Infrastructure Lifecycle" variable group
- `deploy_application` -- checkbox, default true, in the same variable group

### Reference Updates

All `[0]` index references to resources that gain a `count` must be updated throughout the codebase. For example:
- `kubernetes_deployment_v1.corrino_cp_deployment.metadata[0].name` becomes `kubernetes_deployment_v1.corrino_cp_deployment[0].metadata[0].name`
- Outputs referencing app resources need `try()` or conditional expressions to handle count=0

### Test Changes

- Add a new test file `tests/starter_pack_preserve_infra.tftest.hcl` that validates:
  - `deploy_application = false` results in no app resources planned
  - `preserve_infrastructure = true` with `deploy_application = true` creates everything
  - Infrastructure resources are always planned regardless of `deploy_application`
- Update existing test files to account for the new variables (default values mean existing tests pass without changes)

## Out of Scope

- Splitting into two ORM stacks (future consideration if this approach proves insufficient)
- Skill/workflow changes to automate the toggle (skills can be updated later to orchestrate Apply-based teardown)
- Data persistence across teardown cycles (PVCs are destroyed with the app layer; fresh data on redeploy is expected)
