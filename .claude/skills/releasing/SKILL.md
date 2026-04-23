---
name: releasing
description: End-to-end release lifecycle orchestrator — builds the release (version bump, validate, per-pack zips), creates a GitHub Release, plans and executes parallel testing across GPU tracks using agent teams and /testing-pack, handles the bug-fix-rebuild loop, and finalizes (validate zips, Slack announcement, merge PR, tag). Use when cutting a new release, the user says "do a release", "release v0.0.X", or "run the full release process".
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion, TaskCreate, TaskUpdate, TaskGet, TaskList, Skill, TeamCreate, SendMessage
argument-hint: [version]
---

# Releasing

Full release lifecycle: build, publish, test, fix, finalize. Delegates to existing skills where they cover the work; fills gaps for GitHub Release creation, parallel test orchestration, and post-fix rebuild.

## Arguments

- `$0` — Version in semver format (e.g., `v0.0.5`). If not provided, ask the user.

## Skill Delegation Map

| Phase | Delegates to | What it covers |
|---|---|---|
| 1: Build | [RELEASE_BUILD.md](RELEASE_BUILD.md) | Branch, version bump, validate, schema gen/test, zip, commit, push |
| 2: GitHub Release | *(this skill)* | `gh release create` with per-pack zip assets |
| 3: Plan Testing | `/checking-capacity` | GPU capacity + quota per track |
| 4: Execute Testing | `/testing-pack` (via agent teams) | Per-pack two-stack deploy + smoke tests |
| 5: Fix & Rebuild | *(this skill)* + /zip-tf | Bug fix loop, rebuild zips, re-upload assets |
| 6: Finalize | [RELEASE_PUBLISH.md](RELEASE_PUBLISH.md) | Validate zips, Slack announcement, merge PR, tag |

---

## Phase 1: Build Release

Read and follow [RELEASE_BUILD.md](RELEASE_BUILD.md). This handles:
branch creation, version bump, validation, schema gen/tests, commit, push, and per-pack zip creation via `/zip-tf`.

**After build completes**, verify:

```bash
ls -la release_test_matrix/
# Expect: <version>_enterprise_rag.zip, <version>_enterprise_rag_aiq.zip,
#         <version>_paas_rag.zip, <version>_cuopt.zip, <version>_vss.zip,
#         <version>_warehouse_pick_path.zip, <version>_contract_analysis.zip
```

If any zip is missing, stop and investigate.

### 1b. Create Release PR

Create the PR immediately after building. This PR becomes the **testing workspace** — agents post progress and results here throughout the release.

```bash
PR_NUMBER=$(gh pr create --base main --head release_v${VERSION} \
  --title "Release ${VERSION}" \
  --body "$(cat <<'PREOF'
## Release ${VERSION}

Testing workspace — agents will post progress and results below.

### Checklist
- [ ] Build complete
- [ ] GitHub Release created (pre-release)
- [ ] Testing planned
- [ ] All packs tested
- [ ] Bugs fixed (if needed)
- [ ] Release finalized
PREOF
)" --json number --jq '.number')
echo "PR #${PR_NUMBER} created"
```

Record `PR_NUMBER` for use in Phase 4.

---

## Phase 2: Create GitHub Release

**No existing skill covers this.** Create the release directly.

### 2a. Create the release as a pre-release (pending)

Mark as pre-release until testing completes. This prevents users from downloading untested code.

```bash
gh release create $VERSION \
  release_test_matrix/${VERSION}_enterprise_rag.zip \
  release_test_matrix/${VERSION}_enterprise_rag_aiq.zip \
  release_test_matrix/${VERSION}_paas_rag.zip \
  release_test_matrix/${VERSION}_cuopt.zip \
  release_test_matrix/${VERSION}_vss.zip \
  release_test_matrix/${VERSION}_warehouse_pick_path.zip \
  release_test_matrix/${VERSION}_contract_analysis.zip \
  --target release_v${VERSION} \
  --title "$VERSION" \
  --prerelease \
  --notes "Release $VERSION - testing in progress"
```

