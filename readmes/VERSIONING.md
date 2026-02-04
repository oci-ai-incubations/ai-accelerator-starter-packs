# Versioning Guide

This document explains how versioning works in AI Accelerator Starter Packs and how to release new versions.

## Overview

The stack uses semantic versioning (SemVer) in the format `vMAJOR.MINOR.PATCH` (e.g., `v0.0.1`).

- **MAJOR**: Breaking changes that require user action or are not backward compatible
- **MINOR**: New features or enhancements that are backward compatible
- **PATCH**: Bug fixes and minor improvements

## Version Files and Locations

Versioning is managed through several files that must be kept in sync:

| File | Purpose |
|------|---------|
| `AI_ACCELERATOR_STACK_VERSION` | Single source of truth for the current (stack) version |
| `vars.tf` | Default values for `accelerator_pack_stack_version` and `corrino_image_version` variables |


Also note: `corrino_image_version` controls the Corrino backend image tag (e.g., `1.0.11`), while `accelerator_pack_stack_version` is the starter-pack release (e.g., `v0.0.1`).
| `schemas/common_schema.yaml` | Enum list of available versions and default |
| `outputs.tf` | Exposes version as a Terraform output |

## How It Works

1. **Version File**: The `AI_ACCELERATOR_STACK_VERSION` file contains the current version string and is read by Terraform to expose the version as an output.

2. **User Selection**: Users can select a version from a dropdown in the "Advanced Options" section when deploying via OCI Resource Manager. This allows deploying older versions if needed.

3. **Output Display**: After deployment, the version is displayed in the "Version Info" output group.

## Releasing a New Version

When releasing a new version, update these files in order:

### Step 1: Update the Version File

Update `AI_ACCELERATOR_STACK_VERSION` with the new version:

```
v0.1.0
```

### Step 2: Update vars.tf

Update the default value in `vars.tf`:

```hcl
variable "accelerator_pack_stack_version" {
  default     = "v0.1.0"
  description = "Stack version for AI Accelerator Starter Packs"
}
```

### Step 3: Update the Schema

In `schemas/common_schema.yaml`, add the new version to the enum list and update the default:

```yaml
accelerator_pack_stack_version:
  title: "Stack Version"
  type: enum
  enum:
    - "v0.1.0"    # Add new version at the top
    - "v0.0.1"    # Keep previous versions for rollback capability
  default: "v0.1.0"  # Update default to new version
  required: true
  visible: true
```

## Best Practices

1. **Always add new versions to the top** of the enum list in the schema
2. **Keep previous versions** in the enum to allow rollback
3. **Update all files together** in a single commit
4. **Tag releases in git** to maintain clear version history
5. **Document changes** in release notes or changelog
