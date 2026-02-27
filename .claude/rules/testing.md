# Testing Rules

## Terraform Unit Tests
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
- The compartment for test stacks is `ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3grdiqzvz244gwzycpfl2ctlb4nvl7vi7wu55tqi375a`.
- Always verify pods are Running and check Terraform outputs after apply.
- Always destroy infrastructure after testing is complete.
