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
| Open | BUG-009 | Stale nim-llm taint blocks pod scheduling after two-stack pack switch | High | 2026-04-07 |
| Fixed | BUG-010 | worker_node_availability_domain required for paas_rag (CPU-only) | Medium | 2026-04-08 |
| Open | BUG-011 | /checking-capacity only checks GPU — misses FSS, ADB, and other resource quotas | Medium | 2026-04-08 |
| Fixed | BUG-012 | Back-to-back pack switch on VMs leaves stale images filling ephemeral storage | Medium | 2026-04-09 |
| Open | BUG-013 | Infra destroy fails when app destroy hasn't completed — no enforcement of destroy ordering | High | 2026-04-09 |
| Open | BUG-014 | ingress-nginx in app stack creates OCI LB that blocks infra subnet deletion | Medium | 2026-04-09 |
| Open | BUG-015 | enterprise_rag document ingestion API fails with "single positional indexer is out-of-bounds" | Medium | 2026-04-09 |
| Open | BUG-016 | existing_node_subnet_id nil pointer crash in app stack — field easy to miss in ORM UI | Medium | 2026-04-09 |
| Fixed | BUG-017 | common_schema.yaml duplicate entries for cuopt frontend variables | Low | 2026-04-16 |
| Open | BUG-018 | BM.GPU4.8 node loses GPU allocation after app destroy in two-stack pack switch | High | 2026-04-19 |
| Open | BUG-019 | paas_rag app destroy fails with 409-BucketNotEmpty when Object Storage bucket has user-uploaded files | Medium | 2026-04-17 |
| Fixed | BUG-020 | enterprise_rag_aiq skin dropdown override lands on wrong Helm release (rag instead of aiq-aira) | Medium | 2026-04-20 |

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

### BUG-009: Stale nim-llm taint blocks pod scheduling after two-stack pack switch

**Status:** Open (fix incomplete)
**Date found:** 2026-04-07
**Date fixed:** 2026-04-07 (partial — destroy provisioner added but has chicken-and-egg bug)
**Found by:** Track 1 agent during v0.0.5 enterprise_rag → enterprise_rag_aiq two-stack test
**Severity:** High

**Symptoms:**
After deploying enterprise_rag app (round 1), destroying the app stack, re-applying infra with enterprise_rag_aiq zip, and deploying enterprise_rag_aiq app (round 2), 7+ pods are stuck in Pending state. The error from `kubectl describe pod` shows:
```
0/4 nodes are available: 2 node(s) had untolerated taint {workload: nim-llm}
```
The NIM LLM pod (8 GPUs) runs on one GPU node, but the second GPU node — which has 8 free GPUs needed by embed, rerank, nemoretriever, and other NIM services — is blocked by the `workload=nim-llm:NoSchedule` taint.

**Root cause:**
The `label_nim_llm_node` resource in `helm.tf` (gated by `local.deploy_app_rag`) taints **all** GPU worker nodes with `workload=nim-llm:NoSchedule`. This taint persists on the Kubernetes nodes even after the app stack is destroyed — `terraform destroy` removes Terraform state but does not untaint the nodes. When the second app (enterprise_rag_aiq) is deployed, the Helm chart's `label_nim_llm_node` step runs again, but the stale taints from round 1 are already present and block non-LLM GPU pods from scheduling on the second node.

The total GPU budget is exactly 16 (8 for LLM + 1 each for 8 other NIMs), which fits on 2x BM.GPU4.8 (8 GPUs each) — **this is NOT a sizing bug**. It's purely a taint lifecycle issue in the two-stack model.

**Affected files:**
- `ai-accelerator-tf/helm.tf` — `label_nim_llm_node` and `label_nim_llm_node_via_operator` resources taint GPU nodes with no destroy-time cleanup

**Workaround:**
Manually remove the nim-llm taint from the non-LLM GPU node between rounds:
```bash
kubectl taint nodes <second-gpu-node> workload=nim-llm:NoSchedule-
```

**Resolution:**
Added destroy-time provisioners to both `label_nim_llm_node` (local-exec) and `label_nim_llm_node_via_operator` (remote-exec) that remove the `workload=nim-llm` taint and label from all GPU nodes on app stack destroy. Used `input`/`self.output` pattern to pass kubeconfig/SSH details to the destroy provisioner (Terraform 1.5 requires destroy provisioners to only reference `self`). Bumped `triggers_replace` from `v1` to `v2` to force resource replacement on existing stacks so the new destroy provisioner gets registered.

For the `via_operator` variant: removed the resource-level `connection` block entirely because Terraform validates all connection blocks against destroy provisioner rules when any destroy provisioner exists on the resource. Both create and destroy provisioners now have their own inline `connection` blocks using `self.output.*`.

Fixed in commits `c53d237` and `051a533` on `release_v0.0.5`.

**v0.0.6 re-occurrence (2026-04-09):** During v0.0.6 release testing, Track 1 (enterprise_rag → enterprise_rag_aiq in ap-melbourne-1) hit this bug again. The destroy provisioner ran but cleaned 0 nodes. Root cause: the provisioner's node selector uses `nvidia.com/gpu.present=true`, but this label is set by NFD (Node Feature Discovery). When NFD can't schedule on a node because of the `workload=nim-llm:NoSchedule` taint (NFD only tolerates `nvidia.com/gpu`), the `gpu.present` label is never set — so the destroy provisioner's selector matches 0 nodes. **Chicken-and-egg:** the taint blocks NFD → NFD can't set the label → the provisioner can't find the node → the taint persists.

