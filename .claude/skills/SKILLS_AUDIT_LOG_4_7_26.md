# Skills Audit Log — 2026-04-07

Audited all 27 skills (25 active + 2 archived) against the Anthropic Agent Skills Best Practices specification (`skills-best-practices.md`).

## Audit Criteria

| # | Criterion | Source |
|---|---|---|
| C1 | `name` field: max 64 chars, lowercase letters/numbers/hyphens only, no reserved words | Skill structure |
| C2 | `description` field: non-empty, max 1024 chars, third person, includes WHAT + WHEN to use | Writing effective descriptions |
| C3 | SKILL.md body under 500 lines | Token budgets |
| C4 | Progressive disclosure: detail in separate files, references one level deep | Progressive disclosure patterns |
| C5 | Concise: don't over-explain what Claude already knows | Core principles |
| C6 | No hardcoded user-specific paths or environment values | Portability / anti-patterns |
| C7 | Consistent naming pattern across skill collection | Naming conventions |
| C8 | No time-sensitive information | Content guidelines |
| C9 | Consistent terminology | Content guidelines |
| C10 | Clear workflow steps with appropriate degrees of freedom | Workflows and feedback loops |

Severity: **CRITICAL** = violates a hard rule, **MAJOR** = significant quality issue, **MINOR** = improvement opportunity, **PASS** = meets best practices.

---

## Cross-Cutting Findings

### FINDING-X1: Hardcoded User Paths (CRITICAL)

**5 skills** reference `/Users/dkennetz/code/ai-accelerator/` — a different user's home directory. These paths are broken for every other developer. Should use relative paths or `$(git rev-parse --show-toplevel)`.

| Skill | Line(s) | Hardcoded Path |
|---|---|---|
| `lint` | 17 | `cd /Users/dkennetz/code/ai-accelerator/ai-accelerator-tf` |
| `schema-gen` | 20 | `cd /Users/dkennetz/code/ai-accelerator` |
| `integration-test` | 30 | `cd /Users/dkennetz/code/ai-accelerator` |
| `unit-test` | 20 | `cd /Users/dkennetz/code/ai-accelerator/ai-accelerator-tf` |
| `update-stack` | 21, 39 | `cd /Users/dkennetz/code/ai-accelerator`, path to `lifecycle.zip` |

**Fix:** Replace all `/Users/dkennetz/code/ai-accelerator` with `$(git rev-parse --show-toplevel)` or relative paths from the repo root.

### FINDING-X2: Hardcoded OCI Credentials / Profiles (MAJOR)

| Skill | Issue |
|---|---|
| `destroy-stack` | Hardcoded `OCI_CLI_PROFILE=SANJOSE` (line 21) |
| `destroy-stack` | Hardcoded compartment OCID `ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3g...` (line 21) |
| `update-stack` | Hardcoded `OCI_CLI_PROFILE=SANJOSE` (line 38) |

**Fix:** Replace with parameterized profile selection (ask the user or accept as argument), like `checking-capacity`, `diagnosing-stack`, and `monitoring-deployment` already do correctly.

### FINDING-X3: SKILL.md Over 500-Line Limit (MAJOR)

Best practices: *"Keep SKILL.md body under 500 lines for optimal performance. If your content exceeds this, split it into separate files."*

| Skill | Lines | Over by |
|---|---|---|
| `agent-browser` | 750 | +250 (50% over) |
| `setup` | 628 | +128 (26% over) |
| `deploy-and-test` | 610 | +110 (22% over) |
| `vss-test-coverage` | 583 | +83 (17% over) |
| `testing-pack` | 530 | +30 (6% over) |

**Fix:** Extract command references, common patterns, and detailed steps into separate `.md` files. Keep SKILL.md as a high-level guide with links. Some skills (`deploy-and-test`, `testing-pack`) already use `references/` directories but still pack too much into SKILL.md.

### FINDING-X4: Inconsistent Naming Patterns (MINOR)

The skill collection mixes three naming conventions:

| Convention | Skills |
|---|---|
| **Gerund (verb+ing)** — *recommended* | `checking-capacity`, `monitoring-deployment`, `diagnosing-stack`, `releasing`, `testing-pack` |
| **Noun phrase** | `bug-tracker`, `unit-test`, `integration-test`, `schema-lint`, `schema-gen`, `vss-benchmark` |
| **Action phrase (verb)** | `deploy-and-test`, `create-worktree`, `sync-versions`, `update-stack`, `destroy-stack`, `review-pr` |
| **Generic/ambiguous** | `lint`, `setup`, `oci-cli` |

Best practices: *"Use consistent naming patterns to make Skills easier to reference. Consider using gerund form."*

