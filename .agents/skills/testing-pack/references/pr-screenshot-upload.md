# PR Screenshot Upload via Side Branch

## Problem

`gh pr comment` cannot inline-attach binary images. Screenshots saved locally to `/tmp/` are invisible to PR reviewers unless uploaded somewhere GitHub-renderable. The standard GitHub "drag-and-drop in web UI" approach requires human interaction. We need an automation-friendly path.

## Solution

Push screenshots to a dedicated side branch (e.g., `screenshots/pr-<number>`) in the same repo, then reference them in PR comments via `raw.githubusercontent.com` URLs. The PR branch itself stays clean (images are NOT part of the PR diff).

## 3-step flow

### Step 1 — Stage screenshots in a temp dir

Collect all `.png` files the teammate/skill saved during the run into a staging directory with a clean hierarchy (e.g., subdirectories per track or phase):

```bash
SHOT_DIR=$(mktemp -d)
mkdir -p "$SHOT_DIR/<track>/<phase>"
cp /tmp/<screenshot>.png "$SHOT_DIR/<track>/<phase>/"
```

### Step 2 — Push to side branch via a side clone

**Do NOT touch the main working tree.** Use a fresh clone to create/push the orphan branch:

```bash
PR_NUMBER=<pr_number>          # from `gh pr view` earlier
BRANCH="screenshots/pr-${PR_NUMBER}"
REPO="oci-ai-incubations/ai-accelerator-starter-packs"  # adjust if different

CLONE_DIR=$(mktemp -d)
cd "$CLONE_DIR"
git clone --depth 1 --no-checkout git@github.com:${REPO}.git repo
cd repo
git checkout --orphan "${BRANCH}"
git rm -rf --cached . >/dev/null 2>&1 || true
mkdir -p pr-${PR_NUMBER}
cp -r "$SHOT_DIR"/* pr-${PR_NUMBER}/
cat > README.md <<EOF
# PR #${PR_NUMBER} Screenshots

Evidence screenshots from testing runs.
Raw URL pattern: https://raw.githubusercontent.com/${REPO}/${BRANCH}/pr-${PR_NUMBER}/<path>
EOF
git add pr-${PR_NUMBER}/ README.md
git -c user.email="noreply@anthropic.com" -c user.name="Claude (automation)" commit -m "docs: add screenshots for PR #${PR_NUMBER}"
git push --force origin "${BRANCH}"
```

**Why a side clone?** An orphan branch in the primary working tree plus `git clean -fdx` would destroy gitignored local files (venv, /tmp worktrees, build caches). A clean temp clone keeps the primary workspace untouched.

### Step 3 — Embed images in PR comments via raw URLs

After the branch is pushed, edit each PR comment that referenced a local `/tmp/` path to embed the hosted image:

```bash
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pr-${PR_NUMBER}"

# Append image markdown to an existing PR comment by ID
gh api -X PATCH "repos/${REPO}/issues/comments/<comment_id>" -f body="$(cat <<EOF
<original comment body here>

---

### Screenshots

**Caption**
![Caption](${BASE}/<track>/<phase>/<file>.png)
EOF
)"
```

Or if posting fresh:

```bash
gh pr comment ${PR_NUMBER} --body "$(cat <<EOF
## <milestone name>

<context + text evidence>

### Screenshots

**Caption**
![Caption](${BASE}/<track>/<phase>/<file>.png)
EOF
)"
```

## When to upload (per-milestone vs batch)

- **Per-milestone (preferred when parallel tracks are posting live):** after each phase completes, push updated screenshots and include their URLs in that phase's comment. Requires pushing the side branch multiple times (force-push each time).
- **Batch at end (simpler):** save all screenshots locally with `/tmp/<name>.png` paths in comments during the run; at end-of-run, push all screenshots in one commit and PATCH all comments to embed URLs.

Batch at end is simpler and is the recommended default unless teammates coordinate explicit checkpoints.

## Cleanup

The `screenshots/pr-<number>` branch can be deleted after the PR merges. A suggested cleanup step in `finishing-a-development-branch`:

```bash
git push origin --delete screenshots/pr-<number>
```

Or leave it — branches carry near-zero storage cost and preserve evidence for later audit.

## Verification

After updates, verify the images actually render by:

```bash
# HTTP HEAD check on one URL
curl -sI "${BASE}/<path>/<file>.png" | head -3
# Should return 200 OK and content-type: image/png
```

Or spot-check by opening the PR comment in the browser — images should render inline.
