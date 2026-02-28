---
name: schema-gen
description: Generate OCI Resource Manager schema for a starter pack category.
user-invocable: true
allowed-tools: Bash, Read
argument-hint: [category|--all]
---

# Schema Generation

Generate the OCI Resource Manager UI schema by merging common base with category overrides.

## Arguments

- `$0` - Category (`paas_rag`, `cuopt`, `vss`, `enterprise_rag`) or `--all` for all categories

## Command

```bash
cd /Users/dkennetz/code/ai-accelerator
source venv/bin/activate
python3 create_final_schema.py -c $0
```

Or for all categories:
```bash
python3 create_final_schema.py --all
```

## Notes

- The generated `schema.yaml` is gitignored — always regenerate, never edit directly
- This also updates `starter_pack_category.auto.tfvars` with the selected category
- Schema files: `schemas/common_schema.yaml` (shared) + `schemas/<category>_schema.yaml` (overrides)
- Run schema tests after generation: `pytest ai-accelerator-tf/schemas/tests/ -v`
