# Preserve Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable GPU node reuse across test runs by splitting infrastructure and application into independently deployable layers via count gating.

**Architecture:** Two new variables (`deploy_application` and `existing_cluster_id`) gate resource creation. Infrastructure resources (VCN, OKE, node pools) are gated on `local.create_infrastructure`. Application resources (Helm, Corrino, blueprints) are gated on `local.deploy_application`. A destroy-time provisioner calls the Corrino undeploy API before app teardown. Provider configuration is unified through `local.effective_cluster_id` to support both created and existing clusters.

**Tech Stack:** Terraform >= 1.5, OCI Provider ~> 7.0, Kubernetes/Helm providers, Python 3 (for undeploy script)

**Spec:** `docs/superpowers/specs/2026-03-30-preserve-infrastructure-design.md`

---

## File Structure

### New Files
- `ai-accelerator-tf/scripts/undeploy_blueprints.py` — Extracted undeploy logic, shared between deploy job and destroy provisioner

### Modified Files
- `ai-accelerator-tf/vars.tf` — Add `deploy_application`, `existing_cluster_id` variables
- `ai-accelerator-tf/app-locals.tf` — Add `deploy_application`, `use_existing_cluster`, `create_infrastructure`, `effective_cluster_id` locals
- `ai-accelerator-tf/data.tf` — Update kubeconfig data source to support existing cluster
- `ai-accelerator-tf/oke.tf` — Update `local.oke_cluster`, gate node pools, fix `nvidia_gpu_plugin` and `oke_kube_config` references
- `ai-accelerator-tf/kubernetes.tf` — Gate namespaces on `create_infrastructure`
- `ai-accelerator-tf/network.tf` — Gate all networking resources
- `ai-accelerator-tf/capacity_check.tf` — Gate capacity reports
- `ai-accelerator-tf/compute.tf` — Gate bastion/operator
- `ai-accelerator-tf/instance_pools.tf` — Gate instance pools/configs
- `ai-accelerator-tf/custom_image_import.tf` — Gate GPU images
- `ai-accelerator-tf/orm-private-endpoint.tf` — Gate ORM PE
- `ai-accelerator-tf/rbac.tf` — Gate RBAC
- `ai-accelerator-tf/helm.tf` — Gate all Helm releases and related resources on `deploy_application`
- `ai-accelerator-tf/ingress.tf` — Gate all ingress rules
- `ai-accelerator-tf/app-api.tf` — Gate Corrino CP
- `ai-accelerator-tf/app-background.tf` — Gate background worker
- `ai-accelerator-tf/app-configmap.tf` — Gate configmap
- `ai-accelerator-tf/app-migration.tf` — Gate migration job
- `ai-accelerator-tf/app-user.tf` — Gate user job
- `ai-accelerator-tf/app-blueprint-portal.tf` — Gate portal
- `ai-accelerator-tf/app-blueprint-deployment-job.tf` — Gate blueprint resources, add undeploy trigger
- `ai-accelerator-tf/postgres_db.tf` — Gate PostgreSQL
- `ai-accelerator-tf/26ai.tf` — Gate Oracle 26AI
- `ai-accelerator-tf/app-vss-fss.tf` — Gate VSS FSS
- `ai-accelerator-tf/app-vss-download-service.tf` — Gate VSS download
- `ai-accelerator-tf/app-vss-oracle-ux.tf` — Gate VSS Oracle UX
- `ai-accelerator-tf/vss_postgres_db.tf` — Gate VSS PostgreSQL
- `ai-accelerator-tf/object_storage.tf` — Gate PaaS RAG storage
- `ai-accelerator-tf/app-registration.tf` — Gate registration
- `ai-accelerator-tf/app-registration-capacity.tf` — Gate capacity registration
- `ai-accelerator-tf/app-registration-preflight.tf` — Gate preflight registration
- `ai-accelerator-tf/app-aiq-data-ingestion.tf` — Gate AIQ ingestion
- `ai-accelerator-tf/outputs.tf` — Wrap all outputs with `try()` for count=0 safety
- `ai-accelerator-tf/schemas/common_schema.yaml` — Add new variables to ORM UI

### New Test Files
- `ai-accelerator-tf/tests/starter_pack_infra_only.tftest.hcl` — Tests for `deploy_application = false`
- `ai-accelerator-tf/tests/starter_pack_existing_cluster.tftest.hcl` — Tests for `existing_cluster_id`

---

### Task 1: Add Variables and Core Locals

**Files:**
- Modify: `ai-accelerator-tf/vars.tf`
- Modify: `ai-accelerator-tf/app-locals.tf`

- [ ] **Step 1: Add `deploy_application` variable to `vars.tf`**

Add after the existing `skip_capacity_check` variable (around line 512):

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

- [ ] **Step 2: Add core locals to `app-locals.tf`**

Add at the top of the `locals` block (line 2, inside the existing `locals {}`):

