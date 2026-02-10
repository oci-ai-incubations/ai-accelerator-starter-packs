# Schema Test Rules

## Quick Start

Run all schema tests from the repository root:

```bash
pytest ai-accelerator-tf/schemas/tests/ -v
```

Tests automatically generate schemas for all starter packs before running. No manual setup needed beyond `pip install -r requirements.txt`.

## Common Scenarios

### I added a new variable to a category schema

Add the variable name to `required_variables` for that category in `schema_expectations.yaml`:

```yaml
category_specific:
  cuopt:
    required_variables: [cuopt_frontend_enabled, genai_region, my_new_variable]
```

To also check its properties (type, visibility, etc.):

```yaml
category_specific:
  cuopt:
    variable_properties:
      my_new_variable:
        type: string
        visible: true
```

### I hid a variable for a category

Add a property check asserting `visible: false`:

```yaml
category_specific:
  cuopt:
    variable_properties:
      db_password:
        visible: false
```

### I removed a variable from a category

Add it to `absent_variables` to make sure it stays gone:

```yaml
category_specific:
  cuopt:
    absent_variables: [legacy_variable]
```

### I added a new output

For an output that should exist in all categories, add it to the global list:

```yaml
required_outputs:
  - starter_pack_url
  - my_new_output
```

For a category-specific output, add it under that category:

```yaml
category_specific:
  paas_rag:
    required_outputs: [autonomous_database_id, my_new_output]
```

To check output properties:

```yaml
category_specific:
  paas_rag:
    output_properties:
      my_new_output:
        type: string
        visible: true
```

### I added a new deployment size

Update `starter_pack_sizes` for the category:

```yaml
starter_pack_sizes:
  cuopt: [small, medium, large]
```

This must match the `enum` list in the category's `starter_pack_size` variable in its schema YAML.

### I added a new starter pack category

Full checklist:

1. Create `schemas/<category>_schema.yaml`
2. Add the category to `CATEGORIES` in `create_final_schema.py`
3. In `schema_expectations.yaml`:
   - Add `starter_pack_sizes.<category>` with the size list
   - Add `category_specific.<category>` with required/absent/property checks
4. Add the category string to each `@pytest.mark.parametrize("category", [...])` in `test_schema_structure.py`
5. Run `pytest ai-accelerator-tf/schemas/tests/ -v` to verify

## How It Works

Tests are **data-driven**. Most assertions are defined in `schema_expectations.yaml`, not in Python code. When you need a new check, edit the YAML file first.

| File                       | What it does                                          | When to edit                                       |
| -------------------------- | ----------------------------------------------------- | -------------------------------------------------- |
| `schema_expectations.yaml` | Defines what to assert for each category              | Almost always -- this is where you add tests       |
| `conftest.py`              | Runs `create_final_schema.py --all` and loads schemas | Rarely -- only if fixture behavior needs to change |
| `test_schema_structure.py` | Reads expectations and runs assertions                | Only when YAML cannot express the check you need   |

The test fixture runs `create_final_schema.py --all` once per session, generating merged schemas for all categories into `schemas/generated/`. Each test then validates these generated schemas.

## Reference: Assertion Keys in schema_expectations.yaml

**Global (apply to all categories):**

| Key                       | What it checks                                              |
| ------------------------- | ----------------------------------------------------------- |
| `required_top_level_keys` | Schema has these top-level keys (title, variables, etc.)    |
| `required_outputs`        | These outputs exist in every schema                         |
| `required_variables`      | These variables exist in every schema                       |
| `starter_pack_sizes`      | The `starter_pack_size` enum matches this list per category |

**Per-category (under `category_specific.<category>`):**

| Key                   | What it checks                                                                     |
| --------------------- | ---------------------------------------------------------------------------------- |
| `required_outputs`    | These outputs must exist in this category                                          |
| `required_variables`  | These variables must exist in this category                                        |
| `absent_outputs`      | These outputs must NOT exist in this category                                      |
| `absent_variables`    | These variables must NOT exist in this category                                    |
| `variable_properties` | For each variable, assert property values (visible, type, required, default, etc.) |
| `output_properties`   | For each output, assert property values (visible, type, title, etc.)               |

## When to Write Python

Only add new test methods in `test_schema_structure.py` when:

- The check involves cross-field logic (e.g. "if variable X is visible, then output Y must also be visible")
- The assertion cannot be expressed as a simple key/value match in YAML

For everything else, edit `schema_expectations.yaml`.
