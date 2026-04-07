# Known Bugs

Ongoing list of bugs discovered during development and testing. Each entry tracks symptoms, root cause, and resolution.

| Status | ID | Title | Severity | Date |
|--------|---------|-------|----------|------|
| Fixed | BUG-001 | cuOpt variables visible in non-cuOpt ORM stacks | Medium | 2026-03-30 |
| Fixed | BUG-002 | blueprint_deploy_id empty tuple for enterprise_rag_aiq | High | 2026-03-30 |
| Fixed | BUG-003 | Provider host "https://" in existing cluster mode | Critical | 2026-03-31 |
| Fixed | BUG-004 | llamastack secrets "already exists" on existing cluster | High | 2026-03-31 |
| Fixed | BUG-005 | ADB creation fails with 400 — missing private_endpoint_label | Critical | 2026-03-31 |
| Fixed | BUG-006 | Blueprint validation fails — subnetId required for shared_node_pool recipes | Critical | 2026-04-02 |
| Fixed | BUG-007 | VSS infra-only apply fails — blueprint_files.tf references empty FSS resources | Critical | 2026-04-06 |
| Fixed | BUG-008 | Enterprise RAG infra-only apply fails — helm.tf k8s data source missing deploy_application gate | Critical | 2026-04-06 |

---

### BUG-001: cuOpt variables visible in non-cuOpt ORM stacks

**Status:** Fixed
**Date found:** 2026-03-30
**Date fixed:** 2026-03-30
**Found by:** Grant during enterprise_rag_aiq ORM stack testing
**Severity:** Medium

**Symptoms:**
ORM UI displayed `cuopt_frontend_admin_password`, `cuopt_frontend_admin_username`, and `google_maps_api_key` as raw form fields when creating an `enterprise_rag_aiq` stack. These cuOpt-specific fields should not appear in non-cuOpt categories.

**Root cause:**
The three variables were defined in `vars.tf` (added in PR #92, cuOpt frontend feature) but not listed in `schemas/common_schema.yaml` with `visible: false`. ORM displays ALL Terraform variables not controlled by the schema as raw fields. The variables were only hidden via cuOpt-specific schema visibility conditions (`visible: { and: [cuopt_frontend_enabled] }` in `cuopt_schema.yaml`), which doesn't affect other categories.

**Affected files:**
- `ai-accelerator-tf/vars.tf:631-654` — variables defined here
- `ai-accelerator-tf/schemas/common_schema.yaml` — missing `visible: false` entries
- `ai-accelerator-tf/schemas/cuopt_schema.yaml:89-114` — had visibility overrides but only for cuOpt

**Workaround:**
None — the fields appeared in ORM UI for all non-cuOpt categories.

**Resolution:**
Added `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, and `google_maps_api_key` to `common_schema.yaml` with `visible: false`. The cuOpt-specific schema already overrides these with `visible: true` conditionally. Fixed in PR #93, commit `e67bb3c`.

**Verification:** Regenerate schemas (`python3 create_final_schema.py --all`), then verify:
`grep cuopt_frontend_admin schemas/generated/enterprise_rag_aiq_schema.yaml` should show `visible: false`.

**Prevention:** Created `/schema-lint` skill that checks for variables in `vars.tf` missing from `common_schema.yaml`. The core rule: every variable must be `visible: false` in common_schema, then selectively overridden in category-specific schemas.

### BUG-002: blueprint_deploy_id empty tuple for enterprise_rag_aiq

**Status:** Fixed
**Date found:** 2026-03-30
**Date fixed:** 2026-03-30
**Found by:** Grant during ORM plan for enterprise_rag_aiq
**Severity:** High

**Symptoms:**
`terraform plan` fails with:
```
Error: Invalid index
  on vars.tf line 978, in locals:
    random_id.blueprint_deploy_id is empty tuple
```

**Root cause:**
`vars.tf:977` used `var.starter_pack_category != "enterprise_rag"` to gate access to `random_id.blueprint_deploy_id[0].hex`, but `enterprise_rag_aiq` also has this resource at count=0 (both enterprise_rag categories use Helm, not blueprints). The condition only excluded `enterprise_rag`, not `enterprise_rag_aiq`. Pre-existing bug that was masked before because `enterprise_rag_aiq` was added after the original condition was written. The same pattern was repeated for `canonical_blueprint_content` and `starter_pack_blueprint_content`.

**Affected files:**
- `ai-accelerator-tf/vars.tf:977-985` — conditions only checked `!= "enterprise_rag"` instead of `!contains(["enterprise_rag", "enterprise_rag_aiq"], ...)`

**Workaround:**
None — plan fails and blocks deployment.

**Resolution:**
Changed all three conditions in `vars.tf` to use `!contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category)`, matching the same logic used by `random_id.blueprint_deploy_id`'s count condition. Also added `&& local.deploy_application` to `starter_pack_deployment_name` to handle infra-only mode. Fixed in PR #93.

### BUG-003: Provider host "https://" in existing cluster mode

**Status:** Fixed
**Date found:** 2026-03-31
**Date fixed:** 2026-03-31
**Found by:** Grant during ORM apply with existing_cluster_id
**Severity:** Critical

**Symptoms:**
`terraform apply` fails with:
```
Error: Failed to parse value for host: https://
  host must be a URL or a host:port pair: "https://"
