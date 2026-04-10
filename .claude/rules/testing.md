---
globs: ["ai-accelerator-tf/tests/**", "ai-accelerator-tf/schemas/tests/**"]
---

# Testing Rules

## Terraform Unit Tests

- **Version split:** ORM runs Terraform 1.5.7, but unit tests require >= 1.7 (for `mock_provider`). All Terraform code must stay 1.5-compatible — only the test harness uses 1.7+ features. The language constructs under test (locals, count, for_each, validations) behave identically across versions.
- Test files must be flat in `tests/` — Terraform does not recurse subdirectories.
- Every test file needs `override_data` blocks for: `home_region`, `ads`, `oracle_linux`.
- All providers are mocked with `mock_provider` blocks — no real infrastructure.
- Tests are plan-only (`command = plan`).
- See `ai-accelerator-tf/tests/RULES.md` for detailed guidelines.

## Schema Tests

- Schema assertions go in `schema_expectations.yaml`, not in Python test code.
- `conftest.py` auto-generates all schemas before tests run.
- See `ai-accelerator-tf/schemas/tests/RULES.md` for detailed guidelines.

## Integration Tests

- Always ask the user for PR-specific testing requirements before starting.
- Always ask the user which compartment they want to test in. For example, if Grant is testing, he will want to test in Grant-Compartment, but if Dennis is testing he will want to test in his compartment Dennis-Compartment. They should be able to tell you the comparment name, which you can find the compartment ocid for using the oci-cli tool or they will give you the compartment ocid directly.
- Always verify pods are Running and check Terraform outputs after apply.
- Always destroy infrastructure after testing is complete.
