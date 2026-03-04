---
name: setup
description: Create an isolated sandbox environment with all prerequisites, packages, and environment variables needed by /deploy-and-test. Installs tools, extracts config from terraform.tfvars, and produces a sourceable env file.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Write, Edit, AskUserQuestion
argument-hint: (no arguments — re-run to recreate sandbox)
---

# Setup

Creates an isolated sandbox with everything `/deploy-and-test`, `/integration-test`, `/update-stack`, and `/destroy-stack` need. Nothing is installed into the repo working tree — all packages, temp files, and state go into the sandbox.

**Output:** A sandbox directory at `/tmp/dat-sandbox-<timestamp>/` with a sourceable `env.sh` file.

---

## CRITICAL: User interaction rules

Several steps in this skill require user input (tool install confirmation, OCI profile selection, missing tfvars values, pack-specific parameters). Follow these rules strictly:

1. **Always use `AskUserQuestion`** for every question that needs user input. Do NOT skip questions or assume defaults.
2. **Verify the response is non-empty.** After `AskUserQuestion` returns, check that the `answers` field contains an actual selection. If the answer text after "User has answered your questions:" is empty or blank, the user was NOT actually asked. In that case:
   - **Output the question as plain text** in your response message (e.g., "Which OCI CLI profile should I use? Options: DEFAULT, SANJOSE") and **STOP and WAIT** for the user to reply in their next message.
   - Do NOT proceed with an assumed answer. Do NOT continue to the next step.
3. **Never assume a default answer.** If the user doesn't respond or the tool fails silently, halt and ask again via text output.
4. **One question at a time.** Don't batch unrelated questions — ask, wait for a real answer, then proceed.

---

## Step 1: Create sandbox

```bash
export DAT_SANDBOX="/tmp/dat-sandbox-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${DAT_SANDBOX}"/{api-results,ui-recordings,logs,ssh-keys,zips,packages,venv}
echo "Sandbox created: ${DAT_SANDBOX}"
```

| Sub-directory | Contents |
|---|---|
| `api-results/` | curl response bodies from API tests |
| `ui-recordings/` | Continuous `.webm` video recordings from Playwright |
| `logs/` | ORM job logs, kubectl output, test reports |
| `ssh-keys/` | Bastion SSH private key (Scenario 5) |
| `zips/` | `lifecycle.zip` for ORM upload |
| `packages/` | npm packages, Playwright browsers, local tool installs |
| `venv/` | Python virtual environment |

---

## Step 2: Detect platform

```bash
PLATFORM=$(uname -s)   # Darwin or Linux
ARCH=$(uname -m)        # arm64 or x86_64
echo "Platform: ${PLATFORM} ${ARCH}"
```

---

## Step 3: Check and auto-install system tools

Check each required tool. If any are missing, detect the package manager and offer to install them.

### 3a. Check each tool

```bash
TOOLS="oci kubectl terraform python3 zip curl jq node"
MISSING=""
for tool in $TOOLS; do
  if which "$tool" > /dev/null 2>&1; then
    echo "OK: $tool ($(which $tool))"
  else
    echo "MISSING: $tool"
    MISSING="${MISSING} ${tool}"
  fi
done
```

If all tools are present, skip to Step 4.

### 3b. Detect package manager

```bash
if [ "$PLATFORM" = "Darwin" ]; then
  if which brew > /dev/null 2>&1; then
    PKG_MANAGER="brew"
  else
    PKG_MANAGER="none"
  fi
elif [ "$PLATFORM" = "Linux" ]; then
  if which apt-get > /dev/null 2>&1; then
    PKG_MANAGER="apt"
  else
    PKG_MANAGER="none"
  fi
fi
```

If `PKG_MANAGER` is `none`:
- On macOS: Tell user to install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- On Linux without apt: Print manual install instructions and stop.

### 3c. Auto-install missing tools

Ask the user for confirmation: *"The following tools are missing: `<list>`. I can install them using `<brew/apt>`. Shall I proceed?"*

