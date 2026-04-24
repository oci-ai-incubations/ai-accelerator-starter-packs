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
| Fixed (pending) | BUG-009 | Stale nim-llm taint blocks pod scheduling after two-stack pack switch | High | 2026-04-07 |
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
| Fixed | BUG-021 | agent-browser --headed silently ignored on existing session (release-testing blocker) | High | 2026-04-22 |
| Fixed | BUG-022 | /checking-capacity skips vcn-count quota (low-priority assumption invalid in shared tenancy) | High | 2026-04-22 |
| Fixed | BUG-023 | Rapid JS eval on ORM Configure Variables wizard crashes agent-browser iframe, loses session | High | 2026-04-22 |
| Open | BUG-024 | paas_rag /vector_stores/{id}/file_batches rejects file when embedding dim mismatches (1024 vs 1536) | Low | 2026-04-23 |
| Fixed | BUG-025 | agent-browser browser_click by @ref fails on React onClick handlers (CDP native click ignored) | Medium | 2026-04-23 |
| Open (Environmental — OCI-side, not release-blocking; file for OCI support escalation) | BUG-026 | enterprise_rag ingestor/rag-server cannot connect to Oracle 26ai ADB in aiincubations-uk-london-1 — DPY-6000 listener refused | Critical | 2026-04-23 |
| Open | BUG-029 | enterprise_rag v2.5.0 NIMCache pods missing GPU toleration — blocked on scheduling (RELEASE BLOCKER for v0.0.7 helm v2.5.0 path) | Critical | 2026-04-23 |
| Fixed | BUG-027 | testing-pack skill doesn't carve out destroy-via-CLI as a permitted fallback | Low | 2026-04-23 |

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

**Status:** Fixed (pending confirmation on v0.0.7 rebased APPLY)
**Date found:** 2026-04-07
**Date fixed:** 2026-04-07 (partial — destroy provisioner added but has chicken-and-egg bug); 2026-04-23 architectural fix via PR #101 rebase (pending runtime confirmation)
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

**Recurrences:**
- 2026-04-23 during v0.0.7 rebase retest — stale `workload=nim-llm:NoSchedule` taint persisted on node 10.0.106.114 after enterprise_rag app destroy on 2026-04-23 in uk-london-1. Track1-gpu4 detected during pre-reapply verification and manually removed with `kubectl taint nodes 10.0.106.114 workload=nim-llm:NoSchedule-`. Confirms the destroy-provisioner taint cleanup is still not fully reliable.
- 2026-04-23 post-rebase — the 2026-04-23 recurrence above was a **legacy leftover on preserved infra from the pre-rebase v0.0.7 deploy**, not a fresh occurrence of the root cause. The rebased v0.0.7 code (release_v0.0.7 after PR #101 merge) no longer applies the `workload=nim-llm:NoSchedule` taint at all — see Fix section below. No new recurrence is expected once the rebased APPLY runs on a cleanly-tainted node pool.

**Fix:** Eliminated architecturally by PR #101 (helm chart v2.5.0 + NIM Operator) in release_v0.0.7 rebase. The old `workload=nim-llm:NoSchedule` taint is no longer applied; NIM Operator uses native `nvidia.com/gpu` tolerations on NIMCache/NIMService CRs (patched in via terraform_data in commit 2b6e8f9). The 2026-04-23 recurrence was a legacy leftover on preserved infra from the pre-rebase v0.0.7 deploy, not a fresh occurrence of the root cause. Will be closed after track1's rebased APPLY succeeds and Phase 6 confirms no new taints appear.

Code evidence (`ai-accelerator-tf/helm.tf:460-462`):
```
# NIM Operator handles GPU node scheduling via NIMCache/NIMService CRs.
# The workload=nim-llm taint is no longer applied — the nvidia.com/gpu taint
# from GPU Feature Discovery is sufficient, and NIMCache CRs include tolerations.
```
Git diff confirms the `kubectl label` / `kubectl taint` / `# Clean up taints on app stack destroy` lines are all REMOVED in the rebased code. Commits: PR #101 bfa54d1 (v2.5.0 chart + NIM Operator), 2b6e8f9 (NIM Operator post-deploy patches including NIMCache tolerations).

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

**Recurrences:**
- 2026-04-23 during v0.0.7 Track 3 paas_rag/small testing — blocked Phase 7 app destroy after PA-5 uploaded test doc to `paas-rag-oyVDQe-bucket`. Unblocked by manual bucket empty via OCI CLI. Failed destroy job: `ocid1.ormjob.oc1.iad.amaaaaaam3augwaa36amwh2exfz6a5qmudwfisslfggi3vtrklfl5bdqx22a` (us-ashburn-1). Confirms the bug is not yet fixed at the code level — workaround still required on every paas_rag run that exercises file upload.

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

---

### BUG-021: agent-browser --headed silently ignored on existing session (release-testing blocker)

**Status:** Open
**Date found:** 2026-04-22
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by track2-a10 after ~2.5h stuck in headless mode; escalated by team-lead for logging)
**Severity:** High

**Symptoms:**
During `/testing-pack` Phase 3 (ORM UI schema validation), the agent invokes `agent-browser` with a `--session <name>` flag to drive a visible browser for the user to complete IDCS sign-in. If a daemon is already running for the named session (e.g., left over from an earlier call, or created internally by the skill before headed mode was requested), subsequent commands that pass `--headed` (or an equivalent headful flag) are silently accepted and silently ignored. The browser stays headless. No warning, no error, no user-visible window. From the agent's perspective the wizard is "open"; from the user's perspective there is simply no browser to sign into. This looks identical to a stuck IDCS login or expired SSO cookies.

During v0.0.7 release testing this cost track2-a10 roughly 2.5 hours of apparent "sign-in is stuck" before being diagnosed. Track1-gpu4 and track3-cpu had the same symptom pattern in the same session. Recovery required `agent-browser --session <name> close`, then re-launching with both the `--headed` flag AND the `AGENT_BROWSER_HEADED=true` environment variable explicitly set.

**Root cause:**
agent-browser's per-session daemon latches its headless/headful mode from the first command that starts the daemon. Subsequent commands that pass a conflicting mode flag to an already-running daemon are silently ignored — the existing daemon process keeps its original mode. There is no validation that warns when the requested mode differs from the current session mode.

`/testing-pack` Phase 3a ("Authenticate to OCI Console") relies on a visible browser window for the user to complete IDCS sign-in, but the skill does not:
1. Explicitly force headful mode via both flag AND env var on the *first* command that creates the session, OR
2. Detect that the current session is headless-but-should-be-headed and auto-recover.

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — Phase 3a does not force headful and does not document the close+re-launch recovery
- `.claude/skills/testing-pack/references/orm-browser-nav.md` (if it contains the launch command template) — same gap
- agent-browser CLI source (external to this repo) — the real fix for "silently ignored" is upstream: warn or fail when an existing-daemon mode doesn't match the newly-requested mode

**Workaround:**
When the user reports "I only see N browser windows, not 3" or "sign-in is not loading" during Phase 3:
1. Run `agent-browser --session <name> close` to kill the stale headless daemon.
2. Relaunch with BOTH `--headed` flag AND `AGENT_BROWSER_HEADED=true` env var:
   ```bash
   AGENT_BROWSER_HEADED=true agent-browser --headed --session <name> open "https://cloud.oracle.com"
   ```
3. Verify a real OS window opens before proceeding.

**Resolution:**
Fixed by env-var-based session management (`AGENT_BROWSER_HEADED=1` + `AGENT_BROWSER_SESSION`) in `/testing-pack` CRITICAL RULE #5 + `--session-name` sweep across reference files and test-coverage ui-tests. Spec: `docs/superpowers/specs/2026-04-23-release-testing-skill-hardening-design.md`.

**Prior proposed-fix notes (for reference only):** `/testing-pack` Phase 3a should:
- Require both `--headed` and `AGENT_BROWSER_HEADED=true` on the very first `open` command that starts the session (before any headless helper commands run under the same session name).
- Include a preflight "headless-detect" snippet — e.g., query the daemon for its current mode via `browser_get_config` and, if the session exists and is headless, auto-run `close` + relaunch with the headful combination.
- Document this close+relaunch recovery in the skill so future testing runs don't lose hours to the same symptom.

