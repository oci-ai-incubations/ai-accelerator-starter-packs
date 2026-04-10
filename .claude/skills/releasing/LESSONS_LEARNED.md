# Lessons Learned

Anti-patterns and pitfalls discovered during real releases. Read this before starting a release to avoid repeating mistakes.

## GPU Capacity

**Always check BOTH hardware capacity AND tenancy quota.** A region can have hardware available but 0 quota allocated to your tenancy.

- Example: sa-saopaulo-1 showed AVAILABLE hardware but had 0 GPU quota
- `/checking-capacity` checks both — always use it instead of assuming a region works

**Check FSS mount target quotas for VSS packs.** VSS requires file system service mount targets. Some regions/ADs have a mount target quota of 0 even when GPU capacity is available.

- Example: us-phoenix-1 had VM.GPU.A10.2 capacity but 0 FSS mount target quota in PHX-AD-1
- This is not checked by `/checking-capacity` — verify manually if deploying VSS

## ORM UI

**Always explicitly set `starter_pack_size` in the ORM wizard.** The schema defaults to `small`, not `poc`. If you want `poc`, you must select it — ORM will happily deploy the wrong size silently.

- Example: us-phoenix-1 attempt deployed `small` (BM.GPU4.8) instead of `poc` (VM.GPU.A10.2) because the size field defaulted to `small` in the ORM wizard

## Tenancy Housekeeping

**Dynamic group quota (50 per tenancy) fills up fast.** Each stack deploy creates dynamic groups. Stale dynamic groups from old test deployments accumulate.

- Fix: Before testing, list and delete orphaned dynamic groups:
  ```bash
  oci iam dynamic-group list --compartment-id <tenancy_ocid> --all \
    --query 'data[].{name:name, id:id, time:"time-created"}' --output table
  ```
- Delete groups from old deployments that no longer exist

**Customer secret keys have a quota of 2 per user.** If previous deploys didn't clean up, new deploys fail with quota errors.

- `/testing-pack` Phase 5b documents the cleanup command

## Terraform Destroy Provisioners

**Destroy-time provisioners cannot reference external resources in Terraform 1.5.** When adding `provisioner "local-exec" { when = destroy }` blocks:

- Use the `input`/`self.output` pattern to pass values (e.g., kubeconfig path)
- Do NOT use resource-level `connection` blocks — Terraform validates them against destroy provisioner rules even if only the create provisioner uses them
- Instead, put `connection` blocks inside each provisioner individually

Example (from BUG-009 fix):
```hcl
resource "null_resource" "example" {
  input = { kubeconfig = local.kubeconfig_path }

  provisioner "local-exec" {
    command = "kubectl apply -f ..."
    environment = { KUBECONFIG = self.input.kubeconfig }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete ..."
    environment = { KUBECONFIG = self.output.kubeconfig }
  }
}
```

## Stale Kubernetes State

**Terraform destroy removes state but doesn't clean up all Kubernetes side effects.** Taints, labels, and node modifications applied by one app stack persist after destroy.

- Example: BUG-009 — `nim-llm` taint applied to GPU nodes by enterprise_rag. After app destroy, taint remained, blocking enterprise_rag_aiq pods from scheduling
- Fix: Add destroy-time provisioners that explicitly clean up taints/labels
- Always check `kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints` between back-to-back deploys

## Agent Teams vs Background Subagents

**Background subagents silently fail on `AskUserQuestion`.** They cannot prompt the user for input. This means:

- They cannot authenticate to OCI Console
- They cannot request compartment selection
- They fall back to OCI CLI, bypassing the browser-based testing

**Always use agent teams for parallel testing.** Agent teams are full interactive sessions that can use all tools including `AskUserQuestion`.

## Release Zip Lifecycle

**Original zips become stale after bug fixes.** If testing reveals bugs that get fixed:

1. The GitHub Release still has the old, buggy zips
2. You must rebuild ALL 5 zips (not just the affected pack — shared code changes affect all)
3. Delete old assets from the release and re-upload
4. Verify timestamps to confirm the new zips replaced the old ones

**Mark releases as pre-release during testing.** Use `gh release create --prerelease` so users don't download untested code. Promote to latest with `gh release edit --prerelease=false --latest` after all tests pass.