**macOS (brew) install mapping:**

| Tool | Brew command |
|---|---|
| `oci` | `brew install oci-cli` |
| `kubectl` | `brew install kubectl` |
| `terraform` | `brew install terraform` |
| `python3` | `brew install python@3.11` |
| `zip` | `brew install zip` |
| `curl` | `brew install curl` |
| `jq` | `brew install jq` |
| `node` | `brew install node` (npm comes with node) |

Run `brew install <packages>` for all missing tools in a single command where possible.

**Linux (apt) install mapping:**

| Tool | Install method |
|---|---|
| `zip` | `sudo apt-get install -y zip` |
| `curl` | `sudo apt-get install -y curl` |
| `jq` | `sudo apt-get install -y jq` |
| `python3` | `sudo apt-get install -y python3 python3-venv python3-pip` |
| `node` | `sudo apt-get install -y nodejs npm` (or use NodeSource repo for LTS) |
| `oci` | Special: `bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- --accept-all-defaults` |
| `kubectl` | Special: `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/` |
| `terraform` | Special: Add HashiCorp repo then `sudo apt-get install -y terraform` |

For `apt` commands: check if `sudo` is available with `sudo -n true 2>/dev/null`. If sudo requires a password, tell the user to run the install commands themselves.

For the special Linux installs (oci, kubectl, terraform), run each install script individually and check for success.

### 3d. Re-verify after install

```bash
STILL_MISSING=""
for tool in $TOOLS; do
  if ! which "$tool" > /dev/null 2>&1; then
    STILL_MISSING="${STILL_MISSING} ${tool}"
  fi
done
```

If anything is still missing, report the specific tools and stop. **Do NOT proceed until all system tools are present.**

---

## Step 4: OCI CLI bootstrap

### 4a. Check if OCI config exists

```bash
test -f ~/.oci/config && echo "OCI config found" || echo "MISSING: ~/.oci/config"
```

If `~/.oci/config` exists, skip to Step 5.

### 4b. Create OCI config (if missing)

Tell the user: *"Your OCI config file (~/.oci/config) does not exist. I will launch the OCI CLI setup wizard. This is an interactive process — you will answer the prompts directly."*

Provide guidance on what values to have ready:
- **User OCID**: Found in OCI Console → Identity → Users → your user → OCID
- **Tenancy OCID**: Found in OCI Console → Administration → Tenancy Details → OCID
- **Region**: e.g., `us-ashburn-1`, `us-sanjose-1`
- **Generate API key**: Say yes — it will create `~/.oci/oci_api_key.pem`

Then run the wizard with a generous timeout:

```bash
oci setup config
```

Use a **5-minute timeout** (300000ms) on this Bash command to give the user time to complete the interactive prompts.

**Fallback:** If the command times out or fails, use `AskUserQuestion` to tell the user:

> *"The interactive setup timed out. Please run `oci setup config` in a separate terminal, then let me know when you're done."*

Wait for the user to confirm, then proceed.

### 4c. Verify config was created

```bash
test -f ~/.oci/config && echo "OCI config created successfully" || echo "ERROR: ~/.oci/config still missing"
```

If still missing after the fallback, stop and tell the user to create the config manually.

### 4d. Upload API public key (reminder)

After config creation, remind the user: *"Don't forget to upload your API public key (~/.oci/oci_api_key_public.pem) to your OCI user in the Console: Identity → Users → your user → API Keys → Add API Key → Paste Public Key."*

---

## Step 5: OCI CLI profile

### 5a. Ask user for profile

Ask the user: *"Which OCI CLI profile should I use? Common values: `SANJOSE`, `DEFAULT`"*

### 5b. Validate profile

```bash
export OCI_CLI_PROFILE=<user-selected-profile>
oci iam region list --output table 2>&1 | head -5
```

If this returns regions, the profile works. If it errors (expired token, wrong key), tell the user to fix it.

For session-based auth (token auth), check expiry:

```bash
oci session validate --profile ${OCI_CLI_PROFILE} 2>&1
```

