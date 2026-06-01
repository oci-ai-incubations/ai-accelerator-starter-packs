---
name: setup
description: Create an isolated sandbox environment for a specific starter pack. Installs tools, auto-extracts OCI config values into terraform.tfvars, asks for pack-specific variables, and produces a sourceable env file.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Write, Edit, AskUserQuestion
argument-hint: <category> (e.g., vss, cuopt, enterprise_rag, enterprise_rag_aiq, paas_rag)
---

# Setup

Creates an isolated sandbox for deploying and testing a **specific starter pack**. Nothing is installed into the repo working tree — all packages, temp files, and state go into the sandbox.

**Output:** A sandbox directory at `/tmp/dat-sandbox-<timestamp>/` with a sourceable `env.sh` file and a fully populated `terraform.tfvars`.

---

## CRITICAL: User interaction rules

Several steps in this skill require user input (tool install confirmation, OCI profile selection, pack-specific variables). Follow these rules strictly:

1. **Always use `AskUserQuestion`** for every question that needs user input. Do NOT skip questions or assume defaults.
2. **Verify the response is non-empty.** After `AskUserQuestion` returns, check that the `answers` field contains an actual selection. If the answer text after "User has answered your questions:" is empty or blank, the user was NOT actually asked. In that case:
   - **Output the question as plain text** in your response message (e.g., "Which OCI CLI profile should I use? Options: DEFAULT, SANJOSE") and **STOP and WAIT** for the user to reply in their next message.
   - Do NOT proceed with an assumed answer. Do NOT continue to the next step.
3. **Never assume a default answer.** If the user doesn't respond or the tool fails silently, halt and ask again via text output.
4. **One question at a time.** Don't batch unrelated questions — ask, wait for a real answer, then proceed.

---

## Step 1: Ask which starter pack

If the user didn't pass a category argument, ask: *"Which starter pack are you setting up? Options: `vss`, `cuopt`, `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`"*

Then ask for the **size**. Valid sizes per pack:

| Pack | Valid Sizes |
|---|---|
| `vss` | poc, small, medium |
| `cuopt` | poc, small, medium |
| `enterprise_rag` | small |
| `enterprise_rag_aiq` | small |
| `paas_rag` | small, medium |

If the pack only has one size (small), skip asking and use `small`.

Record `STARTER_PACK_CATEGORY` and `STARTER_PACK_SIZE` for later steps.

---

## Step 2: Create sandbox

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

## Step 3: Detect platform

```bash
PLATFORM=$(uname -s)   # Darwin or Linux
ARCH=$(uname -m)        # arm64 or x86_64
echo "Platform: ${PLATFORM} ${ARCH}"
```

---

## Step 4: Check and auto-install system tools

Check each required tool. If any are missing, detect the package manager and offer to install them.

### 4a. Check each tool

