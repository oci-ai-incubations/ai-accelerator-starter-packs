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
2. Confirm on the correct branch (the pattern for the release feature branch is release_v<release_version> such as release_v0.0.4 or release_v0.0.2, not `main`). If we are not on the correct release branch, then look for it. If you cannot find it, create the release branch from latest main.
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
   - make sure to delete all .terraform files that are leftover from testing as this causes ERRORS

4. **Display Summary**
   - Show all files that were updated
   - Display git diff of changes
   - Remind user of next steps

5. **Push Release Branch**
   - Once the user has confirmed everything looks correct, add all commits and push the release branch
     ```bash
     git add -A
     git commit -m "Release v<VERSION>"
     ```

6. **Create Testing Matrix**
   - Ask the user for all the tasks that were completed for this release
   - Ask the user how many testers are going to be testing
   - Assume all the owners will be testers (see ``ACCELERATOR PACK OWNERS` below)
   - Ask the user what today is and how many days we have to do testing (spreading the testing across all the days)
   - Once you have all the tasks for this release from the user, proceed.
   - Look at all commits from this release branch and the previous release branch, including all descriptions of associated pull requests
   - Create a markdown file containing all the commits from the previous release to this release and put in the `release_test_matrix` folder
   - Note: you can tell where the other release ended by looking at when the last feature branch for that release was merged into main (exception is that the v0.0.3 release named it's branch as `v0.0.3` instead of following the right pattern of `release_v0.0.3` ).
   - Once You have found all the commits between the last release and the current release and the markdown is created and in `release_test_matrix` folder, look through all the tasks and try to associate tasks to commmits
   - Update the markdown file in `release_test_matrix` to associate the commits with tasks
   - Review the markdown and come up with a test matrix excel file (see example in `release_test_matrix/example_test_matrix_excel_file.xlsx` to copy this format exactly).
   - Note: You want to make sure there is one tester per accelerator ("starter") pack and that it is not the same as the person who "owns" the starter pack - see the owners at the bottom of this markdown under `ACCELERATOR PACK OWNERS`. Sometimes you cannot make this requirement work so try your best.
   - Note: The goal is to make sure that all new features and functionality as well as the basic accelerator pack functionality works and is tested before we release
   - Note: Make sure that the days for testing are spread evenly so that we minimize the number of GPUs deployed for testing in one day. Look at the `ai-accelerator-tf/vars.tf` for the CPU and GPU footprint of eachs starter pack when figuring this out.
   - Once you have created and uploaded the test matrix that looks similar to the example in `release_test_matrix/example_test_matrix_excel_file.xlsx`, then proceed to the next step.

7. **Create Zip files**
   - For each accelerator pack:
     - Create schema: `python3 create_final_schema.py <starter_pack>`
     - Review the code to make sure NO PERSONAL INFORMATION is found in the
       `ai-accelerator-tf` folder
     - (MAKE SURE THERE IS NO .terraform or terraform lock files before zipping as this causes errors)
     - Zip the `ai-accelerator-tf` folder and name it `<release>_<starter_pack_name>.zip` and put in the `release_test_matrix` folder in this repo
     - Continue to next starter pack, stopping when all starter packs have been zipped and put into the `release_test_matrix` folder

## Version Conventions

- **MAJOR**: Breaking changes requiring user action
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes and minor improvements

## Error Handling

- If any file update fails, stop and report the error
- If validation fails, show errors and suggest fixes
- Never proceed with partial updates - all files must be updated together

##ACCELERATOR PACK OWNERS

Sanjana and Grant - VSS
Dennis - CuOpt
Ritika - Enterprise RAG and Enterprise RAG AIQ
Rob - paas_Rag
