# OCI IAM Identity Domains (IDCS) Integration

This guide wires a customer's **OCI IAM Identity Domain** (formerly **OCI IDCS**) into a
deployed accelerator pack's `accelerator-pack-auth-service` as an OpenID Connect (OIDC)
identity provider. Both names refer to the same product — older tenancies and the OCI
console UI still use "IDCS" in places; newer marketing and the API surface use
"Identity Domains". They are interchangeable for the purposes of this integration.

The worked example targets the cuopt pack deployed at
`https://demo-cuopt-partner.161-153-59-50.nip.io` (region `phx`). Substitute your own
pack hostname for production.

---

## At a glance

**What this integration does:**

- Federates **human SSO** from a customer's OCI tenancy into the pack's auth-service.
  An employee with an Identity Domain login lands at `/login`, clicks "Login with
  Oracle Identity Domains", authenticates against their corporate identity, and is
  returned to the pack with an internal RS256 JWT issued by the pack's auth-service.
- Just-in-time (JIT) provisions a local `User` row keyed by the IDCS `sub` claim.
- Maps IDCS claims (`groups`, `email`, custom claims) to pack roles via the
  `/auth/providers/{id}/mappings` API.

**What this integration does NOT do:**

- Machine-to-machine OAuth2 (`client_credentials` grant) between an IDCS-issued token
  and the pack. That uses the auth-service's **trusted issuers** path with JWKS
  verification — a separate doc (TODO).
- Federate **the pack's** internal admin/service-account tokens out to IDCS. The pack
  always issues its own RS256 tokens after SSO; it does not re-emit IDCS tokens.
- SCIM provisioning from IDCS. Auth-service exposes SCIM 2.0 (`/scim/v2/...`) but the
  IDCS-side SCIM client configuration is out of scope here.

---

## Prerequisites

- An OCI tenancy with at least one **Identity Domain** (Free, Premium, External User,
  or Oracle Apps tier — all support OIDC application registration).
- **Identity Domain Administrator** role on the target domain — required to create
  Confidential Applications.
- A deployed accelerator pack reachable over HTTPS, with **admin** credentials for the
  pack's auth-service (to call `POST /auth/providers`).
- The pack frontend's **public URL**, terminating in TLS. The OIDC redirect must be
  HTTPS; `http://` redirects are rejected by IDCS. For this guide:
  `https://demo-cuopt-partner.161-153-59-50.nip.io`.
- `curl` and `jq` installed locally for verification commands.
- A test user in the Identity Domain that you can log in as (a fresh user works fine
  for verifying JIT provisioning).

**Verify pack reachability before continuing:**

```bash
PACK_URL="https://demo-cuopt-partner.161-153-59-50.nip.io"

curl -sk "${PACK_URL}/auth/health"
# Expected: {"status":"ok"} or similar 200 response
```

---

## The chicken-and-egg bootstrap (first-time deploy)

If you are deploying with a custom DNS which is already registered, you can skip this step. 

IDCS's Confidential Application registration needs the pack's public URL
(for Primary Audience + Redirect URL). The pack's public URL doesn't
exist until the pack is deployed. So the very first time you bring a
pack online with IDCS SSO, you do **two TF applies** with a Console
detour in between.

| Phase | TF state | What happens |
|---|---|---|
| 1. Bootstrap deploy | `enable_auth_service=true`, `enable_oracle_oidc_idcs=false`, all IDCS tfvars empty | Pack starts; auth-service runs with local login only; pack URL becomes known. |
| 2. Console detour | (no TF) | Operator registers the Confidential App in IDCS using the pack URL from phase 1 outputs. IDCS returns `client_id` + `client_secret`. |
| 3. Enable-OIDC apply | Same TF root + new tfvars with IDCS credentials. `enable_oracle_oidc_idcs=true`. | Re-apply rolls the auth-service pod with `AUTH_OIDC_ORACLE_IDCS_*` env vars; operator finishes by calling `POST /auth/providers` once (the env-driven auto-seed is a future enhancement). |

If you skip phase 1 and try to set the tfvars upfront, you have nothing
to put in `auth_oidc_oracle_idcs_client_id` — IDCS hasn't minted them
yet. If you skip phase 3, the auth-service pod has no IDCS provider
registered and `/auth/sso/oracle-idcs/authorize` returns 404.

