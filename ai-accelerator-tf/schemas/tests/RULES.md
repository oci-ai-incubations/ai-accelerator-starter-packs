# Schema Test Rules and Conventions

Guidelines for writing and maintaining schema tests. These rules keep tests simple, maintainable, and self-explanatory.

## Test Structure

- **`conftest.py`**: Fixtures that run `create_final_schema.py --all` and load schemas, expectations, and meta schema.
- **`test_schema_structure.py`**: Core tests. Parametrized by category where appropriate.
- **`schema_expectations.yaml`**: Data-driven assertions. Edit this file to add or change schema checks.

## Adding New Assertions

**Prefer editing `schema_expectations.yaml` over adding Python code.**

### Global Assertions

Add to top-level keys:

- `required_outputs` / `required_variables` — must exist in every schema
- `starter_pack_sizes` — per-category enum values (must match `vars.tf`)

### Category-Specific Assertions

Add under `category_specific.<category>`:

- `required_outputs` / `required_variables` — must exist in this category
- `absent_outputs` / `absent_variables` — must NOT exist in this category
- `variable_properties` — property checks (e.g. `visible`, `type`, `required`)
- `output_properties` — property checks for outputs

Example:

```yaml
category_specific:
  my_category:
    required_outputs: [my_output]
    absent_variables: [legacy_var]
    variable_properties:
      my_var:
        visible: false
        type: string
```

## Adding a New Category

1. Create `schemas/<category>_schema.yaml`
2. Add category to `create_final_schema.py` `CATEGORIES` list
3. Add `starter_pack_sizes.<category>` in `schema_expectations.yaml`
4. Add `category_specific.<category>` with required/absent/property checks

## Conventions

- **Keep tests data-driven**: Use `schema_expectations.yaml` for assertions; avoid hardcoding in Python.
- **Parametrize by category**: Use `@pytest.mark.parametrize("category", [...])` for tests that run per category.
- **Simple property checks**: For `visible`, only plain booleans are asserted; complex `booleanStatement` (e.g. `eq: [...]`) is skipped.
- **Absent means key not in dict**: `absent_variables`/`absent_outputs` assert the key does not exist in `variables`/`outputs`.

## When to Add Python Tests

Add new test methods in `test_schema_structure.py` only when:

- The logic cannot be expressed in `schema_expectations.yaml`
- You need custom validation (e.g. cross-field checks)

## File Roles

| File                       | Purpose                                  |
| -------------------------- | ---------------------------------------- |
| `schema_expectations.yaml` | Edit to add/change assertions            |
| `conftest.py`              | Fixtures; rarely edit                    |
| `test_schema_structure.py` | Test logic; add test classes when needed |