```hcl
  deploy_application    = var.deploy_application
  use_existing_cluster  = var.existing_cluster_id != ""
  create_infrastructure = !local.use_existing_cluster
```

- [ ] **Step 3: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform init -backend=false && terraform validate
```

Expected: Format and validation pass. No functional changes yet — defaults preserve existing behavior.

- [ ] **Step 4: Commit**

```bash
git add ai-accelerator-tf/vars.tf ai-accelerator-tf/app-locals.tf
git commit -m "feat: add deploy_application and existing_cluster_id variables"
```

---

### Task 2: Update Cluster Reference Chain

The provider chain is: `data.oci_containerengine_cluster_kube_config.oke` → `kubernetes.tf` locals → `providers.tf`. We need to make the data source support both created and existing clusters.

**Files:**
- Modify: `ai-accelerator-tf/oke.tf:85-90` — Update `local.oke_cluster`
- Modify: `ai-accelerator-tf/data.tf:35-38` — Update kubeconfig data source
- Modify: `ai-accelerator-tf/oke.tf:208-222` — Fix `nvidia_gpu_plugin` and `oke_kube_config`
- Modify: `ai-accelerator-tf/app-locals.tf` — Add `effective_cluster_id`

- [ ] **Step 1: Add `effective_cluster_id` local to `app-locals.tf`**

Add after the `create_infrastructure` local:

```hcl
  effective_cluster_id = local.use_existing_cluster ? var.existing_cluster_id : local.oke_cluster.id
```

- [ ] **Step 2: Update `local.oke_cluster` in `oke.tf` (line 85-90)**

Replace the existing `local.oke_cluster` with a version that handles null when using existing cluster:

```hcl
locals {
  oke_cluster = local.create_infrastructure ? (
    var.network_configuration_mode == "create_new" ?
    oci_containerengine_cluster.oke_cluster[0] :
    oci_containerengine_cluster.oke_cluster_existing_vcn[0]
  ) : null
}
```

- [ ] **Step 3: Update `data.oci_containerengine_cluster_kube_config.oke` in `data.tf` (line 35-38)**

Replace:
```hcl
data "oci_containerengine_cluster_kube_config" "oke" {
  cluster_id    = local.oke_cluster.id
  token_version = "2.0.0"
}
```

With:
```hcl
data "oci_containerengine_cluster_kube_config" "oke" {
  cluster_id    = local.effective_cluster_id
  token_version = "2.0.0"
}
```

- [ ] **Step 4: Update `nvidia_gpu_plugin` in `oke.tf` (line 208-218)**

Replace the hardcoded `oci_containerengine_cluster.oke_cluster[0].id` with the unified reference and gate on `create_infrastructure`:

```hcl
resource "oci_containerengine_addon" "nvidia_gpu_plugin" {
  addon_name                       = "NvidiaGpuPlugin"
  cluster_id                       = local.effective_cluster_id
  remove_addon_resources_on_delete = true
  override_existing                = true
  configurations {
    key   = "isDcgmExporterDisabled"
    value = "true"
  }
  count = local.create_infrastructure ? 1 : 0
}
```

- [ ] **Step 5: Update `oke_kube_config` data source in `oke.tf` (line 220-222)**

Replace the hardcoded reference:

```hcl
data "oci_containerengine_cluster_kube_config" "oke_kube_config" {
  cluster_id = local.effective_cluster_id
}
```

- [ ] **Step 6: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform validate
```

Expected: Pass. With default values (`existing_cluster_id = ""`), behavior is unchanged.

- [ ] **Step 7: Commit**

```bash
git add ai-accelerator-tf/oke.tf ai-accelerator-tf/data.tf ai-accelerator-tf/app-locals.tf
git commit -m "feat: unify cluster reference chain for existing cluster support"
```

---

### Task 3: Gate Infrastructure Resources

Add `local.create_infrastructure` condition to all infrastructure resources. Resources that already have a count condition get `local.create_infrastructure &&` prepended. Resources with no count get `count = local.create_infrastructure ? 1 : 0`.

**Files:**
- Modify: `ai-accelerator-tf/oke.tf` — Gate cluster, node pools
- Modify: `ai-accelerator-tf/network.tf` — Gate all networking (already has `local.create_network_resources`)
- Modify: `ai-accelerator-tf/instance_pools.tf` — Gate instance pools/configs
- Modify: `ai-accelerator-tf/capacity_check.tf` — Gate capacity reports
- Modify: `ai-accelerator-tf/compute.tf` — Gate bastion/operator
- Modify: `ai-accelerator-tf/custom_image_import.tf` — Gate GPU images
- Modify: `ai-accelerator-tf/orm-private-endpoint.tf` — Gate ORM PE
- Modify: `ai-accelerator-tf/rbac.tf` — Gate RBAC
- Modify: `ai-accelerator-tf/kubernetes.tf` — Gate namespaces