If expired:

```bash
oci session authenticate --profile-name ${OCI_CLI_PROFILE} --region <region>
```

Record the validated profile name for the env file.

---

## Step 6: Python venv (in sandbox)

```bash
python3 -m venv "${DAT_SANDBOX}/venv"
source "${DAT_SANDBOX}/venv/bin/activate"
pip install -r requirements.txt 2>&1 | tail -3
```

This keeps the project's repo-level `venv/` untouched. The sandbox venv is disposable.

---

## Step 7: Playwright browser and MCP verification

### 7a. Install Playwright npm package and browser

```bash
cd "${DAT_SANDBOX}/packages"
npm init -y > /dev/null 2>&1
npm install @playwright/test 2>&1 | tail -3
PLAYWRIGHT_BROWSERS_PATH="${DAT_SANDBOX}/packages/pw-browsers" \
  npx playwright install chromium 2>&1 | tail -3
```

Record the browser path for the env file. This avoids polluting the repo's `node_modules/`.

> **Note:** If npm has network issues (corporate proxy), warn the user but continue — the Playwright MCP server may still work if Playwright is available globally.

### 7b. Verify `.mcp.json` exists

Check that the MCP config file exists in the repo root:

```bash
test -f .mcp.json && echo "MCP config found" || echo "MISSING: .mcp.json"
```

If missing, create it with the Write tool:

```json
{
  "mcpServers": {
    "playwright-test": {
      "command": "npx",
      "args": [
        "playwright",
        "run-test-mcp-server"
      ]
    }
  }
}
```

### 7c. Verify Claude MCP settings

Check that `.claude/settings.local.json` enables MCP servers:

```bash
test -f .claude/settings.local.json && cat .claude/settings.local.json
```

It should contain:

```json
{
  "enableAllProjectMcpServers": true,
  "enabledMcpjsonServers": [
    "playwright-test"
  ]
}
```

If the file is missing or does not contain these keys, create or update it.

> **Important:** If `.claude/settings.local.json` was created or modified, tell the user: *"I updated the MCP settings. You may need to restart Claude Code for the Playwright MCP server to be available."*

---

## Step 8: terraform.tfvars

### 8a. Check if terraform.tfvars exists

```bash
test -f ai-accelerator-tf/terraform.tfvars && echo "tfvars found" || echo "tfvars MISSING"
```

### 8b. If MISSING — create from template

1. Copy the example file:

```bash
cp ai-accelerator-tf/terraform.tfvars.example ai-accelerator-tf/terraform.tfvars
```

2. Ask the user for required values. Use `AskUserQuestion` or direct prompts to collect:

| Variable | Description | Where to find |
|---|---|---|
| `tenancy_ocid` | OCI Tenancy OCID | Console → Administration → Tenancy Details |
| `compartment_ocid` | Target compartment OCID | Console → Identity → Compartments |
| `region` | OCI region (e.g., `us-sanjose-1`) | Chosen by user |
| `current_user_ocid` | Your user OCID | Console → Identity → Users |
| `fingerprint` | API key fingerprint | Console → Identity → Users → API Keys |
| `private_key_path` | Path to API private key | e.g., `~/.oci/oci_api_key.pem` |
| `corrino_admin_username` | Blueprints portal login username | User-chosen |
| `corrino_admin_password` | Blueprints portal login password | User-chosen |
| `corrino_admin_email` | Blueprints portal login email | User-chosen |
| `db_password` | Database password (12+ chars, 1 uppercase, 1 number, 1 special) | User-chosen |

3. Use the Edit tool to replace placeholder values in the copied file. Replace lines like:

```
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaa..."
```

with the user-provided values. Also append Corrino and DB variables that are not in the example file:

```hcl
# Starter Pack
starter_pack_category = "paas_rag"
starter_pack_size     = "small"

# Corrino Admin
corrino_admin_username = "<user-provided>"
corrino_admin_password = "<user-provided>"
corrino_admin_email    = "<user-provided>"

# Database
db_password = "<user-provided>"

# Network
network_configuration_mode = "create_new"
```