```

**Root cause:**
In `kubernetes.tf`, `cluster_endpoint_public_full` derives from `local.oke_cluster.endpoints[0].public_endpoint`. When `existing_cluster_id` is provided, `local.oke_cluster` is `null`, so this returns `""`. Then `cluster_endpoint_public_host = format("https://%s", "")` produces `"https://"`, which is passed to the kubernetes/helm providers as the host.

The kubeconfig data source successfully fetches the server URL (`https://138.2.43.73:6443`) from the existing cluster, but the endpoint locals were not falling back to it.

**Affected files:**
- `ai-accelerator-tf/kubernetes.tf:10-18` — endpoint locals derived from `local.oke_cluster` with no fallback

**Resolution:**
Added `kubeconfig_server_url` local that parses the server URL from the kubeconfig YAML. Updated `cluster_endpoint_public_host` to fall back to `kubeconfig_server_url` when `cluster_endpoint_public_full` is empty. Fixed in PR #93.

**Verification:** `terraform plan` with `existing_cluster_id` set should show a valid `https://<ip>:6443` host, not `"https://"`.

**Verification:** `terraform plan` with `starter_pack_category = "enterprise_rag_aiq"` should succeed without the "empty tuple" error.

### BUG-004: llamastack secrets "already exists" on existing cluster

**Status:** Fixed
**Date found:** 2026-03-31
**Date fixed:** 2026-03-31
**Found by:** Grant during ORM apply with existing_cluster_id on enterprise_rag_aiq
**Severity:** High

**Symptoms:**
`terraform apply` fails with:
```
Error: secrets "llamastack-paas-config" already exists
Error: secrets "llamastack-inference-config" already exists
```

**Root cause:**
`llamastack_config.tf` was missed during Task 4 (gate application resources). The two `kubernetes_secret_v1` resources had no `count` and no `local.deploy_application` gate. When deploying an app-only stack onto an existing cluster that already had these secrets from a previous deployment, Terraform tried to create them and failed.

**Affected files:**
- `ai-accelerator-tf/llamastack_config.tf:6,19` — missing `count = local.deploy_application ? 1 : 0`

**Resolution:**
Added `count = local.deploy_application ? 1 : 0` to both resources. For the immediate "already exists" error: re-running the ORM apply will succeed since Terraform will import the existing resources into state on retry. Fixed in PR #93.

**Verification:** Re-run ORM apply — the secrets will be adopted into Terraform state. Future deploys on existing clusters will work cleanly.

**Prevention:** When adding new Kubernetes resources to the Terraform code, always include `count = local.deploy_application ? 1 : 0` if the resource is application-layer.

### BUG-005: ADB creation fails with 400 — missing private_endpoint_label

**Status:** Fixed
**Date found:** 2026-03-31
**Date fixed:** 2026-03-31
**Found by:** Grant during ORM apply for paas_rag in ap-osaka-1
**Severity:** Critical

**Symptoms:**
`terraform apply` fails with:
```
Error: 400-InvalidParameter, Operation failed. One-way TLS connections require a private endpoint,
a VCN with an access control list (ACL), or a public IP with an ACL.
```
The error occurs on `oci_database_autonomous_database.oracle_26ai[0]` in `26ai.tf` line 6.