- [ ] **Step 1: Gate OKE cluster resources in `oke.tf`**

For `oci_containerengine_cluster.oke_cluster`:
```hcl
# Before
count = var.network_configuration_mode == "create_new" ? 1 : 0
# After
count = local.create_infrastructure && var.network_configuration_mode == "create_new" ? 1 : 0
```

For `oci_containerengine_cluster.oke_cluster_existing_vcn`:
```hcl
# Before
count = var.network_configuration_mode == "bring_your_own" ? 1 : 0
# After
count = local.create_infrastructure && var.network_configuration_mode == "bring_your_own" ? 1 : 0
```

For `oci_containerengine_node_pool.oke_node_pool` (currently NO count):
```hcl
# Add count
count = local.create_infrastructure ? 1 : 0
```

For `oci_containerengine_node_pool.worker_cpu_pool`:
```hcl
# Before
count = local.starter_pack_config.cpu_worker_node_pool_size > 0 ? 1 : 0
# After
count = local.create_infrastructure && local.starter_pack_config.cpu_worker_node_pool_size > 0 ? 1 : 0
```

For `tls_private_key.oke_ssh_key`:
```hcl
# Before
count = var.ssh_public_key == "" ? 1 : 0
# After
count = local.create_infrastructure && var.ssh_public_key == "" ? 1 : 0
```

- [ ] **Step 2: Update `network.tf` — prepend `local.create_infrastructure` to existing conditions**

The networking resources already have `count = local.create_network_resources ? 1 : 0`. Update the `create_network_resources` local definition (find it in the codebase — likely in `app-locals.tf` or `network.tf`) to incorporate `create_infrastructure`:

```hcl
# Find the existing local.create_network_resources definition and update it.
# If it's: create_network_resources = var.network_configuration_mode == "create_new"
# Change to: create_network_resources = local.create_infrastructure && var.network_configuration_mode == "create_new"
```

If `create_network_resources` is used broadly, this single change gates ALL networking resources. If it's defined differently, prepend `local.create_infrastructure &&` to each networking resource's count individually.

- [ ] **Step 3: Gate `instance_pools.tf` resources**

For `oci_core_instance_configuration.worker_nodes_configuration`:
```hcl
# Before
count = local.should_import_nvidia_gpu_image ? 1 : 0
# After
count = local.create_infrastructure && local.should_import_nvidia_gpu_image ? 1 : 0
```

For `oci_core_instance_pool.worker_nodes_pool`:
```hcl
# Before
count = local.should_import_nvidia_gpu_image ? 1 : 0
# After
count = local.create_infrastructure && local.should_import_nvidia_gpu_image ? 1 : 0
```

`oci_core_cluster_network.worker_nodes_cluster_network` already has `count = 0`, no change needed.

- [ ] **Step 4: Gate `capacity_check.tf` resources**

Capacity checks should only run when creating infrastructure. Find each `oci_core_compute_capacity_report` resource's `for_each` and add a `create_infrastructure` gate. Also gate `terraform_data.capacity_validated`:

```hcl
# For capacity_validated, add to its count or wrap in create_infrastructure
count = local.create_infrastructure ? 1 : 0
```

For the capacity reports, update the `for_each` conditionals to include `local.create_infrastructure`:

```hcl
# Pattern for each capacity report:
# Before
for_each = var.skip_capacity_check ? {} : { ... }
# After
for_each = !local.create_infrastructure || var.skip_capacity_check ? {} : { ... }
```

- [ ] **Step 5: Gate `compute.tf` resources (bastion/operator)**

These already have count conditions involving `local.create_network_resources`. If `create_network_resources` was updated in Step 2 to include `create_infrastructure`, these are already gated. If not, prepend `local.create_infrastructure &&` to each count.

- [ ] **Step 6: Gate `custom_image_import.tf` resources**

```hcl
# For oci_core_image.nvidia_image
# Before
count = local.should_import_nvidia_gpu_image ? 1 : 0
# After
count = local.create_infrastructure && local.should_import_nvidia_gpu_image ? 1 : 0

# For oci_core_image.amd_image
# Before
count = local.should_import_amd_gpu_image ? 1 : 0
# After
count = local.create_infrastructure && local.should_import_amd_gpu_image ? 1 : 0
```

- [ ] **Step 7: Gate `orm-private-endpoint.tf` resources**

```hcl
# Already has local.create_orm_private_endpoint condition
# Update the local definition to include create_infrastructure
# Or prepend to each resource's count
```

- [ ] **Step 8: Gate `rbac.tf` resources**

```hcl
# Before (count = 1)
count = 1
# After
count = local.create_infrastructure ? 1 : 0
```

Do this for both `kubernetes_cluster_role_v1.corrino_cluster_role` and `kubernetes_cluster_role_binding_v1.corrino_cluster_role_binding`.

