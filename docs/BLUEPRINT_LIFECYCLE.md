# Blueprint Deployment Lifecycle

Blueprint deployments on OCI AI Blueprints (Corrino) are **immutable** — they cannot be updated in place. The only way to modify a running deployment is to undeploy it and redeploy with a new configuration. This document explains how Terraform manages that lifecycle idempotently.

## The Problem

Terraform needs to behave correctly in three scenarios:

1. **No change to the blueprint** — do nothing. No undeploy, no redeploy.
2. **A different category's blueprint changes** — do nothing. Only the active category matters.
3. **The current category's blueprint changes** — undeploy the old deployment, deploy the new one.

Without special handling, Terraform would either re-run the deployment Job on every `apply` (causing downtime) or never re-run it (missing legitimate changes).

## How It Works

The lifecycle is driven by four resources that form a chain:

```
blueprint content (locals)
    → random_id.blueprint_deploy_id (content hash)
        → kubernetes_job_v1.blueprint_deployment_job (undeploy + deploy)
            → null_resource.wait_for_deployment (URL polling)
```

### 1. Content Hashing (`vars.tf`)

Each blueprint in `blueprint_files.tf` uses `"DEPLOY_NAME"` as a placeholder for the deployment name. At resolve time, two versions are produced:

- **`canonical_blueprint_content`** — replaces `DEPLOY_NAME` with the **static** name (e.g., `"paas"`). This is used only for hashing. It produces a stable hash that changes only when the blueprint's actual configuration changes.
- **`starter_pack_blueprint_content`** — replaces `DEPLOY_NAME` with the **unique** name including a random suffix (e.g., `"paas-167d3256"`). This is the payload submitted to the Corrino API.

The canonical version intentionally excludes the random suffix so the hash doesn't change on every apply.

### 2. Change Detection (`random_id.blueprint_deploy_id`)

```hcl
resource "random_id" "blueprint_deploy_id" {
  keepers = {
    blueprint_hash = sha256(local.canonical_blueprint_content)
  }
}
```

The `keepers` block ties the random ID to the SHA-256 hash of the canonical blueprint content. When the hash changes, `random_id` is replaced, generating a new hex suffix. When nothing changes, the random ID is stable.

Only the **current category and size** feeds into the hash — `local.starter_pack_blueprints[var.starter_pack_category][var.starter_pack_size]`. Changes to other categories' blueprints do not affect it.

### 3. Job Replacement (`kubernetes_job_v1.blueprint_deployment_job`)

```hcl
resource "kubernetes_job_v1" "blueprint_deployment_job" {
  metadata {
    name = "blueprint-deployment-job-${random_id.blueprint_deploy_id[0].hex}"
  }

  lifecycle {
    replace_triggered_by = [random_id.blueprint_deploy_id]
  }

  spec {
    ttl_seconds_after_finished = 31536000  # 1 year
  }
}
```

Three mechanisms work together:

- **Dynamic name**: The Job name includes the random hex suffix. Since Kubernetes Jobs are immutable, a new name avoids collisions when Terraform destroys the old Job and creates the new one.
- **`replace_triggered_by`**: Explicitly forces Job replacement when `random_id` changes, even if no other Job attributes changed.
- **1-year TTL**: The completed Job must persist in the Kubernetes cluster so Terraform sees it as existing on subsequent applies. Without this, Kubernetes garbage-collects the Job and Terraform sees drift, causing a spurious re-run.

### 4. URL Re-polling (`null_resource.wait_for_deployment`)

```hcl
resource "null_resource" "wait_for_deployment" {
  triggers = {
    blueprint_deploy_id = random_id.blueprint_deploy_id[0].hex
  }
}
```

After a new deployment, the URL polling provisioner re-runs to wait for the new deployment to become healthy before resolving the starter pack URL output.

## The Undeploy + Deploy Script

The blueprint deployment Job runs an inline Python script that:

1. Logs into the Corrino API
2. Fetches the current workspace recipes
3. Finds all Ingress-type deployments and undeploys them
4. Polls until the workspace is clear (up to 10 minutes)
5. Submits the new blueprint via `corrino_api_client.py`

This ensures the old deployment is fully removed before the new one is created, avoiding `deployment_name` uniqueness violations.

## The DEPLOY_NAME Placeholder

Blueprint JSON definitions in `blueprint_files.tf` use literal `"DEPLOY_NAME"` strings (and variants like `"DEPLOY_NAME-2"`, `"DEPLOY_NAME-3"` for deployment groups with multiple sub-deployments). These are replaced at two points:

| Local | Replacement | Purpose |
|-------|------------|---------|
| `canonical_blueprint_content` | Static name (e.g., `"paas"`) | Hash input — must be stable across applies |
| `starter_pack_blueprint_content` | Unique name (e.g., `"paas-167d3256"`) | Actual API payload — must be unique per deployment |

## DNS and `public_endpoint.starter_pack`

The `public_endpoint.starter_pack` DNS subdomain uses the **static** deployment name (without random suffix). This is intentional:

- The DNS subdomain should be stable and predictable (e.g., `paas.10-0-0-1.nip.io`)
- Blueprint `service_endpoint_domain` references this value for custom DNS setups
- Using the random suffix here would create a dependency cycle: blueprints → public_endpoint → random_id → canonical content → blueprints

## Verification

To verify the lifecycle works correctly, run three apply cycles:

1. **No-change apply**: `random_id` should show "Refreshing state" only (no "must be replaced"). The Job should not be recreated.
2. **Change a different category's blueprint**: Same as above — `random_id` stays stable.
3. **Change the current category's blueprint**: `random_id` shows "must be replaced", Job shows "will be replaced due to changes in replace_triggered_by", and `wait_for_deployment` shows "must be replaced".