**Fix:** Not urgent, but for new skills prefer gerund form. The generic names `lint`, `setup`, and `oci-cli` should be renamed to be more specific (see per-skill findings below).

### FINDING-X5: Description Quality Variance (MINOR)

Some descriptions are exemplary (include what + when + trigger keywords):
- `schema-lint`, `checking-capacity`, `diagnosing-stack`, `testing-pack`, `create-worktree`

Others only describe WHAT without WHEN/triggers:
- `destroy-stack`, `schema-gen`, `lint`, `oci-cli`, `integration-test`

---

## Per-Skill Audit

### 1. `destroy-stack` — 40 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid format |
| C2 Description | **MAJOR** | Missing trigger keywords — no "when to use" guidance. Should add: "Use when the user says 'tear down', 'destroy stack', 'clean up infra', or after testing is complete." |
| C3 Line limit | PASS | 40 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded SANJOSE profile and compartment OCID (see X1, X2) |
| C10 Workflow | PASS | Clear sequential steps |

---

### 2. `agent-browser` — 750 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid format |
| C2 Description | PASS | Excellent — comprehensive triggers |
| C3 Line limit | **MAJOR** | 750 lines, 50% over limit |
| C4 Disclosure | **MAJOR** | Has `references/` directory but doesn't leverage it enough. Commands reference, patterns, and auth sections should be in separate files. |
| C5 Concise | **MINOR** | Over-explains some basics Claude likely knows (form submission patterns, basic click workflows). The "Common Patterns" and "Security" sections could be in separate reference files. |

**Recommendation:** Keep core workflow (lines 1-50), essential commands (lines 107-203), ref lifecycle, and the deep-dive table in SKILL.md. Move everything else to reference files: `references/patterns.md`, `references/security.md`, `references/advanced.md`.

---

### 3. `lint` — 29 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | **MINOR** | `lint` is too generic. Best practices say avoid "vague names: `helper`, `utils`, `tools`". Better: `linting-terraform` or `terraform-lint`. |
| C2 Description | **MINOR** | Missing trigger keywords. Add: "Use when the user says 'lint', 'check formatting', 'run checks', or before committing Terraform changes." |
| C3 Line limit | PASS | 29 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded `/Users/dkennetz/code/ai-accelerator/ai-accelerator-tf` |

---

### 4. `enterprise-rag-test-coverage` — 96 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid, descriptive |
| C2 Description | PASS | Includes what + context |
| C3 Line limit | PASS | 96 lines |
| C4 Disclosure | PASS | Excellent — splits into `api-tests.md`, `ui-tests.md`, `infra-tests.md` |
| C10 Workflow | PASS | Clear test file organization |

**Status: PASS** — Well-structured skill with proper progressive disclosure.

---

### 5. `schema-lint` — 117 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Excellent — includes what, when, and trigger keywords |
| C3 Line limit | PASS | 117 lines |
| C4 Disclosure | PASS | References `references/common-bugs.md` (one level deep) |
| C10 Workflow | PASS | Clear numbered steps |

**Status: PASS** — Exemplary skill. Good model for others.

---

### 6. `schema-gen` — 35 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid format |
| C2 Description | **MINOR** | Missing trigger keywords. Add: "Use when the user says 'generate schema', 'rebuild schema', or before creating ORM zips." |
| C3 Line limit | PASS | 35 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded `/Users/dkennetz/code/ai-accelerator` |
| C9 Terminology | **MINOR** | Category list in arguments missing `enterprise_rag_aiq` — inconsistent with the 5-pack convention used everywhere else |

---

### 7. `diagnosing-stack` — 321 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Gerund form, descriptive |
| C2 Description | PASS | Excellent — what, when, triggers, and behavioral constraint (read-only) |
| C3 Line limit | PASS | 321 lines |
| C4 Disclosure | PASS | References `references/kubeconfig-patching.md`, `references/error-catalog.md` |
| C10 Workflow | PASS | Clear phased approach, good output template |

**Status: PASS** — Exemplary skill.

---

### 8. `archive` — No SKILL.md

| Criterion | Status | Notes |
|---|---|---|
| — | **MINOR** | Not a functional skill. Contains `old-release-push/` and `old-release-upgrade/` subdirectories with their own SKILL.md files. While these archived skills don't appear in the active skill list, the `archive/` directory appearing in `.claude/skills/` could confuse skill discovery. |

**Recommendation:** Move `archive/` outside `.claude/skills/` (e.g., to `.claude/skills-archive/`) or add a README clarifying it's not an active skill.

---

### 9. `bug-tracker` — 117 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Includes comprehensive trigger list |
| C3 Line limit | PASS | 117 lines |
| C10 Workflow | PASS | Clear usage patterns, template, severity guide |

**Status: PASS** — Well-structured.

---

