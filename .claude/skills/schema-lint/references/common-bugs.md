# Common Schema Bugs

## Bug 1: Variable Visible in Wrong Categories

**Symptom:** ORM UI shows raw variable names (e.g., `cuopt_frontend_admin_password`) in categories where they shouldn't appear (e.g., enterprise_rag_aiq).

**Root Cause:** Variable exists in `vars.tf` but is not listed in `common_schema.yaml` with `visible: false`. ORM displays ALL Terraform variables not controlled by the schema as raw form fields.

**Example (2026-03-30):** `cuopt_frontend_admin_password`, `cuopt_frontend_admin_username`, and `google_maps_api_key` were added to `vars.tf` in the cuOpt frontend PR. They were hidden via cuOpt-specific schema visibility conditions (`visible: { and: [cuopt_frontend_enabled] }`), but not added to `common_schema.yaml` with `visible: false`. This caused them to appear as raw fields in enterprise_rag, enterprise_rag_aiq, paas_rag, and vss stacks.

**Fix:** Add to `common_schema.yaml`:
```yaml
  cuopt_frontend_admin_username:
    type: string
    visible: false
  cuopt_frontend_admin_password:
    type: string
    visible: false
  google_maps_api_key:
    type: string
    visible: false
```

**Prevention:** The rule: every variable in `vars.tf` MUST have an entry in `common_schema.yaml` with `visible: false` unless it should be universally visible. Category-specific schemas then override with `visible: true` where needed.

## Bug 2: Required Variable Shown When Not Applicable

**Symptom:** ORM shows a "This variable is required" error for a field that shouldn't be needed in the current deployment mode.

**Root Cause:** Variable has `required: true` in the schema with no visibility condition. ORM enforces `required` even when the variable is irrelevant.

**Example:** `worker_node_availability_domain` marked as `required: true` in GPU pack schemas. When deploying with `existing_cluster_id` (app-only mode), no nodes are being created, but ORM still requires the AD field.

**Fix options:**
1. Make the field not visible when irrelevant (ORM doesn't enforce `required` on hidden fields)
2. Change `required: false` in schema, add a Terraform `validation` block that only enforces when applicable
3. Use ORM schema visibility conditions: `visible: { not: [existing_cluster_id] }`

## Bug 3: Variable Group References Nonexistent Variable

**Symptom:** ORM UI shows an empty or broken section.

**Root Cause:** A `variableGroups` entry lists a variable name that doesn't exist in the `variables` section.

**Fix:** Ensure every variable in a group is also defined in `variables:`.

## Bug 4: Schema Not Regenerated After vars.tf Change

**Symptom:** New variable appears as raw field even though it was added to common_schema.yaml.

**Root Cause:** `schema.yaml` (the generated file ORM reads) was not regenerated after editing the source YAML files. The zip contains a stale `schema.yaml`.

**Fix:** Always regenerate before zipping:
```bash
python3 create_final_schema.py --all
```

## Bug 5: Type Mismatch Between vars.tf and Schema

**Symptom:** ORM shows wrong input widget (e.g., text field instead of checkbox).

**Root Cause:** Variable type in `common_schema.yaml` doesn't match `vars.tf`. For example, `type: string` in schema but `type = bool` in Terraform.

**Fix:** Match types:
| Terraform type | Schema type |
|---------------|-------------|
| `string` | `string` |
| `bool` | `boolean` |
| `number` | `number` |
| `list(string)` | `array` with `items.type: string` |

## Prevention Checklist

When adding a new variable to `vars.tf`:

- [ ] Add to `common_schema.yaml` with `visible: false`
- [ ] If category-specific: add `visible: true` override in the relevant category schema(s)
- [ ] If universally visible: add to appropriate `variableGroups` and set `visible: true`
- [ ] Regenerate all schemas: `python3 create_final_schema.py --all`
- [ ] Run schema tests: `pytest ai-accelerator-tf/schemas/tests/ -v`
- [ ] Verify in generated schemas: `grep variable_name schemas/generated/*.yaml`