**Fix needed:** Change the destroy provisioner's node selector to something that doesn't depend on NFD labels. Options:
1. Select by `node.kubernetes.io/instance-type` (set by OKE, not NFD)
2. Select all nodes in the GPU worker pool by OKE node pool label
3. Remove taints from ALL worker nodes (not just GPU-labeled ones) — safe since the taint is pack-specific

**Workaround (still valid):**
Manually remove the nim-llm taint from affected GPU nodes between rounds:
```bash
kubectl taint nodes <node-name> workload=nim-llm:NoSchedule-
```

**Prevention:** Any resource that modifies Kubernetes node state (taints, labels) should have a destroy-time provisioner to clean up when the app stack is destroyed. The two-stack model requires clean node state between rounds. Destroy provisioner node selectors must NOT depend on labels set by daemonsets that can be blocked by the very taints being cleaned up.

**Recurrence (v0.0.6):** During Track 1's enterprise_rag → enterprise_rag_aiq pack switch in ap-melbourne-1, the stale `nim-llm` taint reappeared on GPU nodes despite the destroy provisioner fix. The GPU device-plugin daemonset showed DESIRED=0 and the operator-validator was stuck. Manual taint removal (`kubectl taint nodes <node> workload=nim-llm:NoSchedule-`) immediately restored GPU allocation. Root cause of recurrence needs investigation — the destroy provisioner may not have fired correctly during the ORM-managed app destroy, or the taint was re-applied during the infra re-apply before the new app stack was deployed.

### BUG-010: worker_node_availability_domain required for paas_rag (CPU-only)

**Status:** Open
**Date found:** 2026-04-08
**Found by:** Track 3 agent during v0.0.6 paas_rag release testing in us-sanjose-1
**Severity:** Medium

**Symptoms:**
ORM UI shows "This variable is required" validation error on the `worker_node_availability_domain` field when creating a `paas_rag` stack. `paas_rag` is a CPU-only pack with no GPU worker pool, so this field should not be required.

**Root cause:**
The `worker_node_availability_domain` variable has a `required: true` attribute in the ORM schema. The capacity check precondition in `vars.tf` also references this variable. For `paas_rag`, no GPU workers are created, but the schema still marks the field as required because the common schema does not differentiate by category.

**Affected files:**
- `ai-accelerator-tf/schemas/common_schema.yaml` — `worker_node_availability_domain` marked as required
- `ai-accelerator-tf/schemas/paas_rag_schema.yaml` — should override to `required: false` or `visible: false`

**Workaround:**
Fill in any valid AD name — the value is ignored for `paas_rag` since no GPU worker pool is created.

**Resolution:**
Added explicit `required: false` and `visible: false` override for `worker_node_availability_domain` in `paas_rag_schema.yaml`. The common schema had `visible: false` but no `required` field, causing ORM to treat it as required. GPU packs (cuopt, vss, enterprise_rag, enterprise_rag_aiq) already override this to `required: true` with visible titles/descriptions. Fixed on `release_v0.0.6`, commit `25662c9`.

**Date fixed:** 2026-04-08

**Verification:** Regenerate schemas and verify that `generated/paas_rag_schema.yaml` shows `worker_node_availability_domain` with `required: false` and `visible: false`. ORM UI should no longer show the field or require it for paas_rag stacks.

### BUG-011: /checking-capacity only checks GPU — misses FSS, ADB, and other resource quotas

**Status:** Open
**Date found:** 2026-04-08
**Found by:** Release coordinator during v0.0.6 release testing
**Severity:** Medium

**Symptoms:**
`/checking-capacity` reported us-sanjose-1 as viable for VSS (11 VM.GPU.A10.2 available), but the deploy failed because FSS mount target quota was exhausted (2/2 used). The capacity check only validates GPU shape availability and tenancy GPU quota — it does not check quotas for other resources the pack requires.

**Root cause:**
`/checking-capacity` was designed to solve the most common deployment blocker (GPU capacity), but each pack requires additional resources with their own quotas:

| Pack | Additional quota-gated resources |
|---|---|
| `vss` | FSS mount targets, FSS file systems |
| `paas_rag` | ADB instances, ADB OCPUs |
| `enterprise_rag` | ADB instances, ADB OCPUs |
| `enterprise_rag_aiq` | (GPU only — uses Milvus, not ADB) |
| `cuopt` | (GPU only) |

The `/checking-capacity` skill and the releasing skill's Phase 3 (Plan Testing) don't check these additional quotas before selecting a region.

**Affected files:**
- `.claude/skills/checking-capacity/SKILL.md` — only checks `compute` service limits for GPU shapes
- `.claude/skills/releasing/SKILL.md` — Phase 3 relies solely on `/checking-capacity` for region selection

**Workaround:**
Manually check FSS/ADB quotas before deploying:
```bash
# FSS (AD-scoped — requires --availability-domain)
oci limits resource-availability get --service-name filesystem --limit-name mount-target-count \
  --compartment-id <tenancy_ocid> --availability-domain <ad> --region <region>

# ADB (regional — do NOT pass --availability-domain, it will error)
# Note: limit names are workload-specific. Default workload LH/DW uses adw-* limits.
oci limits resource-availability get --service-name database --limit-name adw-ecpu-count \
  --compartment-id <tenancy_ocid> --region <region>
oci limits resource-availability get --service-name database --limit-name adw-total-storage-tb \
  --compartment-id <tenancy_ocid> --region <region>
```