### 10. `zip-tf` — 77 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid, concise |
| C2 Description | PASS | Includes what + when + triggers |
| C3 Line limit | PASS | 77 lines |
| C10 Workflow | PASS | Clear numbered steps with verification |

**Status: PASS** — Good skill with verification step (aligns with "feedback loops" best practice).

---

### 11. `monitoring-deployment` — 318 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Gerund form |
| C2 Description | PASS | Includes what + when |
| C3 Line limit | PASS | 318 lines |
| C10 Workflow | **MINOR** | Step numbering error: Section 3.4 appears twice (lines 153 and 169). Second should be 3.5, and subsequent sections renumbered. |

**Overall: PASS with minor numbering fix needed.**

---

### 12. `cuopt-test-coverage` — 85 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid, descriptive |
| C2 Description | PASS | Good |
| C3 Line limit | PASS | 85 lines |
| C4 Disclosure | PASS | Progressive disclosure into phase files |

**Status: PASS**

---

### 13. `setup` — 628 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | **MINOR** | `setup` is overly generic. Best practices say avoid generic names. Better: `sandbox-setup` or `setting-up-sandbox`. |
| C2 Description | PASS | Good — describes what + when |
| C3 Line limit | **MAJOR** | 628 lines, 26% over limit |
| C4 Disclosure | **MAJOR** | All 11 steps are in SKILL.md. Steps 4 (tool install), 8 (Playwright), and 9 (tfvars) could each be separate files. |
| C10 Workflow | PASS | Excellent sequential workflow with verification |

**Recommendation:** Split into: `SKILL.md` (overview + steps 1-3, 10-11), `TOOL_INSTALL.md` (step 4), `PLAYWRIGHT_SETUP.md` (step 8), `TFVARS_BUILDER.md` (step 9).

---

### 14. `paas-rag-test-coverage` — 90 lines

| Criterion | Status | Notes |
|---|---|---|
| All | PASS | Well-structured with progressive disclosure |

**Status: PASS**

---

### 15. `integration-test` — 53 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | **MINOR** | Missing trigger keywords. Add: "Use when the user says 'run integration tests', 'test the stack', or 'deploy to ORM'." |
| C3 Line limit | PASS | 53 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded `/Users/dkennetz/code/ai-accelerator` |

---

### 16. `vss-benchmark` — 238 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Clear |
| C3 Line limit | PASS | 238 lines |
| C10 Workflow | PASS | Clear steps with auto-select logic |

**Status: PASS**

---

### 17. `unit-test` — 41 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Clear |
| C3 Line limit | PASS | 41 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded `/Users/dkennetz/code/ai-accelerator/ai-accelerator-tf` |

---

### 18. `checking-capacity` — 172 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Gerund form |
| C2 Description | PASS | Excellent — includes what, when, triggers |
| C3 Line limit | PASS | 172 lines |
| C10 Workflow | PASS | Clear phased approach with report template |

**Status: PASS** — Exemplary.

---

### 19. `sync-versions` — 70 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Includes what + when |
| C3 Line limit | PASS | 70 lines |
| C10 Workflow | PASS | Clear 4-step process |

**Status: PASS**

---

### 20. `vss-test-coverage` — 583 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Good |
| C3 Line limit | **MAJOR** | 583 lines, 17% over limit |
| C4 Disclosure | **MINOR** | Already has phase-specific files (`api-tests.md`, `ui-tests.md`, `infra-tests.md`) but the overview SKILL.md itself is still over 500 lines. Some architecture detail or known-issues could be extracted. |

**Recommendation:** Move the detailed architecture components table, known issues, and environment variable tables into a `REFERENCE.md` file. Keep SKILL.md as a concise overview that points to the phase files and reference.

---

### 21. `oci-cli` — 113 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | **MINOR** | `oci-cli` is somewhat generic. Better: `running-oci-commands` or keep as-is since it's a tool name. |
| C2 Description | **MINOR** | Missing trigger keywords. Should add: "Use when the user says 'list instances', 'check OCI', 'query compartments', or needs to run any OCI API operation." |
| C3 Line limit | PASS | 113 lines |
| C5 Concise | **MINOR** | Lists many common OCI commands that Claude could figure out from `oci --help`. The value-add is the ask-before-running pattern and profile setup, not the command catalog. |

---

### 22. `review-pr` — 213 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Clear |
| C3 Line limit | PASS | 213 lines |
| C10 Workflow | PASS | Well-structured 6-step process with templates |

**Status: PASS**

---

### 23. `create-worktree` — 116 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Includes triggers |
| C3 Line limit | PASS | 116 lines |
| C10 Workflow | PASS | Clear steps, good common-mistakes table |

**Status: PASS**

---

