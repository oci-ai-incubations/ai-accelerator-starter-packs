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
| Open | BUG-021 | /checking-capacity skill rejects BM shapes — faultDomain causes 400 CannotParseRequest | Medium | 2026-04-28 |
| Open | BUG-022 | NIM Operator post-deploy patcher deadlocks with helm_release.rag — enterprise_rag/BM apply fails | Critical | 2026-04-29 |
| Invalid | BUG-023 | (RETRACTED) v0.0.8 zip layout — actually correct; rules file disagreed with /zip-tf skill and prior successful releases | — | 2026-05-04 |
| Open | BUG-024 | `.claude/rules/terraform.md` contradicts `/zip-tf` skill on ORM zip layout — caused false-positive release block | Low | 2026-05-04 |
| Fixed | BUG-025 | `skin_dox_pack_core` visible AND defaulted true on paas_rag schema — would silently deploy wrong frontend | High | 2026-05-04 |
| Fixed | BUG-026 | DAC fields (`dac_billing_acknowledgement`, `dac_model_id`, `dac_unit_shape`) visible on paas_rag schema | Medium | 2026-05-04 |
| Fixed | BUG-027 | cuopt frontend credentials hidden in ORM Step 2 — `visible: false` from common_schema.yaml not overridden by cuopt_schema.yaml; group-level visibility ineffective | High | 2026-05-04 |
| Open | BUG-028 | nim-llm pod stuck Pending on multi-node BM enterprise_rag — `label_nim_llm_node` partitioning resource removed in commit `bfa54d1`, no node dedicated for 8-GPU pod | High | 2026-05-04 |
| Open | BUG-029 | enterprise_rag destroy fails — NIMCache/NIMService CRs orphaned by rag chart's `keep` policy; nim_operator destroyed before they can be cleaned, namespace stuck Terminating | High | 2026-05-04 |
| Invalid | BUG-030 | (RETRACTED 2026-05-05 19:55Z) Original hypothesis (GPU-taint blocking coredns) was wrong; actual cause was OCI Out-of-Host-Capacity for VM.Standard.E5.Flex in uk-london-1 AD-1 — capacity issue, not a code bug. Do NOT implement the proposed fix. | — | 2026-05-05 |
| Open | BUG-031 | dox_pack two-stack model fails — DAC + imported_model + endpoint not gated on `deploy_application` | High | 2026-05-05 |
| Open | BUG-032 | enterprise_rag App apply fails — NIMCache RWO PVC Multi-Attach when nim-operator spawns cache-job retry while nim-llm Deployment holds the PVC; pack functionally works but `terraform_data.patch_nim_operator_resources` 30m timeout marks apply FAILED | High | 2026-05-05 |
| Open | BUG-033 | dox_pack contract-backend pod CrashLoopBackOff — ADB wallet not mounted, `TNS_ADMIN` unset → `oracledb DPY-4027: no configuration directory specified`; frontend cascades to HTTP 503 | High | 2026-05-07 |
| Fixed | BUG-034 | warehouse_pick_path schema missing `worker_node_availability_domain` override — wizard hides field with no default, capacity_check.tf precondition fast-fails apply with empty AD value | High | 2026-05-08 |

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

**Repro confirmed during v0.0.8 release testing (2026-05-04):** track3-cpu hit this exact bug again on Track 3 Round 1 paas_rag/small in us-dallas-1. PA-11 cleanup ran (`DELETE /v1/files/{id}` returned HTTP 200, `oci os object bulk-delete --include '*'` returned `{"deleted-objects": []}`), and a post-cleanup `oci os object list` showed an empty `objects` array. But `oci os object list-object-versions` revealed the bucket actually had 2 versioned entries: the original `file-ef91a01a06db4b10960732f57742e269` blob (version `84c1d489-...`) AND a delete-marker (version `a53d138c-...`). PA-11's bulk-delete missed both because it only operates on the "current view" of the bucket, not the versioned object table. App destroy job `ocid1.ormjob.oc1.us-dallas-1.amaaaaaam3augwaafpsyuzfdqwqma5ocov5ih4he5camxqv6mgyedpwpaoja` FAILED on `DeleteBucket` at 22:09:46Z. Manual `oci os object delete --version-id ...` for both entries unblocked the retry destroy. Reinforces fix recommendation #2 (disable versioning) — fix recommendation #1 (force_destroy via local-exec) needs to handle versions too, not just current objects.

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

