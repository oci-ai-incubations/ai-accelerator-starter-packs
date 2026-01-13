# Schema Customization System

This directory contains modular schema files for customizing the OCI Resource Manager UI for each starter pack category.

## Architecture

```
ai-accelerator-tf/
├── schemas/
│   ├── common_schema.yaml      # Base schema (shared definitions)
│   ├── cuopt_schema.yaml       # cuOpt-specific overrides
│   ├── vss_schema.yaml         # VSS-specific overrides
│   ├── paas_rag_schema.yaml    # PaaS RAG-specific overrides
│   └── README.md               # This file
├── schema.yaml                 # AUTO-GENERATED (do not edit directly)
├── starter_pack_category.auto.tfvars
└── ...

create_final_schema.py          # Merge script (in parent directory)
requirements.txt                # Python dependencies
```

## How It Works

1. **`common_schema.yaml`** contains all shared definitions:

   - Hidden variables
   - Common outputs with proper types (`type: link`, `type: ocid`)
   - Base variable groups structure
   - Admin credential variables
   - `primaryOutputButton` setting

2. **Category schemas** (`cuopt_schema.yaml`, etc.) contain **only overrides**:

   - Custom `title`, `description`, `informationalText`
   - Category-specific `starter_pack_size` enum and description
   - Modified `outputGroups` (e.g., hide database for cuopt/vss)
   - Modified `variableGroups` (e.g., hide database section)
   - Custom output titles (e.g., "Open cuOpt Service")

3. **`create_final_schema.py`** deep-merges the common schema with the selected category schema to generate `schema.yaml`.

## Generating schema.yaml

### Prerequisites

```bash
# From the repository root
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Generate Schema

```bash
# Uses category from starter_pack_category.auto.tfvars
python create_final_schema.py

# Or specify category directly
python create_final_schema.py cuopt
python create_final_schema.py vss
python create_final_schema.py paas_rag
```

## Common Modifications

### Add a New Size to a Category

Edit the category schema (e.g., `cuopt_schema.yaml`):

```yaml
variables:
  starter_pack_size:
    type: enum
    enum:
      - small
      - medium
      - large # Add new size
    description: "<strong>SMALL</strong> - specs | <strong>MEDIUM</strong> - specs | <strong>LARGE</strong> - new specs"
```

Then regenerate:

```bash
python create_final_schema.py cuopt
```

### Add a New Hidden Variable

Edit `common_schema.yaml`:

```yaml
variables:
  # Add to the hidden variables section
  my_new_variable:
    type: string
    visible: false
```

### Change Output Formatting

Edit `common_schema.yaml` for shared outputs, or category schema for specific outputs:

```yaml
outputs:
  my_url_output:
    type: link # Makes it a clickable link
    title: "My Service"
    displayText: "Open My Service" # Button text
    visible: true
```

### Hide Database Section for a New Category

Copy from `cuopt_schema.yaml` or `vss_schema.yaml`:

```yaml
# Remove database from outputGroups
outputGroups:
  - title: "Service"
    outputs: [...]
  - title: "Management & API"
    outputs: [...]
  - title: "Monitoring"
    outputs: [...]
  # No database group

# Remove database from variableGroups
variableGroups:
  - title: "Basic Hidden"
    variables: [...]
    visible: false
  - title: "Deployment Configuration"
    variables: [starter_pack_size]
  - title: "Administrator Account"
    variables: [...]
  # No database group

# Hide database variables
variables:
  db_username:
    visible: false
  db_password:
    visible: false

# Hide database outputs
outputs:
  db_username:
    visible: false
  db_password:
    visible: false
  autonomous_database_name:
    visible: false
  autonomous_database_id:
    visible: false
```

### Add a New Starter Pack Category

1. Create `schemas/newpack_schema.yaml`:

```yaml
title: "My New Starter Pack"
description: "Short description"
informationalText: |
  Longer description with details.

outputGroups:
  - title: "New Pack Service"
    outputs:
      - starter_pack_url
      - starter_pack_deployment_name
  # ... rest of groups

variables:
  starter_pack_size:
    type: enum
    enum:
      - small
    title: "New Pack Deployment Size"
    description: "<strong>SMALL</strong> - infrastructure specs"
    default: small
    required: true

outputs:
  starter_pack_url:
    type: link
    title: "Open New Pack Service"
    displayText: "Open New Pack Service"
```

2. Update `starter_pack_category.auto.tfvars`:

```hcl
starter_pack_category = "newpack"
```

3. Generate:

```bash
python create_final_schema.py newpack
```

## Schema Features Reference

### Variable Types

- `string` - Text input
- `password` - Masked password input
- `boolean` - Checkbox
- `integer` / `number` - Numeric input
- `enum` - Dropdown selection
- `oci:identity:compartment:id` - OCI compartment picker

### Output Types

- `string` - Plain text
- `link` - Clickable hyperlink (use with `displayText`)
- `ocid` - Auto-links to OCI console resource
- `csv` - Comma-separated list
- `password` - Masked value

### HTML Formatting in Descriptions

```yaml
description: "<strong>Bold</strong> and <em>italic</em> and <a href='url'>link</a>"
```

### Validation

```yaml
variables:
  username:
    type: string
    minLength: 3
    maxLength: 50
    pattern: "^[a-z][a-zA-Z0-9]+$"
    required: true
```

## Troubleshooting

### Schema not updating?

- Make sure you regenerated: `python create_final_schema.py`
- Check that `schema.yaml` header shows correct category

### Variable not showing in UI?

- Check `visible: false` isn't set
- Verify variable is in a `variableGroups` section

### Output not showing?

- Check `visible: true` is set
- Verify output is in an `outputGroups` section

## Files Overview

| File                     | Purpose            | Edit?                 |
| ------------------------ | ------------------ | --------------------- |
| `common_schema.yaml`     | Shared definitions | ✅ For common changes |
| `cuopt_schema.yaml`      | cuOpt overrides    | ✅ For cuOpt-specific |
| `vss_schema.yaml`        | VSS overrides      | ✅ For VSS-specific   |
| `paas_rag_schema.yaml`   | RAG overrides      | ✅ For RAG-specific   |
| `schema.yaml`            | Generated output   | ❌ Auto-generated     |
| `create_final_schema.py` | Merge script       | ⚠️ Rarely needed      |
