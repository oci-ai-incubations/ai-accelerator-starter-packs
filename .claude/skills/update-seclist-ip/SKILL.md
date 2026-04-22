---
name: update-seclist-ip
description: Update the Chicago production LB security list with your current public IP.
user-invocable: true
allowed-tools: Bash, Read
argument-hint: (no arguments needed)
---

# Update Security List IP

Updates the "Sanjana office" ingress rule on `oke-lb-seclist-kPZRsn-AAJg` in `us-chicago-1` (Production-Hosting compartment) with the current public IP address.

## CRITICAL RULES

1. **Only touch the "Sanjana office" ingress rule.** Do NOT modify, add, or remove any other ingress rule, any egress rule, or any other property of this security list. Ever.
2. **If any step errors out, STOP immediately and ask the user.** Do NOT attempt to debug, retry with different parameters, fix permissions, work around the issue, or take any corrective action whatsoever. Just report the exact error and wait for instructions.
3. **No improvisation.** Follow the steps below exactly as written. Do not add extra commands, modify the approach, or "improve" the process.

## Constants

- **Security List OCID:** `ocid1.securitylist.oc1.us-chicago-1.aaaaaaaafllhdmnnsitgtuuywusrh2vqrs4e5wyqjnulbywbysgdo2evebyq`
- **Region:** `us-chicago-1`

## Steps

### Step 1: Get current public IP

```bash
MY_IP=$(curl -s ifconfig.me)
echo "Current public IP: $MY_IP"
```

### Step 2: Fetch current security list

```bash
SECLIST_ID="ocid1.securitylist.oc1.us-chicago-1.aaaaaaaafllhdmnnsitgtuuywusrh2vqrs4e5wyqjnulbywbysgdo2evebyq"

oci network security-list get \
  --security-list-id "$SECLIST_ID" \
  --region us-chicago-1 \
  --output json > /tmp/seclist-full.json
```

### Step 3: Check if update is needed

Extract the current IP for the "Sanjana office" rule:

```bash
CURRENT_IP=$(jq -r '.data."ingress-security-rules"[] | select(.description == "Sanjana office") | .source' /tmp/seclist-full.json)
echo "Current rule IP: $CURRENT_IP"
echo "New IP: $MY_IP/32"
```

If `$CURRENT_IP` equals `$MY_IP/32`, report that the IP is already up to date and stop.

### Step 4: Build updated rules

Use `jq` to update only the "Sanjana office" ingress rule's `source` field, preserving everything else:

```bash
# Update the ingress rule
jq --arg new_ip "$MY_IP/32" '
  [.data."ingress-security-rules"[] |
    if .description == "Sanjana office"
    then .source = $new_ip
    else .
    end]
' /tmp/seclist-full.json > /tmp/updated-ingress.json

# Extract egress rules unchanged
jq '.data."egress-security-rules"' /tmp/seclist-full.json > /tmp/egress.json
```

### Step 5: Apply the update

Both `--ingress-security-rules` and `--egress-security-rules` must be provided to avoid OCI clearing the other set.

```bash
oci network security-list update \
  --security-list-id "$SECLIST_ID" \
  --region us-chicago-1 \
  --ingress-security-rules "$(cat /tmp/updated-ingress.json)" \
  --egress-security-rules "$(cat /tmp/egress.json)" \
  --force
```

### Step 6: Verify

```bash
oci network security-list get \
  --security-list-id "$SECLIST_ID" \
  --region us-chicago-1 \
  --query "data.\"ingress-security-rules\"[?description=='Sanjana office'].source" \
  --output table
```

Report: "Updated Sanjana office rule from `<old IP>` to `<new IP>/32`."

### Step 7: Cleanup

```bash
rm -f /tmp/seclist-full.json /tmp/updated-ingress.json /tmp/egress.json
```
