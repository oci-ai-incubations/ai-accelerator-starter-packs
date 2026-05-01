# Release Build

Build steps for cutting a new release version. Called by the releasing skill — VERSION is passed from the calling skill.

## Arguments

- `VERSION` — New version in semver format (e.g., `v0.0.5`). Provided by the calling skill; if missing, ask the user.

## Step 1: Prerequisites

1. Ensure working directory is clean (`git status`). If there are uncommitted changes, stop and ask the user.
2. Read the current version from `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`.
3. Ask the user if they also want to update `corrino_image_version` in `vars.tf`.

## Step 2: Create Release Branch

Create the release branch before making any file changes so all edits happen on the correct branch.

```bash
git fetch origin main
git checkout -b release_v<VERSION> origin/main
```

If the branch already exists locally or on the remote, check it out instead:

```bash
git checkout release_v<VERSION>
git pull origin release_v<VERSION>
```

## Step 3: Validate Version Format

- Must match `vMAJOR.MINOR.PATCH` (e.g., `v0.0.5`, `v1.2.0`)
- Split both old and new versions on `.` after stripping the `v` prefix
- Compare MAJOR, then MINOR, then PATCH as integers
- New version must be strictly higher than the current version

If the version is invalid or not higher, stop and report the error.

## Step 4: Update Version Files

All three files must be updated together — never proceed with partial updates.

**a. `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`**
- Replace the entire file contents with the new version string

**b. `ai-accelerator-tf/vars.tf`**
- Update the `accelerator_pack_stack_version` variable's default value to the new version
- If the user requested it in Step 1, also update `corrino_image_version`

**c. `ai-accelerator-tf/schemas/common_schema.yaml`**
- Add the new version to the **top** of the `accelerator_pack_stack_version` enum list
- Update the default to the new version
- Keep all previous versions in the enum for rollback capability

## Step 5: Validate

Run validation with a feedback loop — fix and retry until all checks pass:

```bash
cd ai-accelerator-tf
terraform fmt -recursive
terraform validate
```

Regenerate schemas and run schema tests:

```bash
cd ai-accelerator-tf/schemas
python3 create_final_schema.py --all
cd ..
pytest schemas/tests/ -v
```

Clean build artifacts after validation:

```bash
find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null
rm -f .terraform.lock.hcl
```

If any validation step fails, fix the issues and re-run from the top of this step. Only proceed when everything passes.

Sync SOFTWARE_VERSIONS.md with current container images:

Invoke `/sync-versions` to update `SOFTWARE_VERSIONS.md` with the latest container image versions from `blueprint_files.tf`. This ensures the versions doc ships current with the release. If changes are found, they will appear in the git diff at Step 6.

## Step 6: Display Summary

- List all files that were modified
- Show `git diff` of the changes
- Ask the user to review and confirm before proceeding

## Step 7: Commit and Push

After user confirmation:

```bash
git add ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION \
       ai-accelerator-tf/vars.tf \
       ai-accelerator-tf/schemas/common_schema.yaml \
       SOFTWARE_VERSIONS.md
git commit -m "Release <VERSION>"
git push -u origin release_v<VERSION>
```

## Step 8: Create Per-Pack Zips

For each of the 7 starter pack categories (`enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`, `warehouse_pick_path`, `dox_pack`):

1. Set the category in `ai-accelerator-tf/starter_pack_category.auto.tfvars`:
   ```
   starter_pack_category = "<category>"
   ```

2. Regenerate the ORM schema for that category:
   ```bash
   cd ai-accelerator-tf/schemas
   python3 create_final_schema.py <category>
   ```

3. Invoke `/zip-tf release_test_matrix <VERSION>_<category>` to create the zip.

After all 5 zips are created, verify:

```bash
ls -la release_test_matrix/
# Expect: <VERSION>_enterprise_rag.zip, <VERSION>_enterprise_rag_aiq.zip,
#         <VERSION>_paas_rag.zip, <VERSION>_cuopt.zip, <VERSION>_vss.zip,
#         <VERSION>_warehouse_pick_path.zip, <VERSION>_dox_pack.zip
```

If any zip is missing, stop and investigate before proceeding.

---

## Version Conventions

- **MAJOR**: Breaking changes requiring user action
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes and minor improvements

## Error Handling

- If any file update fails, stop and report the error
- If validation fails, show errors and suggest fixes
- Never proceed with partial updates — all three version files must be updated together
- If branch creation fails (e.g., branch already exists), check it out and verify it is up to date with main
- If `/zip-tf` fails for a category, check the schema generation output and retry
