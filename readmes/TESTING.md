## Core Mechanics

Test files use the `.tftest.hcl` extension and live alongside your Terraform config (or in a `tests/` directory). You run them with `terraform test`. Each file contains **run blocks** that execute sequentially (by default) against your configuration, and each run block can have **assert blocks** to validate conditions.

## Unit vs Integration Testing

The key lever is the `command` attribute on each run block:

- **`command = apply`** (default) — actually creates infrastructure. This is integration testing.
- **`command = plan`** — only runs a plan, creates nothing. This is your unit testing path. Combined with **mock providers** (v1.7+), you get true zero-infrastructure unit tests.

## Structure of a Test File

```hcl
# tests/my_test.tftest.hcl

# 1. Optional: configure providers (or mock them)
mock_provider "aws" {}

# 2. Optional: set variables for all run blocks
variables {
  bucket_prefix = "test"
}

# 3. Run blocks execute in order, each with its own assertions
run "validates_bucket_name" {
  command = plan

  # Override variables for just this run block
  variables {
    bucket_prefix = "override"
  }

  assert {
    condition     = aws_s3_bucket.bucket.bucket == "override-bucket"
    error_message = "S3 bucket name didn't match"
  }
}
```

## Key Features

**Variables** follow a precedence chain: run-block variables override file-level variables, which override CLI/tfvars values. Run-block variables can also reference outputs from earlier run blocks:

```hcl
run "step_two" {
  variables {
    input = run.step_one.some_output
  }
}
```

**Modules** — each run block can target a different module using a `module` block. This is great for setup/teardown patterns:

```hcl
run "setup" {
  module { source = "./testing/setup" }    # creates prereqs
}

run "execute" {}                            # runs main config

run "verify" {
  module { source = "./testing/loader" }   # loads and validates
  assert { ... }
}
```

Each alternate module gets its own state file, and Terraform destroys resources in reverse run-block order at the end — so dependencies clean up correctly.

**`expect_failures`** lets you test that validations _do_ fail when they should:

```hcl
run "rejects_odd_numbers" {
  command = plan
  variables { input = 1 }

  expect_failures = [
    var.input,    # we expect this variable's validation to fail
  ]
}
```

**Parallel execution** (test-level or per-run-block) lets independent run blocks execute simultaneously. A run block with `parallel = false` acts as a synchronization barrier — everything before it must complete, then it runs, then subsequent parallel blocks can proceed.

## State Management

Terraform maintains separate in-memory state files per module source. Run blocks targeting the same module share state, so changes accumulate across run blocks. You can override this with `state_key` to force specific run blocks to share (or not share) state:

```hcl
run "setup" {
  state_key = "main"
  module { source = "./testing/setup" }
}

run "init" {
  state_key = "main"   # shares state with setup, even though different source
}
```

## For Your Use Case (Pure Unit Testing)

The simplest approach is `command = plan` + `mock_provider`:

```hcl
mock_provider "aws" {}

variables {
  environment = "test"
}

run "output_exists" {
  command = plan
  assert {
    condition     = output.vpc_id != null
    error_message = "vpc_id output must be defined"
  }
}

run "resource_has_correct_tags" {
  command = plan
  assert {
    condition     = aws_instance.web.tags["Environment"] == "test"
    error_message = "Environment tag must match variable"
  }
}
```

No cloud credentials needed, no infrastructure created, runs in seconds. This is the closest thing Terraform has to traditional unit testing.

More info here: https://developer.hashicorp.com/terraform/language/tests

---

## Lessons From Our Test Suite (`ai-accelerator-tf/tests/`)

### Test Discovery

`terraform test` discovers `.tftest.hcl` files in the root directory and `tests/` only. It does **not** recurse into subdirectories of `tests/`. Use flat files with prefixed names for organization:

```
tests/
  core_plan.tftest.hcl
  core_validations.tftest.hcl
  starter_pack_enterprise_rag.tftest.hcl
  starter_pack_cuopt.tftest.hcl
  ...
```

### Mock Provider Data Source Overrides

Mock providers return empty lists for data source attributes by default. If your config indexes into data source results (e.g., `data.oci_identity_availability_domains.ads.availability_domains[0].name`), you must supply realistic shapes via `override_data`:

```hcl
mock_provider "oci" {
  override_data {
    target = data.oci_identity_availability_domains.ads
    values = {
      availability_domains = [{
        name = "US-ASHBURN-AD-1"
      }]
    }
  }
}
```

Our test suite overrides 3 OCI data sources that the config indexes into with `[0]`:

- `data.oci_identity_regions.home_region` (used in `providers.tf`)
- `data.oci_identity_availability_domains.ads` (used in `compute.tf`, `oke.tf`, `capacity_check.tf`)
- `data.oci_core_images.oracle_linux` (used in `compute.tf`, `oke.tf`)

### Implicit Provider Dependencies

Not all providers are listed in `required_providers`. Watch for implicit usage:

- `hashicorp/null` — used by `null_resource.wait_for_deployment`
- `hashicorp/cloudinit` — used by instance cloud-init templates

Both need `mock_provider` blocks in test files.

### `command = plan` vs `command = apply` With Mock Providers

**Always use `command = plan` for unit tests.** While `command = apply` might seem safe with mock providers, `local-exec` provisioners are executed by Terraform core (not by providers) and **always run real shell commands during apply**, even when all providers are mocked. This means any `null_resource` with a `local-exec` provisioner will attempt real `curl` calls, file operations, etc.

`override_resource` blocks (both top-level and inside `mock_provider`) do NOT reliably prevent provisioners from executing in Terraform 1.9.x.

The tradeoff: **outputs that depend on `depends_on` chains through apply-time resources remain unknown at plan time.** In our case, `output.starter_pack_url` for dynamic URL starter packs (cuopt, vss, paas_rag) flows through:

```
null_resource.wait_for_deployment (apply-time provisioner)
  → data.http.starter_pack_auth (depends_on null_resource)
  → data.http.starter_pack_workspace
  → data.http.starter_pack_deployment_status
  → locals chain → output
```

The `depends_on` defers all downstream values at plan time regardless of `override_data` or `override_resource`. These outputs simply cannot be unit-tested — they require integration testing with real infrastructure.

### Assertion Strategy

- **Deterministic outputs** (safe for `command = plan`): variable passthroughs (`output.corrino_admin_username`), locals derived from variables (`output.vcn_cidr`, `output.cluster_endpoint_visibility`), default values (`output.db_username`)
- **Provider-computed outputs** (need `command = apply`): anything downstream of resource creation, `depends_on` chains, or data source queries that involve provisioners
- **Variable validations**: use `expect_failures` — always works with `command = plan`

### Running the Tests

```bash
cd ai-accelerator-tf/

terraform test                                                    # all tests
terraform test -filter=tests/core_plan.tftest.hcl                 # core plan only
terraform test -filter=tests/core_validations.tftest.hcl          # validations only
terraform test -filter=tests/starter_pack_enterprise_rag.tftest.hcl  # single starter pack
```

Requires Terraform >= 1.7 (`mock_provider` support). Current `versions.tf` allows >= 1.5 — tests will fail on 1.5/1.6.
