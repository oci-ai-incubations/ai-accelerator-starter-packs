# Terraform Test Rules

Rules to follow when adding or updating tests in `ai-accelerator-tf/tests/`. See [readmes/TESTING.md](../../readmes/TESTING.md) for detailed mechanics and rationale.

## 1. File Naming and Layout

- File extension: `.tftest.hcl`
- Location: flat in `tests/` (no subdirectories — `terraform test` does not recurse)
- Naming: `core_*.tftest.hcl` for core behavior, `starter_pack_<category>.tftest.hcl` for starter pack-specific tests

## 2. Required Mock Providers

Every test file must declare all providers used by the Terraform config. Use `mock_provider` for unit tests:

- `oci` (with required `override_data` blocks — see below)
- `kubernetes`, `helm`, `tls`, `local`, `null`, `cloudinit`, `random`, `http`

## 3. OCI Data Source Overrides

The config indexes into these OCI data sources with `[0]`. Mock providers return empty lists by default, so each test file must include:

```hcl
mock_provider "oci" {
  override_data {
    target = data.oci_identity_regions.home_region
    values = { regions = [{ name = "us-ashburn-1", key = "IAD" }] }
  }
  override_data {
    target = data.oci_identity_availability_domains.ads
    values = { availability_domains = [{ name = "US-ASHBURN-AD-1" }] }
  }
  override_data {
    target = data.oci_core_images.oracle_linux
    values = { images = [{ id = "ocid1.image.oc1..test" }] }
  }
}
```

## 4. File-Level Variables

Use a consistent base `variables` block so plan succeeds. Required variables include:

- `tenancy_ocid`, `compartment_ocid`, `region`, `current_user_ocid`
- `corrino_admin_username`, `corrino_admin_password`, `corrino_admin_email`
- `starter_pack_category` (set per test focus)
- `worker_node_availability_domain` = `"US-ASHBURN-AD-1"`
- `skip_capacity_check` = `true`

## 5. Command: Always `command = plan`

- Use `command = plan` for all unit tests — no `command = apply`
- `local-exec` provisioners run real shell commands during apply; mock providers do not prevent that
- Outputs that depend on `depends_on` chains through apply-time resources (e.g., `output.starter_pack_url` for dynamic URL starter packs) cannot be unit-tested

## 6. Assertion Strategy

- **Safe to assert at plan time**: variable passthroughs, locals from variables, default values, resource attributes computed from variables
- **Not unit-testable**: outputs downstream of `null_resource` provisioners, `depends_on` chains involving HTTP data sources
- **Variable validations**: use `expect_failures` — override one variable to an invalid value, list the variable in `expect_failures`

## 7. Run Block Conventions

- **Comment above each run block**: Add a `# Test: <description>` comment immediately before every `run` block describing what the test validates (e.g., `# Test: invalid network_configuration_mode values are rejected by input validation`)
- Descriptive run names: `plan_succeeds_with_defaults`, `rejects_invalid_*`, `plan_<starter_pack>_small`
- One concern per run block
- For validation tests: override exactly one variable per run block and use `expect_failures`

Example:

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

## 8. Starter Pack Tests

- Static URL packs (e.g., `enterprise_rag`): mock providers suffice
- Dynamic URL packs (e.g., `cuopt`, `vss`, `paas_rag`): do not assert on `output.starter_pack_url` — only assert on deterministic outputs (deployment name, postflight triggers)