Upstream (agent-browser) ideally: detect mode mismatch and either (a) error loudly so the caller knows the flag was rejected, or (b) tear down the mismatched daemon and relaunch automatically.

**Reference:** Discovered during v0.0.7 release testing (2026-04-22). Track1-gpu4 (session `track1-1776884811`), track2-a10 (session `track2-1776884817`), and track3-cpu were all affected by the same underlying behavior. Team-lead escalated via monitor after track2-a10 diagnosed and recovered via explicit close+relaunch.

---

### BUG-022: /checking-capacity skips vcn-count quota (low-priority assumption invalid in shared tenancy)

**Status:** Open
**Date found:** 2026-04-22
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by team-lead after track3-cpu paas_rag infra apply was blocked in us-ashburn-1)
**Severity:** High

**Symptoms:**
During v0.0.7 release testing, track3-cpu ran `/checking-capacity paas_rag small` for us-ashburn-1 and the skill reported capacity OK. Track3 proceeded to apply the infra stack. The apply failed after ~45 seconds with `LimitExceeded`: the `vcn-count` service limit in us-ashburn-1 was 51/51 — the tenancy had already hit the hard cap on VCNs.

The /checking-capacity skill manifest explicitly classifies `vcn-count` as a "high limit, low-priority" quota and skips it by default in the normal run — only "deep" mode inspects it. In the `aiincubations` tenancy (shared by ~50 engineers), this assumption is wrong: stale OKE quick-dev VCNs from other engineers had consumed all 51 slots in us-ashburn-1, so the "it's a high limit, usually fine" heuristic masked a real blocker.

**Root cause:**
`/checking-capacity` has a resource manifest that classifies each OCI quota as priority-check (always audited) vs low-priority (skipped unless `--deep`). `vcn-count` was placed in the low-priority bucket based on the reasonable assumption that per-region VCN limits (default 10, raised to 51 here) are almost never hit in a single-engineer compartment. This assumption does not hold for shared tenancies where orphaned VCNs from unrelated work accumulate across engineers.

The skill therefore reports "capacity OK" when in fact the stack can't create its VCN at all, and the failure doesn't show up until `terraform apply` 30–60 seconds in.

**Affected files:**
- `.claude/skills/checking-capacity/SKILL.md` (or wherever the resource manifest lives — look for the list that marks vcn-count as "skip" or "low-priority")
- See also BUG-011 (similar theme: /checking-capacity only checks GPU and misses FSS/ADB/other quotas) — BUG-022 is a narrower, concrete instance of the same class of problem

**Workaround:**
Before running `terraform apply` on an infra stack in a shared tenancy, manually check VCN usage:
```bash
export OCI_CLI_PROFILE=<profile>
oci limits value list --service-name compute --region <region> \
  --compartment-id <tenancy-ocid> --query 'data[?"name"==`vcn-count`]'
oci network vcn list --compartment-id <tenancy-ocid> --region <region> \
  --query 'data[].{name:"display-name",created:"time-created",lifecycle:"lifecycle-state"}' \
  --output table --all
```
If the count is at/near the limit, identify stale VCNs (old `quick-dev` or `test-*` VCNs from other engineers) and coordinate deletion before proceeding.

During v0.0.7 testing, this was unblocked manually by identifying and deleting stale Grant-owned OKE VCNs in us-ashburn-1.

**Resolution:**
Fixed by reclassifying both `vcn-count` AND `cluster-count` in `/checking-capacity/SKILL.md` as "always check" (not low-priority). Both quotas have identical "high limit, low-priority" classification and identical shared-tenancy failure mode. Spec: `docs/superpowers/specs/2026-04-23-release-testing-skill-hardening-design.md`.

**Prior proposed-fix notes (for reference only):**
1. Remove the "low-priority / skip by default" classification for `vcn-count` in the `/checking-capacity` resource manifest. The cost of one extra API call is trivial; the cost of a silent ~45-second apply failure is not.
2. Add a shared-tenancy smoke check: when the `/checking-capacity` run detects that `vcn-count` usage is >80% of the limit, list the top VCN-consuming compartments (or oldest VCNs) so the user can see candidates to ask about stale ones.
3. Cross-reference BUG-011's broader fix (audit ALL quota types a starter pack actually provisions — FSS, ADB, customer secret keys, VCN, subnets, NAT gateways, etc.) and include `vcn-count` in whatever comprehensive manifest results from that work.

**Reference:** Discovered during v0.0.7 release testing (2026-04-22). Track3-cpu (paas_rag/small) in us-ashburn-1. Unblocked manually; BUG-022 captures the skill gap so future runs fail fast (or succeed reliably) instead of hitting a 45-second apply error.

---

### BUG-023: Rapid JS evaluate on ORM Configure Variables wizard crashes agent-browser iframe, loses session

**Status:** Open
**Date found:** 2026-04-22
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by track2-a10; escalated by team-lead)
**Severity:** High

**Symptoms:**
During `/testing-pack` Phase 3 (or Phase 5) on the ORM Edit Stack wizard Step 2 "Configure Variables" screen, the agent executes a bulk `agent-browser evaluate()` call (the browser automation's JS-in-page primitive) to toggle multiple checkboxes / fill multiple fields in a single JavaScript block. The wizard iframe (the Resource Manager Create/Edit stack wizard is rendered inside an iframe on the OCI Console page) crashes as a result: the browser tab returns to `about:blank`, all OCI session cookies are lost, and every piece of wizard state (uploaded zip, filled variables, stack name) is discarded. The agent cannot recover the in-flight wizard — it must re-authenticate, re-open the stack, re-upload the zip, and re-fill every variable from scratch.

Track 2 hit this mid-Phase 3 after successfully loading Step 2 and then issuing a rapid multi-field `evaluate()` call. Recovery cost was significant: full re-auth (IDCS sign-in + MFA), re-upload of v0.0.7_vss.zip, and full re-entry of every Step 2 variable.

**Root cause:**
The ORM Edit/Create Stack wizard is a nested iframe inside cloud.oracle.com. Rapid sequential DOM mutations from a single-shot `evaluate()` call — especially when they trigger React/Redux state updates across many controlled components at once — can crash the iframe's JavaScript context. When the iframe crashes, the outer page navigates to `about:blank` and OCI session cookies stored in the iframe's origin are lost. There is no crash signal returned to agent-browser; the `evaluate()` call simply returns and subsequent snapshots show an empty page.

`/testing-pack` Phase 3 and Phase 5 do not currently enforce single-field interactions — there's no guardrail against rapid bulk `evaluate()`, and no post-call safety check that verifies the iframe is still mounted before the next step.

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — Phase 3c/3d and Phase 4a/5a describe Step 2 variable filling; no rule against bulk `evaluate()` calls
- `.claude/skills/testing-pack/references/orm-browser-nav.md` (if it contains wizard interaction patterns) — same gap
- Upstream agent-browser — could add iframe-crash detection: after `evaluate()` or `browser_fill_form`, check whether the iframe is still present in the DOM and surface a clear error if it vanished

**Workaround:**
Avoid bulk JS `evaluate()` on the Configure Variables wizard. Instead:
1. Use single-field `browser_fill_form` calls — one field per call.
2. For checkboxes, use individual `browser_click` calls rather than an `evaluate()` that toggles many at once.
3. Between interactions, take a snapshot or call `browser_verify_element_visible` on a stable wizard element to confirm the iframe is still alive.
4. If the tab ever returns to `about:blank`, treat it as a full wizard reset: re-auth, re-open stack, re-upload zip, re-fill everything.

**Resolution:**
Fixed by adding CRITICAL RULE #6 to `/testing-pack/SKILL.md` banning bulk `agent-browser evaluate()` on ORM wizard form fields; Phase 4a/5a instructions now point to Rule #6; Error Handling table has an `about:blank mid-wizard` recovery row. Spec: `docs/superpowers/specs/2026-04-23-release-testing-skill-hardening-design.md`.

**Prior proposed-fix notes (for reference only):**
1. `/testing-pack` Phase 3/5 should document a rule: use one `browser_fill_form` / `browser_click` call per field, never a multi-field `evaluate()` loop on the Configure Variables page.
2. Add a post-interaction safety check: after every form interaction in the ORM wizard, snapshot and verify the iframe's stable selector (e.g., the "Next" button) is still present. If missing, treat as a crash and trigger full re-auth + re-entry.
3. Document in the skill: if agent-browser's tab URL ever becomes `about:blank` mid-wizard, the recovery is NOT "refresh and continue" — it's a full restart from Phase 3a authentication.
4. Upstream (agent-browser): add iframe-crash detection and a clear error return.

**Reference:** Discovered during v0.0.7 release testing (2026-04-22). Track2-a10 (vss/poc) in us-sanjose-1. Wizard state lost; recovery required full re-auth via SSO and re-upload. Bug total this release: 3 (BUG-021 agent-browser headed flag, BUG-022 /checking-capacity vcn-count, BUG-023 wizard iframe crash on bulk `evaluate()`).

---

### BUG-024: paas_rag /vector_stores/{id}/file_batches rejects file when embedding dim mismatches (1024 vs 1536)

**Status:** Open
**Date found:** 2026-04-23
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by track3-cpu in Phase 6 API test PA-6; escalated by team-lead for logging)
**Severity:** Low

