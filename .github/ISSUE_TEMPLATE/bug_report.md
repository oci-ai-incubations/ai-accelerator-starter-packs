---
name: Bug report
about: Report a reproducible bug in the AI Accelerator Starter Packs
title: '[BUG] '
labels: bug
assignees: ''
---

## Description

A clear and concise description of the bug.

## Starter Pack

Which starter pack and size are you using?

- Pack: <!-- cuopt / vss / paas_rag / enterprise_rag / enterprise_rag_aiq -->
- Size: <!-- small / medium -->
- Stack version: <!-- from `terraform output stack_version` or AI_ACCELERATOR_STACK_VERSION file -->

## Deployment Method

- [ ] OCI Resource Manager (Console)
- [ ] Terraform CLI

## OCI Region

<!-- e.g., us-ashburn-1 -->

## Steps to Reproduce

1.
2.
3.

## Expected Behavior

What did you expect to happen?

## Actual Behavior

What actually happened?

## Error Output

```
Paste any error messages, Terraform output, or kubectl logs here.
```

## Console fields or terraform.tfvars (sanitized)

Paste your configuration with **all secrets removed** (replace API keys, passwords, and OCIDs with placeholder values):

```hcl
# Example:
# tenancy_ocid     = "ocid1.tenancy.oc1..REDACTED"
# starter_pack_category = "cuopt"
```

## Additional Context

Any other context, screenshots, or information that might help.
