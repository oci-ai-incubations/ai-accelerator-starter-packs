# Test Matrix Excel Format

Generate an `.xlsx` file matching this structure exactly. See `release_test_matrix/example_test_matrix_excel_file.xlsx` for a concrete example.

## Sheet Layout (single sheet)

### Row 1: Title
`v<VERSION> Test Matrix & Schedule`

### Row 2: Summary
`Testing window: <start date> – <end date>  |  Rule: No tester works on their own pack`

### Per-Pack Test Sections

For each starter pack, create a block:

**Header row** (merged across columns A-H):
`<pack_name>  —  Tester: <name>  |  Owner: <name>  |  <Day N (Day Date)>  |  <GPU shape> | <GPU count> | ~<deploy time>`

**Column headers:**
| Column | Header |
|---|---|
| A | # |
| B | Pack |
| C | Testing Day |
| D | Tester |
| E | Test Case |
| F | Related Task |
| G | Test Steps |
| H | Pass/Fail |
| I | (optional notes) |

**Test rows:** One row per test case with sequential numbering starting at 1 per pack.

**Footer row:** `End of day: Destroy all <pack_name> infrastructure. Verify clean teardown.`

### Summary Tables (after all pack sections)

1. **Infrastructure Requirements** — columns: Pack, GPU Shape, GPU Nodes, Total GPUs, CPU Flex Nodes, ADB, Deploy Time
2. **GPU Usage by Day** — columns: Day, Packs, BM.GPU4.8 Nodes, Total A100 GPUs
3. **Tester Assignments** — columns: Pack, Owner(s), Assigned Tester, Testing Day
4. **Test Coverage Summary** — columns: Pack, Tester, Day, Tests, Key Test Areas (with total row)
5. **Coverage by Task** — columns: Task, Packs Tested, Test Count
6. **Pre-Test Checklist** — checkboxes for: ORM zips generated, tfvars populated, unit tests pass, schema tests pass, lint passes, testers have OCI access, version updated

## Rules

- GPU footprints per pack are in `ai-accelerator-tf/vars.tf` under `local.starter_pack_configs`
- Spread testing days to minimize concurrent GPU usage (max ~16 A100 GPUs per day)
- No tester tests their own pack (cross-assign using [OWNERS.md](OWNERS.md))
- Every pack must include: fresh deploy, re-apply (no change + with change), bastion on/off
- Add pack-specific tests for new features from the release commits
