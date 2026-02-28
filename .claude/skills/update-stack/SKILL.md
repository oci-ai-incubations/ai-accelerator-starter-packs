---
name: update-stack
description: Rebuild zip and update an existing ORM stack with latest code changes, then re-plan.
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: [stack-id]
---

# Update Stack

Rebuild the deployment zip from current code and update an existing ORM stack.

## Arguments

- `$0` - ORM stack OCID (if not provided, list active stacks and ask user to select)

## Steps

1. Regenerate schema for current category:
   ```bash
   cd /Users/dkennetz/code/ai-accelerator
   source venv/bin/activate
   python3 create_final_schema.py -c $(cat ai-accelerator-tf/starter_pack_category.auto.tfvars | grep -oP '(?<=")\w+(?=")')
   ```

2. Clean and create zip:
   ```bash
   rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
   rm -f lifecycle.zip
   cd ai-accelerator-tf && zip -r /Users/dkennetz/code/ai-accelerator/lifecycle.zip . -x '.terraform/*' '.terraform.lock.hcl'
   ```

3. Update stack:
   ```bash
   export OCI_CLI_PROFILE=SANJOSE
   oci resource-manager stack update --stack-id $0 --config-source /Users/dkennetz/code/ai-accelerator/lifecycle.zip --force
   ```

4. Run plan job and poll until completion

5. Report plan results to user
