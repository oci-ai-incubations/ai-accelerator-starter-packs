---
name: release-upgrade
description: Automated release upgrade process for AI Accelerator Starter Packs - updates version files, validates changes, and prepares for tagging
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, TodoWrite
argument-hint: [version]
---

# Release Upgrade

Automate the release upgrade process for AI Accelerator Starter Packs by updating all required version files and preparing for git tagging.

## Arguments

- `$0` - New version number in semantic versioning format (e.g., `v0.0.3`, `v1.0.0`, `v2.1.3`)

If no version is provided, ask the user for the new version number.

## Prerequisites

Before starting:
1. Ensure working directory is clean (`git status`)
2. Confirm on the correct branch (typically a feature branch, not `main`)
3. Ask user if they want to update `corrino_image_version` as well

## Steps

1. **Validate Version Format**
   - Must follow semantic versioning: `vMAJOR.MINOR.PATCH`
   - Must be higher than current version
   - Check current version from `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`

2. **Update Version Files** (all must be updated together):
   
   a. **AI_ACCELERATOR_STACK_VERSION**
      - Path: `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`
      - Update to new version

   b. **vars.tf**
      - Path: `ai-accelerator-tf/vars.tf`
      - Update `accelerator_pack_stack_version` default value
      - Optionally update `corrino_image_version` if requested

   c. **common_schema.yaml**
      - Path: `ai-accelerator-tf/schemas/common_schema.yaml`
      - Add new version to TOP of enum list
      - Update default to new version
      - Keep all previous versions for rollback capability

3. **Run Validation**
   - `cd ai-accelerator-tf && terraform fmt -check -recursive`
   - `terraform validate`
   - If schema was updated: `python3 create_final_schema.py --all` and run schema tests

4. **Display Summary**
   - Show all files that were updated
   - Display git diff of changes
   - Remind user of next steps

## Post-Update Steps (Manual)

After running this skill, the user should:

1. **Commit Changes**
   ```bash
   git add -A
   git commit -m "Release v<VERSION>"
   ```

2. **Create PR to main branch**

3. **After PR is merged, tag the release**
   ```bash
   git checkout main
   git pull
   git tag v<VERSION>
   git push origin v<VERSION>
   ```

4. **Create GitHub Release** (optional)
   - Include release notes
   - Document breaking changes
   - List new features and fixes

## Version Conventions

- **MAJOR**: Breaking changes requiring user action
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes and minor improvements

## Error Handling

- If any file update fails, stop and report the error
- If validation fails, show errors and suggest fixes
- Never proceed with partial updates - all files must be updated together