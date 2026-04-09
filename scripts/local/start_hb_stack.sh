#!/usr/bin/env bash
set -euo pipefail

HB_IMAGE="${HB_IMAGE:-hyperbeam-docker-hyperbeam-edge-release-ephemeral:latest}"
CU_IMAGE="${CU_IMAGE:-hyperbeam-docker-local-cu:latest}"
HB_CONTAINER="${HB_CONTAINER:-hyperbeam-docker-hyperbeam-edge-release-ephemeral-1}"
CU_CONTAINER="${CU_CONTAINER:-hyperbeam-docker-local-cu-1}"
HB_NETWORK="${HB_NETWORK:-hyperbeam-docker_default}"
HB_PORT="${HB_PORT:-8734}"
HB_CONFIG_PATH="${HB_CONFIG_PATH:-/tmp/hb-run/config.release.flat}"
WALLET_PATH="${WALLET_PATH:-../blackcat-darkmesh-write/wallet.json}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

if [[ ! -f "$WALLET_PATH" ]]; then
  echo "wallet not found: $WALLET_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$HB_CONFIG_PATH")"
if [[ -d "$HB_CONFIG_PATH" ]]; then
  echo "$HB_CONFIG_PATH is a directory; replace it with a file and rerun." >&2
  echo "fix: sudo rm -rf $HB_CONFIG_PATH && echo 'priv_key_location: /app/wallet.json' | sudo tee $HB_CONFIG_PATH >/dev/null" >&2
  exit 1
fi
if [[ ! -f "$HB_CONFIG_PATH" ]]; then
  echo 'priv_key_location: /app/wallet.json' > "$HB_CONFIG_PATH"
fi

docker rm -f "$HB_CONTAINER" "$CU_CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$HB_CONTAINER" \
  --network "$HB_NETWORK" \
  -p "$HB_PORT":8734 \
  -v "$HB_CONFIG_PATH":/app/_build/genesis_wasm/rel/hb/config.flat:ro \
  -v "$WALLET_PATH":/app/_build/genesis_wasm/rel/hb/wallet.json:ro \
  "$HB_IMAGE" >/dev/null

# Use HB container network namespace so HB default localhost:6363 CU routes work.
docker run -d \
  --name "$CU_CONTAINER" \
  --network "container:$HB_CONTAINER" \
  -e NODE_CONFIG_ENV=development \
  -e WALLET_FILE=/wallet.json \
  -v "$WALLET_PATH":/wallet.json:ro \
  "$CU_IMAGE" >/dev/null

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E "${HB_CONTAINER}|${CU_CONTAINER}" || true
