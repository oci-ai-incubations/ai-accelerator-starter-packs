# Tmux-Based Multi-Agent Swarm for Release Testing

Alternative to `TeamCreate` that gives the coordinator full control over worker agents, including the ability to interrupt running workers instantly.

## Why Use This Instead of TeamCreate

| Capability | TeamCreate | Tmux Swarm |
|---|---|---|
| Spawn parallel agents | Yes | Yes |
| Agents can use AskUserQuestion | Yes | Yes |
| Interrupt a busy agent | No (Escape only) | Yes (`tmux send-keys`) |
| Send urgent messages | Queued until turn ends | Injected immediately |
| Kill a stuck agent | No | Yes (`tmux send-keys C-c`) |
| Per-agent isolated filesystem | No (shared) | Yes (separate worktrees) |

## Architecture

```
tmux session: "v006-release"
+---------------------------+---------------------------+
| Pane 0: coordinator       | Pane 1: track1-gpu4       |
| (your main Claude session)| claude --worktree /tmp/t1 |
|                           |   /testing-pack ...       |
+---------------------------+---------------------------+
| Pane 2: track2-a10        | Pane 3: track3-cpu        |
| claude --worktree /tmp/t2 | claude --worktree /tmp/t3 |
|   /testing-pack ...       |   /testing-pack ...       |
+---------------------------+---------------------------+
```

Each pane runs an independent `claude` CLI process. The coordinator communicates via `tmux send-keys`.

## Setup

### 1. Create tmux session with panes

```bash
# Create session with coordinator pane
tmux new-session -d -s v006-release -n main

# Split into 4 panes (coordinator + 3 tracks)
tmux split-window -h -t v006-release:main
tmux split-window -v -t v006-release:main.0
tmux split-window -v -t v006-release:main.1

# Label panes for reference
# Pane 0 = coordinator, 1 = track1-gpu4, 2 = track2-a10, 3 = track3-cpu
```

### 2. Create worktrees for each track

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
for track in track1 track2 track3; do
  git worktree add --detach "/tmp/release-${track}" HEAD
done
```

### 3. Launch worker agents

From the coordinator pane, send commands to each worker pane:

```bash
# Track 1: enterprise_rag in ap-melbourne-1
tmux send-keys -t v006-release:main.1 \
  'cd /tmp/release-track1 && claude --dangerously-skip-permissions "$(cat <<'"'"'PROMPT
You are testing enterprise_rag/small for the v0.0.6 release.
Region: ap-melbourne-1
OCI CLI Profile: aiincubations
Compartment: Grant-Compartment (ocid1.compartment.oc1..aaaa...)
Invoke /testing-pack enterprise_rag small --zip-path /path/to/v0.0.6_enterprise_rag.zip
PROMPT
)"' Enter

# Track 2: vss in us-sanjose-1
tmux send-keys -t v006-release:main.2 \
  'cd /tmp/release-track2 && claude --dangerously-skip-permissions "$(cat <<'"'"'PROMPT
You are testing vss/poc for the v0.0.6 release.
Region: us-sanjose-1
...same pattern...
PROMPT
)"' Enter

# Track 3: paas_rag in us-sanjose-1
tmux send-keys -t v006-release:main.3 \
  'cd /tmp/release-track3 && claude --dangerously-skip-permissions "$(cat <<'"'"'PROMPT
You are testing paas_rag/small for the v0.0.6 release.
Region: us-sanjose-1
...same pattern...
PROMPT
)"' Enter
```

### 4. Set up idle notification hook

Create `.claude/hooks/agent-stop-notification.sh` in each worktree (or install via a plugin):

```bash
#!/bin/bash
set -euo pipefail

STATE_FILE=".claude/swarm-state.local.md"
[[ ! -f "$STATE_FILE" ]] && exit 0

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
COORDINATOR=$(echo "$FRONTMATTER" | grep '^coordinator_session:' | sed 's/coordinator_session: *//')
AGENT_NAME=$(echo "$FRONTMATTER" | grep '^agent_name:' | sed 's/agent_name: *//')
ENABLED=$(echo "$FRONTMATTER" | grep '^enabled:' | sed 's/enabled: *//')

[[ "$ENABLED" != "true" ]] && exit 0

if tmux has-session -t "$COORDINATOR" 2>/dev/null; then
  tmux send-keys -t "$COORDINATOR" "Agent ${AGENT_NAME} is idle and ready for next task." Enter
fi
exit 0
```

Register it in each worktree's `.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash .claude/hooks/agent-stop-notification.sh" }] }]
  }
}
```

## Coordinator Commands

### Send a message to a worker (interrupts immediately)

```bash
# Send text that appears as user input in the worker's Claude session
tmux send-keys -t v006-release:main.1 "Stop the current deploy and rebuild the zip" Enter
```

### Kill a stuck worker

```bash
# Send Ctrl+C to cancel current operation
tmux send-keys -t v006-release:main.2 C-c
```

### Check what a worker is doing

```bash
# Capture the last 50 lines of a worker's pane
tmux capture-pane -t v006-release:main.3 -p | tail -50
```

### Restart a worker with new instructions

```bash
tmux send-keys -t v006-release:main.1 C-c
sleep 1
tmux send-keys -t v006-release:main.1 'claude "New instructions here"' Enter
```

## Cleanup

```bash
# Kill all worker panes
tmux kill-session -t v006-release

# Remove worktrees
for track in track1 track2 track3; do
  git worktree remove "/tmp/release-${track}" --force 2>/dev/null
done
```

## Trade-offs

**Pros:**
- Full interrupt capability via `tmux send-keys`
- Each agent has its own isolated worktree (no zip race conditions)
- Can capture pane output for monitoring
- Can kill and restart individual agents

**Cons:**
- More manual setup than `TeamCreate`
- No built-in task list sharing (use a shared file or GitHub PR comments instead)
- Need to manage tmux session manually
- `--dangerously-skip-permissions` is needed for autonomous operation (or pre-configure allowedTools)
- Workers can't use `SendMessage` to each other — coordinate through the coordinator or shared files