**Resolution:**
Pending. The `/checking-capacity` skill should be extended to check all pack-specific resource quotas (FSS for VSS, ADB for paas_rag/enterprise_rag) and only recommend regions where ALL required quotas are available. Note: `enterprise_rag_aiq` does NOT need ADB (uses Milvus instead of Oracle 26ai).

### BUG-012: Back-to-back pack switch on VMs leaves stale images filling ephemeral storage

**Status:** Fixed
**Date found:** 2026-04-09
**Date fixed:** 2026-04-09
**Found by:** Track 2 agent during v0.0.6 cuopt release testing in uk-london-1
**Severity:** Medium

**Symptoms:**
After deploying VSS/poc (Round 1) and switching to cuopt/poc (Round 2) on the same VM.GPU.A10.2 infra, the cuopt NIM pod fails to schedule with `Insufficient ephemeral-storage`. The GPU node has large cached container images from the previous VSS deployment (vss-engine, riva NIM, embedding NIM, rerank NIM, etc.) consuming disk space.

**Root cause:**
The two-stack back-to-back model destroys the app stack but preserves infra (including GPU nodes). Container images from the previous pack remain cached on the node's disk. When the next pack's containers request ephemeral storage (cuopt NIM requests 200Gi), the node doesn't have enough free space.

This is unnecessary for VM shapes — VMs provision in minutes, so there's no benefit to preserving infra between packs. The 6-hour recycle time that motivates infra reuse only applies to bare metal shapes (BM.GPU4.8).

**Affected files:**
- `.claude/skills/releasing/SKILL.md` — Phase 4 track design groups VM packs for back-to-back switching
- `.claude/skills/releasing/PARALLEL_TESTING.md` — back-to-back switching docs don't distinguish VM vs BM

**Workaround:**
For VM tracks, destroy everything (app + infra) between packs and create fresh stacks. This avoids stale images entirely.

**Resolution:**
Updated the releasing skill's track design (Phase 3b in SKILL.md) to only use back-to-back pack switching for bare metal (BM.*) shapes. VM tracks now destroy both stacks and create fresh infra between rounds. Updated PARALLEL_TESTING.md to split the back-to-back section into "Bare Metal Only" and "VM Track Switching" sections. LESSONS_LEARNED.md already contained the rule (added during initial diagnosis). Fixed on `release_v0.0.6`.

**Verification:** During next release, VM tracks (e.g., vss/poc → cuopt/poc) should destroy everything between rounds. No `Insufficient ephemeral-storage` errors on the second pack.

**Prevention:** The releasing skill's Phase 3b now explicitly checks `worker_node_shape` prefix (BM.* vs VM.*) when designing tracks. PARALLEL_TESTING.md documents both workflows separately.

### BUG-013: Infra destroy fails when app destroy hasn't completed — no enforcement of destroy ordering

**Status:** Open
**Date found:** 2026-04-09
**Found by:** Track 2 agent during v0.0.6 VSS/cuopt release testing in uk-london-1
**Severity:** High