### 2b. Verify the release

```bash
gh release view $VERSION --json assets,isPrerelease \
  --jq '{prerelease: .isPrerelease, assets: [.assets[].name]}'
```

Confirm: 6 zip assets attached, `isPrerelease: true`.

### 2c. After all testing passes (Phase 4-5)

Promote to latest:

```bash
gh release edit $VERSION --prerelease=false --latest \
  --notes "$(cat <<'EOF'
Release $VERSION

<release notes — summarize key changes from the commit history>
EOF
)"
```

---

## Phase 3: Plan Testing

### 3a. Analyze GPU requirements

Read `ai-accelerator-tf/vars.tf` → `local.starter_pack_configs` to get the `worker_node_shape` and `worker_node_count` for each pack/size being tested.

Ask the user which packs and sizes to test. Default: all 6 packs at their standard test sizes:

| Pack | Size | GPU Shape | GPU Workers |
|---|---|---|---|
| enterprise_rag | small | BM.GPU4.8 | 2 |
| enterprise_rag_aiq | small | BM.GPU4.8 | 2 |
| cuopt | poc | VM.GPU.A10.2 | 1 |
| vss | poc | VM.GPU.A10.2 | 2 |
| warehouse_pick_path | small | VM.GPU.A10.1 | 1 |
| paas_rag | small | none (CPU) | 0 |
| contract_analysis | small | none (CPU + DAC) | 0 |

### 3b. Design parallel tracks

Group packs by GPU shape. **Back-to-back infra reuse is only for bare metal (BM.\*) shapes.** VM shapes provision in minutes — destroy everything and start fresh between packs.

Check `worker_node_shape` in `vars.tf` → `local.starter_pack_configs` for each pack/size:
- Shape starts with `BM.` → eligible for back-to-back switching (preserve infra between rounds)
- Shape starts with `VM.` → must destroy both stacks between rounds (fresh infra each pack)
- Shape is `none` (CPU) → single round, no switching needed

For the default test matrix (poc/small sizes):

- **Track 1 (BM.GPU4.8):** enterprise_rag/small then enterprise_rag_aiq/small — back-to-back (destroy app, re-apply infra, new app)
- **Track 2 (VM.GPU.A10):** vss/poc, cuopt/poc, warehouse_pick_path/small — sequential with full destroy between rounds (all use VM.GPU.A10.x shapes)
- **Track 3 (CPU):** paas_rag/small, contract_analysis/small -- sequential (CPU-only, no GPU)

Present the track plan to the user and confirm. Adjust if they want different groupings.

**Key principle:** Back-to-back switching only applies when rounds share the same BM worker_node_shape. For BM tracks, re-apply infra every round so the cluster matches the new pack's config. For VM tracks, destroy everything and create fresh stacks — VMs provision in minutes, and preserving infra risks stale container images filling ephemeral storage (BUG-012) and stale taints blocking scheduling (BUG-009).

### 3c. Check resource capacity per track

For **every** track (including CPU-only), invoke `/checking-capacity <category> <size>` to find regions with sufficient capacity and quotas. The capacity check audits all required resources — GPU hardware, FSS (File Storage), ADB (Autonomous Database), and customer secret key quotas — not just GPU.

Present a combined table across all tracks and let the user pick regions:

```
Track 1 (BM.GPU4.8):    ap-melbourne-1, us-sanjose-1, ...
Track 2 (VM.GPU.A10.2): us-sanjose-1, uk-london-1, ...
Track 3 (CPU — paas_rag): us-sanjose-1, us-ashburn-1, ... (ADB + FSS + secret key quotas)
```

Record the region and AD for each track.

---

## Phase 4: Execute Testing

Use **Agent Teams** to run tracks in parallel. See [PARALLEL_TESTING.md](PARALLEL_TESTING.md) for the full setup guide.

### 4a. Enable agent teams

Verify `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled:

```bash
cat ~/.claude/settings.json | grep -o 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS[^,]*'
```

If not set, ask the user to add it to `~/.claude/settings.json`:
```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