This is a one-time per-cluster cost. Subsequent IDCS-credential
rotations are single-apply: update the tfvars `*_client_secret` value
and re-apply.

The TF output `sso_callback_redirect_uris` (added in
`ai-accelerator-tf/outputs.tf`) emits the expected redirect-URL template
for each enabled frontend skin — copy it into the IDCS Console rather
than hand-typing the URL.

---

## Step 1: Register a Confidential Application in IDCS

The OCI Console workflow has two collapsible sections on the OAuth Configuration
page — **Resource Server** at the top and **Client Configuration** below it. We
fill out resource server first (defines what the app *exposes*: audience + scopes),
then client (defines how the app *authenticates*: grant types + redirect URLs).

1. Sign in to the **OCI Console** with an account that has Identity Domain admin
   privileges.
2. Open the navigation menu → **Identity & Security** → **Domains**.
3. Click the **Identity Domain** that will federate users (e.g. `Default` or a
   customer-specific domain).
4. In the left rail click **Integrated applications** → **Add application** at the
   top of the page.
5. Choose **Confidential Application** → **Launch workflow**.
6. **Add application details** page:
   - **Name:** `Cuopt Pack Login` (or another customer-facing name).
   - **Description:** optional.
   - **Application icon:** optional.
   - Click **Next**.

7. **Configure OAuth** page — **Resource Server Configuration** (top section).
   Toggle **Configure this application as a resource server now**.
   - **Access token expiration:** leave default (3600 seconds is fine — the pack
     re-issues its own short-lived tokens regardless).
   - **Refresh token expiration:** leave default.
   - **Is refresh token allowed:** **yes**.
   - **Primary audience:**
     `https://demo-cuopt-partner.161-153-59-50.nip.io/auth/sso/oracle-idcs/`
     The trailing slash matters — the audience is a URL prefix and must match
     `CUOPT_AUTH_TOKEN_AUDIENCE` (or whatever audience your pack BE validates).
   - **Secondary audiences:** skip.
   - **Scopes** — click **+ Add scopes** and for each pack permission you want to
     expose, fill in:
     | Scope name | Description | Requires consent |
     |---|---|---|
     | `cuopt.solve` | Submit cuopt optimization requests | **unchecked** |
     | `cuopt.view` | View cuopt history | **unchecked** |
     | `chat.use` | Interact with the pack chat agent | **unchecked** |
     | `weather.view` | Query weather context for routes | **unchecked** |
     | `config.read` | Read pack configuration | **unchecked** |
     | `admin.users.manage` | Manage users (admin) | **unchecked** |
     | `admin.audit.view` | View audit logs (admin) | **unchecked** |

     **Why "Requires consent" stays unchecked:** the customer runs both the pack and
     the identity domain — this is first-party SSO, not third-party access
     delegation. The consent flow exists for "Sign in with Google" style flows where
     a random app is asking for your data; here it's just a per-login interruption
     for users who already trust the app. The `Bypass consent` toggle in the Client
     section below globally suppresses consent for this app regardless of per-scope
     settings, so leaving the scopes unchecked is the consistent choice.

     Note the **full scope** value IDCS shows for each entry — it has the form
     `<primary_audience><short_name>`, e.g.
     `https://demo-cuopt-partner.161-153-59-50.nip.io/auth/sso/oracle-idcs/cuopt.solve`.
     Auth-service stores the **short name** in claim mappings; the URL form is what
     IDCS embeds in tokens (auth-service splits on the audience prefix).