### 24. `deploy-and-test` — 610 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Good |
| C3 Line limit | **MAJOR** | 610 lines, 22% over limit |
| C4 Disclosure | **MAJOR** | Phase 3 (testing) is extremely detailed and could leverage the test-coverage skills as separate reference files instead of embedding test orchestration inline. The GPU capacity table (Step 2) and sandbox env table (Step 0a) are duplicated from other skills (`checking-capacity`, `setup`). |
| C5 Concise | **MINOR** | Some information is duplicated from `setup` (sandbox dirs table) and `checking-capacity` (GPU shape table). DRY principle suggests referencing those skills instead of repeating. |

**Recommendation:** Extract Phase 1 (capacity check) into a "call `/checking-capacity`" reference. Extract Phase 3 test orchestration details into a `TESTING.md` file. Keep SKILL.md as the high-level workflow.

---

### 25. `testing-pack` — 530 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Includes triggers |
| C3 Line limit | **MAJOR** | 530 lines, 6% over limit |
| C4 Disclosure | **MINOR** | Already uses `references/` directory well (`orm-browser-nav.md`, `cdp-file-upload.md`, `kubeconfig-patching.md`). Phase 5 (app stack) could be condensed since it mirrors Phase 4 closely. |

**Recommendation:** Deduplicate Phase 4 and Phase 5 (infra vs app stack) into a shared reference or condense Phase 5 to only describe differences from Phase 4.

---

### 26. `update-stack` — 44 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Valid |
| C2 Description | PASS | Clear |
| C3 Line limit | PASS | 44 lines |
| C6 Hardcoded | **CRITICAL** | Hardcoded `/Users/dkennetz/code/ai-accelerator` paths (lines 21, 39) AND hardcoded `OCI_CLI_PROFILE=SANJOSE` (line 38) |

---

### 27. `releasing` — 333 lines

| Criterion | Status | Notes |
|---|---|---|
| C1 Name | PASS | Gerund form — recommended style |
| C2 Description | PASS | Excellent — what, when, triggers |
| C3 Line limit | PASS | 333 lines |
| C4 Disclosure | PASS | Uses `PARALLEL_TESTING.md` and `LESSONS_LEARNED.md` references |
| C10 Workflow | PASS | Clear phased approach with delegation map and checklist |

**Status: PASS** — Well-structured orchestrator skill.

---

## Summary

### Issue Counts by Severity

| Severity | Count | Skills Affected |
|---|---|---|
| **CRITICAL** | 7 | `lint`, `schema-gen`, `integration-test`, `unit-test`, `update-stack` (hardcoded paths), `destroy-stack` (hardcoded profile + OCID), `update-stack` (hardcoded profile) |
| **MAJOR** | 8 | `agent-browser`, `setup`, `deploy-and-test`, `vss-test-coverage`, `testing-pack` (over 500 lines), `destroy-stack` (description), `destroy-stack`/`update-stack` (hardcoded credentials) |
| **MINOR** | 12 | Naming, missing triggers, numbering, generic names, description quality |
| **PASS** | 13 | `enterprise-rag-test-coverage`, `schema-lint`, `diagnosing-stack`, `bug-tracker`, `zip-tf`, `cuopt-test-coverage`, `paas-rag-test-coverage`, `vss-benchmark`, `checking-capacity`, `sync-versions`, `review-pr`, `create-worktree`, `releasing` |

### Top Priority Fixes

1. **Fix all hardcoded `/Users/dkennetz/` paths** (5 skills) — These are broken for every developer except dkennetz. Affects: `lint`, `schema-gen`, `integration-test`, `unit-test`, `update-stack`.

2. **Fix hardcoded OCI profiles and OCIDs** (2 skills) — `destroy-stack` and `update-stack` hardcode `SANJOSE` profile and a specific compartment.

3. **Split 5 over-limit SKILL.md files** — `agent-browser` (750), `setup` (628), `deploy-and-test` (610), `vss-test-coverage` (583), `testing-pack` (530) all exceed the 500-line body limit.

4. **Add trigger keywords to 5 descriptions** — `destroy-stack`, `schema-gen`, `lint`, `oci-cli`, `integration-test` describe WHAT but not WHEN.

5. **Rename generic skills** — `lint` → `linting-terraform`, `setup` → `sandbox-setup` (optional but recommended).

### Skills That Are Exemplary (Use as Templates)

- **`schema-lint`** — Perfect description with triggers, clear workflow, references one level deep
- **`checking-capacity`** — Gerund naming, excellent description, clear phased workflow
- **`diagnosing-stack`** — Gerund naming, read-only constraint clearly stated, phased approach
- **`releasing`** — Gerund naming, delegation map, checklist pattern, progressive disclosure

---

*Audited by Claude Opus 4.6 on 2026-04-07*