**Symptoms:**
During Phase 6 API testing of `paas_rag` (test PA-6, file ingestion into a vector store), track3 created a vector store via `POST /v1/vector_stores` with the default embedding configuration, which produces 1024-dim embeddings. On the subsequent `POST /v1/vector_stores/{id}/file_batches` call to attach a file, the API returned a dimension-mismatch error because the file's content was processed with an embedder that produces 1536-dim embeddings (the upload path inferred a different embedding model than the vector store was created with).

Retry with the `/vector_stores` create call setting an explicit `embedding_dim=1536` (matching the file-path inference) succeeded. Total impact: one retry loop, a few minutes of debugging. No data loss; no deployment impact.

**Root cause:**
The paas_rag document ingestion pipeline (backed by LlamaStack) uses different default embedding models in two places:
1. The vector-store creation path defaults to a 1024-dim embedder.
2. The file-batches attach path auto-detects/selects an embedder per file, and for this input it chose a 1536-dim model.

There is no reconciliation between "what the vector store was indexed with" and "what the incoming file's embedder produces," so the mismatch surfaces as a hard API error at attach time instead of being caught at vector-store creation (when the user can still pick the right model).

**Affected surface (not affected files in this repo — this is an API/LlamaStack UX bug exposed through paas_rag):**
- paas_rag `POST /v1/vector_stores` — should surface `embedding_dim` (and/or `embedding_model`) as an explicit, documented, required-in-practice field
- paas_rag `POST /v1/vector_stores/{id}/file_batches` — could either (a) auto-detect mismatch and re-index with the file's dim, or (b) return a much clearer error pointing the user at the dim parameter

**Workaround:**
When creating a vector store for paas_rag document ingestion, explicitly set the embedding dim to match the model you'll use at file-attach time. For the default paas_rag file ingestion path during release testing, that is `embedding_dim=1536`. If unsure, create the vector store after uploading at least one file so the correct dim is known, or retry creation with `embedding_dim=1536` if the 1024 default fails.

**Resolution:**
Pending. Proposed fix options (documented in this entry so whoever picks it up has choices):
1. `POST /v1/vector_stores` should expose `embedding_dim` (or better, `embedding_model`) as an explicit, documented field — validation rejects creation if not set, or at minimum warns that the default may not match typical file inputs.
2. `POST /v1/vector_stores/{id}/file_batches` should auto-detect the dim mismatch and either (a) re-create the vector store with the file's dim (if empty), or (b) re-index the incoming file with the vector store's dim.
3. Minimum viable fix: improve the error message on dim mismatch to name the two dims and point the user at the fix ("vector store uses 1024, file produces 1536; recreate vector store with embedding_dim=1536").

**Reference:** Discovered during v0.0.7 release testing (2026-04-23). Track3-cpu (paas_rag/small) in us-ashburn-1, Phase 6 API test PA-6. Not a release blocker — paas_rag v0.0.7 testing proceeded after retry with explicit `embedding_dim=1536`. Bug total this release: 4 (BUG-021, BUG-022, BUG-023, BUG-024).

---

### BUG-025: agent-browser browser_click by @ref fails on React onClick handlers (CDP native click ignored)

**Status:** Open
**Date found:** 2026-04-23
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by track3-cpu in Phase 6 UI tests; escalated by team-lead)
**Severity:** Medium

**Symptoms:**
During `/testing-pack` Phase 6 UI tests on track3 (and likely applicable to any track driving the OCI Console or other React-heavy pages via agent-browser), `browser_click` calls that target elements by snapshot `@ref` did not fire the page's React `onClick` handler. The click appears to be dispatched at the DOM level (no agent-browser error, element briefly gets focus), but nothing happens — form state doesn't update, no navigation, no API request. Multiple button/link interactions had to be repeated or re-approached.