**Affected files (at original fix time, against chart `aiq-aira-v1.2.1.tgz`):**
- `ai-accelerator-tf/helm.tf` — the `aiq` release's `set` block was missing the frontend image override.
- `ai-accelerator-tf/ingress.tf` — confirms the user URL routes to the AIQ frontend service.
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml:frontend.image` — the hardcoded default that persisted without an override.

**Workaround:** None needed today (catalog has only one `enterprise_rag_aiq` skin).

**Resolution:**
Added two new `set` entries to the `aiq` helm_release's `set = [...]` block, originally at the chart's flat `frontend.image.*` path:

```hcl
{ name = "frontend.image.repository", value = split(":", local.frontend_skin_image_uri)[0] },
{ name = "frontend.image.tag",        value = split(":", local.frontend_skin_image_uri)[1] }
```

Now the enum selection reaches the correct Helm release. The parallel override on the `rag` release is retained — it's a harmless no-op for `enterprise_rag_aiq` (the rag release's frontend isn't exposed via ingress for this pack) and the primary fix for `enterprise_rag` (where the `rag` release IS the user-facing one).

**Update — 2026-04-30, AIQ chart v2.0.0 upgrade (commit `cfc63e6`):**
The AIQ chart was upgraded from `aiq-aira-v1.2.1.tgz` to `aiq2-web-2.0.0.tgz`, which restructured values from flat to nested under `aiq.apps.<component>` (release notes: https://github.com/NVIDIA-AI-Blueprints/aiq/releases/tag/2.0.0). The BUG-020 override on the `aiq` release was correspondingly re-wired to the new value path — see `ai-accelerator-tf/helm.tf:746-753`:

```hcl
{ name = "aiq.apps.frontend.image.repository", value = split(":", local.frontend_skin_image_uri)[0] },
{ name = "aiq.apps.frontend.image.tag",        value = split(":", local.frontend_skin_image_uri)[1] }
```

The `rag` release continues to use the flat `frontend.image.*` path (`helm.tf:549-556`), since its chart shape did not change. The structural test `test_helm_skin_override.py` was updated in the same window to allow per-release expected key paths.

**Verification:**
- `terraform validate` clean.
- Structural test `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py` asserts both `rag` and `aiq` Helm releases carry the chart-appropriate `frontend image` set entries with values derived from `local.frontend_skin_image_uri`. As of the v2.0.0 upgrade, the expected key tuple is per-release: `rag → frontend.image.*`, `aiq → aiq.apps.frontend.image.*`. Drift-verified: test fails if either release's override is removed or moved to the wrong path.
- Pending: live verification on preserved Track 1 infra — redeploy AIQ with the fix, then `helm get values aiq -n aiq` should show `aiq.apps.frontend.image.tag: 2.0.0` in the USER-SUPPLIED VALUES section (or whatever skin tag was selected). `kubectl describe pod -l app=aiq-frontend -n aiq` should show the corresponding image.

**Prevention:**
`test_helm_skin_override.py` locks the invariant: any future helm_release that serves a user-facing frontend under the skin system must carry the chart-appropriate frontend image set entries wired to `local.frontend_skin_image_uri`. If a new Helm-pack category is added, add an entry to `RELEASES_REQUIRING_SKIN_OVERRIDE` (mapping release name to its expected `(repository_key, tag_key)` tuple) at the top of the test file.

**Reference:** Discovered during the `multiple_skins_per_pack` branch post-merge work. Original fix committed in branch `multiple_skins_per_pack`; re-wired against `aiq2-web` v2.0.0 in commit `cfc63e6` on `feature/aiq-v2.0.0-upgrade`. Final verification pending on Track 1 infra redeploy against v2.0.0.


### BUG-021: /checking-capacity skill rejects BM shapes — faultDomain causes 400 CannotParseRequest

**Status:** Open
**Date found:** 2026-04-28
**Found by:** Grant (via Claude Opus 4.7) during v0.0.7 post-release validation capacity check
**Severity:** Medium

**Symptoms:**
The `/checking-capacity` skill's example `shape-availabilities` payload includes `"faultDomain": "FAULT-DOMAIN-1"`. Running the skill against any BM shape (e.g., `BM.GPU4.8`) returns HTTP 400 `ServiceError: CannotParseRequest / "Incorrectly formatted request"` from the `compute-capacity-report` API. The skill's bash script then incorrectly tags the region as `NOT_SUPPORTED` for every region scanned — hiding the true capacity. During v0.0.7 testing, all 21 subscribed regions falsely reported `NOT_SUPPORTED` for `BM.GPU4.8` until `faultDomain` was removed from the payload.

**Root cause:**
BM shapes do not accept `faultDomain` in `compute-capacity-report` payloads — only VM shapes do. The skill's documented example
`[{"instanceShape": "$SHAPE", "faultDomain": "FAULT-DOMAIN-1"}]`
must omit `faultDomain` when the target is a BM shape (or omit it always — the API tolerates the omission for both VM and BM shapes).

**Affected files:**
- `.claude/skills/checking-capacity/SKILL.md` — Phase 3 GPU capacity check section, the `--shape-availabilities` example.

**Workaround:**
Remove `faultDomain` from the payload. Direct verification with the corrected payload showed `us-sanjose-1` had 3 `BM.GPU4.8` hosts available (vs. the skill's incorrect "NOT_SUPPORTED" report).

**Cosmetic follow-up:**
The same skill's printf shows `GPU_QUOTA` / ADW columns as `X/0` when `effective-quota-value` is `null`. A `null` effective-quota means the service default applies, not zero. Display should show `X/—` (or trust `available` as the source of truth). Cosmetic only.

**Classification:** Skill gap — the documented example payload is wrong for BM shapes.

**Resolution:**
Pending. Recommended fix: drop `faultDomain` from the example payload in the SKILL.md and from the reference script. Optionally, only include `faultDomain` when the shape starts with `VM.` (in which case it's still optional, but valid).


### BUG-023: (RETRACTED) v0.0.8 zip layout — false positive

**Status:** Invalid / Retracted (2026-05-04, same day)
**Date found / retracted:** 2026-05-04
**Found by / retracted by:** Monitor agent during v0.0.8 release testing
**Severity:** — (originally filed Critical; not actually a bug)

**What was originally claimed:**
That all `release_test_matrix/v0.0.8_*.zip` files were broken because they wrapped every TF file under a top-level `ai-accelerator-tf/` directory, and that ORM Resource Manager rejects that layout. The claim cited `.claude/rules/terraform.md`'s line that "TF files must be at the zip root (zip from inside `ai-accelerator-tf/`, not the parent directory)."

**Why this is wrong:**
1. The `/zip-tf` skill (`.claude/skills/zip-tf/SKILL.md`, the authoritative skill for building ORM zips) explicitly does `zip -r "${ZIP_NAME}" ai-accelerator-tf/ ...` from the repo root — producing exactly the wrapped layout.
2. The previous release `release_test_matrix/v0.0.7_paas_rag.zip` (and every other v0.0.4–v0.0.7 zip) uses the same wrapped layout and was **successfully deployed via ORM** during v0.0.7 release testing.
3. Team-lead confirmed the wrapped layout is what ORM expects.

The monitor's initial check trusted the `.claude/rules/terraform.md` line over the `/zip-tf` skill and the empirical evidence in past releases. That was the wrong tiebreaker — the rules file is stale; the skill + prior successful releases are authoritative.

**Impact:**
- ~10 minutes of testing held while the bug was being verified.
- track3-cpu, track1-gpu4, and track2-a10 each received a "pause uploads" message that was retracted shortly after (track3-cpu was already stopped; track1 was awaiting OCI Console login; track2 was already in motion).
- No infrastructure deployed, no resources orphaned, no spend.

**Follow-up:** filed as **BUG-024** below — the contradiction between `.claude/rules/terraform.md` and the `/zip-tf` skill that caused this false positive should be fixed so future monitors don't repeat the same mistake.

**Rediscovered:** 2026-05-05 by track3-cpu during the v0.0.8 release re-run. The `track3-cpu` agent independently re-flagged the wrapped layout as a blocker before starting Round 1 (paas_rag) on the same exact set of zips. Team-lead retracted within minutes, citing this bug. Confirms BUG-024 is still actively misleading agents — until `.claude/rules/terraform.md` is corrected, every fresh monitoring/test agent will keep tripping on it. Trap was triggered identically: same rule citation, same zips, same conclusion.


### BUG-024: `.claude/rules/terraform.md` contradicts `/zip-tf` skill on ORM zip layout

**Status:** Open
**Date found:** 2026-05-04
**Found by:** Monitor agent during v0.0.8 release testing (after BUG-023 retraction)
**Severity:** Low (documentation drift — caused one false-positive release-block alert)

**Symptoms:**
`.claude/rules/terraform.md` includes the rule:
> When creating ORM zips, TF files must be at the zip root (zip from inside `ai-accelerator-tf/`, not the parent directory).

But the `/zip-tf` skill (`.claude/skills/zip-tf/SKILL.md`) — which is the authoritative ORM-zip builder used by the `/releasing` flow — explicitly runs:
```bash
zip -r "${ZIP_NAME}" ai-accelerator-tf/ ...
```
from the repo root, producing a wrapped layout where every TF file is under `ai-accelerator-tf/`. Every released zip from v0.0.4 through v0.0.7 uses this wrapped layout and was deployed successfully through ORM.

These two sources are flatly contradictory. The rules file is wrong (or describes an older, unused convention); the skill + the successful release zips are correct.

**Root cause:**
Stale documentation. Either the rule was true at one point under a previous release process and never updated, or it was written based on an incorrect mental model of how ORM ingests zips. ORM accepts both layouts in practice, but this project standardizes on the wrapped form via `/zip-tf`.

**Affected files:**
- `.claude/rules/terraform.md` — last bullet under "Terraform Rules" should be removed or rewritten.

**Impact:**
Caused BUG-023 (a false-positive release-block) when a monitoring agent trusted the rules file over the skill. ~10 min of testing time held; three teammates received and then had to disregard a "pause uploads" message.

**Recommended fix:**
Replace the offending line in `.claude/rules/terraform.md` with something like:
> When creating ORM zips, build with the `/zip-tf` skill (or follow its pattern: `zip -r ZIP ai-accelerator-tf/ ...` from the repo root). The `ai-accelerator-tf/` wrapper directory is intentional and is what ORM expects for this project's stacks.

**Classification:** Skill/docs gap (no code change needed; just align the rules file to match the actual skill behavior).

**Resolution:** Pending. Should be done before the next monitor agent reads the rules file.

### BUG-025: `skin_dox_pack_core` visible AND defaulted true on paas_rag schema

**Status:** Fixed
**Date found:** 2026-05-04
**Found by:** track3-cpu agent during v0.0.8 release testing — Track 3 Round 1 paas_rag/small in us-dallas-1 (PR #112)
**Severity:** High

**Symptoms:**
When creating a `paas_rag` ORM stack with the v0.0.8 zip, Step 2 of the wizard ("Configure variables") displays a `skin_dox_pack_core` checkbox under the Frontend Skins section, **pre-checked**. paas_rag's only valid skin is `skin_paas_rag_core` (oracle-net-frontend). A user accepting the defaults would request the dox_pack frontend (contract-analysis-frontend) inside their paas_rag deployment, which depends on DAC + the dox_pack backend that paas_rag does not provide. Same risk pattern as BUG-001 (cuOpt vars showing in non-cuOpt categories).

Verified during agent-browser checkbox enumeration: `{"skin_dox_pack_core": true}` was the live state on the paas_rag Step 2 form before any user input.

**Root cause (confirmed by monitor agent via independent source-code verification):**
`skin_dox_pack_core` is declared in `ai-accelerator-tf/vars.tf:1148` (with `default = true`) but does NOT appear anywhere in `ai-accelerator-tf/schemas/common_schema.yaml`. ORM renders any Terraform variable not controlled by the schema as a raw form field, using the vars.tf default. The `dox_pack_schema.yaml` correctly overrides this variable, which is why dox_pack itself shipped without issue in v0.0.7 — but every other pack (paas_rag, cuopt, vss, enterprise_rag, enterprise_rag_aiq, warehouse_pick_path) inherits the leak. This is the same pattern as BUG-001 (cuopt vars in non-cuopt schemas) and violates the BUG-001 prevention principle: every variable in vars.tf MUST be `visible: false` in common_schema.yaml.

**Affected files:**
- `ai-accelerator-tf/vars.tf:1148` — `skin_dox_pack_core` declared with `default = true`
- `ai-accelerator-tf/schemas/common_schema.yaml` — missing `visible: false` entry for `skin_dox_pack_core`
- `ai-accelerator-tf/schemas/generated/paas_rag_schema.yaml` (and every non-dox_pack generated schema) — leaks the variable as a visible field

**Workaround:**
Manually uncheck `skin_dox_pack_core` in Step 2 before clicking Next. (Applied in Track 3 Round 1.)

**Verification:**
```bash
grep -A4 'skin_dox_pack_core:' ai-accelerator-tf/schemas/generated/paas_rag_schema.yaml
```
Should show `visible: false` and `default: false` for paas_rag once fixed.

**Resolution:** Fixed. Added a hidden `skin_dox_pack_core` fallback to `common_schema.yaml` and gave all foreign skin fallbacks `default: false`; the schema generator still overrides the current pack's owned skins with catalog defaults, so `dox_pack` keeps `skin_dox_pack_core` visible/default true while every other generated schema hides it/defaults it false.

**Prevention:** Added schema pytest coverage that requires every Terraform variable to be represented in `common_schema.yaml` and every generated category schema. Added a foreign-skin regression test that requires skin toggles to be visible only in their owner pack and hidden/default false everywhere else.

**Cross-pack confirmation (2026-05-04, track2-a10):** Same leak verified on cuopt schema in uk-london-1 during Round 1 cuopt/poc — Step 2 wizard showed `skin_dox_pack_core` checkbox pre-checked. Confirms leak affects every non-dox_pack category. Workaround applied: skin defaults are ignored on cuopt infra stack since `deploy_application=false` makes them moot.

### BUG-026: DAC fields visible on paas_rag schema

**Status:** Fixed
**Date found:** 2026-05-04
**Found by:** track3-cpu agent during v0.0.8 release testing — Track 3 Round 1 paas_rag/small in us-dallas-1 (PR #112)
**Severity:** Medium

**Symptoms:**
When creating a `paas_rag` ORM stack with the v0.0.8 zip, Step 2 displays DAC (Dedicated AI Cluster) configuration fields that belong only to dox_pack:

- `dac_billing_acknowledgement` (checkbox, default unchecked)
- `dac_model_id` (textbox, default `Qwen/Qwen3-VL-235B-A22B-Instruct`)
- `dac_unit_shape` (textbox, default `H100_X8`)

DAC is a dox_pack-only feature. paas_rag does not consume any of these variables.

**Severity rationale:**
Lower than BUG-025 because `dac_billing_acknowledgement` defaults to `false`, so DAC will not auto-provision even if the user accepts defaults — but the visible model ID + shape strings clutter the UI and confuse users into thinking paas_rag involves an H100 cluster, which it does not.

**Root cause (confirmed by monitor agent via independent source-code verification):**
All three DAC variables are declared in `ai-accelerator-tf/vars.tf` but missing from `ai-accelerator-tf/schemas/common_schema.yaml`:
- `dac_model_id` — vars.tf:641 (default `"Qwen/Qwen3-VL-235B-A22B-Instruct"`)
- `dac_unit_shape` — vars.tf:647 (default `"H100_X8"`)
- `dac_billing_acknowledgement` — vars.tf:653 (default `false`)

Same pattern as BUG-025 (and BUG-001): variables present in vars.tf but absent from common_schema.yaml leak into every non-overriding category schema. Only `dox_pack_schema.yaml` correctly handles them, so they appear on every other pack.

**Affected files:**
- `ai-accelerator-tf/vars.tf:641,647,653` — DAC variable declarations
- `ai-accelerator-tf/schemas/common_schema.yaml` — missing `visible: false` entries for all three DAC variables
- `ai-accelerator-tf/schemas/generated/paas_rag_schema.yaml` (and every non-dox_pack generated schema) — leaks all three variables as visible fields

**Workaround:**
Leave DAC fields at their defaults (specifically: `dac_billing_acknowledgement` unchecked) and ignore them. (Applied in Track 3 Round 1.)

**Verification:**
```bash
grep -A4 'dac_billing_acknowledgement\|dac_model_id\|dac_unit_shape' ai-accelerator-tf/schemas/generated/paas_rag_schema.yaml
```
Should show `visible: false` for all three once fixed.

**Resolution:** Fixed. Added hidden common-schema fallbacks for `dac_model_id`, `dac_unit_shape`, and `dac_billing_acknowledgement`. `dox_pack_schema.yaml` remains the only schema that overrides them to visible fields.

**Prevention:** Added schema pytest coverage that checks DAC variables are visible only for `dox_pack` and hidden in every other generated schema.

**Cross-pack confirmation (2026-05-04, track2-a10):** Same DAC field leak verified on cuopt schema in uk-london-1 during Round 1 cuopt/poc — Step 2 wizard showed `dac_billing_acknowledgement`, `dac_model_id` (default `Qwen/Qwen3-VL-235B-A22B-Instruct`), and `dac_unit_shape` (default `H100_X8`). Confirms leak affects every non-dox_pack category, not just paas_rag.


### BUG-027: cuopt frontend credentials hidden in ORM Step 2 — common_schema visible:false not overridden, group visibility ineffective

**Status:** Fixed
**Date found:** 2026-05-04
**Date fixed:** 2026-05-04
**Found by:** track2-a10 during v0.0.8 release testing (Round 1 cuopt/poc, Phase 5 app-stack Step 2); root cause confirmed by monitor agent via independent schema inspection
**Fixed by:** team-lead during v0.0.8 release testing — fix added `visible: true` to all 4 affected vars in `cuopt_schema.yaml` so the deep-merge overrides common_schema's `visible: false`. Group-level `visible: { or: [skin_cuopt_core, skin_cuopt_partner] }` then gates the rendering on the skin toggles. Verified end-to-end: regenerated `ai-accelerator-tf/schema.yaml` shows `visible: true` for all 4. 132 schema tests pass.
**Severity:** High (release-blocking for cuopt — required app-stack credentials cannot be set through the ORM UI)

**Symptoms:**
On the cuopt **app stack** Step 2 wizard, the `cuOpt Frontend Credentials` variable group's two required fields — `cuopt_frontend_admin_username` and `cuopt_frontend_admin_password` — do not render in the form, even when both `skin_cuopt_core` and `skin_cuopt_partner` are set to `true` (which should satisfy the group's `visible: { or: [skin_cuopt_core, skin_cuopt_partner] }` condition). Users cannot fill these credentials through the ORM UI. The variables have `default: ''` with `minLength: 1` (username) and `minLength: 8` + `pattern: ".*[0-9].*"` (password) and `required: true`, so terraform validation will fail at apply if they remain empty.

Verified via:
```bash
unzip -p release_test_matrix/v0.0.8_cuopt.zip ai-accelerator-tf/schema.yaml | sed -n '413,440p'
# Shows: cuopt_frontend_admin_username has visible: false; cuopt_frontend_admin_password has visible: false
```

**Root cause:**
`common_schema.yaml` at lines 474–480 declares both variables with `visible: false`:
```yaml
cuopt_frontend_admin_username:
  type: string
  visible: false
