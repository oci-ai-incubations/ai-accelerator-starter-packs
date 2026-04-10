# Verify Starter Packs in OCI Console

After publishing to the external repo (`oracle-quickstart/oci-ai-blueprints`), verify that each zip loads the correct pack category in the OCI Console's Create Stack wizard.

## Prerequisites

- agent-browser installed
- OCI Console access (user authenticates manually)
- Unique browser session name (e.g., `--session verify-packs`)

## How Packs Load

Packs are **NOT** in the ORM template picker (Quickstarts/Service/Architecture/Private tabs). They load via direct `zipUrl` query parameter — this is the mechanism the OCI Console "Deploy to Oracle Cloud" buttons use.

**URL pattern:**
```
https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-ai-blueprints/releases/download/starter-packs/<ZIPNAME>.zip
```

## Verification Flow Per Pack

### 1. Navigate to the zipUrl

```bash
agent-browser --session verify-packs open "https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle-quickstart/oci-ai-blueprints/releases/download/starter-packs/<ZIPNAME>.zip"
agent-browser --session verify-packs wait --load networkidle
agent-browser --session verify-packs wait 5000  # Zip download + schema parsing needs extra time
agent-browser --session verify-packs snapshot -i
```

### 2. Accept Terms of Use (Step 1)

The Step 1 page shows a Terms of Use checkbox that MUST be checked before proceeding.

```bash
# Find the unchecked checkbox near "Oracle Terms of Use" link
agent-browser --session verify-packs click @<checkbox-ref> --intent "Accept Oracle Terms of Use"
agent-browser --session verify-packs wait 1000
agent-browser --session verify-packs click @<next-button-ref> --intent "Click Next"
agent-browser --session verify-packs wait 5000
agent-browser --session verify-packs snapshot -i
```

### 3. Handle Intermediate Page (if present)

Some packs show an intermediate Step 1 page with the pack title, description, and "More information" button. This happens when the schema has `logoUrl` / `informational` metadata.

**If you see the pack title heading (h4) instead of variables:** Click Next again.

```bash
agent-browser --session verify-packs click @<next-button-ref> --intent "Click Next to Step 2"
agent-browser --session verify-packs wait 5000
agent-browser --session verify-packs snapshot -i
```

### 4. Verify Step 2 (Configure Variables)

Check the deployment size dropdown label and category-specific fields against the fingerprint matrix below.

### 5. Screenshot

```bash
agent-browser --session verify-packs screenshot /tmp/pack-verification/<ZIPNAME>_<category>.png --full
```

## Zip-to-Category Mapping (with swap)

| Zip Name | Expected Category | URL Slug |
|---|---|---|
| `aiQGenAIPowered.zip` | enterprise_rag | `aiQGenAIPowered.zip` |
| `aiQEnterpriseSearch.zip` | paas_rag | `aiQEnterpriseSearch.zip` |
| `enterpriseAgenticAIStarterKit.zip` | enterprise_rag_aiq | `enterpriseAgenticAIStarterKit.zip` |
| `vehicleRouteOptimizer.zip` | cuopt | `vehicleRouteOptimizer.zip` |
| `videoSearchSummarization.zip` | vss | `videoSearchSummarization.zip` |

## Category Fingerprint Matrix

The most reliable identifier is the **deployment size dropdown label** on Step 2:

| Field/Element | enterprise_rag | paas_rag | enterprise_rag_aiq | cuopt | vss |
|---|---|---|---|---|---|
| Deployment Size label | "Enterprise RAG" | "RAG" | "Enterprise RAG + AIQ" | "cuOpt" | "VSS" |
| Worker Node AD field | Yes | **No** | Yes | Yes | Yes |
| OCI GenAI Services Region | No | **Yes** | No | **Yes** | No |
| Tavily API Key | No | No | **Yes** | No | No |
| Google Maps API Key | No | No | No | **Yes** | No |
| Enable cuOpt Frontend | No | No | No | **Yes** | No |
| cuOpt Frontend creds | No | No | No | **Yes** | No |
| Oracle 26ai Database section | **Yes** | **Yes** | No | No | No |
| Use Custom DNS | No | **Yes** | No | **Yes** | **Yes** |

## Quirks and Gotchas

1. **iframe:** The entire ORM form is inside `Iframe "Content body"`. agent-browser handles this transparently — refs from snapshot work across the iframe boundary.

2. **Two-click Next pattern:** When a schema has `logoUrl`/`informational` metadata, the first "Next" shows an intermediate page with the pack title (still Step 1). Click Next AGAIN to reach Step 2.

3. **Wait times:** Zip download + schema parsing needs `wait 5000` after navigation AND after clicking Next. `wait --load networkidle` alone is insufficient — variables render asynchronously.

4. **Terms checkbox:** No label — it's just `checkbox [checked=false]` near `link "Oracle Terms of Use"`. Use the ref from snapshot.

5. **Ref instability:** After every navigation or page transition, refs are invalidated. Always re-snapshot.

6. **Pack title on intermediate page:** The h4 heading shows the pack's display name (e.g., "Enterprise Agentic AI Starter Kit"). The Name field shows `<zipname>-<timestamp>`.
