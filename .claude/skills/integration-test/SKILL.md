---
name: integration-test
description: Run full OCI Resource Manager integration test cycle - schema gen, zip, stack create/update, plan, apply, pod verification, and destroy.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
argument-hint: [category]
---

# Integration Test

Run the full OCI Resource Manager integration test lifecycle for a starter pack category.

## Arguments

- `$0` - Starter pack category: `paas_rag`, `cuopt`, `vss`, or `enterprise_rag`

If no category is provided, ask the user which category to test.

## Prerequisites

Before starting, verify:
1. `ai-accelerator-tf/terraform.tfvars` exists and is populated
2. Ask the user for `OCI_CLI_PROFILE` if not already set (common values: `SANJOSE`, `DEFAULT`)
3. Ask for any PR-specific testing requirements

## Steps

1. **Generate schema**: `cd /Users/dkennetz/code/ai-accelerator && source venv/bin/activate && python3 create_final_schema.py -c $0`
2. **Create zip**: Clean `.terraform` and `.terraform.lock.hcl`, then `cd ai-accelerator-tf && zip -r /Users/dkennetz/code/ai-accelerator/lifecycle.zip . -x '.terraform/*' '.terraform.lock.hcl'`
3. **Create or update stack**: If a stack ID is known from a previous run, update it. Otherwise create a new one in compartment `ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3grdiqzvz244gwzycpfl2ctlb4nvl7vi7wu55tqi375a`
4. **Plan**: Create plan job, poll until completion, check logs for errors
5. **Apply**: Create apply job with `AUTO_APPROVED`, poll in background until completion, check logs
6. **Configure kubectl**: Extract cluster OCID from apply logs, run `oci ce cluster create-kubeconfig`
7. **Verify pods**: `kubectl get pods -n default` — all core pods should be Running
8. **Verify outputs**: Check `starter_pack_url` and `starter_pack_frontend_url` from apply logs
9. **Prompt user** for any additional verification steps
10. **Destroy**: On user confirmation, run destroy job and poll until complete

## Expected Pods by Category

- **Core (always)**: `bp-postgres-*`, `corrino-cp-*`, `corrino-cp-background-*`, `oci-ai-blueprints-portal-*`
- **paas_rag**: `recipe-frontend-paas-*`, `recipe-llamastack-paas-*`, plus `blueprint-deployment-job-*` and `wallet-extractor-job-*` (Completed)
- **cuopt**: `recipe-cuopt-*` (+ `recipe-demo-cuopt-*` if frontend enabled)
- **vss**: `recipe-vss-*`

## Error Handling

- If plan fails, show error logs and stop for user input
- If apply fails, show error logs and stop for user input
- If pods are in CrashLoopBackOff, check logs and report to user (may be transient)
- If destroy fails on k8s provider, suggest updating stack to terraform 1.5.x and retrying