Ensure Homebrew paths are available as a fallback (macOS tools installed via brew won't be found otherwise):

```bash
# Homebrew PATH fallback (macOS)
if [ -d "/opt/homebrew/bin" ]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}"
fi

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

If all tools are present, skip to Step 5.

### 4b. Detect package manager

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

### 4c. Auto-install missing tools

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

### 4d. Re-verify after install

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

## Step 5: OCI CLI bootstrap

### 5a. Check if OCI config exists

```bash
test -f ~/.oci/config && echo "OCI config found" || echo "MISSING: ~/.oci/config"
```

If `~/.oci/config` exists, skip to Step 6.

### 5b. Create OCI config (if missing)

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

### 5c. Verify config was created

```bash
test -f ~/.oci/config && echo "OCI config created successfully" || echo "ERROR: ~/.oci/config still missing"
```

If still missing after the fallback, stop and tell the user to create the config manually.

### 5d. Upload API public key (reminder)

After config creation, remind the user: *"Don't forget to upload your API public key (~/.oci/oci_api_key_public.pem) to your OCI user in the Console: Identity → Users → your user → API Keys → Add API Key → Paste Public Key."*

---

## Step 6: OCI CLI profile selection and extraction

### 6a. List available profiles

```bash
grep '^\[' ~/.oci/config | tr -d '[]'
```

### 6b. Ask user for profile

Show the list from 6a and ask: *"Which OCI CLI profile should I use?"*

### 6c. Validate profile

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

### 6d. Extract OCI identity values from the profile

Parse `~/.oci/config` to extract values for the selected profile. These map directly to terraform.tfvars fields:

```bash
PROFILE_NAME="<user-selected-profile>"

# Extract values from the selected profile section
extract_oci_config() {
  awk -v profile="[${PROFILE_NAME}]" '
    $0 == profile { found=1; next }
    /^\[/ { found=0 }
    found && /^'"$1"'/ { sub(/.*=[ ]*/, ""); print; exit }
  ' ~/.oci/config
}

OCI_TENANCY=$(extract_oci_config "tenancy")
OCI_USER=$(extract_oci_config "user")
OCI_FINGERPRINT=$(extract_oci_config "fingerprint")
OCI_KEY_FILE=$(extract_oci_config "key_file")
OCI_REGION=$(extract_oci_config "region")

echo "From OCI config profile '${PROFILE_NAME}':"
echo "  tenancy_ocid     = ${OCI_TENANCY}"
echo "  current_user_ocid = ${OCI_USER}"
echo "  fingerprint      = ${OCI_FINGERPRINT}"
echo "  private_key_path = ${OCI_KEY_FILE}"
echo "  region           = ${OCI_REGION}"
```

These values will be used to populate terraform.tfvars automatically — **do not ask the user for them**.

Record the validated profile name for the env file.

---

## Step 7: Python venv (in sandbox)

```bash
python3 -m venv "${DAT_SANDBOX}/venv"
source "${DAT_SANDBOX}/venv/bin/activate"
pip install -r requirements.txt 2>&1 | tail -3
```

This keeps the project's repo-level `venv/` untouched. The sandbox venv is disposable.

---

## Step 8: Playwright setup (spec-based, no MCP)

UI tests run as Playwright spec files via `npx playwright test` from the `tests/e2e/` directory in the repo. This step installs dependencies and the Chromium browser.

### 8a. Install npm dependencies in tests/e2e/

```bash
cd "$(git rev-parse --show-toplevel)/tests/e2e"
npm install 2>&1 | tail -3
```

This installs `@playwright/test` from the existing `package.json` in `tests/e2e/`.

### 8b. Install Chromium browser

```bash
npx playwright install chromium 2>&1 | tail -3
```

Playwright stores browsers in `$HOME/Library/Caches/ms-playwright` (macOS) or `$HOME/.cache/ms-playwright` (Linux) by default. Record this path for the env file:

```bash
if [ "$(uname -s)" = "Darwin" ]; then
  PW_BROWSERS="$HOME/Library/Caches/ms-playwright"
else
  PW_BROWSERS="$HOME/.cache/ms-playwright"
fi
```

### 8c. Verify browser installed

```bash
npx playwright --version && echo "Playwright OK"
ls "${PW_BROWSERS}/chromium-"* > /dev/null 2>&1 && echo "Chromium OK" || echo "WARNING: Chromium not found in ${PW_BROWSERS}"
```

If Chromium is missing, retry with explicit path:

```bash
PLAYWRIGHT_BROWSERS_PATH="${PW_BROWSERS}" npx playwright install chromium
```

> **Note:** No MCP server is needed. Tests are executed directly via `npx playwright test vss/` (or other category dirs) from `tests/e2e/`.

---

## Step 9: Build terraform.tfvars

This step creates or updates `terraform.tfvars` using values from the OCI config profile (Step 6d) and user-provided pack-specific variables.

### 9a. Check if terraform.tfvars exists

```bash
test -f ai-accelerator-tf/terraform.tfvars && echo "tfvars found" || echo "tfvars MISSING"
```

### 9b. If MISSING — create from template

```bash
cp ai-accelerator-tf/terraform.tfvars.example ai-accelerator-tf/terraform.tfvars
```

### 9c. Auto-populate OCI identity values

Use the Edit tool to replace the placeholder values in terraform.tfvars with the values extracted from the OCI config profile in Step 6d:

| tfvars variable | Source (from OCI config) |
|---|---|
| `tenancy_ocid` | `OCI_TENANCY` |
| `current_user_ocid` | `OCI_USER` |
| `fingerprint` | `OCI_FINGERPRINT` |
| `private_key_path` | `OCI_KEY_FILE` |
| `region` | `OCI_REGION` |

**Do NOT ask the user for these** — they come directly from the validated OCI config profile.

### 9d. Ask for compartment OCID

The compartment is NOT in the OCI config. Ask the user: *"What compartment OCID should I use for this deployment?"*

If the user provides a compartment name instead of an OCID, look it up:

```bash
oci iam compartment list --compartment-id-in-subtree true --all --query "data[?name=='<compartment-name>'].id | [0]" --raw-output --profile ${OCI_CLI_PROFILE}
```

Use the Edit tool to set `compartment_ocid` in terraform.tfvars.

### 9e. Ask for common user-provided variables

These apply to **all packs** and cannot be auto-extracted. Ask the user for each:

| Variable | Description | Validation |
|---|---|---|
| `corrino_admin_username` | Blueprints portal login username | minLength: 3, maxLength: 50 |
| `corrino_admin_password` | Blueprints portal login password | Required |
| `corrino_admin_email` | Blueprints portal login email | Required |

Also ask:
- `create_bastion` — *"Enable bastion host? (true/false, default: false)"*
- `use_custom_dns` — *"Use custom DNS? (true/false, default: false)"* — **skip for `enterprise_rag` and `enterprise_rag_aiq`** (hidden in their schemas)
  - If `true`, also ask for `fqdn_custom_domain`

Append these to terraform.tfvars using the Edit tool:

```hcl
# Corrino Admin
corrino_admin_username = "<user-provided>"
corrino_admin_password = "<user-provided>"
corrino_admin_email    = "<user-provided>"
```

### 9f. Set starter pack category and size

Append the pack selection from Step 1:

```hcl
# Starter Pack
starter_pack_category = "<from-step-1>"
starter_pack_size     = "<from-step-1>"
```

### 9g. Ask for pack-specific variables

Based on the `STARTER_PACK_CATEGORY` from Step 1, ask for additional variables that are visible/required for that pack:

**`vss`:**

| Variable | Required? | Description |
|---|---|---|
| `worker_node_availability_domain` | Yes | AD with GPU capacity (e.g., `ktQn:US-SANJOSE-1-AD-1`) |

**`cuopt`:**

| Variable | Required? | Description |
|---|---|---|
| `worker_node_availability_domain` | Yes | AD with GPU capacity |
| `genai_region` | If a frontend skin is enabled | OCI GenAI services region |

> **Note:** For blueprint packs (`cuopt`, `vss`, `paas_rag`), per-skin boolean variables (e.g., `skin_cuopt_core`) control which frontends deploy. Ask the user which skins they want to enable for the chosen pack.

**`enterprise_rag`:**

| Variable | Required? | Description |
|---|---|---|
| `worker_node_availability_domain` | Yes | AD with GPU capacity |

**`enterprise_rag_aiq`:**

| Variable | Required? | Description |
|---|---|---|
| `worker_node_availability_domain` | Yes | AD with GPU capacity |
| `tavily_api_key` | Optional | Tavily search API key for AIQ web search |

**`paas_rag`:**

| Variable | Required? | Description |
|---|---|---|
| `db_password` | Yes | Database password (12+ chars, 1 uppercase, 1 lowercase, 1 number, 1 special char from `!@#$%^&*`) |
| `genai_region` | Yes | OCI GenAI services region |

> **Note:** `worker_node_availability_domain` is NOT required for `paas_rag` (no GPU nodes).

Append all pack-specific variables to terraform.tfvars using the Edit tool.

### 9h. Verify terraform.tfvars is gitignored

```bash
git check-ignore ai-accelerator-tf/terraform.tfvars && echo "gitignored: OK" || echo "WARNING: terraform.tfvars is NOT gitignored — do not commit this file"
```

---

## Step 10: Write env file

Extract all variables from the now-populated terraform.tfvars and write the env file:

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
```

Write the sourceable env file:

```bash
cat > "${DAT_SANDBOX}/env.sh" << ENVEOF
# Auto-generated by /setup — source this before running /deploy-and-test
# Sandbox: ${DAT_SANDBOX}
# Pack: ${STARTER_PACK_CATEGORY} (${STARTER_PACK_SIZE})
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Homebrew PATH fallback (macOS)
if [ -d "/opt/homebrew/bin" ]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:\${PATH}"
fi

# Sandbox paths
export DAT_SANDBOX="${DAT_SANDBOX}"
export PATH="${DAT_SANDBOX}/packages/node_modules/.bin:\${PATH}"
export PLAYWRIGHT_BROWSERS_PATH="$HOME/Library/Caches/ms-playwright"

# OCI
export OCI_CLI_PROFILE="${OCI_CLI_PROFILE}"
export TENANCY_OCID="${TENANCY_OCID}"
export COMPARTMENT_OCID="${COMPARTMENT_OCID}"
export REGION="${REGION}"
export CURRENT_USER_OCID="${CURRENT_USER_OCID}"

# Corrino credentials
export CORRINO_USERNAME="${CORRINO_ADMIN_USERNAME}"
export CORRINO_PASSWORD="${CORRINO_ADMIN_PASSWORD}"
export CORRINO_EMAIL="${CORRINO_ADMIN_EMAIL}"
export DB_PASSWORD="${DB_PASSWORD}"

# Starter pack
export STARTER_PACK_CATEGORY="${STARTER_PACK_CATEGORY}"
export STARTER_PACK_SIZE="${STARTER_PACK_SIZE}"

# Set after deploy (Phase 3 populates these)
export STARTER_PACK_URL=""
export CLUSTER_OCID=""
export STACK_OCID=""
ENVEOF

chmod 600 "${DAT_SANDBOX}/env.sh"
echo "Env file: ${DAT_SANDBOX}/env.sh"
```

**Security:** The env file contains credentials — `chmod 600` ensures only the user can read it. It's in `/tmp/` so it won't survive a reboot.

---

## Step 11: Final verification

```bash
echo "═══════════════════════════════════════"
echo "  SETUP VERIFICATION"
echo "  Sandbox: ${DAT_SANDBOX}"
echo "  Pack: ${STARTER_PACK_CATEGORY} (${STARTER_PACK_SIZE})"
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
npx playwright --version > /dev/null 2>&1 && echo "OK" || echo "MISSING"
printf "  %-12s " "chromium"
ls "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"/chromium-* > /dev/null 2>&1 && echo "OK" || echo "MISSING"
echo ""
echo "Configuration:"
printf "  %-12s " "OCI config"
test -f ~/.oci/config && echo "OK" || echo "MISSING"
printf "  %-12s " "OCI profile"
echo "${OCI_CLI_PROFILE:-NOT SET}"
printf "  %-12s " "tfvars"
test -f ai-accelerator-tf/terraform.tfvars && echo "OK" || echo "MISSING"
printf "  %-12s " "env.sh"
test -f "${DAT_SANDBOX}/env.sh" && echo "OK" || echo "MISSING"
echo ""
echo "Starter pack variables:"
printf "  %-28s " "STARTER_PACK_CATEGORY"
echo "${STARTER_PACK_CATEGORY:-MISSING}"
printf "  %-28s " "STARTER_PACK_SIZE"
echo "${STARTER_PACK_SIZE:-MISSING}"
printf "  %-28s " "CORRINO_USERNAME"
test -n "${CORRINO_ADMIN_USERNAME}" && echo "set" || echo "MISSING"
printf "  %-28s " "CORRINO_PASSWORD"
test -n "${CORRINO_ADMIN_PASSWORD}" && echo "set" || echo "MISSING"
printf "  %-28s " "COMPARTMENT_OCID"
test -n "${COMPARTMENT_OCID}" && echo "set" || echo "MISSING"
echo ""
echo "═══════════════════════════════════════"
```

If everything is OK:

> Setup complete. To start testing:
> ```bash
> source ${DAT_SANDBOX}/env.sh
> ```
> Then run `/deploy-and-test`

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
