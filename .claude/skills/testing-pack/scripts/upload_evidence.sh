#!/bin/bash
# Upload screenshot evidence to OCI Object Storage.
#
# Usage:
#   upload_evidence.sh <evidence-dir> [bucket-name] [namespace] [prefix]
#
# Arguments:
#   evidence-dir  Directory containing .png files to upload (required)
#   bucket-name   OCI Object Storage bucket name (default: $EVIDENCE_BUCKET)
#   namespace     OCI tenancy namespace (default: $EVIDENCE_NAMESPACE, or auto-detected)
#   prefix        Object name prefix (default: evidence/<date>)
#
# Environment:
#   OCI_CLI_PROFILE   OCI CLI profile to use (required)
#   EVIDENCE_BUCKET   Default bucket name if not passed as argument
#   EVIDENCE_NAMESPACE Default namespace if not passed as argument
#
# Examples:
#   # Upload all PNGs from a test run
#   export OCI_CLI_PROFILE=aiincubations
#   upload_evidence.sh /tmp/aiq-evidence-20260402 my-test-bucket
#
#   # Auto-detect namespace, custom prefix
#   upload_evidence.sh /tmp/screenshots my-bucket "" "aiq/2026-04-02/run1"

set -euo pipefail

EVIDENCE_DIR="${1:?Usage: upload_evidence.sh <evidence-dir> [bucket] [namespace] [prefix]}"
BUCKET="${2:-${EVIDENCE_BUCKET:-}}"
NAMESPACE="${3:-${EVIDENCE_NAMESPACE:-}}"
PREFIX="${4:-evidence/$(date +%Y-%m-%d)}"

if [ -z "$BUCKET" ]; then
  echo "ERROR: No bucket specified. Pass as argument or set EVIDENCE_BUCKET." >&2
  exit 1
fi

if [ ! -d "$EVIDENCE_DIR" ]; then
  echo "ERROR: Directory not found: $EVIDENCE_DIR" >&2
  exit 1
fi

# Count files to upload
FILE_COUNT=$(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
  echo "No .png files found in $EVIDENCE_DIR"
  exit 0
fi

# Auto-detect namespace if not provided
if [ -z "$NAMESPACE" ]; then
  NAMESPACE=$(oci os ns get --query 'data' --raw-output 2>/dev/null) || {
    echo "ERROR: Could not detect namespace. Pass as argument or set EVIDENCE_NAMESPACE." >&2
    exit 1
  }
fi

echo "Uploading $FILE_COUNT screenshots to: $BUCKET/$PREFIX/"
echo "  Namespace: $NAMESPACE"
echo ""

UPLOADED=0
FAILED=0

for f in "$EVIDENCE_DIR"/*.png; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  OBJECT_NAME="${PREFIX}/${BASENAME}"

  if oci os object put \
    --bucket-name "$BUCKET" \
    --namespace "$NAMESPACE" \
    --name "$OBJECT_NAME" \
    --file "$f" \
    --content-type "image/png" \
    --force \
    --no-retry 2>/dev/null; then
    echo "  ✓ $BASENAME"
    UPLOADED=$((UPLOADED + 1))
  else
    echo "  ✗ $BASENAME (upload failed)" >&2
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "Done: $UPLOADED uploaded, $FAILED failed"
echo "Bucket path: $BUCKET/$PREFIX/"