8. **Configure OAuth** page — **Client Configuration** (scroll down). Toggle
   **Configure this application as a client now**.
   - **Allowed grant types:** check **Authorization code**, **Refresh token**,
     **and Client Credentials**. The first two drive the user login flow. The third
     is needed because IDCS gates its JWKS endpoint behind an OAuth bearer token —
     auth-service performs a `client_credentials` grant under the hood to fetch
     signing keys (see "Why we need Client Credentials + an app role" below). Do
     NOT enable Implicit, Resource owner, or JWT assertion grants.
   - **Allow non-HTTPS URLs:** leave **unchecked**.
   - **Redirect URL:**
     `https://demo-cuopt-partner.161-153-59-50.nip.io/sso/callback/oracle-idcs`
     The frontend's `<SSOCallback>` route at `/sso/callback/:slug` handles this. The
     path deliberately sits outside `/auth/*` because the ingress routes `/auth/*`
     unconditionally to the auth-service pod; an FE callback under that prefix
     would be shadowed and return 404. The `oracle-idcs` slug must match the
     provider you register in Step 3.
   - **Post-logout redirect URL:** `https://demo-cuopt-partner.161-153-59-50.nip.io/login`
   - **Logout URL:** leave blank (optional).
   - **Client type:** **Confidential**.
   - **Bypass consent:** check this so users aren't prompted at every login (see
     "Why" rationale in the Resource Server section above).
   - **Client IP Address:** **Anywhere**. Restricting by Network Perimeter is for
     deployments where the OAuth client is on a known IP range — our pack BE
     reaches IDCS from the cluster, which is dynamic.
   - **Token issuance policy:** **All**. "Specific" lets you whitelist which users
     can get tokens through this app; "All" allows any user in the identity domain
     who completes the auth-code flow. Use "Specific" later if you need per-app
     allowlists.
   - **Add resources:** leave **unchecked**. This is for the case where this app
     is itself an OAuth client of *another* app's API (delegated access). We're
     going the other direction — this app is the resource the user accesses.
   - **Add app roles:** click **Add app role** and grant the app a role that
     allows reading `/admin/v1/SigningCert/jwk`. **"Identity Domain Administrator"**
     is the reliably-working choice; "Authenticator Client" is too narrow on most
     tenants. See "Why we need Client Credentials + an app role" immediately below.

> **Why we need Client Credentials + an app role.** Standard OIDC has each
> Identity Provider serve its signing keys at a public `jwks_uri`. IDCS deviates
> from the spec: it advertises `jwks_uri` at `/admin/v1/SigningCert/jwk`, which
> rejects unauthenticated requests on hardened identity domains (a 401). To
> verify the ID token signature, auth-service therefore performs a
> `client_credentials` grant against the IDCS token endpoint using this app's
> credentials, then retries the JWKS fetch with `Authorization: Bearer`. That
> grant only works if the app (a) has `Client Credentials` enabled in its allowed
> grant types and (b) has been granted an identity-domain app role that includes
> read access to the SigningCert endpoint. The token is cached in-process per
> `(token_url, client_id)` until shortly before its IdP-reported expiry, so the
> CC round-trip is paid at most a handful of times an hour, not per login.
>
> **Minimum role.** If you're security-paranoid, try the smallest role you can
> find that mentions SigningCert / OAuth Trust / Signing Key access; restart
> auth-service or trigger a fresh login; if the JWKS fetch still 401s, broaden
> the role and try again. Identity Domain Administrator is overkill but always
> works. A future auth-service change may relax this requirement by switching to
> token introspection — track that in your follow-up issues if you take this
> path.

9. Click **Next** → **Finish**.
10. You land on the application detail page. **Activate** the application via the
    button at the top (the app is created in **Inactive** state).
11. Click the **OAuth configuration** tab and copy:
    - **Client ID** (UUID-shaped).
    - **Client secret** — click **Show secret**, copy it. IDCS lets you re-fetch
      this from the same screen, but treat it as a real secret.

Set them in your shell for the remaining steps:

```bash
IDCS_CLIENT_ID="<paste-client-id>"
IDCS_CLIENT_SECRET="<paste-client-secret>"
```

---

## Step 2: Identify your Identity Domain's discovery URL

Each Identity Domain has a unique base URL of the form
`https://idcs-<32-hex-chars>.identity.oraclecloud.com` (or a vanity URL if your
tenancy uses one). The OIDC discovery document lives at
`/.well-known/openid-configuration` relative to that base.

1. From the **Domain overview** page in the OCI Console copy the **Domain URL**. It
   looks like `https://idcs-abc123def456.identity.oraclecloud.com`.
2. Fetch and validate the discovery document:

```bash
IDCS_DOMAIN_URL="https://idcs-<your-id>.identity.oraclecloud.com"

curl -s "${IDCS_DOMAIN_URL}/.well-known/openid-configuration" | jq '{
  issuer,
  authorization_endpoint,
  token_endpoint,
  userinfo_endpoint,
  jwks_uri,
  response_types_supported
}'
```

**Expected output:**

```json
{
  "issuer": "https://idcs-abc123def456.identity.oraclecloud.com",
  "authorization_endpoint": "https://idcs-abc123def456.identity.oraclecloud.com/oauth2/v1/authorize",
  "token_endpoint": "https://idcs-abc123def456.identity.oraclecloud.com/oauth2/v1/token",
  "userinfo_endpoint": "https://idcs-abc123def456.identity.oraclecloud.com/oauth2/v1/userinfo",
  "jwks_uri": "https://idcs-abc123def456.identity.oraclecloud.com/admin/v1/SigningCert/jwk",
  "response_types_supported": ["code", "token", "id_token", "code id_token", "token id_token"]
}
```

**Record the `issuer` value verbatim.** The auth-service compares the `iss` claim of
incoming ID tokens against this string character-for-character. For modern Identity
Domains the issuer is the per-tenant domain URL above. For legacy IDCS instances it
may be the literal string `https://identity.oraclecloud.com/` — use whatever
discovery returns.

**Record the `jwks_uri` value.** IDCS uses the non-standard path
`/admin/v1/SigningCert/jwk` (not `/oauth2/v1/keys` or `/jwks.json`), and on most
identity domains it rejects unauthenticated GETs. Auth-service handles this
transparently by performing a `client_credentials` grant and retrying the JWKS
fetch with a bearer token — which is why Step 1 enables that grant type and
adds an app role to the OAuth client. Confirm the gate yourself with:

```bash
# Returns HTTP 401 on hardened identity domains (expected):
curl -sk -o /dev/null -w '%{http_code}\n' "${IDCS_DOMAIN_URL}/admin/v1/SigningCert/jwk"
```

If you get a 200 instead, your identity domain serves JWKS publicly and the
Client Credentials grant + app role steps in Step 1 are belt-and-braces but not
strictly required.

---

## Step 3: Register IDCS as an OIDC provider in auth-service

You need an **admin** access token from the pack's auth-service. If the pack was
first-user-bootstrapped, the first registered user is automatically an admin — log in
with that account.

```bash
PACK_URL="https://demo-cuopt-partner.161-153-59-50.nip.io"

ADMIN_TOKEN=$(curl -sk -X POST "${PACK_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"<admin-email>","password":"<admin-password>"}' \
  | jq -r '.access_token')

# Verify the token works:
curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" "${PACK_URL}/auth/me" | jq
# Expected: 200 with your user object including role(s)
```

Register IDCS as a provider:

```bash
curl -sk -X POST "${PACK_URL}/auth/providers" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"oidc\",
    \"slug\": \"oracle-idcs\",
    \"name\": \"Oracle Identity Domains\",
    \"config\": {
      \"issuer\": \"${IDCS_DOMAIN_URL}\",
      \"client_id\": \"${IDCS_CLIENT_ID}\",
      \"client_secret\": \"${IDCS_CLIENT_SECRET}\",
      \"scope\": \"openid email profile groups\"
    },
    \"is_active\": true,
    \"priority\": 100
  }" | jq
```

**Expected response:** `201 Created` with the full provider object including a
numeric `id`. Capture it:

```bash
PROVIDER_ID=$(curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${PACK_URL}/auth/providers" | jq '.[] | select(.slug=="oracle-idcs") | .id')
echo "${PROVIDER_ID}"
```

**Notes:**

- The auth-service auto-fetches the OIDC discovery document on first authorize call
  and caches `authorize_url`, `token_url`, `userinfo_url`, and `jwks_url` from it.
  You do **not** need to supply those manually. (If discovery is unreachable from the
  pack pod's network, add them explicitly under `config` as a fallback.)
- The `scope` value above includes `groups`. IDCS only emits `groups` in tokens if
  you've added a custom claim mapping — see **Troubleshooting** below.
- `slug` must be unique across providers and is the URL segment in
  `/auth/sso/{slug}/...`. Keep it stable; renaming requires deleting and recreating
  the provider, which orphans existing external-identity links.

Verify the public discovery endpoint now lists IDCS:

```bash
curl -sk "${PACK_URL}/auth/sso/providers" | jq
# Expected: array containing an object with slug="oracle-idcs", type="oidc", is_active=true
```

---

## Step 4 (optional): Define claim → role mappings

By default, JIT-provisioned users land in the pack's default role (typically `user`
or `pending`, depending on the pack model). To grant admin or pack-specific roles
based on IDCS attributes, register claim mappings.

