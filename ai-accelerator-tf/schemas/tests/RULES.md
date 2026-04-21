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
    required_variables: [skin_cuopt_core, genai_region, my_new_variable]
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

### I hid a variable or output for a category (visible: false)

The variable/output exists in the schema but is hidden from the UI. Add it in the category schema (e.g. `cuopt_schema.yaml`) by using `visible: false`, then assert it in expectations:

```yaml
category_specific:
  cuopt:
    variable_properties:
      db_password:
        visible: false
    output_properties:
      db_username:
        visible: false
```

This is different from absent (`absent_variables` / `absent_outputs`): by using `visible: false`, the variable/output will still stay in the schema; it is just hidden. Use absent (`absent_variables` / `absent_outputs`) only when the variable/output must not exist in the schema at all for that starter pack category.

### I removed a variable (or output) from a starter pack category schema.yaml

Add it to `absent_variables` or `absent_outputs` so it does not come back in the schema.yaml for that specific starter pack category:

```yaml
category_specific:
  cuopt:
    absent_variables: [legacy_variable]
    absent_outputs: [deprecated_output]
```

Use this when you deliberately removed something and want a regression guard. It also applies when a variable/output would break or confuse a category if it ever appeared in the schema for that starter pack category (e.g. from a bad merge or common-schema change).

**Note:** Absent is not the same as `visible: false`. Absent means the variable/output must NOT exist in the schema at all. If you want a variable to exist but be hidden from the UI, add it in the category schema (e.g. `cuopt_schema.yaml`) and set `visible: false`. Use `variable_properties` / `output_properties` to assert that.

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

| Key                   | What it checks                                                                                                                                |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `required_outputs`    | These outputs must exist in this category                                                                                                     |
| `required_variables`  | These variables must exist in this category                                                                                                   |
| `absent_outputs`      | These outputs must NOT exist in this category. Use for regression (removed outputs) or to guard against category-inappropriate outputs.       |
| `absent_variables`    | These variables must NOT exist in this category. Use for regression (removed variables) or to guard against category-inappropriate variables. |
| `variable_properties` | For each variable, assert property values (visible, type, required, default, etc.)                                                            |
| `output_properties`   | For each output, assert property values (visible, type, title, etc.)                                                                          |

**What does "absent" mean?**  
Variables/outputs listed as absent must NOT exist in that category's schema at all. Two main use cases:

1. **Regression guard**: You removed a variable or output from a category. Adding it to absent ensures it does not reappear (e.g. after a merge or refactor).
2. **Category-inappropriate**: A variable or output would break or confuse a category if it appeared (e.g. cuOpt should not expose a DB variable). Absent catches it if a merge or common-schema change ever adds it.

**Absent vs. visible: false:** Absent means the variable/output does not exist in the schema. To hide something that exists (from common or the category schema), use `visible: false` in the category schema (e.g. `cuopt_schema.yaml`) and assert it with `variable_properties` or `output_properties`.

## When to Write Python

Only add new test methods in `test_schema_structure.py` when:

- The check involves cross-field logic (e.g. "if variable X is visible, then output Y must also be visible")
- The assertion cannot be expressed as a simple key/value match in YAML

For everything else, edit `schema_expectations.yaml`.