- [ ] **Step 9: Gate `kubernetes.tf` namespace resources**

For `kubernetes_namespace_v1.cluster_tools`:
```hcl
# Before (no count)
# After
count = local.create_infrastructure ? 1 : 0
```

For `kubernetes_namespace_v1.milvus`:
```hcl
# Before
count = var.starter_pack_category == "vss" ? 1 : 0
# After
count = local.create_infrastructure && var.starter_pack_category == "vss" ? 1 : 0
```

**Important:** `cluster_tools` namespace is referenced by Helm releases via `kubernetes_namespace_v1.cluster_tools.id`. When it gains a count, this becomes `kubernetes_namespace_v1.cluster_tools[0].id`. All references in `helm.tf` must be updated in Task 4.

- [ ] **Step 10: Fix all `[0]` index references for newly-counted infra resources**

`oci_containerengine_node_pool.oke_node_pool` previously had no count. Every reference to it must now use `[0]`. Search the entire codebase:

```bash
cd ai-accelerator-tf && grep -rn "oke_node_pool\b" --include="*.tf" | grep -v "\[0\]" | grep -v "count"
```

Update every match to use `[0]` indexing. Common locations:
- `helm.tf` — `depends_on` blocks
- `postgres_db.tf` — `depends_on`
- `26ai.tf` — `depends_on`
- `secrets.tf` — `depends_on`
- `outputs.tf` — direct references (handled in Task 6)

Similarly for `kubernetes_namespace_v1.cluster_tools`:
```bash
grep -rn "cluster_tools\b" --include="*.tf" | grep -v "\[0\]" | grep -v "count"
```

Update all references to `kubernetes_namespace_v1.cluster_tools[0]`.

- [ ] **Step 11: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform validate
```

- [ ] **Step 12: Commit**

```bash
git add ai-accelerator-tf/
git commit -m "feat: gate all infrastructure resources on create_infrastructure"
```

---

### Task 4: Gate Application Resources

Add `local.deploy_application` condition to all application resources.

**Files:**
- Modify: All `app-*.tf` files, `helm.tf`, `ingress.tf`, `postgres_db.tf`, `26ai.tf`, `vss_postgres_db.tf`, `object_storage.tf`

- [ ] **Step 1: Gate `helm.tf` resources**

For EVERY `helm_release` resource (ingress_nginx, nvidia-gpu-operator, cert_manager, cert_manager_issuers, prometheus, grafana) and related resources (grafana PVC, vllm dashboard configmap):

```hcl
# Resources with no existing count — add:
count = local.deploy_application ? 1 : 0

# Resources with existing count — prepend:
# Before
count = var.starter_pack_category == "vss" ? 1 : 0
# After
count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0
```

Apply to all Helm releases and Kubernetes resources in `helm.tf`:
- `helm_release.ingress_nginx`
- `helm_release.nvidia-gpu-operator`
- `helm_release.cert_manager`
- `helm_release.cert_manager_issuers`
- `helm_release.prometheus`
- `helm_release.grafana`
- `kubernetes_persistent_volume_claim_v1.grafana`
- `kubernetes_config_map_v1.vllm_dashboard`
- `helm_release.milvus`
- `helm_release.rag`
- `helm_release.aiq`
- All `terraform_data` and `local_sensitive_file` resources in helm.tf

Also update `depends_on` references to newly-counted resources. For example, every `depends_on = [oci_containerengine_node_pool.oke_node_pool]` becomes `depends_on = [oci_containerengine_node_pool.oke_node_pool]` — `depends_on` with count-0 resources resolves to an empty set (no-op), so the references still work syntactically. **No changes needed to `depends_on` entries.**

Update `namespace` references to `kubernetes_namespace_v1.cluster_tools[0].id` (from Step 10 of Task 3).

- [ ] **Step 2: Gate `ingress.tf` resources**

For all ingress rules — add `local.deploy_application` to their count:

```hcl
# grafana_ingress (no current count) — add:
count = local.deploy_application ? 1 : 0

# prometheus_ingress (no current count) — add:
count = local.deploy_application ? 1 : 0

# corrino_cp_ingress — prepend:
count = local.deploy_application && var.ingress_nginx_enabled ? 1 : 0

# oci_ai_blueprints_portal_ingress — prepend:
count = local.deploy_application && var.ingress_nginx_enabled ? 1 : 0

# enterprise_rag_frontend_ingress — prepend:
count = local.deploy_application && var.starter_pack_category == "enterprise_rag" ? 1 : 0