### 4b. Create team and launch teammates

Create one team with one teammate per track:

```
Team: <version>-release-test
  track1-<shape_short>  — <pack1> + <pack2> in <region>
  track2-<shape_short>  — <pack3> + <pack4> in <region>
  track3-cpu            — <pack5> in <region>
```

Each teammate message should include:
1. The pack category and size to test
2. The region and OCI CLI profile
3. The compartment OCID
4. Instruction to invoke `/testing-pack <category> <size> --zip-path release_test_matrix/<VERSION>_<category>.zip` — this uses the pre-built release zip directly, skipping worktree creation and zip rebuilding. This ensures teammates test the exact zips that will ship to users and avoids race conditions on shared temp files.
5. For **BM tracks** (back-to-back): instruction to destroy the app stack (preserve infra), then invoke `/testing-pack <category2> <size2> --zip-path release_test_matrix/<VERSION>_<category2>.zip` for the second pack
6. For **VM tracks** (sequential fresh): instruction to destroy both stacks (app first, then infra), clean up resources (customer secret keys, orphaned ADB), then invoke `/testing-pack <category2> <size2> --zip-path release_test_matrix/<VERSION>_<category2>.zip` fresh (creates new infra + app stacks)
7. `PR_NUMBER=<number>` — the GitHub PR number for posting test progress and results

### 4c. Launch monitor teammate

In addition to the testing tracks, launch a **monitor** teammate. See [MONITOR_TEAMMATES.md](MONITOR_TEAMMATES.md) for the full guide.

The monitor's prompt should include:
1. The `/testing-pack` skill path to read
2. The OCI CLI profile and compartment OCID
3. The expected pack/size/region for each track
4. Instruction to **log every deviation in `BUGS.md` via `/bug-tracker log` immediately** — not at the end, not in a batch, but as each deviation is found
5. Instruction to report deviations to team-lead via SendMessage with the BUG-NNN ID
6. Access to OCI CLI, context7 MCP, and agent-browser (with its own unique session name)

The monitor independently cross-checks OCI state (stack variables, job status, resource state) rather than trusting teammate self-reports. It verifies: zip paths, starter_pack_size, two-stack model compliance, destroy ordering, and required app stack variables.

### 4d. Monitor progress

Teammates are full interactive Claude sessions. They will ask questions via `AskUserQuestion` when they need input (OCI login, compartment selection, etc.).

Check in periodically with `SendMessage` to get status updates. The monitor teammate will also proactively report deviations.

### 4d. Collect results

As each teammate completes, collect the test report from Phase 7 of `/testing-pack`.

Build a combined results table:

```
| Pack              | Size  | Region         | Track   | Result | Bugs Found |
|-------------------|-------|----------------|---------|--------|------------|
| paas_rag            | small | us-sanjose-1   | Track 3 | PASS   | —          |
| enterprise_rag      | small | ap-melbourne-1 | Track 1 | PASS   | BUG-XXX    |
| enterprise_rag_aiq  | small | ap-melbourne-1 | Track 1 | FAIL   | BUG-YYY    |
| vss                 | poc   | uk-london-1    | Track 2 | PASS   | —          |
| cuopt               | poc   | uk-london-1    | Track 2 | PASS   | —          |
| warehouse_pick_path | small | uk-london-1    | Track 2 | PASS   | —          |
| contract_analysis | small | <region>       | Track 3 | PASS   | —          |
```

### 4e. Post combined results to PR

After all teammates complete, post a combined summary to the PR:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## Release $VERSION — Combined Test Results

| Pack | Size | Region | Infra | API | UI | Overall |
|---|---|---|---|---|---|---|
| <pack> | <size> | <region> | X/Y | X/Y | X/Y | PASS/FAIL |
...