First, list the role IDs in the pack:

```bash
curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${PACK_URL}/auth/roles" | jq '.[] | {id, name}'
```

Example: grant the pack's `admin` role to anyone in the IDCS group
`cuopt-admins`:

```bash
ADMIN_ROLE_ID=<paste-from-above>

curl -sk -X POST "${PACK_URL}/auth/providers/${PROVIDER_ID}/mappings" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"claim_key\": \"groups\",
    \"claim_value_pattern\": \"cuopt-admins\",
    \"role_id\": ${ADMIN_ROLE_ID},
    \"priority\": 100,
    \"is_regex\": false
  }" | jq
```

**Verify the mapping registered:**

```bash
curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${PACK_URL}/auth/providers/${PROVIDER_ID}/mappings" | jq
# Expected: array containing the mapping you just created
```

**IDCS does not emit a `groups` claim by default** — see **Troubleshooting** below
for how to add it in the IDCS application config. If you don't want to depend on
groups, you can map on `email` (e.g. `claim_value_pattern: ".*@oracle\\.com$"` with
`is_regex: true`) or any other claim IDCS returns.

---

## Step 5: Test the SSO flow end-to-end

### Browser flow (recommended for first verification)

1. Open `https://demo-cuopt-partner.161-153-59-50.nip.io/login` in a clean browser
   profile (no existing session).
2. The login page should now show a **"Login with Oracle Identity Domains"** button
   alongside the local username/password form. The button label is derived from the
   provider's `name` field — if it doesn't appear, recheck Step 3.
3. Click the button. The browser redirects to
   `https://idcs-<your-id>.identity.oraclecloud.com/oauth2/v1/authorize?...` with
   `client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, and `nonce`
   query params.
4. Authenticate at the IDCS login form using a test user in the domain.
5. IDCS redirects back to
   `https://demo-cuopt-partner.161-153-59-50.nip.io/sso/callback/oracle-idcs?code=...&state=...`.
6. The frontend's `SSOCallback` page exchanges the code for internal tokens, stores
   them, and routes to the post-login landing page. Expected: you are signed in as
   the JIT-provisioned user, and the user appears in `GET /auth/users` (admin-listed).

### Headless / curl flow

The pure-curl flow exercises the same endpoints without a browser. It cannot complete
the IDCS user-consent step automatically, so use this only after one successful
browser login (which seeds the user session at IDCS).

```bash
REDIRECT_URI="${PACK_URL}/sso/callback/oracle-idcs"

# 1. Ask auth-service to build the authorize URL:
AUTH_RESP=$(curl -sk \
  "${PACK_URL}/auth/sso/oracle-idcs/authorize?redirect_uri=${REDIRECT_URI}")
echo "${AUTH_RESP}" | jq
# Expected: {authorize_url, state, provider_slug}

# 2. Save the state — auth-service persists it server-side and rejects callbacks
#    whose state doesn't match.
SSO_STATE=$(echo "${AUTH_RESP}" | jq -r '.state')

# 3. Open the authorize_url in a browser (or driver), complete login, and grab the
#    'code' query param from the callback URL the browser is redirected to.
CODE="<paste-code-from-callback-url>"

# 4. Exchange the code for an internal token pair:
TOKEN_RESP=$(curl -sk -X POST "${PACK_URL}/auth/sso/oracle-idcs/token" \
  -H "Content-Type: application/json" \
  -d "{\"code\":\"${CODE}\",\"redirect_uri\":\"${REDIRECT_URI}\"}")
echo "${TOKEN_RESP}" | jq
# Expected: {access_token, refresh_token, token_type, expires_in}

USER_TOKEN=$(echo "${TOKEN_RESP}" | jq -r '.access_token')
```