# enterprise_rag_aiq_frontend_ingress — prepend:
count = local.deploy_application && var.starter_pack_category == "enterprise_rag_aiq" ? 1 : 0
```

- [ ] **Step 3: Gate `app-api.tf`, `app-background.tf`, `app-configmap.tf`, `app-migration.tf`, `app-user.tf`**

Each of these files contains resources with no current count. Add to each:

```hcl
count = local.deploy_application ? 1 : 0
```

Resources:
- `kubernetes_service_v1.corrino_cp_service`
- `kubernetes_deployment_v1.corrino_cp_deployment`
- `kubernetes_deployment_v1.corrino_cp_background_deployment`
- `kubernetes_config_map_v1.corrino-configmap`
- `kubernetes_job_v1.corrino_migration_job` (already has `count = 1`, change to `count = local.deploy_application ? 1 : 0`)
- `kubernetes_job_v1.corrino_user_job`

Update all internal cross-references to use `[0]` indexing. For example, `corrino_cp_service` depends on `corrino_cp_deployment` — update `depends_on` references.

- [ ] **Step 4: Gate `app-blueprint-portal.tf`**

```hcl
# Both resources — add:
count = local.deploy_application ? 1 : 0
```

- [ ] **Step 5: Gate `app-blueprint-deployment-job.tf` resources**

For `blueprint_config_map`:
```hcl
# Before
count = contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 0 : 1
# After
count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
```

For `configure_oke_for_blueprint_deployment_job`:
```hcl
# Before
count = local.starter_pack_config.create_ngc_secrets_in_cluster ? 1 : 0
# After
count = local.deploy_application && local.starter_pack_config.create_ngc_secrets_in_cluster ? 1 : 0
```

For `random_id.blueprint_deploy_id`:
```hcl
# Before
count = !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
# After
count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
```

For `blueprint_deployment_job`:
```hcl
# Before
count = contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 0 : 1
# After
count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0
```

For `custom_dns_configuration_warning`:
```hcl
# Before
count = var.use_custom_dns ? 1 : 0
# After
count = local.deploy_application && var.use_custom_dns ? 1 : 0
```

- [ ] **Step 6: Gate `postgres_db.tf`**

All resources gain `local.deploy_application`:

```hcl
# kubernetes_config_map_v1.postgres_secret — add:
count = local.deploy_application ? 1 : 0

# kubernetes_persistent_volume_claim_v1.postgresql_pv_claim — add:
count = local.deploy_application ? 1 : 0

# kubernetes_deployment_v1.postgres — add:
count = local.deploy_application ? 1 : 0

# kubernetes_service_v1.postgres — add:
count = local.deploy_application ? 1 : 0

# data.kubernetes_service_v1.postgres_service — add:
count = local.deploy_application ? 1 : 0
```

Update all internal `depends_on` and attribute references to use `[0]`.

- [ ] **Step 7: Gate `26ai.tf`**

```hcl
# All resources already have count = local.needs_26ai ? 1 : 0
# Prepend:
count = local.deploy_application && local.needs_26ai ? 1 : 0
```

- [ ] **Step 8: Gate VSS resources (`app-vss-fss.tf`, `app-vss-download-service.tf`, `app-vss-oracle-ux.tf`, `vss_postgres_db.tf`)**

All VSS resources already have `count = var.starter_pack_category == "vss" ? 1 : 0`. Prepend:

```hcl
count = local.deploy_application && var.starter_pack_category == "vss" ? 1 : 0
```

- [ ] **Step 9: Gate `object_storage.tf`**

```hcl
# oci_objectstorage_bucket.paas_rag_bucket
# Before
count = var.starter_pack_category == "paas_rag" ? 1 : 0
# After
count = local.deploy_application && var.starter_pack_category == "paas_rag" ? 1 : 0

# oci_identity_customer_secret_key.aws_compat_access_key
# Before
count = var.starter_pack_category == "paas_rag" && var.aws_access_key_id == null ? 1 : 0
# After
count = local.deploy_application && var.starter_pack_category == "paas_rag" && var.aws_access_key_id == null ? 1 : 0
```

- [ ] **Step 10: Gate registration resources (`app-registration.tf`, `app-registration-capacity.tf`, `app-registration-preflight.tf`)**

All resources gain `local.deploy_application ? 1 : 0` or prepend to existing count.

- [ ] **Step 11: Gate `app-aiq-data-ingestion.tf`**

```hcl
# Before
count = var.starter_pack_category == "enterprise_rag_aiq" ? 1 : 0
# After
count = local.deploy_application && var.starter_pack_category == "enterprise_rag_aiq" ? 1 : 0
```

- [ ] **Step 12: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform validate
```

Fix any reference errors from newly-counted resources missing `[0]` indexing.

- [ ] **Step 13: Commit**

```bash
git add ai-accelerator-tf/
git commit -m "feat: gate all application resources on deploy_application"
```

---

### Task 5: Create Undeploy Script and Destroy-Time Provisioner

**Files:**
- Create: `ai-accelerator-tf/scripts/undeploy_blueprints.py`
- Modify: `ai-accelerator-tf/app-blueprint-deployment-job.tf`

- [ ] **Step 1: Create `scripts/undeploy_blueprints.py`**

