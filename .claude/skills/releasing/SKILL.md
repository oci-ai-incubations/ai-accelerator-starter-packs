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
#         <version>_paas_rag.zip, <version>_cuopt.zip, <version>_vss.zip
```

If any zip is missing, stop and investigate.

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

Confirm: 5 zip assets attached, `isPrerelease: true`.

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

Ask the user which packs and sizes to test. Default: all 5 packs at their standard test sizes:

| Pack | Size | GPU Shape | GPU Workers |
|---|---|---|---|
| enterprise_rag | small | BM.GPU4.8 | 2 |
| enterprise_rag_aiq | small | BM.GPU4.8 | 2 |
| cuopt | poc | VM.GPU.A10.2 | 1 |
| vss | poc | VM.GPU.A10.2 | 2 |
| paas_rag | small | none (CPU) | 0 |

### 3b. Design parallel tracks

Group packs by GPU shape to maximize infrastructure reuse:

- **Track 1 (BM.GPU4.8):** enterprise_rag then enterprise_rag_aiq (back-to-back, re-apply infra between)
- **Track 2 (VM.GPU.A10.2):** vss then cuopt (back-to-back, re-apply infra to scale GPU pool)
- **Track 3 (CPU only):** paas_rag (independent)

Present the track plan to the user and confirm. Adjust if they want different groupings.

**Key principle:** Re-apply infra every round so the cluster matches the new pack's exact config (node count, shape, ADB, etc.).

### 3c. Check GPU capacity per track

For each GPU track, invoke `/checking-capacity <category> <size>` to find regions with both hardware availability AND quota.

Present a combined table across all tracks and let the user pick regions:

```
Track 1 (BM.GPU4.8):  ap-melbourne-1, us-sanjose-1, ...
Track 2 (VM.GPU.A10.2): us-sanjose-1, uk-london-1, ...
Track 3 (CPU only):   any region — ask user preference
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
4. Instruction to invoke `/testing-pack <category> <size>`
5. For back-to-back tracks: instruction to destroy app stack, update infra with next pack's zip, re-apply, then `/testing-pack` for the second pack

### 4c. Monitor progress

Teammates are full interactive Claude sessions. They will ask questions via `AskUserQuestion` when they need input (OCI login, compartment selection, etc.).

Check in periodically with `SendMessage` to get status updates.

### 4d. Collect results

As each teammate completes, collect the test report from Phase 7 of `/testing-pack`.

Build a combined results table:

```
| Pack              | Size  | Region         | Track   | Result | Bugs Found |
|-------------------|-------|----------------|---------|--------|------------|
| paas_rag          | small | us-sanjose-1   | Track 3 | PASS   | —          |
| enterprise_rag    | small | ap-melbourne-1 | Track 1 | PASS   | BUG-XXX    |
| enterprise_rag_aiq| small | ap-melbourne-1 | Track 1 | FAIL   | BUG-YYY    |
| vss               | poc   | uk-london-1    | Track 2 | PASS   | —          |
| cuopt             | poc   | uk-london-1    | Track 2 | PASS   | —          |
```

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

### 5c. Rebuild all 5 zips

After all fixes are committed:

```bash
rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
```

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`:

1. Set category: `echo 'starter_pack_category = "<category>"' > ai-accelerator-tf/starter_pack_category.auto.tfvars`
2. Regenerate schema: `source venv/bin/activate && python3 create_final_schema.py -c <category>`
3. Delete old zip: `rm -f release_test_matrix/${VERSION}_<category>.zip`
4. Invoke `/zip-tf release_test_matrix ${VERSION}_<category>` to create the new zip

### 5d. Re-upload to GitHub Release

```bash
# Delete old assets
for asset in enterprise_rag enterprise_rag_aiq paas_rag cuopt vss; do
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

## Error Handling

| Situation | Action |
|---|---|
| `/release-upgrade` fails | Fix the issue and re-run the skill |
| `gh release create` fails | Check if release already exists; use `gh release edit` if so |
| No GPU capacity in any region | Report to user; wait for capacity or adjust pack sizes |
| Agent team creation fails | Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var |
| Testing reveals bugs | Enter Phase 5 fix-rebuild loop |
| `/release-push` fails on PR merge | Check for conflicts; resolve manually |

---

## Checklist

Copy and track progress:

```
Release Progress — $VERSION:
- [ ] Phase 1: /release-upgrade completed
- [ ] Phase 2: GitHub Release created (pre-release)
- [ ] Phase 3: Test tracks planned, regions selected
- [ ] Phase 4: All packs tested
- [ ] Phase 5: Bugs fixed, zips rebuilt (if needed)
- [ ] Phase 6a: GitHub Release promoted to latest
- [ ] Phase 6b: /release-push completed (Slack, PR merge, tag)
```

## Reference Files

- **[RELEASE_BUILD.md](RELEASE_BUILD.md)** — Build phase: branch, version bump, validate, zip creation
- **[RELEASE_PUBLISH.md](RELEASE_PUBLISH.md)** — Publish phase: validate zips, rename, Slack, merge PR, tag
- **[PARALLEL_TESTING.md](PARALLEL_TESTING.md)** — Agent teams setup, browser isolation, permissions, back-to-back pack switching
- **[LESSONS_LEARNED.md](LESSONS_LEARNED.md)** — Anti-patterns and pitfalls discovered during real releases