4. Verify the file is gitignored:

```bash
git check-ignore ai-accelerator-tf/terraform.tfvars && echo "gitignored: OK" || echo "WARNING: terraform.tfvars is NOT gitignored — do not commit this file"
```

### 8c. If EXISTS — extract variables

Parse `ai-accelerator-tf/terraform.tfvars` to extract all variables needed by deploy-and-test:

```bash
TFVARS="ai-accelerator-tf/terraform.tfvars"

extract_var() {
  grep "^${1}" "${TFVARS}" 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/'
}

TENANCY_OCID=$(extract_var tenancy_ocid)
COMPARTMENT_OCID=$(extract_var compartment_ocid)
REGION=$(extract_var region)
CURRENT_USER_OCID=$(extract_var current_user_ocid)
CORRINO_ADMIN_USERNAME=$(extract_var corrino_admin_username)
CORRINO_ADMIN_PASSWORD=$(extract_var corrino_admin_password)
CORRINO_ADMIN_EMAIL=$(extract_var corrino_admin_email)
DB_PASSWORD=$(extract_var db_password)
STARTER_PACK_CATEGORY=$(extract_var starter_pack_category)
STARTER_PACK_SIZE=$(extract_var starter_pack_size)
FINGERPRINT=$(extract_var fingerprint)
PRIVATE_KEY_PATH=$(extract_var private_key_path)
```

### 8d. Check required variables

```bash
MISSING_VARS=""
for var in TENANCY_OCID COMPARTMENT_OCID CURRENT_USER_OCID CORRINO_ADMIN_USERNAME CORRINO_ADMIN_PASSWORD CORRINO_ADMIN_EMAIL DB_PASSWORD; do
  eval val=\$$var
  if [ -z "$val" ]; then
    MISSING_VARS="${MISSING_VARS} ${var}"
  fi
done

if [ -n "${MISSING_VARS}" ]; then
  echo "MISSING from terraform.tfvars:${MISSING_VARS}"
fi
```

If any are missing, list them and ask the user to add them to `ai-accelerator-tf/terraform.tfvars` before proceeding.

---

## Step 9: Ask for additional test parameters

Ask the user for any pack-specific variables not in terraform.tfvars:

| Variable | When needed | Example |
|---|---|---|
| `VSS_BUCKET_NAME` | VSS pack — bucket listing and summarization tests | `my-video-bucket` |
| `VSS_OBJECT_KEY` | VSS pack — upload/summarize e2e flow | `test-video.mp4` |
| `CUOPT_FRONTEND_ENABLED` | cuopt pack — whether demo UI is deployed | `true` / `false` |

Only ask if the `STARTER_PACK_CATEGORY` from tfvars matches a pack that needs them, or if the user specifies a pack as an argument.

---

## Step 10: Write env file

Write a sourceable env file that deploy-and-test (and all other skills) can consume:

```bash
cat > "${DAT_SANDBOX}/env.sh" << 'ENVEOF'
# Auto-generated by /setup — source this before running /deploy-and-test
# Sandbox: ${DAT_SANDBOX}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Sandbox paths
export DAT_SANDBOX="${DAT_SANDBOX}"
export PATH="${DAT_SANDBOX}/packages/node_modules/.bin:${PATH}"
export PLAYWRIGHT_BROWSERS_PATH="${DAT_SANDBOX}/packages/pw-browsers"

# OCI
export OCI_CLI_PROFILE="<validated-profile>"
export TENANCY_OCID="<extracted>"
export COMPARTMENT_OCID="<extracted>"
export REGION="<extracted>"
export CURRENT_USER_OCID="<extracted>"

# Corrino credentials
export CORRINO_USERNAME="<extracted>"
export CORRINO_PASSWORD="<extracted>"
export CORRINO_EMAIL="<extracted>"
export DB_PASSWORD="<extracted>"

# Starter pack (from tfvars — can be overridden by deploy-and-test arguments)
export STARTER_PACK_CATEGORY="<extracted>"
export STARTER_PACK_SIZE="<extracted>"

# Pack-specific (filled if user provided them)
export VSS_BUCKET_NAME=""
export VSS_OBJECT_KEY=""

# Set after deploy (Phase 3 populates these)
export STARTER_PACK_URL=""
export CLUSTER_OCID=""
export STACK_OCID=""
ENVEOF

chmod 600 "${DAT_SANDBOX}/env.sh"
echo "Env file: ${DAT_SANDBOX}/env.sh"
```