Extract the undeploy logic from the existing inline Python in `app-blueprint-deployment-job.tf` (lines 130-171):

```python
#!/usr/bin/env python3
"""Undeploy all Ingress-type blueprint deployments via the Corrino API.

Usage: undeploy_blueprints.py <api_url> <username> <password>

Exits 0 if:
  - API is not reachable (nothing to undeploy)
  - No token obtained (Corrino not ready)
  - No deployments found
  - All deployments successfully undeployed
Exits 1 if:
  - Undeploy fails for any deployment
  - Timeout waiting for workspace to clear
"""
import json
import ssl
import sys
import time
import urllib.request
from urllib.error import HTTPError
from urllib.parse import urlencode

api_url = sys.argv[1].rstrip("/")
username, password = sys.argv[2], sys.argv[3]

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Login
try:
    login = urllib.request.urlopen(
        urllib.request.Request(
            api_url + "/login/",
            data=urlencode({"username": username, "password": password}).encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        ),
        context=ctx,
    )
    token = json.load(login).get("token") if login else None
except Exception as e:
    print("API not reachable, skipping undeploy:", e)
    sys.exit(0)

if not token:
    print("No token, skipping undeploy.")
    sys.exit(0)

# Get workspace recipes
try:
    req = urllib.request.Request(
        api_url + "/workspace/",
        headers={"Authorization": "Token %s" % token},
        method="GET",
    )
    ws = json.load(urllib.request.urlopen(req, context=ctx))
    recipes = ws.get("recipes") or {}
except Exception as e:
    print("No workspace, skipping undeploy:", e)
    sys.exit(0)

# Find Ingress-type deployments
uuids = [
    r.get("deployment-uuid", "")
    for r in recipes.values()
    if r.get("type") == "Ingress" and r.get("deployment-uuid")
]

# Undeploy each
for uuid in uuids:
    try:
        r = urllib.request.urlopen(
            urllib.request.Request(
                api_url + "/undeploy/",
                data=json.dumps({"deployment_uuid": uuid}).encode(),
                headers={
                    "Authorization": "Token %s" % token,
                    "Content-Type": "application/json",
                },
                method="POST",
            ),
            context=ctx,
        )
        print("Undeploy %s succeeded" % uuid)
    except HTTPError as e:
        if e.code == 404:
            print("Deployment %s not found (already undeployed)" % uuid)
        else:
            print("Undeploy %s failed: %s" % (uuid, e))
            sys.exit(1)
    except Exception as e:
        print("Undeploy %s failed: %s" % (uuid, e))
        sys.exit(1)

# Wait for workspace to clear
if uuids:
    print("Waiting for workspace recipes to clear...")
    for attempt in range(60):
        try:
            ws = json.load(
                urllib.request.urlopen(
                    urllib.request.Request(
                        api_url + "/workspace/",
                        headers={"Authorization": "Token %s" % token},
                        method="GET",
                    ),
                    context=ctx,
                )
            )
            recipes = ws.get("recipes") or {}
            if not recipes:
                print("Workspace recipes cleared after %ds." % (attempt * 10))
                break
            print(
                "  Attempt %d: %d recipe(s) remaining, waiting 10s..."
                % (attempt + 1, len(recipes))
            )
        except Exception as e:
            print("  Poll failed:", e)
        time.sleep(10)
    else:
        print("Timeout waiting for workspace to clear.")
        sys.exit(1)

print("Undeploy complete.")
```

- [ ] **Step 2: Add `terraform_data.blueprint_undeploy` to `app-blueprint-deployment-job.tf`**

Add at the end of the file:

```hcl
# Destroy-time provisioner: undeploys all blueprints via Corrino API before app teardown.
# During terraform destroy, this resource is destroyed FIRST (inverse dependency order),
# so Corrino and the ingress are still alive when the undeploy script runs.
resource "terraform_data" "blueprint_undeploy" {
  count = local.deploy_application && !contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0

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

- [ ] **Step 3: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform validate
```

- [ ] **Step 4: Commit**

```bash
git add ai-accelerator-tf/scripts/undeploy_blueprints.py ai-accelerator-tf/app-blueprint-deployment-job.tf
git commit -m "feat: add blueprint undeploy script and destroy-time provisioner"
```

---

### Task 6: Update Outputs

All outputs that reference infrastructure or application resources need `try()` wrappers or conditionals to handle count=0.

**Files:**
- Modify: `ai-accelerator-tf/outputs.tf`

- [ ] **Step 1: Update infrastructure-related outputs**