cuopt_frontend_admin_password:
  type: password
  visible: false
```

`cuopt_schema.yaml` at lines 93–108 redefines both variables with rich metadata (title, description, minLength, pattern) but does NOT include an explicit `visible: true` (or any visibility key at all). The author's intent was for the group-level `visible: { or: [...] }` on `cuOpt Frontend Credentials` to control rendering. But:

1. `create_final_schema.py`'s deep-merge logic merges per-variable dicts. Since `cuopt_schema.yaml`'s variable definitions don't include a `visible` key, the merge keeps the `visible: false` from common_schema.
2. ORM's UI renderer treats variable-level `visible: false` as authoritative — variableGroup-level visibility cannot un-hide a variable that has `visible: false` set on itself.

Net effect: the variables are permanently hidden in the UI regardless of the group condition.

This is the **inverse of BUG-025/026's pattern**:
- BUG-025/026: variables NOT in common_schema → leak everywhere (need to be added with `visible: false`).
- BUG-027: variables in common_schema with `visible: false` AND a category-specific group expects to surface them → never renders (need explicit `visible: true` in the category schema).

**Affected files:**
- `ai-accelerator-tf/schemas/common_schema.yaml:474–480` — base `visible: false` declarations
- `ai-accelerator-tf/schemas/cuopt_schema.yaml:93–108` — needs explicit `visible: true` (or repeated `or` condition) on each variable
- `release_test_matrix/v0.0.8_cuopt.zip` — currently broken at the schema layer

**Workaround for in-flight track2-a10 cuopt deploy:**
Cancel the wizard before submitting Step 3, then update the stack vars via OCI CLI to inject the two credentials, then submit a fresh APPLY job:
```bash
# 1. Get current vars
OCI_CLI_PROFILE=aiincubations oci resource-manager stack get \
  --stack-id <APP_STACK_OCID> --region uk-london-1 --query 'data.variables' > /tmp/vars.json

# 2. Edit /tmp/vars.json to add cuopt_frontend_admin_username and cuopt_frontend_admin_password

# 3. Update stack
OCI_CLI_PROFILE=aiincubations oci resource-manager stack update \
  --stack-id <APP_STACK_OCID> --region uk-london-1 \
  --variables file:///tmp/vars.json --force

# 4. Submit apply
OCI_CLI_PROFILE=aiincubations oci resource-manager job create-apply-job \
  --stack-id <APP_STACK_OCID> --region uk-london-1 \
  --execution-plan-strategy AUTO_APPROVED
```

**Resolution (next release):**
Add explicit `visible: true` (or replicate the `or: [skin_cuopt_core, skin_cuopt_partner]` condition) to the `cuopt_frontend_admin_username` and `cuopt_frontend_admin_password` blocks in `cuopt_schema.yaml`. Recommended: just `visible: true`, since the group-level condition already gates the entire group. This makes the variable-level visibility match the intent.

Add a structural test in `schemas/tests/test_schema_structure.py` (or extend the new TestSchemaVisibility class from BUG-025's fix) that asserts: for any variableGroup with conditional `visible:`, every member variable must NOT have `visible: false` (otherwise the group condition has no effect). This locks the invariant going forward.

**Classification:** Code bug + skill gap. Code: cuopt_schema.yaml needs the override. Skill: `/schema-lint` should detect the variable-level-vs-group-level visibility mismatch.

**Reference:** Discovered when track2-a10 tried to fill the cuopt frontend credentials in the v0.0.8_cuopt.zip Step 2 wizard during Round 1 release testing on 2026-05-04. The same memory rule applies as for BUG-025/026 (BUG-001 prevention principle): every variable in vars.tf must be controllable from common_schema, then per-category schemas override visibility selectively.


### BUG-028: nim-llm pod stuck Pending on multi-node BM enterprise_rag — `label_nim_llm_node` partitioning resource removed in commit `bfa54d1`

**Status:** Open
**Date found:** 2026-05-04
**Found by:** track1-gpu4 during v0.0.8 release testing (Round 1 enterprise_rag/small on 2× BM.GPU4.8 in uk-london-1 / AD-1)
**Severity:** High (release-blocker for `enterprise_rag` and `enterprise_rag_aiq` on multi-node BM.GPU shapes)
**Affected packs:** `enterprise_rag`, `enterprise_rag_aiq`

**Symptoms:**
After `helm_release.rag` apply SUCCEEDED at 22:08:45Z, the NIM Operator created NIMCache + NIMService CRs and pods came up asynchronously over the following 30+ minutes. The 6 small NIM service pods (1 GPU each) scheduled across both BM.GPU4.8 nodes via cache-PVC affinity (4 nemoretrievers on `10.0.111.140`, 2 nemotron embedding+ranking on `10.0.99.116`). When nim-llm's cache finished at ~22:34Z and the NIM Operator created the nim-llm service pod (~22:41Z), the pod went immediately Pending and stayed Pending for 31+ minutes with:

```
0/4 nodes are available: 4 Insufficient nvidia.com/gpu.
preemption: Preemption is not helpful for scheduling.
```

nim-llm requests 8 GPUs; both BM.GPU4.8 nodes already had 4 + 2 GPUs consumed by the small NIMs. Neither node had 8 contiguous free GPUs. The default kubernetes scheduler does NOT proactively evict to make room for a Pending pod, so this state is permanent without manual intervention.

Empirical evidence (track1-gpu4 cluster):
- 4 nodes (2 control plane + 2 BM.GPU4.8 workers) all have empty `workload=nim-llm` labels and no `workload` taints
- Apply log grep across 42,778 lines for `label_nim_llm_node|workload=nim-llm|kubectl taint|kubectl label node`: **0 matches**
- Stack zip's `helm.tf` lines 460-462 contain only the comment `# The workload=nim-llm taint is no longer applied`, no resource

**Root cause:**
Commit `bfa54d1` ("feat: upgrade enterprise RAG helm chart to v2.5.0 with NIM Operator", 2026-04-15) deleted the `terraform_data.label_nim_llm_node` and `terraform_data.label_nim_llm_node_via_operator` resources from `helm.tf` (116 lines removed) and stripped the `workload=nim-llm` nodeSelector + toleration from nim-llm's section in `helm-values/enterprise-rag-values.yaml` (and `enterprise-rag-aiq-values.yaml`). The commit message states "NIMCache CRs include tolerations" — true, but the NIM Operator handles per-pod tolerations only; it does NOT partition nodes. Without a node tainted for nim-llm, the small NIMs spread across both GPU nodes via PVC affinity, leaving neither with 8 contiguous free GPUs.

The pre-`bfa54d1` config worked by:
1. `terraform_data.label_nim_llm_node` ran during apply (BEFORE NIM Operator created pods): labeled the first GPU node with `workload=nim-llm` and tainted it `workload=nim-llm:NoSchedule`.
2. helm-values gave nim-llm `nodeSelector: workload: nim-llm` AND `tolerations: [key=workload, value=nim-llm]` — so nim-llm could ONLY land on (and tolerate) the labeled node.
3. The 6 small NIMs lacked the `workload=nim-llm` toleration, so they avoided the tainted node and consolidated on the other one (6 × 1 GPU = 6 of 8 fits).

Without the resource AND the helm-values nodeSelector/toleration, the partitioning is gone and the scheduler can't anticipate that splitting the small NIMs leaves no room for nim-llm.