**Workaround that works:** use `browser_evaluate` with either:
- `element.click()` (HTMLElement.click() invokes React's synthetic event path), or
- `element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }))` (the explicit synthetic dispatch that matches what React is listening for).

Both workarounds reliably trigger the React handler where `browser_click @ref` silently does not.

**Root cause:**
agent-browser's `browser_click` by `@ref` appears to dispatch a native CDP-level click (via `Input.dispatchMouseEvent` or similar). React (including the OCI Console and most modern React apps) installs its event listeners on the root via synthetic event delegation, not on individual DOM nodes. Depending on how the synthetic listener is wired — and whether React detects the event as "trusted" — a CDP native click can miss the React event path entirely.

There is no error from agent-browser; the call reports success. The symptom is a silent test flake: the UI doesn't change, subsequent assertions fail, the tester doesn't know which interaction didn't land.

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — Phase 6 UI test patterns for each pack; should prefer `browser_evaluate`-based click for React pages
- `.claude/skills/*-test-coverage/` — pack-specific test coverage specs that use `browser_click` in UI phases may need updating
- Upstream agent-browser — click adapter should route through the synthetic-event-compatible path when a React (or other framework with synthetic events) is detected

**Workaround:**
For any click in Phase 6 UI tests on React-heavy pages (OCI Console, starter-pack frontends if they're React-based):
```
// Preferred: click via the element's native .click() method (triggers React)
agent-browser --session <name> evaluate --stdin <<'EOF'
document.querySelector('<selector>').click();
EOF

// Fallback: explicit synthetic dispatch
agent-browser --session <name> evaluate --stdin <<'EOF'
var el = document.querySelector('<selector>');
el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
EOF
```
Prefer `.click()` because it's one line and React recognizes it reliably. Use the explicit dispatch only when the target isn't an HTMLElement or `.click()` is unavailable (e.g., SVG, some custom elements).

Caveat vs. BUG-023: BUG-023 warns against *bulk* JS evaluate() on the ORM Configure Variables wizard because rapid multi-mutation crashes the iframe. BUG-025's workaround is a *single-target* click — not a multi-field bulk operation — so the BUG-023 guidance (avoid bulk eval) does NOT forbid this pattern. One click via evaluate() per button is fine and recommended.

**Resolution:**
Fixed by adding Phase 6c-3 React click pattern subsection to `/testing-pack/SKILL.md` + rewriting all 65 `click @<ref>` calls across the 4 non-stub `*-test-coverage/ui-tests.md` files (paas-rag 27, enterprise-rag 17, vss 10, cuopt 11) to use `evaluate` + `.click()`. wpp-test-coverage is a TODO stub with no changes. Upstream issue against `vercel-labs/agent-browser` is a separate follow-up. Spec: `docs/superpowers/specs/2026-04-23-release-testing-skill-hardening-design.md`.

**Prior proposed-fix notes (for reference only):**
1. `/testing-pack` Phase 6 UI tests (and the per-pack test-coverage skills) should use the `browser_evaluate` `.click()` pattern as PRIMARY for React-heavy pages, with `browser_click @ref` as a fallback rather than the default.
2. Document the pattern in agent-browser README / troubleshooting section.
3. Upstream agent-browser: detect React on the page (via `window.React`, React DevTools hook, or `data-reactroot` / `__reactFiber$`) and, when present, dispatch clicks via the synthetic event path (equivalent to calling `.click()` or firing a bubbling MouseEvent) instead of — or in addition to — the raw CDP click.

**Reference:** Discovered during v0.0.7 release testing (2026-04-23). Track3-cpu (paas_rag/small) in us-ashburn-1, Phase 6 UI tests — multiple button clicks silently failed via `browser_click @ref`, succeeded via `browser_evaluate` + `.click()`. OCI Console is React-based, so this is likely to recur across every track's Phase 3/5 ORM interactions as well — the reason Tracks 1 and 2 haven't hit it yet is that their Phase 3/5 mostly used `browser_fill_form` (which goes through a different input adapter that React handles correctly via input events) rather than `browser_click @ref`. Bug total this release: 5 (BUG-021, BUG-022, BUG-023, BUG-025 skill gaps; BUG-024 product UX).

### BUG-026: enterprise_rag ingestor/rag-server cannot connect to Oracle 26ai ADB — DPY-6000 listener refused

**Status:** Open — **Reclassified as Environmental / OCI-side (not release-blocking)**. File for OCI support escalation.
**Date found:** 2026-04-23
**Found by:** track1-gpu4 during v0.0.7 release testing (enterprise_rag/small on BM.GPU4.8, uk-london-1)
**Severity:** Critical (but NOT a release code blocker — see reclassification below)

**Symptoms:**
- Frontend HTTP endpoint `GET /api/health?check_dependencies=true` returns HTTP 500 "Internal Server Error".
- Ingestor-server pod logs show:
  ```
  nvidia_rag.rag_server.response_generator.APIError: Oracle database is unavailable at tcps://aiaccelOk6ptj.adb.uk-london-1.oraclecloud.com:1521/g2ec18f1706c18c_aiacceloracle26aiok6ptj_high.adb.oraclecloud.com. Please verify Oracle is running and credentials are correct.
  ERROR:nvidia_rag.utils.vdb.oracle.oracle_vdb:Failed to connect to Oracle at tcps://...: DPY-6005: cannot connect to database
  DPY-6000: Listener refused connection. (Similar to ORA-12506)
  ```
- Direct test from within pod using `python3 + oracledb` also fails with DPY-6000 using both:
  - Easy-connect DSN form (`tcps://host:1521/service_name`)
  - Long-form `(description=(address=...)(connect_data=...))`
- ADB CLI reports state=AVAILABLE, open-mode=READ_WRITE, private endpoint on the app stack's autonomous_db_subnet. No paused state.
- Deleting + restarting the ingestor pod does not resolve — fresh pod hits the same error.
- Hostname resolves correctly inside the pod (`getent hosts` returns the private IP 10.0.2.27).

**Root cause (provisional):**
Unknown — needs further debugging. Possibilities:
1. ADB private-endpoint listener has not registered the service name despite reporting AVAILABLE (stale listener state after the two-stack preserve-infra apply cycle).
2. Pod network path to the ADB private endpoint is bounced but the listener declines registration — possibly a wallet/TLS mismatch where the ADB requires the pod to present a wallet ssl-cert that the Helm chart doesn't inject when deploying against an "existing" ADB discovered via `data` source rather than a freshly provisioned `resource`.
3. Possible subnet/NSG/SL mismatch — but hostname resolution working suggests DNS is OK, and reaching the listener suggests TCP reaches; only the listener's service registration path is broken.

**Affected files (to investigate):**
- `ai-accelerator-tf/26ai.tf` — how ADB is provisioned vs how the Helm chart is pointed at it.
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — Oracle vector-store connection config.
- `ai-accelerator-tf/secrets.tf` / `oci-config-secret` — wallet handling for existing-ADB path.
- `ai-accelerator-tf/kubernetes.tf` (data.oracle_db_adb_database or similar) — existing-ADB data lookup may return stale connection strings.

**Workaround:**
None yet. The pod is stuck in a state where every API call hits the ADB and returns 500. Healthcheck / generate / collection APIs are all unusable. The infra layer (cluster, pods, GPUs) is fine — only the ADB connection is broken.

**Impact on release testing:**
- Round 1 (enterprise_rag/small, v0.0.7) Phase 6 API tests all blocked at EA-1.
- Frontend UI tests would also fail — the first action on the UI (loading collections) hits `/api/collections` which calls the same vector-store op.
- This blocks Round 2 too, because Round 2 reuses the same infra (cluster + ADB subnet) with a different app Helm release.

**Next debugging step:**
Compare ORACLE_CS service name (from pod env) against the list of registered services on the ADB listener. Check if the ADB was re-provisioned during the v0.0.7 app apply (state.tfstate "created" timestamp is 2026-04-23T01:27:02Z, which IS during the v0.0.7 app apply — so fresh ADB, ~17h old). Try `lsnrctl status` equivalent from OCI side.

**2026-04-23 confirmation — REPRODUCES cleanly under helm v2.5.0 + NIM Operator 3.1.0 + fresh ADB + v0.0.6 rag-retrieval-oci image:**

Reproduces cleanly under helm chart v2.5.0 + NIM Operator 3.1.0 + fresh ADB `aiaccelBVx8Nw` + v0.0.6 rag-retrieval-oci image. Verified via direct `python3 oracledb.connect()` from ingestor-server pod on 2026-04-23 (at 21:26Z, during Track 1's rebased v0.0.7 app apply). Rules out chart regression, rag-server image regression, AND ADB provisioning race.

Test details:
- DSN: `tcps://aiaccelBVx8Nw.adb.uk-london-1.oraclecloud.com:1521/g2ec18f1706c18c_aiacceloracle26aibvx8nw_high.adb.oraclecloud.com` (same connection-string format, same `_high` service-name suffix as the pre-rebase test)
- Error: identical `DPY-6005 / DPY-6000 / ORA-12506` "Listener refused connection" — definitive reproduction
- ADB state: AVAILABLE / READ_WRITE / workload=UNKNOWN_ENUM_VALUE (the 26ai lifecycle-state enum the OCI CLI doesn't yet recognize) / created 2026-04-23T20:36:30Z (fresh on this rebased apply — ~50 min old at test time)
- Cluster-side image tags verified at test time: `rag-server:v0.0.6`, `ingestor-server:v0.0.6`, `k8s-nim-operator 3.1.0` — all correct per PR #101 / SOFTWARE_VERSIONS.md
- NIM Operator present, NIMCache CRs for 7 models created, nim-llm-cache-pod Running (nemotron-3-super-120b-a12b:1.8.0) under BUG-029 manual-workaround toleration fix

**Cross-track evidence (Track 3 / paas_rag / us-ashburn-1):**

paas_rag (Track 3) connected successfully to a 26ai ADB in `us-ashburn-1` using identical `oracledb` thin-mode connection semantics, same service-name suffix convention. This is strong supporting evidence that **26ai globally is not broken**; the issue is scoped to the aiincubations tenancy's `uk-london-1` 26ai fleet specifically. Phase 6 API tests on paas_rag (PA-1 through PA-11) all passed, including vector-store creation and file ingestion — all of which exercise the Python `oracledb` client path that BUG-026 fails on in uk-london-1.

**Hypotheses ruled out by this retest:**
- **Chart regression:** ruled out. v2.5.0 chart fails the same way v2.3.x did.
- **rag-server image regression:** ruled out. v0.0.6 image tags confirmed running, error still reproduces.
- **ADB provisioning race:** ruled out. A completely fresh ADB (50 min old at test time) still refuses the listener.
- **PR #101 nv-ingest DNS fix (commit 28243ba) as a BUG-026 fix path:** ruled out — the DNS fix addresses a different symptom class (nv-ingest resolving the Corrino API DNS); BUG-026 is an Oracle listener-level refusal, not a DNS-level failure (the pod resolves the ADB hostname correctly).

**Remaining hypothesis (narrowed to exactly one):**
- **OCI tenancy+region specific 26ai listener issue in aiincubations-uk-london-1.** All client-side and chart-side hypotheses ruled out. The ADB reports AVAILABLE but its listener rejects incoming service-name-registered connections. paas_rag in us-ashburn-1 proves the same client code works elsewhere. This is an OCI ADB / 26ai fleet issue scoped to one region/tenancy combination, upstream of anything release code can fix.

**What was NOT re-verified in the post-SUCCEEDED / pre-destroy window (21:49:51Z → 21:53:51Z):**
- `GET /api/health?check_dependencies=true` via frontend/ingress — would have returned 500 regardless since the direct `oracledb` test already proved the ADB is unreachable upstream.
- End-to-end ingestion or chat API smoke tests — blocked by the same ADB issue.

Not re-testing these is fine: the direct `oracledb.connect()` call is a stricter test than the API endpoints (both the API and the direct test share the same failure mode, and proving the underlying connection fails is sufficient).

**Reclassification (team-lead, 2026-04-23):**
BUG-026 is **Environmental / OCI-side (not release-blocking)**. All release code paths are correct; the failure is entirely in the OCI ADB listener layer in aiincubations-uk-london-1. File for OCI support escalation against the ADB `aiaccelBVx8Nw` (or any fresh 26ai ADB provisioned in this tenancy/region).

**Release implications:**
- Release **can ship** — enterprise_rag code is validated against v2.5.0 + NIM Operator + v0.0.6 images; the Terraform paths for ADB provisioning, Helm deployment, and client-side connection config are all correct.
- uk-london-1 enterprise_rag deployments will fail at first ADB connection attempt until OCI support resolves the regional listener issue.
- Other regions (e.g., us-ashburn-1 where Track 3 paas_rag succeeded) are unaffected.
- Separate from BUG-029 (helm chart v2.5.0 toleration deadlock), which IS a release-code blocker.

**Next action:** Open an OCI support ticket referencing ADB `aiaccelBVx8Nw` in uk-london-1 (aiincubations tenancy), include the `DPY-6005 / DPY-6000 / ORA-12506` error pattern, and request listener-side introspection (equivalent to `lsnrctl services`) on the ADB. Cross-reference Track 3's successful us-ashburn-1 paas_rag connection as the working baseline.

**Resolution:**
Pending.

---

### BUG-027: testing-pack skill doesn't carve out destroy-via-CLI as a permitted fallback

**Status:** Open
**Date found:** 2026-04-23
**Found by:** Monitor agent during v0.0.7 release testing (surfaced by team-lead after track1-gpu4 used OCI CLI for app destroy when browser session expired)
**Severity:** Low

**Symptoms:**
During v0.0.7 release testing, Track 1's browser session (`track1-1776884811`) expired mid-test. Rather than re-authenticate through IDCS + MFA just to click "Destroy" in the ORM UI, the teammate ran the destroy via OCI CLI (`oci resource-manager job create-destroy-job ...`). The destroy succeeded.

However, `/testing-pack`'s CRITICAL RULE #3 explicitly restricts CLI usage:
> "OCI CLI is ONLY used for: listing stacks (Phase 1 discovery), resolving compartment OCIDs, and kubectl/helm commands. Never for stack create/update/apply."

The rule says "Never for stack create/update/apply" — it does NOT explicitly mention destroy. The teammate claimed "destroy is carved out," but there is no written carve-out. This created a compliance ambiguity that the monitor had to escalate.

**Root cause:**
The skill's CRITICAL RULE #3 was written with the intent that CLI bypasses the UI validation the skill is meant to test. For create/update/apply, that's a genuine concern — the wizard exercises required-field validation, dropdown defaults (starter_pack_size!), schema visibility, and file-upload CDP paths. For destroy, there is effectively no UI validation to test: the Destroy button just confirms and runs. CLI destroy is substantively equivalent to UI destroy.

But the rule text as written forbids all "stack create/update/apply" by CLI and is silent on destroy. A strict reading forbids only the three named operations; a stricter reading (argued by some teammates during parallel tracks) treats the list as exhaustive. The absence of an explicit carve-out forces judgment calls mid-test.

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — CRITICAL RULES section (rule #3 and rule #4 "Destroy before deleting app stack" both touch destroy but don't address CLI vs UI)

**Workaround:**
Two options when the browser session expires and only a destroy is needed:
1. (Preferred per current rule text) Re-open browser + re-auth + click Destroy in the UI. Slow, re-triggers IDCS/MFA, but unambiguous.
2. (Used by Track 1) Run `oci resource-manager job create-destroy-job --stack-id <ocid> --execution-plan-strategy AUTO_APPROVED` via CLI. Fast, no user action needed, but technically not blessed by the skill.

**Resolution:**
Fixed by extending CRITICAL RULE #3 in `/testing-pack/SKILL.md` with an explicit catch-all: the UI-only rule applies to destroy jobs as well. If the browser session is unavailable mid-test, wait for or re-establish a browser session before running any stack operation — including destroy. CLI destroy is not a permitted fallback. RULE #4 also clarified to say "re-authenticate before Destroy" rather than pointing at the CLI command. Error Handling table has a "browser session expired mid-test" recovery row. Spec: `docs/superpowers/specs/2026-04-23-release-testing-skill-hardening-design.md`.

**Prior proposed-fix notes (for reference only):**
1. **Explicit carve-out.** Update CRITICAL RULE #3 to: "OCI CLI is ONLY used for: listing stacks (Phase 1 discovery), resolving compartment OCIDs, kubectl/helm commands, **and stack destroy jobs when the browser session is unavailable**. Never for stack create/update/apply." Rationale: destroy doesn't exercise UI validation.
2. **Strict rule with documented recovery.** Keep the current rule text but add a short section "When the browser session expires before destroy" that tells the teammate to reopen + re-auth. Costs a few minutes per destroy but keeps the rule unambiguous.
3. **Make the rule op-specific.** Rewrite rule #3 as a per-operation table: create/update/apply = browser required; destroy/list/inspect = CLI permitted. Cleanest long-term but biggest edit.

Recommend option 1 (explicit carve-out) — low skill-drift risk, matches what teammates already do under pressure, and the rationale is defensible.

**Reference:** Discovered during v0.0.7 release testing (2026-04-23). Track1-gpu4 used CLI for the app destroy after browser session expired; team-lead flagged the rule ambiguity and asked monitor to log. Not a release blocker — destroy succeeded and caused no downstream issues. Bug total this release: 7 (BUG-021 through BUG-027).

---

### BUG-028: testing-pack doesn't enforce PR screenshot uploads — systematic skip under time pressure

**Status:** Open
**Date found:** 2026-04-23
**Found by:** Monitor agent during v0.0.7 release testing (confirmed by PR #104 screenshot audit at monitor request — zero screenshots across 14 comments and all 3 active tracks)
**Severity:** Medium

**Symptoms:**
During v0.0.7 release testing, all three testing tracks (`track1-gpu4`, `track2-a10`, `track3-cpu`) posted milestone updates to PR #104 with **no screenshots attached**. A monitor-driven audit of all 14 PR comments found zero markdown image references (no `![...](...)` syntax, no `user-images.githubusercontent.com` URLs, no `github.com/user-attachments/` links). Track 2 in particular posted nothing at all — not even text.

Specific coverage gap:
| Track | Direct PR comments | Screenshots |
|---|---|---|
| track1-gpu4 (enterprise_rag/small) | 2 (Phase 3/4 start, Phase 5+6 status) | 0 |
| track2-a10 (vss/poc) | 0 | 0 |
| track3-cpu (paas_rag/small) | 10 (full Phase 4–7 lifecycle + test tables) | 0 |

Track 3 reached Phase 7 destroy without ever attaching a screenshot; the skill's "bulk upload at end-of-run via the side-branch flow" never executed. Track 1 skipped screenshot uploads entirely for Round 1 before the rebase reset state. Track 2 is even further behind — no PR evidence at all.

**Root cause:**
`/testing-pack` Phase 0h tells the teammate screenshots will be attached later ("Screenshots will be attached in the bulk upload at end-of-run via the side-branch flow in `references/pr-screenshot-upload.md`"), with per-milestone comments that include the line "Screenshots will be attached in the bulk upload at end-of-run." This is a soft promise with:

1. **No checklist-gate on Phase 7 completion** — Phase 7 closes out without verifying that the side-branch upload actually ran.
2. **No friction for skipping** — a teammate under time pressure (IDCS timeouts, rebase churn, long apply cycles) naturally drops "nice to have" work when tools (agent-browser) are themselves flaky. Screenshots are the first thing cut.
3. **No monitor-visible failure** — text-only PR comments look "complete" even though they're missing the visual evidence release reviewers use to confirm UI actually rendered, ORM wizard actually showed the correct pack/size, etc.
4. **Side-branch upload flow is documented in a reference file, not the main phase flow** — easy to skip on a busy run.

The net effect: on the v0.0.7 run, release reviewers must trust teammate text assertions about what the UI looked like, instead of seeing the UI. That defeats one of the main reasons `/testing-pack` exists (to catch UX regressions the OCI CLI would miss).

**Affected files:**
- `.claude/skills/testing-pack/SKILL.md` — Phase 0h (soft promise), per-phase milestone sections (no explicit required-screenshot list), Phase 7 (no verify step), CRITICAL RULES (no rule requiring screenshots)
- `.claude/skills/testing-pack/references/pr-screenshot-upload.md` — documented but not enforced

**Workaround:**
Monitor-driven nudging (as happened this release): audit PR #104 comments for missing screenshots and ping each track with a concrete list of screenshots to post. Track 3 can run the side-branch upload now that Phase 7 is effectively done; Track 1 should capture screenshots as it reapplies post-rebase; Track 2 should backfill Phase 3/4 posts with screenshots.

**Resolution:**
Pending. Proposed fix:
1. **Add a required-screenshots list to each milestone.** Phase 3 requires schema-validation screenshots of BOTH infra and app wizards. Phase 4 requires an infra APPLY SUCCEEDED job screenshot. Phase 5 requires app APPLY SUCCEEDED + extracted frontend URLs. Phase 6 requires at least one screenshot per pack-specific UI test. Phase 7 requires a DESTROY SUCCEEDED screenshot.
2. **Gate Phase 7 on screenshot attachment.** Explicitly: "Before marking Phase 7 complete, verify PR has at least N screenshots (N = sum of per-milestone required counts). If any are missing, run the side-branch bulk upload now."
3. **Promote the side-branch upload from a reference to a Phase step.** Add "Phase 7a: Bulk-upload saved screenshots to PR" as its own numbered step — not a footnote.
4. **Add a CRITICAL RULE:** "Every milestone comment MUST include at least one screenshot. Text-only evidence is not acceptable for phases that exercise the UI."

**Reference:** Discovered during v0.0.7 release testing (2026-04-23). PR #104 screenshot audit returned 0 images across 14 comments. Team-lead classified screenshots as "release evidence, not optional" and asked monitor to log. All three active tracks affected, confirming this is a systematic skill gap and not an individual teammate error. Bug total this release: 8 (BUG-021 through BUG-028).

### BUG-029: enterprise_rag v2.5.0 NIMCache pods missing GPU toleration — blocked on scheduling

**Status:** Open — **RELEASE BLOCKER** for v0.0.7 helm chart v2.5.0 path
**Date found:** 2026-04-23
**Found by:** track1-gpu4 during v0.0.7 rebased release testing (enterprise_rag/small on BM.GPU4.8, uk-london-1); dependency-graph analysis confirmed by team-lead 2026-04-23
**Severity:** Critical (release blocker)

**Symptoms:**
- After deploying with the post-rebase v0.0.7 zip (nvidia-blueprint-rag v2.5.0 + NIM Operator 3.1.0), 7 NIMCache-backed pods sit Pending in the `rag` namespace for >50 min:
  - `nim-llm-cache-pod`, `nemotron-embedding-ms-cache-pod`, `nemotron-ranking-ms-cache-pod`
  - `nemoretriever-ocr-v1-pod`, `nemoretriever-page-elements-v3-pod`, `nemoretriever-table-structure-v1-pod`, `nemoretriever-graphic-elements-v1-pod`
- `kubectl describe pod` shows:
  ```
  0/4 nodes are available: 2 node(s) didn't match Pod's node affinity/selector, 2 node(s) had untolerated taint {nvidia.com/gpu: present}
  ```
- NIMCache CRs: all NotReady (or blank status, for ones whose cache download hasn't started)
- NIMService CRs: all NotReady (downstream of NIMCache)
- PVCs for cache volumes: Pending (WaitForFirstConsumer — because the pods can't schedule to a node yet)

**Root cause:**
The NIMCache CRs in the v2.5.0 chart (`nvidia-blueprint-rag`) create their cache downloader pods with only the default tolerations (`node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable`, both NoExecute). They lack the toleration for `nvidia.com/gpu=present:NoSchedule` that every GPU-tainted node in OKE has by default. This is the same class of issue as BUG-009 (workload=nim-llm taint) but in reverse — instead of a stale taint on the node, the *pod spec* is missing the taint toleration.

The pod's `nodeSelector` is correctly `feature.node.kubernetes.io/pci-10de.present=true` (matches GPU nodes), but OKE also applies `nvidia.com/gpu=present:NoSchedule` to those nodes via gpu-operator's auto-tainting, and the NIMCache CR template doesn't include the matching toleration. Result: nodes match the selector but reject the pod via the NoSchedule taint.

**Affected files (to investigate):**
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — maybe needs `tolerations:` stanza added for NIM Operator NIMCache CRs.
- Upstream: NVIDIA `nvidia-blueprint-rag` chart v2.5.0 NIMCache CR template / NIM Operator 3.1.0 default toleration list.

**Workaround (not yet tested):**
Remove the `nvidia.com/gpu=present:NoSchedule` taint from the GPU nodes:
```bash
kubectl taint nodes 10.0.106.114 nvidia.com/gpu=present:NoSchedule-
kubectl taint nodes 10.0.108.242 nvidia.com/gpu=present:NoSchedule-
```
This allows non-GPU pods to be scheduled on GPU nodes too, which is undesirable for production. Better fix: add `tolerations:` block to NIMCache CR template in chart values.

**Impact on release testing:**
- Round 1 (enterprise_rag/small, v0.0.7 rebased) Phase 5 app apply may eventually SUCCEED at the Terraform level (helm_release.rag likely exits with a pending-install state waiting for NIMCache readiness), but Phase 6 smoke tests will be blocked until the cache pods schedule.
- BUG-026 cannot be re-verified (it depends on NIM pods being Running, which depends on NIMCache being Ready) until this is unblocked.

**Live cluster image confirmation (v0.0.7 tags on running pods):**
- rag-server: `nvidia-rag-retrieval-oci:v0.0.6` — correct, bumped per SOFTWARE_VERSIONS.md
- ingestor-server: `nvidia-rag-ingestion-oci:v0.0.6` — correct
- rag-frontend: `enterprise-rag-frontend:v0.0.2` — unchanged
- nim-llm-cache: `nemotron-3-super-120b-a12b:1.8.0` — new model image (per v2.5.0)
- nemoretriever-*: `nemotron-*` / `nemoretriever-*` images per v2.5.0 chart defaults

**Resolution:**
Pending.

**Dependency-graph analysis (team-lead, 2026-04-23):**

Confirmed a deadlock in the rebased `helm.tf`:
- `helm_release.rag` defaults to `wait = true` (Terraform blocks until all Helm-managed resources report Ready).
- `terraform_data.patch_nim_operator_resources` declares `depends_on = [helm_release.rag]`.
- Therefore the tolerations that NIMCache pods need to schedule are only applied **after** `helm_release.rag` reports complete.
- But `helm_release.rag` cannot complete because its pods (the NIMCache-backed ones) cannot reach Ready without those tolerations.

Net effect: Terraform apply either times out waiting on `helm_release.rag`, or exits with a partial/error state and the `patch_nim_operator_resources` step never runs. In either case, PR #101's post-install patching approach as-coded cannot close the loop on a clean deploy. The manual workaround (applying the taint/toleration fix out-of-band) is what's letting Track 1 continue to validate BUG-026 right now, but it's not a shippable path for customers.

This makes BUG-029 a **release blocker** for the v0.0.7 helm-chart-v2.5.0 path (Track 1 / enterprise_rag+aiq only; vss/paas_rag/cuopt/wpp unaffected since they don't use the rag helm release or NIMCache CRs).

**Proposed fixes (team-lead, 2026-04-23 — pick one):**

1. **Change `helm_release.rag` to `wait = false`.** Lowest-risk edit. Terraform returns after Helm dispatches the release instead of waiting for pod readiness; the `terraform_data.patch_nim_operator_resources` step then fires and applies tolerations to NIMCache CRs; pods reach Ready on the next reconcile. Trade-off: Terraform's completion signal no longer implies "application is live" — downstream consumers (smoke tests, the blueprint deploy job) must poll cluster state themselves.

2. **Move tolerations into chart values so no post-install patching is needed.** Cleanest long-term. Add a `tolerations:` stanza to the NIMCache CR templates in `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` (and/or a corresponding values override the chart exposes). The `terraform_data.patch_nim_operator_resources` step can then be deleted. Risk: may require chart support we don't control, depending on whether the `nvidia-blueprint-rag` v2.5.0 templates expose per-CR toleration overrides.

3. **Add a pre-install hook that patches NIMCache CRs before pods are created.** Use a Helm chart `pre-install` / `pre-upgrade` hook (or a separate `null_resource`/`terraform_data` with `depends_on` inverted — i.e. runs *before* `helm_release.rag`) that creates a mutating admission policy or patches the NIMCache CRDs themselves so every new NIMCache CR is born with the toleration. Highest complexity; avoids touching `wait = true`. Only worth it if option 1's downstream-polling shift is unacceptable.

Team-lead recommendation: option 1 first (unblocks the chart right now), then option 2 as the real fix in a follow-up PR so `wait = true` can return.

**Status of Track 1 validation under the manual workaround:**
Track 1 is applying the manual toleration removal as a workaround so that Phase 6 smoke tests can still re-verify BUG-026 (ADB DPY-6000). This proves PR #101's *intent* works (the nv-ingest DNS fix + v0.0.6 images + NIM Operator) but does NOT prove the *as-shipped* Terraform code handles the deploy cleanly. Release go/no-go decision deferred until Phase 6 completes and we can separately decide whether to ship the fix in-release (option 1) or block shipping until option 2 is in.

**Release-summary flag:** Must appear as a top-line blocker in the end-of-release summary to PR #104, regardless of Phase 6 outcome. Close-out only possible after one of the three fixes above is merged AND a clean (no-manual-workaround) apply verifies cache pods schedule + rag release reports healthy + Phase 6 passes.

---

### BUG-030: enterprise_rag v2.5.0 app destroy hangs on NIMCache/NIMService finalizers — `resource-policy: keep` annotation preserves CRs after Helm uninstall

**Status:** Open — **RELEASE BLOCKER** (customer can't cleanly destroy without manual finalizer removal)
**Date found:** 2026-04-23
**Found by:** track1-gpu4 during v0.0.7 rebased release testing (enterprise_rag/small on BM.GPU4.8, uk-london-1); escalated by team-lead
**Severity:** High — complements BUG-029 as a destroy-path bug (vs BUG-029's apply-path deadlock)

**Symptoms:**
- `oci resource-manager job create-destroy-job` on the enterprise_rag app stack FAILS with a Terraform error: `context deadline exceeded on kubernetes_namespace_v1.app_namespace[0]`.
- `kubectl describe ns rag` shows finalizers present on the namespace; namespace stuck in `Terminating`.
- The NIMCache and NIMService CRs in the `rag` namespace are NOT deleted by the Helm uninstall. `kubectl get nimcache,nimservice -n rag` still lists all 7 NIMCache and all 7 NIMService CRs after Helm reports the release gone.
- Their controller's finalizers prevent the namespace from fully deleting, so `kubernetes_namespace_v1` times out waiting on namespace deletion.

**Root cause:**
PR #101's v2.5.0 chart (`nvidia-blueprint-rag`) marks NIMCache and NIMService CRs with the Helm annotation `helm.sh/resource-policy: keep`. That annotation tells Helm to preserve those objects on `helm uninstall` — likely intended upstream so cache volumes persist across upgrade cycles. In our destroy flow, that's the wrong behavior: we want the namespace (and everything in it) fully removed.

Chain of events on destroy:
1. Terraform destroys `helm_release.rag` → Helm runs `helm uninstall rag -n rag`.
2. Helm honors `resource-policy: keep` and leaves all 7 NIMCache + 7 NIMService CRs in the `rag` namespace.
3. Terraform then destroys `kubernetes_namespace_v1.app_namespace[0]` → Kubernetes tries to delete the namespace.
4. Namespace deletion blocks on the CRs' own finalizers (owned by the NIM Operator controller).
5. `kubernetes_namespace_v1` times out with `context deadline exceeded`.

Net effect: the destroy fails mid-way. The infra stack's OKE cluster is left in an inconsistent state with orphaned CRs, orphaned namespace in `Terminating`, and an ACTIVE ORM app stack that Terraform can't reconcile.

**Affected files:**
- Upstream: `nvidia-blueprint-rag` chart v2.5.0 — NIMCache and NIMService CR templates ship with `helm.sh/resource-policy: keep`.
- Release-repo candidates for fix:
  - `ai-accelerator-tf/helm.tf` — where `helm_release.rag` is declared; candidate for a destroy-time `provisioner "local-exec" { when = destroy ... }` step to strip the annotation / finalizers before uninstall.
  - `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — if the chart exposes a values override to suppress the `resource-policy: keep` annotation, we can set it here.

**Workaround used by track1-gpu4 (2026-04-23):**
```bash
# For each stuck CR, clear the finalizer so the controller deletion can proceed:
for cr in $(kubectl get nimcache -n rag -o name); do
  kubectl patch "$cr" -n rag --type=merge -p '{"metadata":{"finalizers":[]}}'
done
for cr in $(kubectl get nimservice -n rag -o name); do
  kubectl patch "$cr" -n rag --type=merge -p '{"metadata":{"finalizers":[]}}'
done
# Then retry the destroy job.
```
Applied to all 7 NIMCache + 7 NIMService CRs on Track 1's v0.0.7-rebased app stack. Destroy then proceeded.

**Proposed fixes (pick one):**

1. **Cleanest: add a destroy-time Terraform provisioner.** Either a `provisioner "local-exec" { when = destroy ... }` on `helm_release.rag` itself, OR a separate `terraform_data` resource with `depends_on = [helm_release.rag]` and a destroy-time action. The provisioner runs `kubectl patch` (or equivalent) to clear the NIMCache + NIMService finalizers BEFORE Helm uninstall removes the release. This mirrors the approach already used for other teardown-sensitive resources in this codebase.

2. **Or: override `resource-policy: keep` via chart values.** If the v2.5.0 chart exposes a values override to disable the `keep` annotation (or set it to `delete`), flip it in `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml`. Lowest effort if supported.

3. **Or: remove `resource-policy: keep` from NIMCache/NIMService CR templates in values entirely.** Only viable if the chart's templates are locally rendered or if NVIDIA will accept a PR upstream; otherwise fork-pinning territory.

**Classification:** Same release-blocker family as BUG-029 — both are v2.5.0 chart orchestration bugs introduced by the PR #101 rebase (apply-path + destroy-path respectively). Both must be fixed before shipping v0.0.7.

**Release implications:**
- Customer flow "`terraform destroy`" or ORM destroy on enterprise_rag app stack **fails without manual intervention**. Unacceptable for v0.0.7 ship.
- Combined with BUG-029 (apply-path deadlock), the v0.0.7 enterprise_rag path is broken in both directions (can't apply cleanly without manual toleration fix, can't destroy cleanly without manual finalizer fix).
- vss/paas_rag/cuopt/warehouse_pick_path unaffected (no NIMCache/NIMService CRs).

**Close-out gating:** One of the 3 proposed fixes merged AND a clean (no-manual-workaround) destroy completes against an enterprise_rag app stack that was applied via the rebased v0.0.7 path. Ideally demonstrated in the same test cycle as BUG-029's close-out.

**Reference:** Discovered during Track 1's Round 1 → Round 2 transition on 2026-04-23 (post-BUG-029 manual workaround). Teardown job submitted 2026-04-23T21:53:51Z for app stack `Enterprise RAG - App - v0.0.7 2026-04-22 1824` (Track 1's app stack OCID `ocid1.ormstack.oc1.uk-london-1.amaaaaaam3augwaa5fvnopcj6uokwllhuo6spwl4rgqgxsh72yhgte744fdq`). Workaround steps above confirmed unsticking the destroy. **Release-summary flag:** must appear as a top-line blocker alongside BUG-029.

**Evidence (CLI-confirmed timeline):**

App stack OCID (uk-london-1): `ocid1.ormstack.oc1.uk-london-1.amaaaaaam3augwaa5fvnopcj6uokwllhuo6spwl4rgqgxsh72yhgte744fdq`

- **2026-04-23T21:53:51Z** — DESTROY submitted (no manual workaround).
  Job OCID: `ocid1.ormjob.oc1.uk-london-1.amaaaaaam3augwaaamkm4awauepnavhzp5k3fc63pepjox5eexawaeno3kza`
- **2026-04-23T21:59:51Z** — **DESTROY FAILED** after 6 min (context deadline on `kubernetes_namespace_v1.app_namespace`) — BUG-030 firing.
  Same job OCID as above; terminal state FAILED recorded on the job.
- **2026-04-23T~22:00 → ~22:22Z** — operator cleared finalizers on all 7 NIMCache + 7 NIMService CRs via `kubectl patch ... -p '{"metadata":{"finalizers":[]}}'` (see Workaround section above). ~23 min of manual recovery overhead between the FAILED destroy and the retry.
- **2026-04-23T22:22:11Z** — DESTROY re-submitted after workaround.
  Job OCID: `ocid1.ormjob.oc1.uk-london-1.amaaaaaam3augwaa32qjeqprwsuctty5wmk2cxg4c34ftw7jftcp3eykrxsq`
- **2026-04-23T22:23:04Z** — **DESTROY SUCCEEDED** (53s — fast, because the namespace-deletion block was the only thing stuck).

This timeline is pulled directly from `oci resource-manager job list` on the Track 1 app stack; it serves as audit-trail evidence for the release-blocker classification of BUG-030. Any customer running the v0.0.7 enterprise_rag pack through its full lifecycle will hit the same failure on first destroy attempt without the finalizer-clearing workaround.

---

### BUG-031: Release zips have TF files nested under `ai-accelerator-tf/` — CLI `resource-manager stack update --config-source` rejects them; only ORM Console auto-unpacks

**Status:** Open
**Date found:** 2026-04-23
**Found by:** track1-gpu4 during v0.0.7 rebased release testing (CLI-path stack update on enterprise_rag app stack); escalated by team-lead
**Severity:** Low — skill / release-packaging tooling gap; does not affect the ORM Console path customers use

**Symptoms:**
`oci resource-manager stack update --config-source release_test_matrix/v0.0.7_<pack>.zip` fails to recognize the Terraform code because every `.tf` file inside the zip is nested under a top-level `ai-accelerator-tf/` directory. The CLI does not flatten or auto-descend; it looks for `.tf` files at the root of the archive and finds none, so the upload is rejected (or the subsequent plan errors out with "no Terraform configuration found").

The ORM Console's UI upload path is more forgiving: when a user uploads the same zip through the browser, the Console's upload handler detects the single-subdirectory layout and auto-flattens during unpack, so the Terraform code is placed at the stack root. CLI and Console therefore accept different zip layouts for the same logical input.

This divergence is invisible at build time (the zips pass all smoke checks — `unzip -l` looks correct, `schema.yaml` is present at the expected path, the Console accepts them). It only surfaces when someone reaches for the CLI during release testing and gets a confusing rejection from a file that "clearly contains Terraform."

**Root cause:**
The `/zip-tf` skill (and the `/releasing` skill that calls it) packages the repo's `ai-accelerator-tf/` directory using `zip -r <out>.zip ai-accelerator-tf/`, which preserves the directory prefix in the archive. That matches how humans usually think about the source tree, and the Console handles it. The CLI's `--config-source` expects a "Terraform project archive" layout with `.tf` files at zip root, which is a valid but stricter convention.

CLAUDE.md (`.claude/rules/terraform.md`) already acknowledges this: "When creating ORM zips, TF files must be at the zip root (zip from inside `ai-accelerator-tf/`, not the parent directory)." — but the `release_test_matrix/` zips produced by `/releasing` don't follow that rule, because the `/zip-tf` skill zips from the repo root.

**Affected files:**
- `.claude/skills/zip-tf/` — the skill that produces the nested-layout zips
- `.claude/skills/releasing/` — invokes `/zip-tf` for per-pack release zips
- `release_test_matrix/v0.0.7_*.zip` — existing v0.0.7 release zips, all nested
- `.claude/rules/terraform.md` — documents the flat-zip-root rule but it isn't enforced by the tooling
- `.claude/skills/testing-pack/SKILL.md` — CRITICAL RULE #3 restricts CLI usage but doesn't call out this specific packaging mismatch

**Workaround (used by Track 1 on 2026-04-23):**
Repack the zip with TF files at the root before the CLI update:
```bash
cd ai-accelerator-tf && zip -r /tmp/flat.zip .
oci resource-manager stack update --config-source /tmp/flat.zip --stack-id <ocid>
```
Adds ~10 seconds per stack update when doing CLI-path work.

**Classification:** Skill gap + packaging convention mismatch between the UI and CLI ORM paths. Companion to BUG-027 (testing-pack doesn't carve out destroy-via-CLI as a permitted fallback): both bugs point to the same underlying gap — the release-packaging and testing skills assume UI-only interaction, while teammates legitimately use CLI for efficiency during release testing.

**Proposed fix options:**

1. **Produce two zip variants.** Update `/zip-tf` to emit a UI-compatible nested variant AND a CLI-compatible flat variant. Name them accordingly: `v0.0.7_cuopt.zip` (current layout, UI-compatible) and `v0.0.7_cuopt-flat.zip` (CLI-compatible). Slightly more build output but zero ambiguity at consumption time.

2. **Pack flat by default.** The ORM Console accepts both the nested and the flat layout (it just auto-flattens the nested case), so switching to a single flat layout satisfies both consumers. Simpler than option 1; updates one skill (`/zip-tf`) and nothing else downstream. Recommended.

3. **Document the asymmetry in `/testing-pack`.** Lowest effort but highest ongoing tax — every teammate who reaches for the CLI has to remember to re-pack. This is what the workaround above already does.

Team-lead recommendation (implicit): option 2 is the cleanest — one layout that works everywhere.

**Release implications:**
- Not a customer-facing blocker. Customers use the ORM Console upload path, which already handles the nested layout transparently.
- Blocker for internal tooling / release-testing teammates who legitimately use CLI (per the workaround). Costs ~10s per stack update; no data-loss or state-corruption risk.
- Does NOT need to block v0.0.7 shipping, but should be fixed before v0.0.8 to remove the ongoing friction and reduce the chance of a teammate hitting it in production-adjacent work.

**Close-out gating:** One of the 3 fixes above merged. If option 2 is chosen, a smoke check that `unzip -l release_test_matrix/v0.0.X_cuopt.zip | head -20` shows `.tf` files at the zip root (no `ai-accelerator-tf/` prefix) is sufficient.

**Reference:** Discovered during v0.0.7 rebased release testing on 2026-04-23. Track 1's CLI-based stack update against Track 1's enterprise_rag app stack failed at `--config-source` step; manual repack via `cd ai-accelerator-tf && zip -r /tmp/flat.zip .` resolved it. Team-lead classified and escalated for logging. Bug total this release: 11 (BUG-021 through BUG-031).