**Overall: X/Y packs passed**
EOF
)"
```

If any pack failed, also update the PR body checklist to reflect the current state.

### 4f. Upload collected screenshots to the PR

Each `/testing-pack` teammate saves milestone screenshots locally (Phase 3 schema, Phase 4 infra success, Phase 5 app success, frontend loaded, Phase 6 UI evidence). In Phase 7 of each teammate's testing-pack run, screenshots are uploaded to a side branch `screenshots/pr-${PR_NUMBER}` and embedded into the per-track PR comments.

Verify after all tracks complete:
```bash
# Branch should exist with all tracks' screenshots
git ls-remote origin "refs/heads/screenshots/pr-${PR_NUMBER}" | head -1

# Sample URL should return 200
BASE="https://raw.githubusercontent.com/oci-ai-incubations/ai-accelerator-starter-packs/screenshots/pr-${PR_NUMBER}/pr-${PR_NUMBER}"
curl -sI "${BASE}/<track>/<phase>.png" | head -3
```

If a teammate did not complete its screenshot upload (e.g., crashed mid-run), manually stage its `/tmp/` screenshots into the side branch using the flow in `.claude/skills/testing-pack/references/pr-screenshot-upload.md`.

The `screenshots/pr-<number>` branch lives separate from the release branch; it does NOT appear in the PR diff and can be deleted after merge.

---

## Phase 5: Fix & Rebuild (if bugs found)

If any pack failed or bugs were discovered during testing:

### 5a. Fix bugs

For each bug:
1. Log in `BUGS.md` via `/bug-tracker log`
2. Fix the code on the `release_v<VERSION>` branch
3. Run `terraform fmt -recursive && terraform validate` after each fix
4. Commit the fix with a descriptive message

### 5b. Run unit tests

```bash
cd ai-accelerator-tf && terraform init -backend=false && terraform test
```

### 5c. Rebuild all 6 zips

After all fixes are committed:

```bash
rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
```

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`, `warehouse_pick_path`, `contract_analysis`:

1. Set category: `echo 'starter_pack_category = "<category>"' > ai-accelerator-tf/starter_pack_category.auto.tfvars`
2. Regenerate schema: `source venv/bin/activate && python3 create_final_schema.py -c <category>`
3. Delete old zip: `rm -f release_test_matrix/${VERSION}_<category>.zip`
4. Invoke `/zip-tf release_test_matrix ${VERSION}_<category>` to create the new zip

### 5d. Re-upload to GitHub Release

```bash
# Delete old assets
for asset in enterprise_rag enterprise_rag_aiq paas_rag cuopt vss warehouse_pick_path contract_analysis; do
  gh release delete-asset $VERSION ${VERSION}_${asset}.zip --yes 2>/dev/null
done

# Upload new assets
gh release upload $VERSION release_test_matrix/${VERSION}_*.zip
```

### 5e. Verify updated assets

```bash
gh release view $VERSION --json assets \
  --jq '.assets[] | "\(.name) \(.size) \(.createdAt)"'
```

Confirm all 5 zips have updated timestamps.

### 5f. Re-test failed packs (optional)

Ask the user if they want to re-test the packs that failed. If yes, launch new teammates for just those packs using the same agent teams approach.

### 5g. Push branch

```bash
git push origin release_v${VERSION}
```

---

## Phase 6: Finalize

Only proceed when all packs pass (or user explicitly decides to ship with known issues).

### 6a. Promote the GitHub Release

If still marked as pre-release, promote it (see Phase 2c).

### 6b. Publish

Read and follow [RELEASE_PUBLISH.md](RELEASE_PUBLISH.md). This handles:
validate zip files, rename to display names, generate Slack announcement, merge release PR, and push release tag.

### 6c. Verify completion

```bash
git tag --list 'release_v*' --sort=-version:refname | head -5
gh release view $VERSION
```

---

## Phase 7: Publish to External Repo

After Phase 6 (Finalize) completes, invoke:

```
/publish-external <VERSION>
```

This uploads the release zips to `oracle-quickstart/oci-ai-blueprints` with the console zip names and the enterprise_rag/paas_rag swap workaround. See the `/publish-external` skill for details.

---

## Phase 8: Verify Packs in OCI Console