---

## Step 6: Verify the round-trip

After SSO, the token in hand is the **pack's** RS256 JWT — not the IDCS token.
Auth-service exchanges IDCS credentials for its own short-lived RS256 access
token (RFC 9068 `at+jwt`), which the pack BE then validates locally by
fetching the auth-service's JWKS once and verifying the signature on each
request. No per-request call back to either IDCS or auth-service.

```bash
# 1. Confirm auth-service recognises the user:
curl -sk -H "Authorization: Bearer ${USER_TOKEN}" "${PACK_URL}/auth/me" | jq
# Expected: 200 with the JIT-provisioned user object including:
#   - email matching the IDCS user
#   - role(s) reflecting any claim mappings that fired
#   - external_identities array containing the IDCS link

# 2. Confirm the pack backend accepts the token:
curl -sk -H "Authorization: Bearer ${USER_TOKEN}" "${PACK_URL}/api/config" | jq
# Expected: 200 with the pack's config payload. A 401 here means the pack BE rejects
# the token — see Troubleshooting "Pack BE returns 401 after SSO" below.

# 3. Inspect the audit log entry for the login:
curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${PACK_URL}/auth/audit?action=sso_login&limit=5" | jq
# Expected: a row with the SSO login event for the JIT-provisioned user.
```

If all three return 200 with the expected shapes, the integration is end-to-end
working.

---

## Troubleshooting

### `Failed to fetch JWKS from <discovery-url>` or `JWKS fetch failed (401) for .../admin/v1/SigningCert/jwk`

Two different failures land here:

**(a) Auth-service can't reach the IDCS discovery endpoint at all.**
- **Discovery URL typo.** Re-check the `issuer` field: it must be the bare domain URL
  with no trailing slash and no `/.well-known/...` suffix.
- **Egress blocked.** The pack's egress security list / NSG may not allow outbound
  HTTPS to `*.identity.oraclecloud.com`. Add a rule.
- **DNS resolution.** Exec into the auth-service pod and run
  `curl -v ${IDCS_DOMAIN_URL}/.well-known/openid-configuration` — if DNS fails, fix
  cluster DNS.

```bash
kubectl exec -n auth-service deploy/auth-service -- \
  curl -sv "${IDCS_DOMAIN_URL}/.well-known/openid-configuration" 2>&1 | head -20
```

**(b) Auth-service reached `/admin/v1/SigningCert/jwk` and got 401.** This means
the `client_credentials` fallback path either is not enabled on the IDCS app or
the app's granted role doesn't include SigningCert read access.

Confirm the CC grant works from your machine first:

```bash
curl -sk -X POST "${IDCS_DOMAIN_URL}/oauth2/v1/token" \
  -u "${IDCS_CLIENT_ID}:${IDCS_CLIENT_SECRET}" \
  -d 'grant_type=client_credentials' \
  -d 'scope=urn:opc:idm:__myscopes__'
```

- **`unauthorized_client`** → the IDCS app doesn't have **Client Credentials** in
  its allowed grant types. Edit OAuth configuration → Client Configuration →
  Allowed grant types → check Client Credentials → save → reactivate.
- **200 with an `access_token`** → grant works, now use it to hit the gated
  endpoint:

  ```bash
  CC_TOKEN=$(curl -sk -X POST ... | jq -r .access_token)
  curl -sk -o /dev/null -w '%{http_code}\n' \
    "${IDCS_DOMAIN_URL}/admin/v1/SigningCert/jwk" \
    -H "Authorization: Bearer ${CC_TOKEN}"
  ```

  - **401 again** → the granted app role doesn't allow SigningCert read. Switch
    to "Identity Domain Administrator" (or another role that includes admin
    read), save, reactivate.
  - **200** → IDCS is fine; auth-service should also succeed on the next login.
    If it doesn't, the auth-service hasn't seen your IDCS config change yet —
    restart the pod (`kubectl rollout restart deploy/<auth-service>`) to bust
    the in-process CC-token cache.

### `Invalid ID token from IdP`

Auth-service's `exchange_oidc_code` verified the ID token signature and rejected it.
Causes:

- **Wrong client secret.** Regenerate in IDCS, update via
  `PATCH /auth/providers/{id}` with a new `config.client_secret`.
- **Clock skew.** Auth-service allows ±300s skew on `exp`/`iat`. If your pack node
  clock is more than 5 minutes off, NTP is broken. Verify with
  `kubectl exec -n auth-service deploy/auth-service -- date -u`.
- **Token issuer mismatch.** The `iss` claim in the ID token did not match the
  `issuer` you registered. Check the discovery doc again — modern Identity Domains
  return per-tenant issuers; legacy IDCS returns a fixed string.

### `Invalid state`

The `state` parameter returned in the callback does not match what auth-service
generated 10 minutes ago. Causes:

- **Stale callback.** User took longer than 10 minutes to authenticate. Restart the
  flow from `/login`.
- **Cross-browser callback.** The user started the flow in one browser and finished
  in another. State is bound to the originating session.
- **Cookie blocked.** Strict cookie policy or third-party cookie blocker on the
  user's browser prevented the state cookie from being set. Test in a clean profile.

### `JIT-provisioned user has role=pending`

The user logged in successfully but lacks any granted role. Causes:

- **No claim mapping fired.** Verify the IDCS token contains the claim you mapped on.
  Run the curl flow above, capture the access token, and decode it:
  ```bash
  curl -sk -X POST "${IDCS_DOMAIN_URL}/oauth2/v1/userinfo" \
    -H "Authorization: Bearer ${IDCS_ACCESS_TOKEN}" | jq
  ```
  If the claim you're mapping on isn't present, you need to add it in IDCS.

### `Groups claim missing from token`

IDCS does **not** emit `groups` in tokens by default. To add it:

1. Console → Identity Domains → your domain → **Settings** → **Token issuance
   policy**.
2. Open the **OAuth Client and User Information** section.
3. Add a **custom claim** named `groups`:
   - **Name:** `groups`
   - **Type:** `User`
   - **Value type:** `Expression`
   - **Expression:** `$(user.groups)`
   - **Mode:** `Always`
   - **Token type:** `ID` (and `Access` if you also want it in access tokens).
4. Save and reactivate the application.

Alternatively, map on a claim IDCS always emits (`sub`, `email`, `preferred_username`)
and use OCI group sync to keep that claim's value in lockstep with your authorisation
model.

### `Wrong audience` / `Invalid audience`

The pack BE rejects the auth-service token (or auth-service rejects the IDCS token)
because the `aud` claim doesn't match. Causes:

- The **Primary Audience** you set in Step 1 must match `CUOPT_AUTH_TOKEN_AUDIENCE`
  (or the pack-specific `*_AUTH_TOKEN_AUDIENCE` env var) in the pack BE's
  configuration. Both should be
  `https://demo-cuopt-partner.161-153-59-50.nip.io/auth/sso/oracle-idcs/` with a
  trailing slash.
- If you change the audience in IDCS, update the pack BE's env via the TF
  `*_auth_token_audience` variable and redeploy.

### Pack BE returns 401 after SSO

The auth-service issued a token but the pack BE refuses it. The pack BE
validates RS256 signatures locally against the auth-service's JWKS; failures
usually mean the BE either can't reach the JWKS endpoint, doesn't trust the
issuer, or sees a token whose `aud`/`exp` doesn't match. Causes:

- **`<PACK>_AUTH_TRUSTED_ISSUERS` missing or stale.** Verify the env contains
  the auth-service issuer URL the token was minted under:
  ```bash
  kubectl exec -n default deploy/<pack>-backend -- printenv \
    | grep -E 'AUTH_TRUSTED_ISSUERS|AUTH_LOCAL_ISSUER_URL|AUTH_TOKEN_AUDIENCE'
  ```
  The trusted-issuers list MUST contain the value of the token's `iss` claim
  (decode the token at jwt.io to inspect). TF stamps this from
  `local.auth_service_trusted_issuers` in `auth-locals.tf`.
- **JWKS unreachable.** Pack BE tries the in-cluster JWKS URL first
  (`<PACK>_AUTH_LOCAL_JWKS_URL`), then falls back to the public issuer's
  `/.well-known/jwks.json`. If both fail (network policy / cluster DNS / TLS
  trust), every token validates 401. Exec into the BE pod:
  ```bash
  kubectl exec -n default deploy/<pack>-backend -- \
    curl -sv "$<PACK>_AUTH_LOCAL_JWKS_URL"
  ```