```hcl
output "oke_kube_config" {
  value = data.oci_containerengine_cluster_kube_config.oke_kube_config.content
}

output "cluster_id" {
  description = "OKE cluster OCID -- pass this as existing_cluster_id to subsequent app-only stacks"
  value       = local.effective_cluster_id
}

output "cluster_name" {
  description = "Name of the OKE cluster"
  value       = try(local.oke_cluster.name, "existing-cluster")
}

output "public_cluster_endpoint_full" {
  description = "Kubernetes API endpoint (public)"
  value       = local.cluster_endpoint_public_full
}

output "private_cluster_endpoint_full" {
  description = "Kubernetes API endpoint (private)"
  value       = local.cluster_endpoint_private_full
}

output "node_pool_id" {
  description = "ID of the node pool"
  value       = try(oci_containerengine_node_pool.oke_node_pool[0].id, null)
}

output "node_pool_kubernetes_version" {
  description = "Kubernetes version of the node pool"
  value       = try(oci_containerengine_node_pool.oke_node_pool[0].kubernetes_version, null)
}
```

- [ ] **Step 2: Update connection-related outputs**

```hcl
output "connection_instructions" {
  description = "Instructions for connecting to the cluster"
  value = local.create_bastion_effective && local.create_network_resources ? {
    bastion_ssh              = "ssh -i <private_key_file> opc@${oci_core_instance.bastion[0].public_ip}"
    operator_ssh_via_bastion = "ssh -i <private_key_file> -J opc@${oci_core_instance.bastion[0].public_ip} opc@${oci_core_instance.operator[0].private_ip}"
    kubectl_setup            = "After connecting to operator instance, run: ./configure_oke.sh"
    } : {
    direct_access = local.cluster_endpoint_visibility == "Public" ? "Configure kubectl with: oci ce cluster create-kubeconfig --cluster-id ${local.effective_cluster_id}" : "Cluster has private endpoint - use bastion/operator setup"
  }
}

output "kubeconfig_command" {
  description = "Command to generate kubeconfig file"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${local.effective_cluster_id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0"
}
```

- [ ] **Step 3: Wrap app-specific outputs with conditionals**

For outputs that reference app resources (starter_pack_url, blueprints_portal_url, corrino_api_url, etc.), wrap with `try()`:

```hcl
output "starter_pack_url" {
  description = "Starter pack FQDN"
  value       = local.deploy_application ? local.public_endpoint.starter_pack : null
}

output "blueprints_portal_url" {
  description = "Portal FQDN"
  value       = local.deploy_application ? local.public_endpoint.blueprint_portal : null
}

output "corrino_api_url" {
  description = "Corrino API URL"
  value       = local.deploy_application ? local.public_endpoint.api : null
}

output "prometheus_url" {
  description = "Prometheus FQDN"
  value       = local.deploy_application ? local.public_endpoint.prometheus : null
}

output "grafana_url" {
  description = "Grafana FQDN"
  value       = local.deploy_application ? local.public_endpoint.grafana : null
}

output "external_ip" {
  description = "Public IP address of the ingress load balancer."
  value       = local.deploy_application && var.use_custom_dns ? local.network.external_ip : "N/A"
}
```

- [ ] **Step 4: Add new `cluster_ca_certificate` output**

```hcl
output "cluster_ca_certificate" {
  description = "OKE cluster CA certificate (base64 encoded) -- needed for bring-your-own-cluster provider configuration"
  value       = try(base64encode(local.cluster_ca_certificate), null)
  sensitive   = true
}
```

- [ ] **Step 5: Run `terraform fmt` and `terraform validate`**

```bash
cd ai-accelerator-tf && terraform fmt -recursive && terraform validate
```

- [ ] **Step 6: Commit**

```bash
git add ai-accelerator-tf/outputs.tf
git commit -m "feat: update outputs for count=0 safety and add cluster_ca_certificate"
```

---

### Task 7: Update ORM Schema

**Files:**
- Modify: `ai-accelerator-tf/schemas/common_schema.yaml`

- [ ] **Step 1: Add variables to `common_schema.yaml`**

Add a new variable group for Infrastructure Lifecycle. Find the `variableGroups:` section and add:

```yaml
  - title: "Infrastructure Lifecycle"
    variables:
      - deploy_application
      - existing_cluster_id
```

Add variable definitions in the `variables:` section:

```yaml
  deploy_application:
    type: boolean
    default: true
    title: "Deploy Application"
    description: "When unchecked, only infrastructure (VCN, OKE cluster, node pools) is created. Use this to create an infrastructure-only stack for node reuse."
    required: false

  existing_cluster_id:
    type: string
    default: ""
    title: "Existing Cluster OCID"
    description: "OCID of an existing OKE cluster to deploy onto. When provided, all infrastructure creation is skipped. Get this value from the cluster_id output of an infrastructure-only stack."
    required: false
```

- [ ] **Step 2: Regenerate schema and run schema tests**

```bash
cd ai-accelerator-tf/schemas && python3 create_final_schema.py --all
cd .. && source ../venv/bin/activate && pytest schemas/tests/ -v
```

- [ ] **Step 3: Commit**

```bash
git add ai-accelerator-tf/schemas/common_schema.yaml
git commit -m "feat: add deploy_application and existing_cluster_id to ORM schema"
```

