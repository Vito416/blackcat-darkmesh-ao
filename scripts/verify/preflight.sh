#!/usr/bin/env bash
# Lightweight preflight checks for the AO repo.
# - validates JSON schemas are well-formed
# - ensures Lua sources have no syntax errors

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT_DIR

echo "[verify] JSON schemas"
python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
schemas = sorted((root / "schemas").rglob("*.json"))
if not schemas:
    raise SystemExit("No schemas found under schemas/")

for path in schemas:
    with path.open("r", encoding="utf-8") as f:
        json.load(f)
    print(f"  ✓ {path.relative_to(root)}")
PY

echo "[verify] Lua syntax"

lua_runner=()
if command -v luac >/dev/null 2>&1; then
  lua_runner=(luac -p)
elif command -v lua5.4 >/dev/null 2>&1; then
  lua_runner=(lua5.4 -e "assert(loadfile(arg[1]))")
elif command -v lua >/dev/null 2>&1; then
  lua_runner=(lua -e "assert(loadfile(arg[1]))")
fi

if [ ${#lua_runner[@]} -eq 0 ]; then
  echo "Lua interpreter/compiler not found. Install lua5.4 (or luac) to run syntax checks." >&2
  exit 1
fi

find "$ROOT_DIR/ao" -name '*.lua' -print -exec "${lua_runner[@]}" {} \;

echo "[verify] done"

# optional contract smoke tests
if command -v lua5.4 >/dev/null 2>&1; then
  ROCKS_LUA_PATH=$(luarocks --lua-version=5.4 path --lr-path 2>/dev/null || true)
  ROCKS_LUA_CPATH=$(luarocks --lua-version=5.4 path --lr-cpath 2>/dev/null || true)
  LUA_PATH_BASE="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua"
  if [ -n "${ROCKS_LUA_PATH}" ]; then
    LUA_PATH_EFFECTIVE="${LUA_PATH_BASE};${ROCKS_LUA_PATH}"
  else
    LUA_PATH_EFFECTIVE="${LUA_PATH_BASE}"
  fi
  if [ "${RUN_DEPS_CHECK:-0}" -eq 1 ]; then
    echo "[verify] deps check"
    LUA_PATH="${LUA_PATH_EFFECTIVE}" \
    LUA_CPATH="${ROCKS_LUA_CPATH}" \
      lua5.4 "$ROOT_DIR/scripts/verify/deps_check.lua"
  fi
  echo "[verify] contract smoke tests"
  METRICS_ENABLED=0 \
  METRICS_DISABLED=1 \
  AUTH_REQUIRE_SIGNATURE=0 \
  AUTH_REQUIRE_NONCE=0 \
  AUTH_REQUIRE_TIMESTAMP=0 \
  AUTH_RATE_LIMIT_MAX_REQUESTS=100000 \
  SKIP_CONTRACTS="${SKIP_CONTRACTS:-0}" \
  SKIP_CATALOG=1 \
  SKIP_ACCESS=1 \
  LUA_PATH="${LUA_PATH_EFFECTIVE}" \
  LUA_CPATH="${ROCKS_LUA_CPATH}" \
    lua5.4 "$ROOT_DIR/scripts/verify/contracts.lua"
  echo "[verify] outbox HMAC separation"
  OUTBOX_HMAC_SECRET=preflight-hmac-secret \
  AUTH_REQUIRE_SIGNATURE=0 \
  AUTH_REQUIRE_NONCE=0 \
  AUTH_REQUIRE_TIMESTAMP=0 \
  AUTH_REQUIRE_JWT=0 \
  LUA_PATH="${LUA_PATH_EFFECTIVE}" \
  LUA_CPATH="${ROCKS_LUA_CPATH}" \
    lua5.4 "$ROOT_DIR/scripts/verify/outbox_hmac_separation.lua"
  if [ "${RUN_INTEGRITY_REGISTRY_SPEC:-0}" = "1" ]; then
    echo "[verify] integrity registry lifecycle spec"
    METRICS_ENABLED=0 \
    METRICS_DISABLED=1 \
    LUA_PATH="${LUA_PATH_EFFECTIVE}" \
    LUA_CPATH="${ROCKS_LUA_CPATH}" \
      lua5.4 "$ROOT_DIR/scripts/verify/integrity_registry_spec.lua"
  fi
  if [ "${RUN_FUZZ:-0}" -eq 1 ]; then
    echo "[verify] fuzz/property tests"
    LUA_PATH="${LUA_PATH_EFFECTIVE}" \
    LUA_CPATH="${ROCKS_LUA_CPATH}" \
      lua5.4 "$ROOT_DIR/scripts/verify/fuzz.lua"
  fi
fi
