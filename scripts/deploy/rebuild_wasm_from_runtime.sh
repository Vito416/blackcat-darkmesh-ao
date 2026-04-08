#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-registry}"
DIST_DIR="dist/${TARGET}"
RUNTIME_SOURCE="dist/registry/process.lua"

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "dist target not found: ${DIST_DIR}" >&2
  exit 1
fi

if [[ ! -f "${DIST_DIR}/process.lua" ]]; then
  echo "missing ${DIST_DIR}/process.lua (run build first)" >&2
  exit 1
fi

if [[ ! -f "${DIST_DIR}/config.yml" ]]; then
  echo "missing ${DIST_DIR}/config.yml (run build first)" >&2
  exit 1
fi

if [[ "${TARGET}" != "registry" ]]; then
  if [[ ! -f "${RUNTIME_SOURCE}" ]]; then
    echo "missing ${RUNTIME_SOURCE}; cannot synthesize runtime wrapper for ${TARGET}" >&2
    exit 1
  fi

  python3 - "$RUNTIME_SOURCE" "${DIST_DIR}/process.lua" "$TARGET" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
target = sys.argv[3]
text = source.read_text(encoding='utf-8')
needle = 'return require("ao.registry.process")'
idx = text.rfind(needle)
if idx < 0:
    raise SystemExit(f'Could not find marker `{needle}` in {source}')
replacement = f'return require("ao.{target}.process")'
patched = text[:idx] + replacement + text[idx + len(needle):]
dest.write_text(patched, encoding='utf-8')
print(f'synthesized runtime process.lua for {target}: {dest}')
PY
fi

echo "Rebuilding WASM from ${DIST_DIR}/process.lua ..."
docker run \
  --platform linux/amd64 \
  -v "$(pwd)/${DIST_DIR}:/src" \
  p3rmaw3b/ao:0.1.5 \
  ao-build-module

if [[ "$(strings "${DIST_DIR}/process.wasm" | grep -Fc "function process.handle")" -eq 0 ]]; then
  echo "ERROR: Built WASM is missing process.handle runtime symbol (${TARGET})" >&2
  exit 1
fi

echo "Done: ${DIST_DIR}/process.wasm"
