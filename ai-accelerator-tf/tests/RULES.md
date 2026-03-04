# Terraform Unit Test Rules

These are **unit tests** that run `terraform plan` with mock providers. No cloud credentials are needed and no infrastructure is created. They validate variable validations, output values, locals, and deterministic resource attributes.

Integration tests that deploy real infrastructure and validate end-to-end behavior will be added in a future iteration.

## Do I Need a Test?

**Changes that NEED a unit test:**

- Added a variable with a `validation {}` block -- test that invalid values are rejected
- Added or changed an `output {}` block that is deterministic at plan time (variable passthrough, local, default)
- Added a new starter pack category -- test it plans successfully with correct deployment name
- Added a new starter pack size -- test it plans successfully
- Changed `locals` logic that affects outputs (e.g. networking CIDRs, endpoint visibility)
- Changed default values for variables -- verify the defaults flow through to outputs

**Changes that DO NOT need a unit test:**

- Added a new resource without new `validation {}` blocks on variables or new `output {}` blocks -- no new test needed because `plan_succeeds_with_defaults` already verifies the entire config plans successfully
- Changed Helm chart values or configmap content (not testable at plan time)
- Changed `local-exec` provisioner scripts (runs at apply time only)
- Changed outputs that depend on dynamic URLs / `data.http` / `depends_on` chains (not testable at plan time)
- Documentation-only changes (README, comments)
- Schema-only changes (tested separately -- see `schemas/tests/`)

## Quick Start

```bash
cd ai-accelerator-tf/
terraform test                                                         # all tests
terraform test -filter=tests/core_plan.tftest.hcl                      # one file
terraform test -filter=tests/starter_pack_cuopt.tftest.hcl             # one starter pack
```

**Note:** The main module targets Terraform 1.5 for OCI Resource Manager compatibility (`required_version = ">= 1.5"` in `versions.tf`). However, tests require **Terraform >= 1.7** locally because `mock_provider` is a 1.7+ feature. Run tests with a local Terraform install, not through OCI Resource Manager.

## Common Scenarios

### I added a new variable with a validation block

Add a `run` block in `core_validations.tftest.hcl`. Override exactly one variable to an invalid value, and list it in `expect_failures`:

```hcl
# Test: invalid network_configuration_mode values are rejected by input validation
run "rejects_invalid_network_mode" {
  command = plan

  variables {
    network_configuration_mode = "invalid"
  }

  expect_failures = [var.network_configuration_mode]
}
```

### I added a new output

Add an `assert` block inside a `run` block in the relevant test file. For outputs shared across all packs, add to `core_plan.tftest.hcl`:

```hcl
# Inside run "plan_succeeds_with_defaults"
assert {
  condition     = output.my_new_output == "expected_value"
  error_message = "my_new_output should match expected value"
}
```

For a starter-pack-specific output, add the assert to that pack's test file (e.g. `starter_pack_cuopt.tftest.hcl`).

### I added a new starter pack category

Create a new file `tests/starter_pack_<category>.tftest.hcl`. Copy the boilerplate from an existing file (see [Boilerplate Reference](#boilerplate-reference) below), then change:

1. Set `starter_pack_category` in the `variables` block
2. Add a `run` block asserting on deployment name and postflight triggers:

```hcl
# Test: my_pack starter pack plans successfully with correct deployment name
run "plan_my_pack_small" {
  command = plan

  assert {
    condition     = output.starter_pack_deployment_name == "my-pack"
    error_message = "my_pack deployment name should be 'my-pack'"
  }

  assert {
    condition     = null_resource.postflight_registration.triggers.starter_pack_category == "my_pack"
    error_message = "postflight trigger should capture starter pack category"
  }

  assert {
    condition     = null_resource.postflight_registration.triggers.region == "us-ashburn-1"
    error_message = "postflight trigger should capture region"
  }
}
```

### I added a new starter pack size

Add a new `run` block in the existing starter pack test file. Override `starter_pack_size` and assert on the same deterministic values:

```hcl
# Test: cuopt medium size plans successfully
run "plan_cuopt_medium" {
  command = plan

  variables {
    starter_pack_size = "medium"
  }

  assert {
    condition     = output.starter_pack_deployment_name == "cuopt"
    error_message = "cuopt medium deployment name should be 'cuopt'"
  }

  assert {
    condition     = null_resource.postflight_registration.triggers.starter_pack_category == "cuopt"
    error_message = "postflight trigger should capture starter pack category"
  }
}
```

### I added a new URL output for a starter pack

It depends on whether the URL is **static** or **dynamic**:

- **Static URL** (like `enterprise_rag`, where `blueprint_file == ""`): The URL is computed from variables/locals at plan time. You can assert on it directly:

```hcl
assert {
  condition     = output.my_service_url != ""
  error_message = "my_service_url should be set"
}
```

- **Dynamic URL** (like `cuopt`, `vss`, `paas_rag`, where `blueprint_file != ""`): The URL flows through `null_resource` provisioners and `data.http` calls that only resolve at apply time. **You cannot unit-test dynamic URLs.** Instead, assert on deterministic values like deployment name and postflight triggers (see examples above).

If you add a new output in `outputs.tf`, also add it to the schema -- see [schemas/tests/RULES.md](../schemas/tests/RULES.md) for schema test instructions.

### I added a new OCI data source indexed with `[0]`

If your code does something like `data.oci_my_resource.foo.items[0].id`, mock providers return empty lists by default and the plan will fail. Add an `override_data` block inside `mock_provider "oci"` in **every** test file:

```hcl
mock_provider "oci" {
  # ... existing overrides ...

  override_data {
    target = data.oci_my_resource.foo
    values = {
      items = [{
        id = "ocid1.myresource.oc1..test"
      }]
    }
  }
}
```

### I need to use a new Terraform provider

Add a `mock_provider` line in **every** test file:

```hcl
mock_provider "my_new_provider" {}
```

## What CAN and CANNOT Be Tested

All tests use `command = plan` -- no infrastructure is created.

**Safe to assert at plan time:**

- Variable passthroughs (e.g. `output.corrino_admin_username`)
- Locals derived from variables (e.g. `output.vcn_cidr`, `output.cluster_endpoint_visibility`)
- Default values (e.g. `output.db_username`)
- Resource attributes computed from variables (e.g. `null_resource.postflight_registration.triggers`)

**NOT unit-testable (requires apply with real infrastructure):**

- Outputs downstream of `null_resource` provisioners with `local-exec`
- Dynamic URLs that flow through `depends_on` chains and `data.http` calls
- Any output that depends on actual cloud API responses

**Why no `command = apply`?** Mock providers do not prevent `local-exec` provisioners from running real shell commands. Using `apply` would attempt real `curl` calls and file operations.

## Boilerplate Reference

Every test file needs this boilerplate. Copy it as a starting point:

```hcl
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
  starter_pack_category           = "enterprise_rag"   # change per test file
  worker_node_availability_domain = "US-ASHBURN-AD-1"
  skip_capacity_check             = true
}
```

## Conventions

- **File extension**: `.tftest.hcl`
- **Location**: Flat in `tests/` (no subdirectories -- `terraform test` does not recurse)
- **File naming**: `core_*.tftest.hcl` for shared behavior, `starter_pack_<category>.tftest.hcl` for per-pack tests
- **Run block naming**: `plan_succeeds_with_defaults`, `rejects_invalid_*`, `plan_<category>_<size>`
- **Comment before every run block**: `# Test: <what this validates>`
- **One concern per run block**: Each run block tests one thing
- **Validation tests**: Override exactly one variable per run block, use `expect_failures`
