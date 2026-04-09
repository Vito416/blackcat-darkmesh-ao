#!/usr/bin/env bash
set -euo pipefail

TX="${1:-${AO_TX:-}}"
TIMEOUT_SEC="${TIMEOUT_SEC:-3600}"
INTERVAL_SEC="${INTERVAL_SEC:-30}"

if [ -z "$TX" ]; then
  echo "Usage: scripts/deploy/wait_finalized.sh <TX>" >&2
  echo "or: AO_TX=<TX> scripts/deploy/wait_finalized.sh" >&2
  exit 2
fi

deadline=$(( $(date +%s) + TIMEOUT_SEC ))
last_status=""

echo "Waiting for finalization: $TX (timeout=${TIMEOUT_SEC}s interval=${INTERVAL_SEC}s)"
echo "Viewblock: https://viewblock.io/arweave/tx/$TX"

while [ "$(date +%s)" -lt "$deadline" ]; do
  status_json="$(curl -sS "https://arweave.net/tx/${TX}/status" || true)"
  if [ -n "$status_json" ] && echo "$status_json" | grep -q '"block_height"'; then
    height="$(echo "$status_json" | sed -n 's/.*"block_height":[[:space:]]*\([0-9]\+\).*/\1/p')"
    confs="$(echo "$status_json" | sed -n 's/.*"number_of_confirmations":[[:space:]]*\([0-9]\+\).*/\1/p')"
    echo "Finalized: block_height=${height:-unknown} confirmations=${confs:-unknown}"
    exit 0
  fi

  if [ "$status_json" != "$last_status" ]; then
    if [ -z "$status_json" ]; then
      echo "Status: empty response (likely not indexed yet)"
    else
      echo "Status: $status_json"
    fi
    last_status="$status_json"
  else
    echo "Still waiting..."
  fi
  sleep "$INTERVAL_SEC"
done

echo "Timeout waiting for finalization: $TX" >&2
exit 1