Replace all `<extracted>` placeholders with actual values from Step 8.

**Security:** The env file contains credentials — `chmod 600` ensures only the user can read it. It's in `/tmp/` so it won't survive a reboot.

---

## Step 11: Final verification

```bash
echo "═══════════════════════════════════════"
echo "  SETUP VERIFICATION"
echo "  Sandbox: ${DAT_SANDBOX}"
echo "═══════════════════════════════════════"
echo ""
echo "System tools:"
for tool in oci kubectl terraform python3 zip curl jq node npm; do
  printf "  %-12s " "$tool"
  which "$tool" > /dev/null 2>&1 && echo "OK" || echo "MISSING"
done
echo ""
echo "Sandbox packages:"
printf "  %-12s " "python venv"
test -f "${DAT_SANDBOX}/venv/bin/activate" && echo "OK" || echo "MISSING"
printf "  %-12s " "playwright"
test -d "${DAT_SANDBOX}/packages/pw-browsers" && echo "OK" || echo "MISSING (UI tests will use MCP fallback)"
echo ""
echo "Configuration:"
printf "  %-12s " "OCI config"
test -f ~/.oci/config && echo "OK" || echo "MISSING"
printf "  %-12s " "OCI profile"
echo "${OCI_CLI_PROFILE:-NOT SET}"
printf "  %-12s " "tfvars"
test -f ai-accelerator-tf/terraform.tfvars && echo "OK" || echo "MISSING"
printf "  %-12s " ".mcp.json"
test -f .mcp.json && echo "OK" || echo "MISSING"
printf "  %-12s " "MCP settings"
test -f .claude/settings.local.json && echo "OK" || echo "MISSING"
printf "  %-12s " "env.sh"
test -f "${DAT_SANDBOX}/env.sh" && echo "OK" || echo "MISSING"
echo ""
echo "Environment variables (from tfvars):"
printf "  %-24s " "CORRINO_USERNAME"
test -n "${CORRINO_ADMIN_USERNAME}" && echo "set" || echo "MISSING"
printf "  %-24s " "CORRINO_PASSWORD"
test -n "${CORRINO_ADMIN_PASSWORD}" && echo "set" || echo "MISSING"
printf "  %-24s " "COMPARTMENT_OCID"
test -n "${COMPARTMENT_OCID}" && echo "set" || echo "MISSING"
printf "  %-24s " "STARTER_PACK_CATEGORY"
echo "${STARTER_PACK_CATEGORY:-not set}"
echo ""
echo "═══════════════════════════════════════"
```

If everything is OK:

> Setup complete. To start testing:
> ```bash
> source ${DAT_SANDBOX}/env.sh
> ```
> Then run `/deploy-and-test <category> <size>`

If anything is missing, list exactly what to fix.

---

## How deploy-and-test consumes this

Deploy-and-test Phase 0 sources the env file:

```bash
# Phase 0 in deploy-and-test:
# If DAT_SANDBOX is not set, look for the most recent sandbox
if [ -z "${DAT_SANDBOX}" ]; then
  DAT_SANDBOX=$(ls -td /tmp/dat-sandbox-* 2>/dev/null | head -1)
fi
source "${DAT_SANDBOX}/env.sh"
```

All phases then use `${DAT_SANDBOX}` for temp files and `${CORRINO_USERNAME}`, `${CORRINO_PASSWORD}`, etc. for test inputs. No more reading terraform.tfvars mid-flight.