After publishing to external, verify that each zip loads the correct pack category in the OCI Console. See [VERIFY_CONSOLE_PACKS.md](VERIFY_CONSOLE_PACKS.md) for the full playbook.

### 8a. Launch verification agent

Use agent-browser with a unique session (e.g., `--session verify-packs`). The user must authenticate in the OCI Console manually.

### 8b. Test each pack via zipUrl

For each of the 5 packs, navigate to:
```
https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-ai-blueprints/releases/download/starter-packs/<ZIPNAME>.zip
```

Accept Terms of Use, click through to Step 2 (Configure Variables), and verify the correct pack loaded using the **Category Fingerprint Matrix** in VERIFY_CONSOLE_PACKS.md. The deployment size dropdown label is the most reliable identifier:

| Zip | Expected Label |
|---|---|
| `aiQGenAIPowered.zip` | "Enterprise RAG Deployment Size" |
| `aiQEnterpriseSearch.zip` | "RAG Deployment Size" |
| `enterpriseAgenticAIStarterKit.zip` | "Enterprise RAG + AIQ Deployment Size" |
| `vehicleRouteOptimizer.zip` | "cuOpt Deployment Size" |
| `videoSearchSummarization.zip` | "VSS Deployment Size" |
| `warehousePickPathOptimizer.zip` | "Optimizer Deployment Size" |
| `contractAnalysis.zip` | "Contract Analysis Deployment Size" |

### 8c. Screenshot each pack

Save screenshots to `/tmp/pack-verification/<ZIPNAME>_<category>.png`. Present results to the user.

If any pack loads the wrong category, **STOP** — the swap workaround may be incorrect or the wrong zip was uploaded. Check the zip contents with `unzip -p <zip> ai-accelerator-tf/starter_pack_category.auto.tfvars`.

---

## Error Handling

| Situation | Action |
|---|---|
| Build phase fails | Fix the issue and re-run RELEASE_BUILD.md steps |
| `gh release create` fails | Check if release already exists; use `gh release edit` if so |
| No GPU capacity in any region | Report to user; wait for capacity or adjust pack sizes |
| Agent team creation fails | Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var |
| Testing reveals bugs | Enter Phase 5 fix-rebuild loop |
| Publish phase fails on PR merge | Check for conflicts; resolve manually |

---

## Checklist

Copy and track progress:

```
Release Progress — $VERSION:
- [ ] Phase 1: Release build completed (RELEASE_BUILD.md)
- [ ] Phase 2: GitHub Release created (pre-release)
- [ ] Phase 3: Test tracks planned, regions selected
- [ ] Phase 4: All packs tested (with monitor teammate)
- [ ] Phase 5: Bugs fixed, zips rebuilt (if needed)
- [ ] Phase 6a: GitHub Release promoted to latest
- [ ] Phase 6b: Release publish completed (RELEASE_PUBLISH.md)
- [ ] Phase 7: Published to external repo
- [ ] Phase 8: All 5 packs verified in OCI Console
```

## Reference Files

- **[RELEASE_BUILD.md](RELEASE_BUILD.md)** — Build phase: branch, version bump, validate, zip creation
- **[RELEASE_PUBLISH.md](RELEASE_PUBLISH.md)** — Publish phase: validate zips, rename, Slack, merge PR, tag
- **[PARALLEL_TESTING.md](PARALLEL_TESTING.md)** — Agent teams setup, browser isolation, permissions, back-to-back pack switching
- **[MONITOR_TEAMMATES.md](MONITOR_TEAMMATES.md)** — Monitor agent setup, compliance checks, bug tracking requirements
- **[VERIFY_CONSOLE_PACKS.md](VERIFY_CONSOLE_PACKS.md)** — OCI Console pack verification playbook, zipUrl approach, category fingerprint matrix
- **[LESSONS_LEARNED.md](LESSONS_LEARNED.md)** — Anti-patterns and pitfalls discovered during real releases
- **`/publish-external`** — Upload release zips to external oracle-quickstart/oci-ai-blueprints pre-release (separate skill)