**Affected files:**
- `ai-accelerator-tf/helm.tf:460-462` — comment block where `terraform_data.label_nim_llm_node` + `_via_operator` resources used to live
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml:557-572` — nim-llm section missing `nodeSelector: workload: nim-llm` + `tolerations: [key=workload, value=nim-llm]`
- `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml:557-572` — same gap
- `release_test_matrix/v0.0.8_enterprise_rag.zip` — broken
- `release_test_matrix/v0.0.8_enterprise_rag_aiq.zip` — broken (same NIM stack, same gap)

**Why this didn't show up in commit bfa54d1's testing:**
Commit message says "Tested on OKE cluster in ap-osaka-1 with 2x BM.GPU.A100-v2.8 nodes." Same shape arithmetic (2 nodes × 8 GPUs = 16 total, nim-llm needs 8). The bug is non-deterministic at small scale — the scheduler's "spread" behavior depends on which cache job's PVC gets bound to which node first, which depends on OCI CSI provisioner ordering. ap-osaka-1's apply may have happened to land all 6 small NIM cache PVCs on a single node, leaving the other node free for nim-llm. uk-london-1's apply did not get that lucky.

**Workaround (manual, for users on v0.0.8):**
After enterprise_rag apply succeeds and nim-llm goes Pending, manually apply the partitioning:
```bash
NODE=$(kubectl get nodes -l 'nvidia.com/gpu.present=true' --sort-by=.metadata.name -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE" workload=nim-llm --overwrite
kubectl taint node "$NODE" workload=nim-llm:NoSchedule --overwrite

# Delete small NIM pods on that node so they reschedule onto the other node
kubectl get pods -n rag -o jsonpath='{range .items[?(@.spec.nodeName=="'"$NODE"'")]}{.metadata.name}{"\n"}{end}' | xargs -r kubectl -n rag delete pod
```
Recovery is non-trivial because the small NIM pods need to be evicted and re-scheduled on the other node, and the operator may take a few minutes to reconcile.

**Resolution (next release, v0.0.9):**
Restore the `terraform_data.label_nim_llm_node` and `terraform_data.label_nim_llm_node_via_operator` resources in `helm.tf` (the original 116-line block from before commit `bfa54d1`). Restore the `nodeSelector: workload: nim-llm` and matching `tolerations` block on nim-llm in both `helm-values/enterprise-rag-values.yaml` and `helm-values/enterprise-rag-aiq-values.yaml`. The destroy provisioner from BUG-009's fix should be preserved.

**Prevention:**
Add a release-test gate that fails if any tested BM.GPU shape with 2+ nodes does not have a `workload=nim-llm:NoSchedule` taint on exactly one GPU node after apply succeeds. Or, more thoroughly, add an apply-time precondition that asserts nim-llm has the right nodeSelector when targeting BM.GPU shapes.

**Classification:** Code regression. Tested behavior on v0.0.7 was correct; commit `bfa54d1` removed both halves of the partitioning together. Recommend a code revert + re-test on multi-node BM.GPU4.8 in uk-london-1 before shipping v0.0.9.

**Decision for v0.0.8 release:** SKIP `enterprise_rag` and `enterprise_rag_aiq` from the v0.0.8 ship lineup. Customers wanting these packs continue to use v0.0.7. Fix lands in v0.0.9.


### BUG-029: enterprise_rag destroy fails — NIMCache/NIMService CRs orphaned, nim_operator destroyed before cleanup, namespace stuck Terminating

**Status:** Open
**Date found:** 2026-05-04
**Found by:** track1-gpu4 during v0.0.8 release testing (Round 1 enterprise_rag/small destroy after BUG-028 was identified)
**Severity:** High (release-blocker for clean teardown; user can manually unstick but it's a poor UX)
**Affected packs:** `enterprise_rag`, `enterprise_rag_aiq`

**Symptoms:**
ORM destroy job for the enterprise_rag app stack runs through the resource graph correctly — `helm_release.rag` is destroyed before `helm_release.nim_operator` per the depends_on chain — but the helm uninstall of the rag chart returns immediately with a "These resources were kept due to the resource policy" warning listing all NIMCache CRs:

```
helm_release.rag[0]: Destruction complete after 1s

Warning: Helm uninstall returned an information message
These resources were kept due to the resource policy:
[NIMCache] nemoretriever-graphic-elements-v1
[NIMCache] nemoretriever-ocr-v1
[NIMCache] nemoretriever-page-elements-v3
[NIMCache] nemoretriever-table-structure-v1
[NIMCache] nemotron-embedding-ms-cache
[NIMCache] nemotron-ranking-ms-cache
[NIMCache] nim-llm-cache
```

Then `helm_release.nim_operator` destroys (also fast — 0s helm uninstall). Then `kubernetes_namespace_v1.app_namespace[0]: Destroying... [id=rag]` runs, hangs for 4-5 minutes "Still destroying", and finally fails with:

```
Error: context deadline exceeded
```

The `rag` namespace stays in Terminating state indefinitely because the orphan NIMCache CRs have finalizers waiting for the NIM Operator to clean them up — but the NIM Operator helm release was already destroyed, so the finalizers never run.

**Root cause:**
The nvidia-blueprint-rag-v2.5.0 helm chart annotates NIMCache and NIMService CRs with `helm.sh/resource-policy: keep`, intentionally leaving them in the cluster after `helm uninstall rag`. This is presumably so users can keep their downloaded models across helm upgrades. But for a clean destroy, those CRs become orphans because:

1. `helm_release.rag` destroys → CRs are kept (per chart's `keep` annotation)
2. `helm_release.nim_operator` destroys → operator deployment removed; its CRDs may still exist briefly but the controller is gone
3. `kubernetes_namespace_v1.app_namespace[0]` destroys → blocked because the orphan NIMCache/NIMService CRs in that namespace have finalizers (e.g., `apps.nvidia.com/nimcache-protection`) that need the operator to release them
4. Operator is gone → finalizers never resolve → namespace stays in Terminating until Terraform's 5-min context timeout fires

The depends_on chain in `helm.tf` is correct on apply (rag depends on nim_operator), so destroy correctly tears down rag first. The issue is that rag's helm uninstall does NOT actually clean up the resources it created (NIMCache CRs) — it just disowns them. By the time nim_operator is destroyed, those orphans are still in the namespace with operator-owned finalizers.

**Empirical evidence (track1-gpu4 destroy at 23:07Z):**
```
22:13:29  Helm uninstall returned: "[NIMCache] ... kept due to resource policy"
23:08:33  helm_release.rag: Destruction complete after 1s
23:08:42  helm_release.nim_operator: Destroying... [id=nim-operator]
23:08:42  kubernetes_namespace_v1.app_namespace[0]: Destroying... [id=rag]
23:08:43  helm_release.nim_operator: Destruction complete after 0s
23:09:10  Still destroying... [id=rag, 10s elapsed]
23:09:20  Still destroying... [id=rag, 20s elapsed]
... (repeats every 10s)
23:13:29  Still destroying... [id=rag, 4m50s elapsed]
23:13:29  Error: context deadline exceeded
```

NIM Operator was destroyed in 0s while the namespace was still trying to delete — the controller that owned the CR finalizers was already gone before the namespace's finalizer cascade began.

**Affected files:**
- `ai-accelerator-tf/helm.tf:474-489` — `helm_release.nim_operator` (no destroy-time provisioner to clean CRs)
- `ai-accelerator-tf/helm.tf:491-...` — `helm_release.rag` (no override of the chart's keep annotation, no destroy-time CR cleanup)
- `release_test_matrix/v0.0.8_enterprise_rag.zip` — broken destroy
- `release_test_matrix/v0.0.8_enterprise_rag_aiq.zip` — same NIM stack, same destroy bug

**Workaround (manual, for users on v0.0.8):**
When destroy fails with "context deadline exceeded" on the `rag` namespace, manually clean up the orphans then retry:

```bash
# Force-finalize any orphan NIMCache CRs (operator is already gone, so just strip finalizers)
kubectl -n rag get nimcache.apps.nvidia.com -o name 2>/dev/null \
  | xargs -r -I{} kubectl -n rag patch {} --type=merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n rag get nimservice.apps.nvidia.com -o name 2>/dev/null \
  | xargs -r -I{} kubectl -n rag patch {} --type=merge -p '{"metadata":{"finalizers":[]}}'

# Force-delete the namespace (will succeed once finalizers are clear)
kubectl get ns rag -o json | jq '.spec.finalizers=[]' \
  | kubectl replace --raw "/api/v1/namespaces/rag/finalize" -f - \
  || kubectl delete ns rag --force --grace-period=0

# Retry the ORM destroy job — should succeed now
```

Track1-gpu4 used this workaround successfully on 2026-05-05 at 00:10Z (app destroy retry SUCCEEDED).

**Resolution (next release, v0.0.9):**
Add a `null_resource` (or `terraform_data`) that runs a destroy-time provisioner BEFORE `helm_release.nim_operator` is destroyed, explicitly deleting the NIMCache and NIMService CRs while the operator is still running:

```hcl
resource "null_resource" "nim_cr_cleanup" {
  count = local.deploy_app_rag ? 1 : 0
  triggers = {
    namespace  = local.starter_pack_config.app_namespace
    kubeconfig = local_sensitive_file.kubeconfig_patch[0].filename
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG=${self.triggers.kubeconfig}
      echo "Cleaning up orphan NIMCache/NIMService CRs before nim_operator destroy..."
      kubectl -n ${self.triggers.namespace} delete nimcache.apps.nvidia.com --all --ignore-not-found --timeout=120s || true
      kubectl -n ${self.triggers.namespace} delete nimservice.apps.nvidia.com --all --ignore-not-found --timeout=120s || true
    EOT
  }
  depends_on = [helm_release.rag]
}

# Wire nim_operator's destroy to wait for the CR cleanup:
resource "helm_release" "nim_operator" {
  ...
  depends_on = [..., null_resource.nim_cr_cleanup]
}
```

With this resource in place, destroy ordering becomes:
1. `helm_release.rag` destroyed (chart's keep policy leaves CRs)
2. `null_resource.nim_cr_cleanup` destroys → kubectl deletes the orphan CRs (operator still running, finalizers clean up)
3. `helm_release.nim_operator` destroys (now safe — no orphans depending on it)
4. `kubernetes_namespace_v1.app_namespace` destroys (no orphan finalizers blocking)

**Prevention:**
A pytest-level test on the destroy plan would help: assert that for `enterprise_rag*` packs, the destroy-graph order is `rag → nim_cr_cleanup → nim_operator → namespace`. More broadly: any helm chart that uses the `keep` resource-policy annotation needs an explicit Terraform-managed cleanup resource between the chart and any operator that owns finalizers on those kept resources.

**Classification:** Code bug + skill gap. Code: missing destroy-time CR cleanup resource. Skill: `/testing-pack` skill should include a destroy-validation phase that asserts namespace deletes within a reasonable time (currently the skill only validates apply-time success).

**Decision for v0.0.8 release:** SKIP `enterprise_rag` and `enterprise_rag_aiq` from the v0.0.8 ship lineup (combined with BUG-028). Both bugs share the same affected packs and both need fixing for the next release. Customers running v0.0.7 are unaffected (v0.0.7 has the partitioning resource AND the helm chart predates the keep-policy NIMCache pattern).

---

### BUG-030: (RETRACTED) enterprise_rag/aiq infra apply fails — was OCI Out-of-Host-Capacity, not a code bug

**Status:** Invalid (retracted 2026-05-05 19:55 UTC)
**Date found:** 2026-05-05
**Date retracted:** 2026-05-05 (same day, ~75 min after first filed)
**Found by:** Grant via track1-bmgpu4 during v0.0.8 release re-test
**Severity:** —

**HEADLINE — DO NOT IMPLEMENT THE PROPOSED FIX BELOW**

The original hypothesis — that infra apply failed because GPU-tainted nodes blocked coredns scheduling — was the *symptom*, not the cause. After being pushed by team-lead for the actual TF error, I queried `oci ce work-request list --cluster-id <my-cluster>` then `oci ce work-request-error list --compartment-id <C> --work-request-id <WR>` and found:

```
NODEPOOL_CREATE work request status: FAILED at 2026-05-05T18:16:11Z
  code: InternalError
  message: 1 node(s) launch failure ... Out of host capacity.
  shape: VM.Standard.E5.Flex
  endpoint: https://iaas.uk-london-1.oraclecloud.com/20160918/instances
  timestamp: 2026-05-05T18:16:09.379Z
```

The OKE-managed control-plane node pool (`oci_containerengine_node_pool.oke_node_pool`, size=2, VM.Standard.E5.Flex, the resource that hosts coredns + system pods) tried to launch its first instance at 18:16:09Z, OCI returned 500 InternalError "Out of host capacity" in `uk-london-1` AD-1. Terraform's create-with-retry held the resource as "Still creating..." for the next ~20 min waiting for OCI to recover, then timed out at the 30-min mark and reported APPLY FAILED.

The BM.GPU4.8 instance pool DID succeed (work request 18:35:31Z) — that's why the cluster came up ACTIVE with 2 GPU nodes Ready. The `nvidia.com/gpu=present:NoSchedule` taint on those nodes is correct + working as designed; coredns was supposed to land on the missing E5.Flex control-plane nodes. v0.0.7 worked because v0.0.7 was deployed in regions/ADs that had E5.Flex headroom; the same code in uk-london-1 AD-1 today hits OOC.

**Classification:** OCI capacity issue. Same family as track 2's hit. Not a code bug. v0.0.8 release is NOT blocked by this for er/er-aiq.

**Lessons learned (skill, not code):**
1. `oci resource-manager job get-job-logs` truncates at ~1550 entries. The TF "Apply complete!" / final error block is often beyond this cap when long-poll resources (Still creating...) dominate the log stream. ORM Console UI shows the same truncated log.
2. For OKE node pool `Still creating...` failures, query `oci ce work-request list --cluster-id <ID>` then `oci ce work-request-error list --compartment-id <C> --work-request-id <WR>`. This is where the actual compute error surfaces.
3. `/diagnosing-stack` skill should add this exact check sequence for any OKE-related FAILED stack.

**Recommendation for v0.0.8 release:**
- Retry on a different region/AD with confirmed E5.Flex headroom + BM.GPU4.8 quota (uk-london-1 was the only candidate with both BM.GPU4.8 AND ECPU quota, but capacity is transient)
- OR retry uk-london-1 AD-1 later (capacity may recover)
- Do NOT skip er/er-aiq from the release lineup based on this failure

---

**ORIGINAL (INCORRECT) HYPOTHESIS PRESERVED FOR HISTORICAL REFERENCE — DO NOT IMPLEMENT**

(Below was the wrong diagnosis. Kept for transparency on what was learned.)

Infra-only apply of `enterprise_rag/small` on `BM.GPU4.8` in `uk-london-1` FAILED at 18:36:01Z (~29 min into apply). OKE cluster reached ACTIVE; both BM.GPU4.8 worker nodes joined cluster as Ready with NVIDIA GPU device plugin Running. But `helm list --all-namespaces` shows ZERO Helm releases — the apply timed out before any chart could install.

`kubectl get pods -n kube-system` shows:
```
coredns-5fb7d7c686-xx9hc               0/1     Pending   88m
kube-dns-autoscaler-7fb69ccd99-jqf6n   0/1     Pending   88m
```

`kubectl describe pod -n kube-system coredns-5fb7d7c686-xx9hc` events:
```
Warning  FailedScheduling  3m42s (x11 over 53m)  default-scheduler
0/2 nodes are available: 2 node(s) had untolerated taint {nvidia.com/gpu: present}.
no new claims to deallocate, preemption: 0/2 nodes are available:
2 Preemption is not helpful for scheduling.
```

**Root cause:**
1. OKE 1.34.1 auto-applies taint `nvidia.com/gpu=present:NoSchedule` to nodes with GPUs (the BM.GPU4.8 instances).
2. `vars.tf` `local.starter_pack_configs.enterprise_rag.small` (and `enterprise_rag_aiq.small`, `enterprise_rag_aiq.medium`) sets `cpu_worker_node_pool_size = 0`. There is NO non-GPU worker node pool — the cluster has zero untainted nodes.
3. `coredns` and `kube-dns-autoscaler` have tolerations only for `CriticalAddonsOnly`, `oci.oraclecloud.com/oke-is-preemptible`, and `node.kubernetes.io/{not-ready,unreachable}` — they do NOT tolerate `nvidia.com/gpu=present`. So they cannot schedule.
4. With cluster DNS broken, any chart that depends on DNS during install (cert-manager and ingress-nginx use webhook calls during chart bootstrap) fails. `helm_release.cert_manager` (or whichever runs first in `helm.tf`) timed out.
5. Terraform aborted at the 30-min mark → APPLY FAILED → no rollback (cluster, node pool, instance pool all still RUNNING).

**Affected files:**
- `ai-accelerator-tf/vars.tf` — `local.starter_pack_configs.enterprise_rag.small`, `local.starter_pack_configs.enterprise_rag_aiq.small`, `local.starter_pack_configs.enterprise_rag_aiq.medium` all have `cpu_worker_node_pool_size = 0`
- `ai-accelerator-tf/helm.tf` — installs cert-manager / ingress-nginx without explicit GPU-taint tolerations
- (Possibly) `ai-accelerator-tf/oke.tf` — control-plane / system addon configuration

**Affected packs / sizes:**
- `enterprise_rag/small` (BM.GPU4.8) — confirmed FAIL
- `enterprise_rag_aiq/small` (BM.GPU4.8) — predicted FAIL (same config)
- `enterprise_rag_aiq/medium` (BM.GPU.A100-v2.8) — predicted FAIL (same config; A100-v2 likely has same auto-taint)
- `cuopt/*`, `vss/*`, `paas_rag/*` — NOT affected (they have `cpu_worker_node_pool_size >= 1`)

**Why it didn't surface in v0.0.7:**
Two candidate explanations (need to verify):
- (Likely) v0.0.7 `vars.tf` had `cpu_worker_node_pool_size > 0` for er/er-aiq, providing untainted nodes for system pods. v0.0.8 dropped it (need git blame).
- (Possible) Earlier OKE versions did not auto-apply the `nvidia.com/gpu=present` NoSchedule taint, only the CriticalAddonsOnly / standard taints. OKE 1.34.1 may be the regression.

**Repro:**
1. Deploy `enterprise_rag/small` infra-only ORM stack (`deploy_application=false`, `skip_capacity_check=true`).
2. Wait ~30 min — apply will fail.
3. Connect kubectl to the OKE cluster — verify coredns Pending with `untolerated taint {nvidia.com/gpu: present}`.

**Fix candidates:**
- (Preferred) Add a small CPU worker node pool: set `cpu_worker_node_pool_size = 1` for er/er-aiq across all sizes, with `instanceShape = "VM.Standard.E5.Flex"`, ocpus 1-2, memory 8-16. Hosts coredns + Helm controllers; minimal cost. Matches the cuopt/vss design.
- (Alternative) Patch coredns + kube-dns-autoscaler tolerations via a `kubernetes_manifest` Terraform resource to tolerate `nvidia.com/gpu=present:NoSchedule`. Smaller diff but rebuilds cluster pods after every apply; less idiomatic.
- (Alternative) Configure node pool to NOT apply the `nvidia.com/gpu` taint via `oci_containerengine_node_pool` `node_metadata` or similar OKE setting, if such an option exists.

**Workaround for in-flight test (NOT recommended for release):**
`kubectl taint nodes --all nvidia.com/gpu-` then re-run apply. This unblocks the cluster but shouldn't ship — the GPU taint exists for a reason (it ensures only GPU-aware pods land on GPU nodes).

**Stack OCID where this was observed:**
- Stack: `ocid1.ormstack.oc1.uk-london-1.amaaaaaam3augwaa26e6ylkbdamvxavaqeqqywpdh6danfje5ivmrkv34kfa`
- Failed job: `ocid1.ormjob.oc1.uk-london-1.amaaaaaam3augwaauyidhqyyu5owsq6xda2az5zqnhxzpcqdatclknvtmaoa`
- OKE cluster (still ACTIVE): `ocid1.cluster.oc1.uk-london-1.aaaaaaaa6uboy4fhhp7jukim5rlh6itxawok5acd5beag43mncc6nftv7a5a`

**Decision for v0.0.8 release:**
Combined with BUG-028 + BUG-029, this confirms `enterprise_rag` and `enterprise_rag_aiq` should be SKIPPED from the v0.0.8 ship lineup. Three release-blocking bugs in those two packs.


### BUG-031: dox_pack two-stack model fails — DAC + imported_model + endpoint not gated on `deploy_application`

**Status:** Open
**Date found:** 2026-05-05
**Found by:** track3-cpu during v0.0.8 release re-test, code-verified by Monitor agent
**Severity:** High (release blocker for dox_pack only)

**Symptoms:**
App-stack APPLY fails with `400-LimitExceeded` on `oci_generative_ai_dedicated_ai_cluster.dox_pack_dac` because the infra stack already claimed the H100 quota:

```
Error: 400-LimitExceeded
Service: Generative Ai Dedicated Cluster
Operation: CreateDedicatedAiCluster
Endpoint: POST https://generativeai.eu-frankfurt-1.oci.oraclecloud.com/20231130/dedicatedAiClusters
Resource: oci_generative_ai_dedicated_ai_cluster.dox_pack_dac
Limit: dedicated-unit-h100-count
```

**Root cause:**
`ai-accelerator-tf/genai_dac.tf` declares the DAC, the imported model, and the model serving endpoint with `count = local.needs_dac ? 1 : 0` where:

```hcl
locals {
  needs_dac = var.starter_pack_category == "dox_pack"
}
```

The gate is **only** on `starter_pack_category == "dox_pack"` — there is **no `&& var.deploy_application` (or `deploy_infrastructure`)** condition. Therefore both stacks (`deploy_application=false` infra and `deploy_application=true` app) try to create the same three GenAI resources. In a two-stack flow:

- Phase 4 (infra apply, `deploy_application=false`): DAC `dox-pack-dac-<deploy_id>` created. Consumes 8/8 H100 cards in fra.
- Phase 5 (app apply, `deploy_application=true`): TF tries to create a SECOND DAC instance. OCI returns `400-LimitExceeded` because the first one is still ACTIVE.

The same defect applies to the imported model and endpoint resources, but they are encountered first, do their long work (model import is ~48 min), and then the apply hits the DAC step and fails.

**Affected files:**
- `ai-accelerator-tf/genai_dac.tf:9-11` — `locals.needs_dac` definition
- `ai-accelerator-tf/genai_dac.tf:18-37` — `oci_generative_ai_imported_model.qwen3_vl` (gated only on `needs_dac`)
- `ai-accelerator-tf/genai_dac.tf:39-59` — `oci_generative_ai_dedicated_ai_cluster.dox_pack_dac` (gated only on `needs_dac`)
- `ai-accelerator-tf/genai_dac.tf:62-77` — `oci_generative_ai_endpoint.qwen3_vl_endpoint` (gated only on `needs_dac`)

**Classification:** Code bug (count-gate defect). Will reproduce on every dox_pack two-stack run until patched. Not capacity, not transient, not a NIM/Corrino/llamastack issue.

**Recommended fix:**
Update `local.needs_dac` to gate on `deploy_application` so the DAC + model + endpoint live only in the app stack (DAC is hourly-billed → tied to app lifecycle, not long-lived infra):

```hcl
locals {
  needs_dac = var.starter_pack_category == "dox_pack" && var.deploy_application
}
```

Verify after patch:
1. `terraform plan` for infra-only (deploy_application=false): plan should NOT include `oci_generative_ai_*.qwen3_vl*` or `dox_pack_dac` resources.
2. `terraform plan` for app (deploy_application=true): plan SHOULD include all three GenAI resources.
3. End-to-end two-stack deploy: infra completes ~12 min (no DAC/model), app completes ~50-60 min (model import + DAC + endpoint + helm).

**Repro:**
1. Deploy `dox_pack/small` infra-only ORM stack (`deploy_application=false`, `genai_region=eu-frankfurt-1`, `dac_billing_acknowledgement=true`). Apply succeeds in ~98 min (model import + DAC). DAC ends ACTIVE, holding 8/8 H100 cards.
2. Deploy app stack (`deploy_application=true`, same `existing_cluster_id` etc.). Model re-imports successfully (~49 min), then DAC creation fails with `400-LimitExceeded`.

**Stack OCIDs where this was observed (preserved per team-lead's direction):**
- Infra (SUCCEEDED): `ocid1.ormstack.oc1.us-dallas-1.amaaaaaam3augwaaml6c6ugyz6klbsa6g3u4imw7rf3n2itnhooc6wtmzm4q`
- App (FAILED): `ocid1.ormstack.oc1.us-dallas-1.amaaaaaam3augwaa7tx3xqqawoo4syofzsj4eioeqoutrs4dkiqjtfvpiaoa`
- App apply job (FAILED): `ocid1.ormjob.oc1.us-dallas-1.amaaaaaam3augwaaavitjyarvn3zfoiett3vcwt7faqhcboygf4orqrcidla` (finished 2026-05-05T23:33:46Z)
- Live ACTIVE DAC (created by infra Phase 4 at 20:19:12Z, holding all 8 cards): `ocid1.generativeaidedicatedaicluster.oc1.eu-frankfurt-1.amaaaaaam3augwaanazd7hxa6dl2j2f4nvqebvfr3pcun5d6mpy366lnbh7q`

**Cost note:** the live DAC is billing hourly (H100_X8 unit, fra) until the infra stack is destroyed or the DAC is deleted manually. Coordinate with team-lead on cost vs preserve-state-for-diagnosis trade-off.

**Decision for v0.0.8 release:**
- dox_pack v0.0.8 ship lineup: BLOCKED by BUG-031 unless patch is applied and re-tested. Schema validation (BUG-025/026 regression) PASSED, infra apply PASSED, model import PASSED, but full end-to-end app apply cannot complete with the current count gate.
- Recommend cutting v0.0.9 with BUG-031 fix and re-testing dox_pack only, OR shipping v0.0.8 with dox_pack marked as "schema-validated, deployment blocked by BUG-031 — fix in v0.0.9".

---

### BUG-032: enterprise_rag App apply fails — NIMCache RWO PVC Multi-Attach blocks `patch_nim_operator_resources` even though pack is functional

**Status:** Open
**Date found:** 2026-05-05
**Found by:** Grant via track1-bmgpu4 during v0.0.8 release re-test, code-context verified by Monitor agent
**Severity:** High (release-correctness blocker for `enterprise_rag` + `enterprise_rag_aiq`; pack is functionally usable but ORM apply state is FAILED)

**TL;DR:** The `enterprise_rag/small` app stack apply fails at `terraform_data.patch_nim_operator_resources` after a 30-min timeout waiting for `nimservices/nim-llm` Ready=True. The pod IS healthy and the model IS serving requests (smoke tests PASS), but the NIMCache CR's status condition `JobCompleted` never flips True because nim-operator spawns a *retry* cache-job pod that gets stuck in `FailedAttachVolume: Multi-Attach error` against the same RWO PVC the nim-llm Deployment is holding.

**This is NOT BUG-028.** BUG-028 fix (commits `01191d6` + `206773e`) is **VALIDATED** by this run — nim-llm pod scheduled fine, no `FailedScheduling: Insufficient nvidia.com/gpu` events, no PVC affinity errors at scheduling time.

**Symptoms:**

- `oci resource-manager job get` for app stack: `lifecycle-state: FAILED, time-finished: 2026-05-06T00:00:41Z`, op `APPLY`
- ORM job log tail:
  ```
  Waiting for NIMService CRs to be Ready (up to 30m)...
  nimservice.apps.nvidia.com/nemotron-ranking-ms condition met        ← Ready
  nimservice.apps.nvidia.com/nemotron-embedding-ms condition met      ← Ready
  nimservice.apps.nvidia.com/nemoretriever-ocr-v1 condition met       ← Ready
  nimservice.apps.nvidia.com/nemoretriever-graphic-elements-v1 ...    ← Ready
  nimservice.apps.nvidia.com/nemoretriever-page-elements-v3 ...       ← Ready
  nimservice.apps.nvidia.com/nemoretriever-table-structure-v1 ...     ← Ready
  error: timed out waiting for the condition on nimservices/nim-llm
    TIMED OUT: nimservice/nim-llm
  ERROR: the following NIMService CRs are not Ready:
    - nim-llm
  ```
- `kubectl get pods -n rag -l app.kubernetes.io/name=nim-llm` — `nim-llm-599f644859-kqbhz 1/1 Running` (60+ min uptime)
- `kubectl logs nim-llm-...` — continuous `GET /v1/health/ready HTTP/1.1 200` responses; model loaded
- `kubectl exec ... curl -X POST /v1/chat/completions` — returns real chat completion from `nvidia/nemotron-3-super-120b-a12b`
- `kubectl get nimservice -n rag nim-llm`:
  ```yaml
  status:
    conditions:
    - type: Ready
      status: "False"
      reason: NIMCacheNotReady
      message: NIMCache nim-llm-cache not ready
      lastTransitionTime: "2026-05-05T22:53:11Z"   ← never updated since deploy
    state: NotReady
  ```
- `kubectl get nimcache -n rag nim-llm-cache`:
  ```yaml
  status:
    conditions:
    - type: NIM_CACHE_JOB_COMPLETED
      status: "False"
      reason: JobFailed
      message: The Job to cache NIM has failed
    state: InProgress
  ```
- `kubectl get jobs -n rag` — `nim-llm-cache-job   Running   0/1   55m+`
- `kubectl describe pod nim-llm-cache-job-qn466` (the stuck retry pod):
  ```
  Events:
    Normal  Scheduled            Successfully assigned rag/nim-llm-cache-job-qn466 to 10.0.101.80
    Warning FailedAttachVolume   Multi-Attach error for volume "csi-d03a658e-ffd5-4546-97e9-d6725cd81952"
                                 Volume is already used by pod(s) nim-llm-599f644859-kqbhz
  ```

**Root cause:**

1. nim-operator spawns the *initial* `nim-llm-cache-job` pod, which downloads the model to PVC `nim-llm-cache-pvc` (`accessModes: [ReadWriteOnce]`), succeeds, and is reaped.
2. The Job object's `succeeded` field never increments (the operator's controller doesn't propagate the pod completion to the Job). The Job stays `Running 0/1`.
3. The nim-llm Deployment pod claims the same RWO PVC, mounts it, loads the model from the cache, becomes Ready 1/1, and starts serving.
4. nim-operator (k8s-nim-operator-3.1.0) sees the Job at `0/1 Running` and spawns a *retry* cache-job pod.
5. The retry pod tries to mount the same RWO PVC. CSI returns `Multi-Attach error: Volume is already used by pod(s) nim-llm-...`. The retry pod is stuck in `Pending → ContainerCreating` indefinitely.
6. Operator never reconciles `NIMCache.status.conditions[NIM_CACHE_JOB_COMPLETED]` to True, never flips `NIMService.status.conditions[Ready]` to True.
7. `terraform_data.patch_nim_operator_resources` runs `kubectl wait --for=condition=Ready nimservice/nim-llm --timeout=30m`, hits the 30-min wall, returns non-zero. Terraform marks the apply FAILED.

**Functional validation (smoke tests PASS):**

```
kubectl exec -n rag nim-llm-... -- curl -sS -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"nvidia/nemotron-3-super-120b-a12b","messages":[{"role":"user","content":"Reply with one word: hello"}],"max_tokens":10}'

→ 200 OK
{
  "id": "chatcmpl-94675323f71ed270",
  "object": "chat.completion",
  "model": "nvidia/nemotron-3-super-120b-a12b",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", ...},
    "finish_reason": "length"
  }],
  "usage": {"prompt_tokens": 22, "total_tokens": 32, "completion_tokens": 10}
}
```

Model `nvidia/nemotron-3-super-120b-a12b` at FP8 quantization (`/model-store/.../snapshots/rl-030326-fp8/`), `max_model_len: 32768`, 38167/40960 MiB GPU0 utilization. Pack works. Customer can use the cluster.

**Affected files:**

- `ai-accelerator-tf/helm.tf:594` — `terraform_data.patch_nim_operator_resources` (the resource that times out)
- `ai-accelerator-tf/helm.tf:761` — `terraform_data.patch_nim_operator_resources_via_operator` (same wait condition, will hit same issue)
- nim-operator chart `k8s-nim-operator-3.1.0` — operator's spawn-retry logic for cache jobs
- helm-values for nim-llm (rag chart `nvidia-blueprint-rag-v2.5.0`) — PVC `accessModes` defaults to `[ReadWriteOnce]`

**Affected packs / sizes:**

- `enterprise_rag/small` (BM.GPU4.8) — confirmed FAIL
- `enterprise_rag_aiq/small` (BM.GPU4.8) — predicted FAIL (same nim-operator chart, same PVC pattern)
- `enterprise_rag_aiq/medium` (BM.GPU.A100-v2.8) — predicted FAIL (same chart)

**Repro:**

1. Deploy `enterprise_rag/small` end-to-end (infra + app) on a healthy OKE cluster with BM.GPU4.8 + sufficient FSS.
2. Observe app apply timeout at `patch_nim_operator_resources` after 30 min.
3. Verify pod is Ready 1/1 and model is serving via `curl /v1/chat/completions`.
4. Verify `nim-llm-cache-job-*` retry pod is stuck `FailedAttachVolume: Multi-Attach`.

**Fix candidates:**

- **(a) Switch PVC `accessModes` to `[ReadWriteMany]`.** OKE FSS-backed PVCs support RWX. Lets the nim-llm Deployment AND the retry cache-job pod coexist mounting the same PVC. Probably the cleanest one-line helm-values fix. Risk: needs FSS not block storage; need to verify default `oke-fss` storage class is used here.
- **(b) Suppress operator retry-spawn once NIMCache state is otherwise satisfied.** Configure nim-operator via helm values to not spawn retry jobs when the underlying NIMService pod is Ready. Less code-localized; depends on operator chart parameters.
- **(c) Split cache PVC and serving PVC.** Cache job mounts a temp PVC, copies the cached model to a separate read-only PVC that the nim-llm Deployment mounts. More invasive chart restructuring.
- **(d) Widen the patcher's `kubectl wait` predicate** to accept the pod being Ready 1/1 even if the NIMService.status.conditions[Ready] is still False. Would unstick apply but masks the underlying operator bug.

**Workaround for in-flight test (NOT for shipping):**

```
kubectl delete pod -n rag nim-llm-cache-job-qn466
# But the operator will respawn it, leading to the same Multi-Attach loop
```

OR

```
kubectl patch nimservice -n rag nim-llm --subresource=status --type=merge \
  -p '{"status":{"conditions":[{"type":"Ready","status":"True","lastTransitionTime":"2026-05-06T00:00:00Z","reason":"PodReady","message":"manual override"}],"state":"Ready"}}'
# Then re-run apply — patch_nim_operator_resources should see Ready=True and complete
```

(Manual subresource patch — NOT a release-acceptable workaround, but demonstrates the bug is purely in the CR status reconciliation layer, not the actual data path.)

**Stack OCIDs where this was observed:**

- App stack: `ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaa34uz2j72yv65fhw5hm3izvlyzc23vjqzexog2z4qhfza`
- Failed app job: `ocid1.ormjob.oc1.us-sanjose-1.amaaaaaam3augwaaljqfroyb6c3sijbif2cqrxumus47p5b5lzdsd4vfyamq`
- Infra stack: `ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaa36wqai2lpepvs3uymr2lntnotlzc4luju5itmeu52aqa`
- OKE cluster: `ocid1.cluster.oc1.us-sanjose-1.aaaaaaaaldpn7mp443ajpejixedo6enlgp7n4vo3uo2re3fgkc7qxne25emq` (`AI-Accel-OKE-oTKAI4`)
- Region: `us-sanjose-1`, AD: `TrcQ:US-SANJOSE-1-AD-1`

**Decision for v0.0.8 release:**

Two paths:
- **Ship v0.0.8 with documented workaround:** Pack is functionally correct (smoke tests pass). Customers following docs will see "FAILED" in ORM Console — that's a poor experience but the cluster is usable. Document in known-issues that the apply will show FAILED but the pack is ready for use.
- **Hold for v0.0.9 with fix candidate (a):** One-line PVC accessModes change (RWO → RWX), rebuild zip, retest. Tactical risk: short.

Recommend **fix candidate (a)** for v0.0.9 unless ship pressure is acute, in which case ship v0.0.8 with workaround docs and fold the fix into v0.0.9.

**Cross-references:**
- BUG-028 (Open, 2026-05-04): nim-llm Pending due to `label_nim_llm_node` removal — **fix VALIDATED by this run** (no Pending, no FailedScheduling)
- BUG-029 (Open, 2026-05-04): destroy hangs on orphan NIMCache CRs — UNTESTED in this run (no destroy yet)
- BUG-022 (Open, 2026-04-29): NIM Operator post-deploy patcher deadlocks — different deadlock mode (helm release ordering); BUG-032 is a separate operator-side reconciliation issue

### BUG-033: dox_pack contract-backend pod CrashLoopBackOff — ADB wallet not mounted, TNS_ADMIN unset

**Status:** Open
**Date found:** 2026-05-07
**Found by:** Grant via track3-cpu during v0.0.8 release re-test (dox_pack/small Round 2, us-sanjose-1), exposed by BUG-031 fix unblocking the app apply path
**Severity:** High (release-correctness blocker for `dox_pack` — frontend serves HTTP 503 because contract-backend cannot connect to ADB)

**TL;DR:** The dox_pack `recipe-contract-backend-*` pod CrashLoopBackOffs at startup with `oracledb.exceptions.DatabaseError: DPY-4027: no configuration directory specified` because the deployment uses a TCPS DSN to Autonomous Database but never mounts the ADB wallet bundle and never sets `TNS_ADMIN`. The cascading failure takes down `recipe-skin-dox-pack-core-*` (nginx upstream lookup of `contract-backend-svc` fails), which makes the public ingress respond HTTP 503. **This is NOT a BUG-031 regression** — it is a pre-existing dox_pack blueprint config gap that was masked while BUG-031 prevented the app stack from ever finishing apply.

**Symptoms:**

- ORM app stack apply: **SUCCEEDED** (DAC, imported model, endpoint, all helm releases, blueprint deployment all green)
- Public ingress (`https://dox-pack.<deploy-id>.nip.io`) returns **HTTP 503 Service Temporarily Unavailable**
- `kubectl get pods -n default`:
  ```
  recipe-contract-backend-dox-pa-553ee34f-98d9f7866-rfq7x    0/1   CrashLoopBackOff   13 (3m42s ago)   45m
  recipe-dox-frontend-dox-pack-4-553ee34f-5499978dd6-shm4z   1/1   Running            0                45m
  recipe-llamastack-dox-pack-41b-553ee34f-6495968d4f-96dpw   1/1   Running            0                45m
  recipe-skin-dox-pack-core-dox--553ee34f-686fd9f9fc-lrdwc   0/1   CrashLoopBackOff   13 (3m38s ago)   45m
  ```
- `kubectl logs recipe-contract-backend-...` (tail):
  ```
  File "/app/database.py", line 33, in _oracle_creator
    return oracledb.connect(...)
  File ".../oracledb/impl/base/connect_params.pyx", line 1206, in TnsnamesFileReader.read_tnsnames
  sqlalchemy.exc.DatabaseError: (oracledb.exceptions.DatabaseError) DPY-4027: no configuration directory specified
  ERROR:    Application startup failed. Exiting.
  ```
- `kubectl logs recipe-skin-dox-pack-core-...` (tail):
  ```
  2026/05/07 23:22:27 [emerg] 1#1: host not found in upstream "contract-backend-svc" in /etc/nginx/conf.d/default.conf:14
  nginx: [emerg] host not found in upstream "contract-backend-svc" in /etc/nginx/conf.d/default.conf:14
  ```
- `kubectl get deploy recipe-contract-backend-* -o json | jq`:
  ```json
  {
    "envFrom": null,
    "volumes": null,
    "volumeMounts": null,
    "has_TNS_ADMIN": false
  }
  ```
- The deployment env DOES contain a TCPS DSN:
  ```
  DB_MODE=oracle
  DB_USER=ADMIN
  DB_PASSWORD=<redacted>
  DB_DSN=tcps://aiaccel<id>.adb.us-sanjose-1.oraclecloud.com:1521/<id>_aiacceloracle26ai<id>_high.adb.oraclecloud.com
  ```

**Root cause:**

`python-oracledb` in thin mode using a TCPS DSN against Autonomous Database requires either:
1. The wallet bundle's `tnsnames.ora` + `sqlnet.ora` available in a directory pointed to by `TNS_ADMIN`, OR
2. The wallet/connection-string parameters passed explicitly to `oracledb.connect(config_dir=..., wallet_location=..., wallet_password=...)`.

The dox_pack contract-backend blueprint:
- Sets `DB_DSN=tcps://...` (correct DSN format for ADB mTLS)
- Does NOT set `TNS_ADMIN` env var
- Does NOT include an `envFrom` block referencing a wallet ConfigMap/Secret
- Does NOT include a `volumes` entry for the wallet, and therefore no `volumeMounts` either

So at pod startup, `oracledb.connect(dsn=DB_DSN, ...)` triggers the TNS-names file reader, which has no `TNS_ADMIN` and no wallet to read, and raises `DPY-4027`. SQLAlchemy wraps it and FastAPI exits during application startup. K8s restarts → CrashLoopBackOff.

**Why this was masked until now:**

BUG-031 (dox_pack DAC double-declared) prevented the dox_pack app stack from ever completing `terraform apply`. The stack always failed at the GenAI DAC creation step (400-LimitExceeded contention with the same DAC declared in the infra stack). The contract-backend blueprint deployment never ran. The wallet/TNS_ADMIN gap therefore was never observed in any prior apply.

With BUG-031 fixed (commit `215f5ee`, `genai_dac.tf:10` adds `&& local.deploy_application` gate), the app apply now goes all the way through to the blueprint deploy job, the contract-backend Deployment is created, the pod boots, and BUG-033 surfaces.

**Affected files:**

- `ai-accelerator-tf/blueprint_files.tf` — dox_pack blueprint payload likely missing wallet mount + `TNS_ADMIN` env in the contract-backend recipe component
- `ai-accelerator-tf/helm-values/` — if a dox_pack-specific helm-values file backs the contract-backend chart, wallet/envFrom config belongs there too
- ADB resource declaration (likely `app-*.tf`) — wallet bundle is currently being created/used at infra-time but no mechanism exposes it to runtime pods

**Affected packs / sizes:**

- `dox_pack/small` (us-sanjose-1, GenAI eu-frankfurt-1) — confirmed FAIL
- All dox_pack sizes — predicted FAIL (same blueprint contract-backend recipe)

**Repro:**

1. Deploy `dox_pack/small` end-to-end (infra two-stack model + app two-stack model) on a healthy OKE cluster with adequate DAC quota in `genai_region` and BUG-031 fix applied.
2. Wait for app apply SUCCESS.
3. `kubectl get pods -n default | grep contract-backend` — CrashLoopBackOff.
4. `kubectl logs <contract-backend-pod>` — `DPY-4027: no configuration directory specified`.
5. `curl https://dox-pack.<deploy-id>.nip.io/` — HTTP 503.

**Fix candidates:**

- **(a) Mount the ADB wallet via Secret + set TNS_ADMIN.** Create a Kubernetes Secret containing the wallet ZIP contents (`tnsnames.ora`, `sqlnet.ora`, `cwallet.sso`, etc.). Add `volumes:` referencing the Secret, `volumeMounts: [{ mountPath: /opt/oracle/wallet, name: adb-wallet }]`, and `env: [{ name: TNS_ADMIN, value: /opt/oracle/wallet }]` to the contract-backend deployment. This mirrors how paas_rag wires its ADB wallet (verify by reading paas_rag blueprint's contract-backend equivalent — paas_rag connects to Oracle 26ai ADB the same way and works, so the wiring exists somewhere in the codebase).
- **(b) Switch to oracledb wallet-in-DSN format.** Use `oracledb.connect(dsn=<easy-connect-with-wallet>, wallet_location=..., wallet_password=...)` with the wallet bytes pulled from a Secret at runtime. More invasive (requires changing `database.py` in the contract-backend container image).
- **(c) Use OCI Vault Service for wallet.** Init container fetches wallet from OCI Vault, writes to emptyDir volume, sets TNS_ADMIN. Heavier; better long-term posture.

Recommend **fix candidate (a)** — it matches existing patterns in the codebase (paas_rag does this), is one Terraform diff, and avoids changing the contract-backend container image.

**Stack OCIDs where this was observed:**

- App stack: `ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaaekqpwcisf3vaexlzdci5rjrg4wlbokq6mn5a2doquglq`
- App job (SUCCEEDED): `ocid1.ormjob.oc1.us-sanjose-1.amaaaaaam3augwaaehfhwycibl3y5vv2r6qo65m3wm4tkmuze3uqlaxzmk7q`
- Infra stack: `ocid1.ormstack.oc1.us-sanjose-1.amaaaaaam3augwaaeqhfumfseqm6d4gypcytxhwrnhncw23vgwuptpociirq`
- OKE cluster region: `us-sanjose-1`
- GenAI region: `eu-frankfurt-1`

**Decision for v0.0.8 release:**

This is a **pre-existing config gap**, NOT a regression introduced by the v0.0.8 schema fixes (BUG-025/026/027). It was masked by BUG-031 in all prior dox_pack runs. Disposition options:
- **Ship v0.0.8 without dox_pack:** Drop dox_pack from the v0.0.8 supported-pack matrix until BUG-033 is fixed. dox_pack was a candidate-pack anyway; cuopt/vss/paas_rag/enterprise_rag/enterprise_rag_aiq were the in-scope packs.
- **Hold for v0.0.9 with fix candidate (a):** Add wallet Secret + volumeMount + TNS_ADMIN to dox_pack blueprint. Tactical risk: medium (need to confirm wallet bundle availability at blueprint render time).

Recommend **ship v0.0.8 without dox_pack in the supported matrix**, fold fix into v0.0.9.

**Cross-references:**
- BUG-031 (Open, 2026-05-05): dox_pack DAC double-declared — **fix VALIDATED end-to-end by this run** (DAC quota fra used=8 from app stack only); BUG-033 was previously masked by BUG-031

---

### BUG-034: warehouse_pick_path schema missing `worker_node_availability_domain` override → ORM apply fast-fails

**Status:** Fixed (commit pending on `release_v0.0.8`)
**Date found:** 2026-05-08
**Found by:** Grant + track2-a10 during v0.0.8 release re-test (wpp/small Round 3, us-sanjose-1)
**Severity:** High (release-correctness blocker for `warehouse_pick_path` — apply cannot succeed via ORM wizard without manual stack-update var patch)

**TL;DR:** `warehouse_pick_path_schema.yaml` did not override the common schema's `worker_node_availability_domain: visible: false` declaration, so the ORM wizard hid the field with no default. wpp uses `worker_node_shape = "VM.GPU.A10.1"` (GPU pack), and `capacity_check.tf:271` has a precondition `local.starter_pack_config.worker_node_shape == "none" || var.worker_node_availability_domain != ""` — empty AD value fast-fails apply in 1m17s with `Error: Resource precondition failed`. End users following the wizard cannot deploy wpp without a runtime workaround.

**Symptoms:**

- ORM wpp INFRA apply FAILED at 1m17s elapsed (way too fast for real apply — indicates precondition/var validation error)
- Job log error excerpt:
  ```
  Error: Resource precondition failed
    on capacity_check.tf line 271, in resource "terraform_data" "capacity_validated":
   271:       condition     = local.starter_pack_config.worker_node_shape == "none" || var.worker_node_availability_domain != ""
      ├────────────────
      │ local.starter_pack_config.worker_node_shape is "VM.GPU.A10.1"
      │ var.worker_node_availability_domain is ""
  worker_node_availability_domain is required for GPU starter packs (cuopt,
  vss, enterprise_rag). It is optional for paas_rag.
  ```
- ORM wizard never showed the AD field for the user to fill in
- Comparing `cuopt_schema.yaml` / `vss_schema.yaml` / `enterprise_rag_schema.yaml` / `enterprise_rag_aiq_schema.yaml`: all four override `worker_node_availability_domain` with `visible: true, required: true` and add it to the appropriate `variableGroup`. Only `warehouse_pick_path_schema.yaml` was missing the override.

**Root cause:**

When the warehouse_pick_path pack was added, the schema author forgot to mirror the per-pack override pattern from cuopt/vss for the `worker_node_availability_domain` field. The common schema declares the variable as `visible: false` (defaulting to "system uses this internally, no user input"), and each GPU pack must explicitly override it to `visible: true, required: true` in its own schema file. Without the override, the ORM wizard hides the field, the variable lands as `""`, and the GPU-precondition gate triggers.

**Affected files:**

- `ai-accelerator-tf/schemas/warehouse_pick_path_schema.yaml` — missing the override block + `variableGroups` entry
- `ai-accelerator-tf/capacity_check.tf` — error message at line 272 omits `warehouse_pick_path` and `enterprise_rag_aiq` from the GPU pack list (cosmetic but misleading)

**Affected packs / sizes:**

- `warehouse_pick_path/small` (any region) — confirmed FAIL via ORM wizard (track2-a10 fast-fail at 15:18:25Z)
- All wpp sizes — predicted FAIL (single GPU shape across the pack)

**Repro:**

1. Download `release_test_matrix/v0.0.8_warehouse_pick_path.zip` (pre-fix).
2. Create new ORM stack from zip in any region with A10 capacity.
3. Fill the wizard's required fields (does NOT include AD — field is hidden).
4. Run apply.
5. Apply FAILS in ~1m17s with `Error: Resource precondition failed` on `worker_node_availability_domain != ""`.

**Fix:**

1. **Schema override** — `ai-accelerator-tf/schemas/warehouse_pick_path_schema.yaml`:
   - Add `worker_node_availability_domain` to `variableGroups[1].variables` ("Deployment Configuration").
   - Add `variables.worker_node_availability_domain` block with `title`, `description`, `required: true`, `visible: true` (mirroring cuopt/vss pattern, with A10-specific AD-discovery instructions).
2. **Capacity check error message** — `ai-accelerator-tf/capacity_check.tf:272`:
   - Update error message from `"required for GPU starter packs (cuopt, vss, enterprise_rag). It is optional for paas_rag."` to `"required for GPU starter packs (cuopt, vss, enterprise_rag, enterprise_rag_aiq, warehouse_pick_path). It is optional for CPU-only packs (paas_rag, dox_pack)."` — accurate listing of which packs the precondition gates.

**Verification:**

- `terraform fmt -check -diff -recursive` ✓ clean
- `terraform validate` ✓ Success
- `terraform test -filter=tests/starter_pack_warehouse_pick_path.tftest.hcl` ✓ pass
- `pytest ai-accelerator-tf/schemas/tests/ -v` ✓ 132 passed
- Schema regeneration (`python create_final_schema.py -c warehouse_pick_path`) ✓ produces `schema.yaml` with the new field visible
- Zip rebuilt at `release_test_matrix/v0.0.8_warehouse_pick_path.zip` (176889 bytes, 2026-05-08T18:30:18Z) and re-uploaded to GH release v0.0.8

**Workaround validation (track 2):**

Before the schema fix landed, track2-a10 patched the failed wpp INFRA stack via `oci resource-manager stack update --variables` to add `worker_node_availability_domain = TrcQ:US-SANJOSE-1-AD-1`, then re-applied. The patched apply ran cleanly and SUCCEEDED at 16:47:48Z (~16m), proving the underlying TF code is correct — only the schema was wrong. End-users without OCI CLI access could not have applied this workaround.

**Cross-references:**

- BUG-027 (Fixed, 2026-05-04): same shape — cuopt frontend creds visibility override missing, fixed by commit `81cc0c9`. BUG-034 is the wpp-pack equivalent of the same per-pack-override-omission class of bug.