**Root cause:**
The ADB resource had `is_mtls_connection_required = false` (one-way TLS) and `subnet_id` set, but was missing `private_endpoint_label`. In OCI, `subnet_id` alone does NOT create a private endpoint — the `private_endpoint_label` attribute is what tells OCI to create the ADB as a private endpoint database. Without it, OCI attempted to create a public endpoint ADB with one-way TLS, which requires an IP allowlist ACL (`whitelisted_ips`) that wasn't configured.

The connection string logic at line 72 already referenced `.private_endpoint`, confirming the original intent was a private endpoint ADB — the label was simply never added.

**Affected files:**
- `ai-accelerator-tf/26ai.tf:6-41` — missing `private_endpoint_label` attribute

**Workaround:**
None — ADB creation fails and blocks deployment.

**Resolution:**
Added `private_endpoint_label = "aiaccel${random_string.deploy_id.result}"` to the ADB resource. This creates a proper private endpoint ADB, satisfying the one-way TLS security requirement. The label uses the same deploy ID suffix for consistency and uniqueness.

**Verification:** Re-run ORM apply — ADB should create successfully with a private endpoint.

**Prevention:** When configuring OCI ADB with `is_mtls_connection_required = false`, always include `private_endpoint_label` to ensure a private endpoint is created.

### BUG-006: Blueprint validation fails — subnetId required for shared_node_pool recipes

**Status:** Fixed
**Date found:** 2026-04-02
**Date fixed:** 2026-04-03
**Found by:** Grant during paas_rag two-stack integration test in ap-osaka-1
**Severity:** Critical

**Symptoms:**
Blueprint deployment job returns HTTP 400 from Corrino API:
```
[llamastack] Validator logic error / Parameter subnetId cannot be None, whitespace or empty string
[frontend] Validator logic error / Parameter subnetId cannot be None, whitespace or empty string
```
The `null_resource.wait_for_deployment` polls indefinitely because the blueprint was never deployed. ORM apply eventually times out.

**Root cause:**
The `SubnetValidator` in Corrino (`api/control_plane/validator/subnet_validator.py`) calls `OciNetworkDao.get_subnet()` for every recipe component. It first tries `cmd.get_recipe_pod_subnet_ocid()` (from the blueprint payload), then falls back to `settings.OKE_NODE_SUBNET_ID`. In the two-stack model, `OKE_NODE_SUBNET_ID` was empty because `local.network.oke_node_subnet_id` resolved to `var.existing_node_subnet_id` which defaulted to `""` — the variable existed in `vars.tf` but was never exposed in the ORM schema for users to populate.

The full chain: `app-configmap.tf` → `local.network.oke_node_subnet_id` → `local.create_network_resources ? oci_core_subnet.oke_nodes_subnet[0].id : var.existing_node_subnet_id` → `""` (default) → Corrino `SubnetValidator` → OCI SDK `get_subnet(None)` → `ValueError`.

**Affected files:**
- `ai-accelerator-tf/outputs.tf` — missing `node_subnet_id` output
- `ai-accelerator-tf/schemas/common_schema.yaml` — `existing_node_subnet_id` was `visible: false` and not in any variable group
- `ai-accelerator-tf/app-locals.tf:162` — `oke_node_subnet_id` correctly fell back to `var.existing_node_subnet_id`, but that variable was always empty in app-only stacks

**Workaround:**
None — blueprint validation fails and blocks deployment.

**Resolution:**
Added `node_subnet_id` output to `outputs.tf` (mirrors the pattern of `autonomous_db_subnet_id`). Made `existing_node_subnet_id` visible in `common_schema.yaml` with title, description, and placement in the "Advanced Options" variable group between `existing_cluster_id` and `existing_autonomous_db_subnet_id`. Added `node_subnet_id` to the "Infrastructure (for App-Only Stack)" output group so users can copy it from the infra stack UI.

The infra stack now outputs the node subnet OCID, which the user copies into the app stack's "Existing Node Subnet OCID" field. This populates `OKE_NODE_SUBNET_ID` in the Corrino configmap, allowing the `SubnetValidator` to pass.

**Verification:** Deploy a two-stack paas_rag: infra stack outputs `node_subnet_id`, app stack receives it as `existing_node_subnet_id`, blueprint deploys successfully (HTTP 200 from Corrino API, deployment status reaches `monitoring`/`active`).