**How this was discovered (exact sequence of events):**
During the v0.0.6 release, Track 2 was testing VSS/poc in uk-london-1. After completing VSS testing, it needed to destroy both stacks to deploy cuopt fresh (VM tracks don't reuse infra — see BUG-012). Here's exactly what Track 2 did:

1. **Submitted app stack destroy** — ORM started running `terraform destroy` on the app stack
2. **Polled app destroy status** every 3 minutes — after ~9 minutes, the app destroy **FAILED**. The `undeploy_blueprints.py` destroy provisioner couldn't reach the Corrino API (the Corrino CP pod may have already been terminated by an earlier destroy step, creating a chicken-and-egg problem)
3. **Immediately submitted infra stack destroy** without retrying or investigating the app destroy failure. Track 2 reasoned that "since we're destroying everything anyway, the infra destroy would tear down the entire cluster including all app resources"
4. **Infra destroy failed** with `409-Conflict: subnet references service VNIC` — the OCI load balancer (created by ingress-nginx's Kubernetes Service) was still alive because the app stack was never fully cleaned up
5. **Three infra destroy retries** all failed on the same subnet VNIC conflict
6. **Manual intervention required** — the release coordinator had to identify and delete the orphaned OCI load balancer via `oci lb load-balancer delete`, after which the infra destroy succeeded

**Key lesson:** The Track 2 agent's reasoning ("infra destroy will clean up everything") was wrong. ORM's `terraform destroy` only destroys resources in its own state file. The app stack's load balancer is managed by the OCI cloud controller (triggered by Kubernetes), not by Terraform. Destroying the OKE cluster (infra) does NOT automatically clean up OCI load balancers — they become orphaned.

**Symptoms:**
Infra stack destroy failed repeatedly with `409-Conflict: subnet references service VNIC` in uk-london-1. Three destroy attempts all failed on the LB subnet, requiring manual OCI CLI intervention to delete the orphaned load balancer.

**Root cause:**
Track 2 started infra destroy before the app destroy had succeeded. The app destroy failed (Corrino API unreachable → `undeploy_blueprints.py` errored), leaving the entire app layer running: Helm releases, pods, services, ingress resources, and the OCI load balancer. The infra destroy then couldn't delete the LB subnet because the app's load balancer still had a VNIC attached to it.

The `/testing-pack` and `/destroy-stack` skills do not enforce or verify that app destroy succeeded before allowing infra destroy to proceed. There is no guardrail preventing an agent from submitting infra destroy after a failed app destroy.

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — Phase 5b destroy instructions say "app first then infra" but don't enforce it
- `.claude/skills/releasing/PARALLEL_TESTING.md` — destroy ordering documented but not enforced
- `.claude/skills/destroy-stack/SKILL.md` — no pre-flight check for active app stacks or OCI load balancers in the subnet

**Workaround:**
Manually delete the OCI load balancer via CLI, then retry infra destroy:
```bash
oci lb load-balancer list --compartment-id <compartment> --query "data[?\"subnet-ids\"[?contains(@, '<lb_subnet_ocid>')]].id" --raw-output
oci lb load-balancer delete --load-balancer-id <lb_ocid> --force
```

**Resolution:**
Pending. Two complementary fixes:
1. **Skill-level:** The `/destroy-stack` skill should verify app stack destroy succeeded (check ORM job status = SUCCEEDED) before allowing infra destroy. If app destroy failed, require the user to retry or acknowledge before proceeding.
2. **Terraform-level:** See BUG-014 for the architectural fix (move ingress-nginx to infra stack + LB cleanup safety net).

### BUG-014: ingress-nginx in app stack creates OCI LB that blocks infra subnet deletion (architectural)

**Status:** Open
**Date found:** 2026-04-09
**Found by:** Senior architect investigation during v0.0.6 release
**Severity:** Medium

**How this was discovered:**
After diagnosing BUG-013, we investigated why the infra destroy couldn't recover even after multiple retries. The release coordinator identified the specific OCI load balancer blocking the subnet and deleted it manually. This prompted a deeper architectural investigation: why does destroying the app stack leave an OCI load balancer alive, and why can't the infra stack destroy handle it?

Two architect teammates were spawned to analyze the codebase. They traced the dependency chain: `helm_release.ingress_nginx` (app stack) → Kubernetes Service type LoadBalancer → OCI cloud controller creates OCI LB → LB gets VNIC in `oke_lb_subnet` (infra stack). The architectural mismatch — the resource that triggers LB creation lives in a different Terraform state than the resource that owns the subnet — means Terraform can never handle the destroy ordering correctly across stacks.

The architects also identified an async race condition: even if ingress-nginx moves to the infra stack, `helm uninstall` completes before the OCI cloud controller finishes deleting the LB (async operation). A `terraform_data.wait_for_lb_cleanup` safety net resource was recommended to bridge this gap.

**Symptoms:**
Even with correct app-before-infra destroy ordering, there is an async race condition: `helm uninstall ingress-nginx` completes when Kubernetes objects are deleted, but the OCI cloud controller deletes the load balancer asynchronously. Terraform may proceed to destroy the LB subnet before the OCI LB is fully terminated.

**Root cause:**
Architectural mismatch: `ingress-nginx` (which creates the OCI LB via Kubernetes Service type LoadBalancer) is in the app stack, but `oke_lb_subnet` (where the LB is placed) is in the infra stack. These resources should be in the same Terraform state so destroy ordering is handled correctly. Additionally, the OCI cloud controller's async LB deletion means even correct Terraform ordering within a single state has a race window.

**Affected files:**
- `ai-accelerator-tf/helm.tf:2-3` — `ingress_nginx` gated on `deploy_application`
- `ai-accelerator-tf/kubernetes.tf:42` — `cluster_tools` namespace gated on `deploy_application`
- `ai-accelerator-tf/network.tf` — `oke_lb_subnet` gated on `create_network_resources`

**Workaround:**
Always destroy app stack first and verify completion. Manually delete remaining OCI LBs before infra destroy.

**Resolution:**
Pending (v0.0.7). Recommended fix from architect analysis:
1. Move `ingress-nginx` and `cluster_tools` namespace to infra stack (gate on `deploy_infrastructure`)
2. Add `cluster_tools_namespace` local for app-stack resources to reference the namespace by name
3. Add `terraform_data.wait_for_lb_cleanup` with destroy provisioner that polls until OCI LBs are gone before subnet deletion
4. ~5 files changed, no state migration needed if app stack is destroyed first (standard workflow)

### BUG-015: enterprise_rag document ingestion API fails with "single positional indexer is out-of-bounds"

**Status:** Open
**Date found:** 2026-04-08
**Found by:** Track 1 agent during v0.0.6 enterprise_rag testing in ap-melbourne-1 (test EA-5)
**Severity:** Medium

**Symptoms:**
API document ingestion (EA-5) fails with error "single positional indexer is out-of-bounds" during the indexing phase. The document extraction succeeds but indexing fails. Interestingly, UI-based document ingestion (EU-4) succeeds on the same setup — suggesting a different code path or timing difference between API and UI ingestion.

**Root cause:**
Unknown. Likely an issue in the RAG ingestor server's indexing pipeline when called via the API path. The error message suggests a pandas/dataframe indexing issue in the ingestion code (upstream NVIDIA blueprint code, not our Terraform).

**Affected files:**
- Upstream: `nvcr.io/nvidia/blueprint/ingestor-server:2.3.0` (for enterprise_rag_aiq) or `ord.ocir.io/.../nvidia-rag-ingestion-oci:v0.0.3` (for enterprise_rag)

**Workaround:**
Use UI-based document ingestion instead of API. The UI path succeeds.

**Resolution:**
Pending. Needs investigation in the RAG ingestor server logs to identify the exact failure point. May be an upstream NVIDIA blueprint bug.

### BUG-016: existing_node_subnet_id nil pointer crash in app stack — field easy to miss in ORM UI

**Status:** Open
**Date found:** 2026-04-08
**Found by:** Track 2 (VSS) and Track 3 (paas_rag) during v0.0.6 release testing
**Severity:** Medium

**How this was discovered:**
Both Track 2 (VSS in uk-london-1) and Track 3 (paas_rag in us-sanjose-1) hit the same issue independently. When creating the app stack, they filled in `existing_cluster_id` but missed `existing_node_subnet_id`. The app stack apply then crashed:
- VSS: `can not marshal a nil pointer` on `data.oci_core_subnet.vss_fss_node_subnet[0]`
- paas_rag: `Parameter subnetId cannot be None, whitespace or empty string` from Corrino SubnetValidator

Both were fixed by going back to the infra stack's "Application Information" tab, copying the `node_subnet_id` output, and pasting it into the app stack's `existing_node_subnet_id` field.

**Symptoms:**
App stack apply fails with nil pointer or subnetId validation error when `existing_node_subnet_id` is empty. The field exists in the ORM schema but is not prominently surfaced — it's easy to miss when creating the app stack.

**Root cause:**
The `existing_node_subnet_id` variable was added in BUG-006 fix (v0.0.4) and is visible in the schema under "Advanced Options". However, in the ORM UI, it's grouped with other advanced fields and not marked as required for the app stack. Users (and testing agents) consistently miss it because the primary field they focus on is `existing_cluster_id`.

The Corrino SubnetValidator requires a subnet ID for `shared_node_pool` recipes. When `existing_node_subnet_id` is empty, the `OKE_NODE_SUBNET_ID` configmap entry is empty, and the validator fails.

**Affected files:**
- `ai-accelerator-tf/schemas/common_schema.yaml` — `existing_node_subnet_id` should be more prominently displayed or conditionally required when `existing_cluster_id` is set
- `ai-accelerator-tf/app-configmap.tf` — populates `OKE_NODE_SUBNET_ID` from the variable

**Workaround:**
Always copy `node_subnet_id` from the infra stack outputs and paste into `existing_node_subnet_id` in the app stack. The `/testing-pack` skill Phase 4c documents this.

**Resolution:**
Pending. Options:
1. Make `existing_node_subnet_id` conditionally required when `existing_cluster_id` is set (ORM schema `required` + `visible` conditions)
2. Add a validation block in `vars.tf` that errors if `existing_cluster_id` is set but `existing_node_subnet_id` is empty
3. Auto-derive the node subnet from the cluster OCID via a data source (eliminates the manual copy step entirely)

### BUG-017: common_schema.yaml duplicate entries for cuopt frontend variables

**Status:** Fixed
**Date found:** 2026-04-16
**Date fixed:** 2026-04-16
**Found by:** Grant during multi-skin refactor (branch `multiple_skins_per_pack`)
**Severity:** Low

**Symptoms:**
`schemas/common_schema.yaml` contained duplicate hidden-variable entries for the cuOpt frontend variables. `cuopt_frontend_enabled` appeared twice, and `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, and `google_maps_api_key` were each defined more than once. YAML parsers tolerate duplicate keys by silently keeping the last occurrence, so the generated schema happened to be correct, but the source file was noisy, confusing to read, and easy to break during future edits (e.g., updating one copy but not the other).

**Root cause:**
The entries were added incrementally across multiple PRs:
- The original BUG-001 fix added `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, and `google_maps_api_key` with `visible: false`.
- A later PR that introduced `cuopt_frontend_enabled` added another block for the same three variables plus `cuopt_frontend_enabled` itself, instead of editing the existing block.
- A still-later change added a second `cuopt_frontend_enabled` entry (this time as a hidden fallback for the multi-skin transition) without noticing the earlier copy.

No schema-lint check flagged duplicate YAML keys in `common_schema.yaml`, and the generated per-category `schema.yaml` files looked correct because YAML "last key wins" semantics masked the duplication.

**Affected files:**
- `ai-accelerator-tf/schemas/common_schema.yaml` — duplicate entries for `cuopt_frontend_enabled` (x2), `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, `google_maps_api_key`

**Workaround:**
None needed — the generated schemas were functionally correct due to YAML last-key-wins semantics. Purely a source-file cleanliness issue.

**Resolution:**
Consolidated the duplicate entries in `common_schema.yaml` so each variable appears exactly once with `visible: false`. Removed the stale `frontend_skin` hidden fallback at the same time. Fixed on branch `multiple_skins_per_pack` in commit `fe1bfcc` as part of the multi-skin refactor (spec 2026-04-16).

**Verification:**
- `grep -c "^  cuopt_frontend_enabled:" ai-accelerator-tf/schemas/common_schema.yaml` should return `1`.
- `grep -c "^  cuopt_frontend_admin_username:" ai-accelerator-tf/schemas/common_schema.yaml` should return `1`.
- `python3 ai-accelerator-tf/schemas/create_final_schema.py --all` succeeds and `pytest ai-accelerator-tf/schemas/tests/ -v` passes.

**Prevention:**
Extend `/schema-lint` to detect duplicate top-level variable keys in `common_schema.yaml` (and per-category schemas). Since PyYAML's default loader silently drops duplicates, the check needs a custom loader or a pre-parse pass that scans raw lines under `variables:` for repeated keys.

**Reference:** Discovered during the `multiple_skins_per_pack` refactor (spec 2026-04-16) when auditing `common_schema.yaml` as part of replacing `cuopt_frontend_enabled` with per-skin boolean variables.

### BUG-018: BM.GPU4.8 node loses GPU allocation after app destroy in two-stack pack switch

**Status:** Open
**Date found:** 2026-04-19
**Found by:** `track1-bm` teammate during multi-skin feature validation (Track 1, enterprise_rag → enterprise_rag_aiq back-to-back in us-sanjose-1)
**Severity:** High

**How this was discovered:**
Track 1 was testing the multi-skin feature on two Helm packs sequentially on 2× BM.GPU4.8 in us-sanjose-1 AD-1. After enterprise_rag completed successfully (all pods Running, tests PASS), the teammate destroyed the app stack only (preserving infra + GPU nodes per the BM shape reuse strategy in `feedback_gpu_destroy_vs_reapply.md`). The enterprise_rag_aiq app apply then ran 43+ min and got stuck because 8 of its pods failed to schedule with `Insufficient nvidia.com/gpu`. Diagnosis with `kubectl describe node` showed that one of the two GPU nodes (10.0.101.47) reported 0 capacity and 0 allocatable for `nvidia.com/gpu`, and had label `nvidia.com/gpu.present=false`. The other GPU node (10.0.97.85) correctly reported 8/8 GPUs but those were all consumed by the new rag-nim-llm-0 pod.

**Symptoms:**
After destroying an app stack and redeploying a different app stack on the same preserved BM.GPU4.8 infra:
- One GPU worker node's kubelet reports `capacity: nvidia.com/gpu = 0` and `allocatable: nvidia.com/gpu = 0` (should be 8/8).
- Node label `nvidia.com/gpu.present` is `false` (should be `true`).
- GPU device plugin daemonset may report DESIRED=0 on the affected node, or may be missing entirely.
- Pods requesting GPUs get `0/N nodes are available: Insufficient nvidia.com/gpu` and stay Pending.
- Other BM.GPU4.8 nodes in the same pool report GPUs correctly — the failure is per-node.

**Root cause (suspected):**
When the app stack is destroyed, the GPU operator (Helm release owned by the app stack) is uninstalled. On BM.GPU4.8, the nvidia-container-runtime / device-plugin state on the node is tightly coupled to the operator's lifecycle. The uninstall sequence evicts pods and cleans up Kubernetes objects, but some nodes end up in a state where the GPU device plugin is gone AND the node labels that NFD uses to re-enable it (`nvidia.com/gpu.present`) are cleared. When the next app stack is applied, the new GPU operator install doesn't fully re-enumerate GPUs on that node — it assumes `gpu.present=false` means no GPUs exist.

This is related to but distinct from BUG-009 (stale `nim-llm` taint after two-stack pack switch):
- BUG-009 symptom: taint `workload=nim-llm:NoSchedule` persists → pods blocked by taint.
- BUG-018 symptom: GPU capacity reports 0 → pods blocked by insufficient resources.

Both are triggered by the same workflow (destroy app, redeploy different app on preserved infra) and share the same underlying class of problem: Helm lifecycle on the app stack leaves GPU-node state corrupted for the next round.

**Affected files:**
- `ai-accelerator-tf/helm.tf` — GPU operator Helm release gated by `local.deploy_app_rag` / similar; destroy doesn't ensure node GPU state is restored.
- Likely interacts with `nvidia-device-plugin` / `node-feature-discovery` daemonsets managed by the GPU operator chart.

**Workaround:**
Two options, try in order from least-invasive to most:

1. Restart the nvidia device plugin pod on the affected node:
   ```bash
   kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset --field-selector spec.nodeName=<affected-node>
   # Wait ~1 min; then re-check:
   kubectl describe node <affected-node> | grep 'nvidia.com/gpu'
   ```

2. Cordon, drain, uncordon to force re-enumeration:
   ```bash
   kubectl cordon <affected-node>
   kubectl drain <affected-node> --ignore-daemonsets --delete-emptydir-data
   kubectl uncordon <affected-node>
   ```

3. Reboot the BM node via OCI console (last resort — BM reboots take 15-30 min):
   - Go to Compute → Instances → select the affected BM.GPU4.8 → Reboot.

**Resolution:**
Pending. Likely fixes to investigate:

1. Add a destroy-time provisioner to the GPU operator Helm release that explicitly restarts the device plugin daemonset on all GPU nodes before uninstalling (ensures clean state).
2. Add a create-time provisioner to the next app stack's GPU operator that verifies `nvidia.com/gpu.present=true` on all worker nodes, and if not, triggers a device plugin restart.
3. Move the GPU operator out of the app stack and into the infra stack so its lifecycle is decoupled from per-pack app redeploys (similar to the BUG-014 recommendation for ingress-nginx).

**Prevention:**
Any Helm release that manages node-level device drivers or daemonsets must either (1) live in the infra stack to avoid redeploy churn, or (2) have destroy/create provisioners that explicitly restore node state. The two-stack model + BM shape reuse strategy assumes node state is durable across app-stack lifecycle events, but GPU operator state clearly is not.

**Reference:** Discovered during Track 1 of the `multiple_skins_per_pack` branch testing (2026-04-19) when validating the Helm-pack path of the multi-skin feature. The bug does not affect the multi-skin feature itself — the schema assertions (no Frontend Skins group for Helm packs) were already validated before the apply stalled. It is a pre-existing two-stack infrastructure issue that happens to surface during sequential Helm-pack testing.

### BUG-019: paas_rag app destroy fails with 409-BucketNotEmpty when Object Storage bucket has user-uploaded files

**Status:** Open
**Date found:** 2026-04-17
**Found by:** `track3-cpu` teammate during multi-skin feature validation (Track 3, paas_rag/small in us-sanjose-1)
**Severity:** Medium

**How this was discovered:**
Track 3 ran the paas_rag Phase 6 API test suite end-to-end. PA-5 uploaded a small test document (`test-doc.txt`) via `POST /v1/files`, which LlamaStack stored in the stack's Object Storage bucket `paas-rag-<suffix>-bucket`. PA-9 and PA-10 deleted the file attachment and vector store via the LlamaStack API, but those deletes only purge the vector-store index — they do NOT remove the underlying object from Object Storage. The object remained in the bucket. When the app stack destroy ran afterwards, Terraform attempted to `DeleteBucket` and the API returned `409-BucketNotEmpty`.

**Symptoms:**
After running API tests that upload files (PA-5 or equivalent) and then attempting to destroy the paas_rag app stack, the destroy job fails at the `oci_objectstorage_bucket.paas_rag_bucket` deletion step with:
```
Error: 409-BucketNotEmpty, Bucket named 'paas-rag-<suffix>-bucket' is not empty. Delete all object versions first.
Request Target: DELETE https://objectstorage.<region>.oraclecloud.com/n/<ns>/b/paas-rag-<suffix>-bucket
```
The ORM job ends in state `FAILED` with `failure-details.code = TERRAFORM_EXECUTION_ERROR`. The ADB has already been destroyed by this point; all Helm releases and most compute resources are gone — only the bucket (and whatever depends on it) blocks completion.

**Root cause:**
Two factors combine:

1. **LlamaStack file lifecycle:** Files uploaded via `POST /v1/files` are stored in OCI Object Storage. The Corrino/LlamaStack API for deleting vector store attachments (`DELETE /v1/vector_stores/{id}/files/{fileId}`) removes the vector store index entry but does not call `DeleteObject` on the underlying storage. Even `DELETE /v1/vector_stores/{id}` (full vector store delete) only removes the index, not the files. There is no documented API to remove a file from storage.

2. **Versioned bucket semantics:** The `oci_objectstorage_bucket` resource in Terraform (`ai-accelerator-tf/*.tf` — location TBD) likely enables versioning. A plain `oci os object delete` on a versioned bucket only creates a delete-marker; the prior version (and the marker itself) still count as objects in the bucket. `DeleteBucket` requires zero objects AND zero versions.

**Affected files:**
- The Terraform bucket resource for paas_rag (grep for `oci_objectstorage_bucket` in `ai-accelerator-tf/` — likely in a paas_rag- or blueprint-specific .tf file). The resource does not set `force_destroy = true` or use a provisioner to empty the bucket before destroy.
- `.claude/skills/paas-rag-test-coverage/api-tests.md` — test PA-5 uploads a file that is never cleaned up. PA-9/PA-10 only delete the vector store membership, not the underlying Object Storage object.

**Workaround:**

Before retrying destroy, manually empty the bucket:

```bash
export OCI_CLI_PROFILE=<profile>
NS=$(oci os ns get --query 'data' --raw-output)
BUCKET=paas-rag-<suffix>-bucket  # from the ORM destroy error message
REGION=<stack-region>

# 1. List all versions (current + delete markers)
oci os object list-object-versions --namespace-name "$NS" --bucket-name "$BUCKET" --region "$REGION" --all \
  --query 'data[].{name:name, version:"version-id"}' --output json > /tmp/versions.json

# 2. Delete every version
python3 -c "
import json, subprocess
for v in json.load(open('/tmp/versions.json')):
    subprocess.run(['oci','os','object','delete',
        '--namespace-name','$NS','--bucket-name','$BUCKET','--region','$REGION',
        '--name',v['name'],'--version-id',v['version'],'--force'])
"

# 3. Verify empty
oci os object list-object-versions --namespace-name "$NS" --bucket-name "$BUCKET" --region "$REGION" --query 'length(data)'
# Should return null or 0. Then retry the ORM destroy job.
```

Track 3's bucket had exactly 2 versions to remove (1 current data object + 1 delete-marker created when a prior CLI delete was attempted).

**Resolution:**
Pending. Recommended fixes in order of preference:

1. **Add `force_destroy = true` / empty-on-destroy provisioner to the paas_rag bucket resource.** `oci_objectstorage_bucket` supports neither `force_destroy` nor `lifecycle.destroy_before_create` for emptying, so this likely requires a `local-exec` destroy provisioner that shells out to `oci os object bulk-delete --force` (and handles versioned objects). Example:
   ```hcl
   resource "null_resource" "bucket_empty_on_destroy" {
     triggers = { bucket = oci_objectstorage_bucket.paas_rag.name, ns = oci_objectstorage_bucket.paas_rag.namespace, region = var.region }
     provisioner "local-exec" {
       when    = destroy
       command = "oci os object bulk-delete --namespace-name '${self.triggers.ns}' --bucket-name '${self.triggers.bucket}' --region '${self.triggers.region}' --force --include '*' || true"
     }
   }
   ```
   (Caveat: `bulk-delete` does not handle object versions — may need a custom script.)

2. **Disable versioning on the paas_rag bucket** if retention isn't required. `versioning = "Disabled"` on `oci_objectstorage_bucket` removes the version-deletion complexity. Trade-off: no object history for user uploads.

3. **Add file-storage cleanup to the LlamaStack API path** in Corrino so that `DELETE /v1/vector_stores/{id}/files/{fileId}` also removes the Object Storage object. This is the "cleanest" fix but requires changes to the upstream LlamaStack layer, not just this Terraform module.

4. **Document the manual workaround** in `paas-rag-test-coverage/api-tests.md` and/or `testing-pack` skill so operators know to empty the bucket before destroy.

**Prevention:**
Every Object Storage bucket that accepts user uploads (via the app itself or tests) must either (1) be emptied on destroy via a provisioner, or (2) have versioning disabled and rely on Terraform's empty-bucket check at destroy time. The testing-pack skill's Phase 7 should add a pre-destroy bucket-empty step for paas_rag (and enterprise_rag if it also uploads files).

**Reference:** Discovered during Track 3 of the `multiple_skins_per_pack` branch testing (2026-04-17). Destroy job that failed: `ocid1.ormjob.oc1.us-sanjose-1.amaaaaaam3augwaaliugbktvutq3n7pep43vmppumfnzrmdgs65ojg5vabva`. Retry job after manual bucket-empty: `ocid1.ormjob.oc1.us-sanjose-1.amaaaaaam3augwaapa2rxnd2gsx5hlfe2zjsdfngwrtkwuvkxtnqvxxdro7a`. The bug does not affect the multi-skin feature itself — paas_rag Phase 6 test results (5 infra + 10 API + 6 UI PASS) are valid; this only affects cleanup.

### BUG-020: enterprise_rag_aiq skin dropdown override lands on wrong Helm release

**Status:** Fixed
**Date found:** 2026-04-20
**Date fixed:** 2026-04-20
**Found by:** Opus 4.7 review agent during spec review of `docs/skins/BACKEND_API_CONTRACT.md`
**Severity:** Medium (latent — zero user impact today)

**How this was discovered:**
Post-merge review of the design spec for a new skin API contract doc. The reviewer cross-checked every factual claim against the Terraform source files and flagged that for `enterprise_rag_aiq`, the `frontend.image.{repository,tag}` override emitted by the `skin_enterprise_rag_aiq` enum dropdown was attached to the `rag` Helm release's `set` block, but the user-facing URL `aiq.<fqdn>` routes to a different release entirely.

**Symptoms:**
For `enterprise_rag_aiq`, selecting a different skin via the ORM `Frontend Skin` dropdown has no effect on what the user sees. The deployed aira-frontend pod's image always matches the value hardcoded in `aiq-aira-values.yaml` (`aira-frontend:v1.2.0`), regardless of the dropdown selection.

**Today's user-visible impact:** ZERO. The catalog has exactly one `enterprise_rag_aiq` skin entry and its `image_uri` already equals the hardcoded default, so the bug is latent.

**Future impact:** The instant a second skin is added to the `enterprise_rag_aiq` catalog in `frontend_skins.yaml`, users who select it get AIRA anyway and see the unexpected behavior.

**Root cause:**
`enterprise_rag_aiq` deploys TWO Helm releases: the `rag` release (from `nvidia-blueprint-rag-v2.3.0.tgz`) as a dependency, and the `aiq` release (from `aiq-aira-v1.2.1.tgz`) for the AIQ-specific stack. The ingress at `ingress.tf:223` routes `aiq.<fqdn>` → `aiq-aira-aira-frontend` service, which belongs to the `aiq` release.

Before the fix, `helm.tf:647-654` set `frontend.image.repository` and `frontend.image.tag` only on the `rag` helm_release. The `aiq` helm_release's `set` block (lines 771-784) did not override these values, so `aiq-aira-values.yaml`'s hardcoded `frontend.image.tag: v1.2.0` always won.

**Affected files:**
- `ai-accelerator-tf/helm.tf:771-797` — the `aiq` release's `set` block was missing the frontend image override.
- `ai-accelerator-tf/ingress.tf:~210-235` — confirms the user URL routes to `aiq-aira-aira-frontend`.
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml:frontend.image` — the hardcoded default that persists without an override.

**Workaround:** None needed today (catalog has only one `enterprise_rag_aiq` skin).

**Resolution:**
Added two new `set` entries to the `aiq` helm_release's `set = [...]` block:

```hcl
{ name = "frontend.image.repository", value = split(":", local.frontend_skin_image_uri)[0] },
{ name = "frontend.image.tag",        value = split(":", local.frontend_skin_image_uri)[1] }
```

Now the enum selection reaches the correct Helm release. The parallel override on the `rag` release is retained — it's a harmless no-op for `enterprise_rag_aiq` (the rag release's frontend isn't exposed via ingress for this pack) and the primary fix for `enterprise_rag` (where the `rag` release IS the user-facing one).

**Verification:**
- `terraform validate` clean.
- New structural test `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py` asserts both `rag` and `aiq` Helm releases carry the `frontend.image.{repository,tag}` set entries with values derived from `local.frontend_skin_image_uri`. Drift-verified: test fails if either release's override is removed.
- Pending: live verification on preserved Track 1 infra — redeploy AIQ with the fix, then `helm get values aiq-aira -n aiq` should show `frontend.image.tag: v1.2.0` in the USER-SUPPLIED VALUES section (not just chart default). `kubectl describe pod -l app=aira-frontend` should show image `aira-frontend:v1.2.0` (same as hardcoded today, but the override is now applied at the `aiq` release level).

**Prevention:**
The new `test_helm_skin_override.py` locks the invariant: any future helm_release that serves a user-facing frontend under the skin system must carry the `frontend.image.{repository,tag}` set entries wired to `local.frontend_skin_image_uri`. If a new Helm-pack category is added, its release must be appended to `RELEASES_REQUIRING_SKIN_OVERRIDE` at the top of the test file.

**Reference:** Discovered during the `multiple_skins_per_pack` branch post-merge work. Fix committed in branch multiple_skins_per_pack; final verification pending on Track 1 infra redeploy.
