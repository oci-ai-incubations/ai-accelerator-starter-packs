# Test Matrix Creation

Create a test matrix for the release so testers can validate all new features and baseline functionality.

## Inputs to Gather

1. Ask the user for all tasks/features completed in this release
2. Ask the user how many testers are available (assume all owners from [OWNERS.md](OWNERS.md) are testers)
3. Ask the user how many days are available for testing (use today's date as the start reference)

## Steps

1. **Collect commit history**
   - Find all commits between the previous release branch and this release branch
   - The previous release ended when its last feature branch merged into main
   - Exception: v0.0.3 used branch name `v0.0.3` instead of `release_v0.0.3`
   - Create a markdown file in the `release_test_matrix/` folder listing all commits

2. **Associate tasks to commits**
   - Match the user-provided tasks to commits from step 1
   - Look at PR descriptions for additional context
   - Update the markdown file with task-to-commit associations

3. **Build the test matrix**
   - Generate an xlsx file following the format in [TEST_MATRIX_FORMAT.md](TEST_MATRIX_FORMAT.md)
   - Place it in the `release_test_matrix/` folder

## Scheduling Rules

- Spread testing days evenly to minimize concurrent GPU usage
- Check GPU footprints in `ai-accelerator-tf/vars.tf` (`local.starter_pack_configs`) when scheduling
- Target max ~16 A100 GPUs deployed on any single day
- Assign testers so nobody tests their own pack (see [OWNERS.md](OWNERS.md))

## Baseline Tests (every pack must include)

- Fresh deploy with static subdomains
- Re-apply with no changes (idempotent)
- Re-apply with a config change
- Bastion enabled (deploy + SSH verification)
- Bastion disabled (verify no bastion in plan)
- End-of-day destroy + clean teardown verification
