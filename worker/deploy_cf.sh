#!/usr/bin/env bash
set -euo pipefail

# One-shot deploy helper for Cloudflare Worker (blackcat-inbox).
# Generates fresh secrets, creates KV namespace, updates wrangler.toml, sets secrets, and publishes.
#
# Requirements: wrangler CLI, jq, perl, openssl.

ENV=production

rand_hex() { openssl rand -hex 32; }

WORKER_AUTH_TOKEN="$(rand_hex)"
INBOX_HMAC_SECRET="$(rand_hex)"
NOTIFY_HMAC_SECRET="$(rand_hex)"
METRICS_BEARER_TOKEN="$(rand_hex)"
# Optional extras (leave blank to skip):
FORGET_TOKEN=""
SENDGRID_KEY=""
NOTIFY_WEBHOOK=""

WR="npx --yes wrangler@4"

ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
if [ -z "$ACCOUNT_ID" ]; then
  echo "Set CLOUDFLARE_ACCOUNT_ID env var (find it in CF dashboard: Workers & Pages → Overview)." >&2
  exit 1
fi

# Pass account id/token to wrangler via env
export CF_ACCOUNT_ID="$ACCOUNT_ID"
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
fi

echo "=== Wrangler whoami ==="
$WR whoami

echo "=== Create KV namespace INBOX_KV (${ENV}) ==="
KV_OUT=$($WR kv namespace create --binding INBOX_KV --env "$ENV")
KV_ID=$(echo "$KV_OUT" | awk '/ID:/ {print $NF}' | head -n1 | tr -d '\"')
if [ -z "$KV_ID" ]; then
  echo "Failed to obtain KV ID. Output:" >&2
  echo "$KV_OUT" >&2
  exit 1
fi
echo "KV_ID=$KV_ID"

echo "=== Patch wrangler.toml with KV ID ==="
tmpfile=$(mktemp)
perl -0777 -pe "s/id = \"x+\"/id = \"$KV_ID\"/g" wrangler.toml >"$tmpfile" && mv "$tmpfile" wrangler.toml

echo "=== Set secrets ==="
put_secret() { printf '%s' "$2" | $WR secret put "$1" --env "$ENV" >/dev/null; }
put_secret WORKER_AUTH_TOKEN "$WORKER_AUTH_TOKEN"
put_secret INBOX_HMAC_SECRET "$INBOX_HMAC_SECRET"
put_secret NOTIFY_HMAC_SECRET "$NOTIFY_HMAC_SECRET"
put_secret METRICS_BEARER_TOKEN "$METRICS_BEARER_TOKEN"
[ -n "$FORGET_TOKEN" ] && put_secret FORGET_TOKEN "$FORGET_TOKEN"
[ -n "$SENDGRID_KEY" ] && put_secret SENDGRID_KEY "$SENDGRID_KEY"
[ -n "$NOTIFY_WEBHOOK" ] && put_secret NOTIFY_WEBHOOK "$NOTIFY_WEBHOOK"

echo "=== Publish ==="
$WR publish --env "$ENV"

echo "=== Summary ==="
echo "Worker auth token:   $WORKER_AUTH_TOKEN"
echo "Inbox HMAC secret:   $INBOX_HMAC_SECRET"
echo "Notify HMAC secret:  $NOTIFY_HMAC_SECRET"
echo "Metrics bearer:      $METRICS_BEARER_TOKEN"
echo "KV ID:               $KV_ID"
$WR deployments list --env "$ENV" | head -n 5