---

### Task 8: Add Terraform Unit Tests

**Files:**
- Create: `ai-accelerator-tf/tests/starter_pack_infra_only.tftest.hcl`
- Create: `ai-accelerator-tf/tests/starter_pack_existing_cluster.tftest.hcl`

- [ ] **Step 1: Create `tests/starter_pack_infra_only.tftest.hcl`**

```hcl
# Tests for infrastructure-only mode (deploy_application = false)

mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = {
      regions = [{
        name = "us-ashburn-1"
        key  = "IAD"
      }]
    }
  }

  override_data {
    target = data.oci_identity_availability_domains.ads
    values = {
      availability_domains = [{
        name = "US-ASHBURN-AD-1"
      }]
    }
  }

  override_data {
    target = data.oci_core_images.oracle_linux
    values = {
      images = [{
        id = "ocid1.image.oc1..test"
      }]
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}
mock_provider "random" {}
mock_provider "http" {}

variables {
  tenancy_ocid                    = "ocid1.tenancy.oc1..test"
  compartment_ocid                = "ocid1.compartment.oc1..test"
  region                          = "us-ashburn-1"
  current_user_ocid               = "ocid1.user.oc1..test"
  corrino_admin_username          = "testadmin"
  corrino_admin_password          = "TestP@ssw0rd123!"
  corrino_admin_email             = "test@example.com"
  starter_pack_category           = "enterprise_rag"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  deploy_application              = false
}

run "infra_only_creates_cluster" {
  command = plan

  assert {
    condition     = output.cluster_id != null
    error_message = "Infrastructure-only mode should still create the cluster"
  }
}

run "infra_only_skips_app_outputs" {
  command = plan

  assert {
    condition     = output.starter_pack_url == null
    error_message = "Infrastructure-only mode should not output starter_pack_url"
  }

  assert {
    condition     = output.corrino_api_url == null
    error_message = "Infrastructure-only mode should not output corrino_api_url"
  }
}
```

- [ ] **Step 2: Create `tests/starter_pack_existing_cluster.tftest.hcl`**

```hcl
# Tests for bring-your-own-cluster mode (existing_cluster_id provided)

mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = {
      regions = [{
        name = "us-ashburn-1"
        key  = "IAD"
      }]
    }
  }

  override_data {
    target = data.oci_identity_availability_domains.ads
    values = {
      availability_domains = [{
        name = "US-ASHBURN-AD-1"
      }]
    }
  }

  override_data {
    target = data.oci_core_images.oracle_linux
    values = {
      images = [{
        id = "ocid1.image.oc1..test"
      }]
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}
mock_provider "random" {}
mock_provider "http" {}

variables {
  tenancy_ocid                    = "ocid1.tenancy.oc1..test"
  compartment_ocid                = "ocid1.compartment.oc1..test"
  region                          = "us-ashburn-1"
  current_user_ocid               = "ocid1.user.oc1..test"
  corrino_admin_username          = "testadmin"
  corrino_admin_password          = "TestP@ssw0rd123!"
  corrino_admin_email             = "test@example.com"
  starter_pack_category           = "enterprise_rag"
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
  existing_cluster_id             = "ocid1.cluster.oc1.us-ashburn-1.testcluster"
}

run "existing_cluster_validation_accepts_valid_ocid" {
  command = plan
}

run "existing_cluster_skips_node_pool_output" {
  command = plan

  assert {
    condition     = output.node_pool_id == null
    error_message = "Existing cluster mode should not output node_pool_id"
  }
}

run "rejects_invalid_cluster_ocid" {
  command = plan

  variables {
    existing_cluster_id = "not-a-valid-ocid"
  }

  expect_failures = [var.existing_cluster_id]
}
```

- [ ] **Step 3: Run all tests**

```bash
cd ai-accelerator-tf && terraform test
```

Expected: All tests pass (new and existing).

- [ ] **Step 4: Commit**

```bash
git add ai-accelerator-tf/tests/
git commit -m "test: add unit tests for infra-only and existing-cluster modes"
```

---

### Task 9: Final Validation

- [ ] **Step 1: Run full linting suite**

```bash
cd ai-accelerator-tf
terraform fmt -check -diff -recursive
terraform validate
```

- [ ] **Step 2: Run all Terraform tests**

```bash
terraform test
```

- [ ] **Step 3: Run schema tests**

```bash
cd schemas && python3 create_final_schema.py --all
cd .. && source ../venv/bin/activate && pytest schemas/tests/ -v
```

- [ ] **Step 4: Verify default behavior unchanged**

Confirm that with default variable values (`deploy_application = true`, `existing_cluster_id = ""`), a `terraform plan` produces the same resource set as before this change. The existing `core_plan.tftest.hcl` passing confirms this.

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A && git commit -m "fix: address linting and test issues"
```
