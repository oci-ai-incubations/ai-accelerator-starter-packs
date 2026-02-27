---
name: destroy-stack
description: Destroy an OCI Resource Manager stack's infrastructure.
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: [stack-id]
---

# Destroy Stack

Tear down infrastructure managed by an ORM stack.

## Arguments

- `$0` (optional) - ORM stack OCID. If not provided, list active stacks and ask user to select.

## Steps

1. If no stack ID provided, list stacks:
   ```bash
   export OCI_CLI_PROFILE=SANJOSE
   oci resource-manager stack list -c ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3grdiqzvz244gwzycpfl2ctlb4nvl7vi7wu55tqi375a --all
   ```

2. Confirm with user before destroying

3. Create destroy job:
   ```bash
   oci resource-manager job create-destroy-job --stack-id $0 --execution-plan-strategy AUTO_APPROVED
   ```

4. Poll job status until completion (check every 60s)

5. Verify destroy logs are clean

## If Destroy Fails

- If it fails on the Kubernetes provider, update the stack with `--terraform-version 1.5.x` and retry
- If that doesn't work, try with `--refresh=false` if available
- Report any remaining errors to the user