**Prevention:** When adding a new `existing_*` variable for the two-stack model, ensure it is: (1) output from the infra stack, (2) visible in the ORM schema, (3) in the "Advanced Options" variable group, and (4) in the "Infrastructure (for App-Only Stack)" output group. The Corrino `SubnetValidator` should also be updated to skip validation when `recipe_use_shared_node_pool = true` (defense in depth).

### BUG-007: VSS infra-only apply fails — blueprint_files.tf references empty FSS resources

**Status:** Fixed
**Date found:** 2026-04-06
**Date fixed:** 2026-04-07
**Found by:** Track 2 agent during v0.0.5 VSS release testing
**Severity:** Critical

**Symptoms:**
`terraform apply` with `deploy_application = false` (infra-only stack) fails with:
```
Error: Invalid index
  on blueprint_files.tf line 503, in locals:
  503: mount_target_ocid = oci_file_storage_mount_target.vss_mount_target[0].id
       oci_file_storage_mount_target.vss_mount_target is empty tuple
```
Same error on lines 500, 902, 1342 — all referencing `oci_file_storage_file_system.vss_fss[0].id` or `oci_file_storage_mount_target.vss_mount_target[0].id`.

**Root cause:**
VSS blueprint locals in `blueprint_files.tf` used `var.starter_pack_category == "vss"` to gate the `input_file_system` blocks, but this condition is true even when `deploy_application = false`. The FSS resources (`vss_mount_target`, `vss_fss`) have count conditions that evaluate to 0 when `deploy_application = false`, making them empty tuples. The `[0]` indexing then fails.

**Affected files:**
- `ai-accelerator-tf/blueprint_files.tf` lines 500, 902, 1342 — `input_file_system` blocks gated only on category, not on `deploy_application`

**Workaround:**
None — infra-only apply fails and blocks the two-stack model for VSS.

**Resolution:**
Changed the `input_file_system` condition from `var.starter_pack_category == "vss"` to `local.deploy_app_vss` (which is `local.deploy_application && var.starter_pack_category == "vss"`). This ensures the FSS references are only evaluated when the application layer is being deployed and the resources actually exist. Fixed on `release_v0.0.5`, commit `77979f3`.

**Verification:** `terraform apply` with `deploy_application = false` and `starter_pack_category = "vss"` should succeed without the empty tuple error.

**Prevention:** All resource references in blueprint locals should use the compound `deploy_app_*` locals from `app-locals.tf` rather than raw category checks, since these include the `deploy_application` gate.

### BUG-008: Enterprise RAG infra-only apply fails — helm.tf k8s data source missing deploy_application gate

**Status:** Fixed
**Date found:** 2026-04-06
**Date fixed:** 2026-04-06
**Found by:** Track 1 agent during v0.0.5 enterprise_rag release testing
**Severity:** Critical

**Symptoms:**
`terraform apply` with `deploy_application = false` (infra-only stack) fails with:
```
Error: Get "http://localhost/api/v1/namespaces/rag/secrets/ngc-api-secret": dial tcp [::1]:80: connect: connection refused

  with data.kubernetes_secret_v1.ngc_api_secret[0],
  on helm.tf line 512, in data "kubernetes_secret_v1" "ngc_api_secret":
```

**Root cause:**
`data.kubernetes_secret_v1.ngc_api_secret` in `helm.tf` line 512 had a count condition gated only on the starter pack category (`contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0`) but NOT on `deploy_application`. When `deploy_application = false`, no OKE cluster exists yet, so the Kubernetes provider defaults to `localhost:80` and the data source connection fails.

**Affected files:**
- `ai-accelerator-tf/helm.tf:517` — count condition missing `local.deploy_application` check

**Workaround:**
None — infra-only apply fails and blocks the two-stack model for enterprise_rag.

**Resolution:**
Changed count condition from `contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category) ? 1 : 0` to `local.deploy_app_rag ? 1 : 0` which includes the `deploy_application` check. Fixed by Track 1 agent during v0.0.5 testing.

**Verification:** `terraform apply` with `deploy_application = false` and `starter_pack_category = "enterprise_rag"` should succeed without the localhost connection error.

**Prevention:** All `data` sources that query the Kubernetes API must include `local.deploy_application` in their count condition, since the cluster does not exist during infra-only deploys.