- **Audience mismatch.** The token's `aud` claim must equal
  `<PACK>_AUTH_TOKEN_AUDIENCE` (default: the pack-category name, e.g.
  `cuopt`). Tokens minted by `/auth/sso/{slug}/token` carry the
  configured audience automatically; tokens minted directly by an IdP
  for service-account use need their audiences in this list too.
- **`kid` rotated.** auth-service rotates its signing key via
  `POST /auth/admin/keys/rotate`. Pack BE refreshes its JWKS on a `kid`
  miss (exactly one refresh per miss); if the rotation predates that
  refresh window for some reason, restart the BE pod to force a fresh
  JWKS fetch.

---

## Known limitations

- **Refresh tokens from IDCS are opaque** (not JWT). Auth-service does not pass them
  through — it issues its own RS256 refresh token and discards the IDCS refresh
  token after the initial code exchange. If you need long-lived IDCS sessions, the
  user must re-authenticate when the auth-service refresh token expires (default 7
  days).
- **Scope naming is URL-form in IDCS, short-form in auth-service.** IDCS stores
  scopes as `<primary_audience><short_name>` (e.g.
  `https://demo-cuopt-partner.../cuopt.solve`). Auth-service claim mappings work
  on the short name (`cuopt.solve`). Don't try to mix them.
- **Single-tenant federation only.** Mapping one auth-service deployment to multiple
  Identity Domains (multi-tenant federation) is not tested and may break the JIT
  external-identity uniqueness constraint.
- **Mutable `sub` claim.** IDCS uses the **login name** as the `sub` claim by
  default, and that's a mutable attribute. If a user renames their IDCS login,
  auth-service will JIT-provision a duplicate user. Mitigation: in IDCS, set the
  application's **subject mapping** to use the stable user GUID (`user_id`) instead.
- **No `iss` enforcement for legacy IDCS.** Legacy (non-Identity-Domains) IDCS
  tenancies return a fixed `iss` of `https://identity.oraclecloud.com/`. If you have
  multiple legacy tenancies behind one auth-service deployment, the `iss` check
  cannot distinguish them — use modern Identity Domains for any new integration.
- **Machine-to-machine (`client_credentials`) federation is a separate path** and is
  not enabled by this guide. That uses auth-service's trusted-issuers feature with
  JWKS verification and `audience`-gated `/oauth/token` exchange. A future doc will
  cover it.
- **SCIM provisioning from IDCS to auth-service** is configurable but is not covered
  here. The auth-service SCIM endpoints (`/scim/v2/Users`, `/scim/v2/Groups`) are
  bearer-gated by `AUTH_SCIM_TOKEN`; wiring IDCS as a SCIM client is symmetric to
  this OIDC setup but uses a different IDCS application type ("Confidential
  Application" → "SCIM provisioning").

---

## Reference: IDCS-specific quirks

| Item | IDCS value | Note |
|---|---|---|
| Discovery path | `/.well-known/openid-configuration` | Standard. |
| Authorize endpoint | `/oauth2/v1/authorize` | Standard. |
| Token endpoint | `/oauth2/v1/token` | Standard. |
| Userinfo endpoint | `/oauth2/v1/userinfo` | Standard. |
| JWKS endpoint | `/admin/v1/SigningCert/jwk` | **Non-standard** — most providers use `/jwks.json` or `/oauth2/v1/keys`. Auth-service reads it from discovery, so no manual config needed. |
| Issuer | Per-tenant URL (modern) or `https://identity.oraclecloud.com/` (legacy) | Whichever discovery returns. |
| `sub` claim | Login name (mutable) | Override to `user_id` (GUID) via subject-mapping config in the IDCS application. |
| `groups` claim | Not emitted by default | Add a custom claim mapping as described in Troubleshooting. |
| Refresh tokens | Opaque (not JWT) | Not passed through by auth-service. |
| Scope format in tokens | `<primary_audience><short_name>` URL | Auth-service stores short name. |
