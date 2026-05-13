#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER_IMAGE="${DOCKER_IMAGE:-p3rmaw3b/ao:0.1.5}"
RUNTIME_TEMPLATE="${RUNTIME_TEMPLATE:-registry}"
MIN_INITIAL_MEMORY="${MIN_INITIAL_MEMORY:-8388608}"

docker_bind_path() {
  local path="$1"
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wslpath >/dev/null 2>&1 && command -v docker.exe >/dev/null 2>&1; then
    wslpath -w "${path}"
  else
    printf '%s' "${path}"
  fi
}

cd "${ROOT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if [[ ! -d "dist/${RUNTIME_TEMPLATE}" ]]; then
  echo "missing dist/${RUNTIME_TEMPLATE}; build baseline runtime first (or set RUNTIME_TEMPLATE)" >&2
  exit 1
fi

if [[ ! -f "dist/${RUNTIME_TEMPLATE}/config.yml" ]]; then
  echo "missing dist/${RUNTIME_TEMPLATE}/config.yml" >&2
  exit 1
fi

echo "[1/4] Building resolver Lua bundle"
node scripts/build-ao-bundles.mjs --target resolver

echo "[2/4] Preparing dist/resolver runtime scaffold from dist/${RUNTIME_TEMPLATE}"
rm -rf dist/resolver
cp -a "dist/${RUNTIME_TEMPLATE}" dist/resolver

echo "[2.1/4] Composing runtime wrapper + resolver bundle"
python3 - <<'PY'
from pathlib import Path
import re
import sys

runtime = Path("dist/resolver/process.lua")
bundle = Path("dist/resolver-bundle.lua")

runtime_text = runtime.read_text(encoding="utf-8")
bundle_text = bundle.read_text(encoding="utf-8")

# Keep runtime return intact; strip resolver bundle terminal return so it only
# contributes package.preload chunks.
bundle_text = re.sub(
    r"\nreturn require\(\"ao\.resolver\.process\"\)\s*$",
    "\n",
    bundle_text,
    flags=re.MULTILINE,
)

marker = "\nreturn process"
idx = runtime_text.rfind(marker)
if idx < 0:
    print(f"runtime wrapper marker not found: {marker!r}", file=sys.stderr)
    sys.exit(1)

# Keep the full AO runtime wrapper (process.handle, scheduler plumbing, etc.).
# Inject resolver preload chunks, require resolver hooks once, then return
# the runtime process table.
injected = (
    "\n-- injected resolver bundle (preload-only)\n"
    + bundle_text
    + "\nlocal __ok_resolver, __err_resolver = pcall(require, \"ao.resolver.process\")\n"
    + "if not __ok_resolver then error(__err_resolver) end\n"
    + "local function __dm_promote_tags(msg)\n"
    + "  if type(msg) ~= \"table\" then return msg end\n"
    + "  local tags = msg.Tags or msg.tags\n"
    + "  if type(tags) == \"table\" then\n"
    + "    for _, tag in ipairs(tags) do\n"
    + "      if type(tag) == \"table\" then\n"
    + "        local name = tag.name or tag.Name\n"
    + "        local value = tag.value or tag.Value\n"
    + "        if type(name) == \"string\" and msg[name] == nil then\n"
    + "          msg[name] = value\n"
    + "        end\n"
    + "      end\n"
    + "    end\n"
    + "  end\n"
    + "  if msg.Action == nil and msg.action ~= nil then msg.Action = msg.action end\n"
    + "  if msg['Request-Id'] == nil then\n"
    + "    if msg.requestId ~= nil then\n"
    + "      msg['Request-Id'] = msg.requestId\n"
    + "    elseif msg['request-id'] ~= nil then\n"
    + "      msg['Request-Id'] = msg['request-id']\n"
    + "    elseif msg.Id ~= nil then\n"
    + "      msg['Request-Id'] = msg.Id\n"
    + "    end\n"
    + "  end\n"
    + "  if msg.Host == nil and msg.host ~= nil then msg.Host = msg.host end\n"
    + "  if msg.Path == nil and msg.path ~= nil then msg.Path = msg.path end\n"
    + "  if msg.Method == nil and msg.method ~= nil then msg.Method = msg.method end\n"
    + "  return msg\n"
    + "end\n"
    + "if type(process) == \"table\" then\n"
    + "  local __orig_process_handle = process.handle\n"
    + "  process.handle = function(msg)\n"
    + "    msg = __dm_promote_tags(msg)\n"
    + "    if type(normalizeMsg) == \"function\" then pcall(normalizeMsg, msg) end\n"
    + "    if type(__orig_process_handle) == \"function\" then\n"
    + "      local ok_orig, orig_res = pcall(__orig_process_handle, msg)\n"
    + "      if ok_orig and orig_res ~= nil then return orig_res end\n"
    + "    end\n"
    + "    if type(_G.handle) == \"function\" then\n"
    + "      local routed = _G.handle(msg)\n"
    + "      if routed ~= nil then return routed end\n"
    + "    end\n"
    + "    return nil\n"
    + "  end\n"
    + "end\n"
)
composed = runtime_text[:idx] + injected + runtime_text[idx:]
runtime.write_text(composed, encoding="utf-8")

if 'function process.handle' not in composed:
    print("composed runtime is missing process.handle", file=sys.stderr)
    sys.exit(1)
if 'package.preload["ao.resolver.process"]' not in composed:
    print("composed runtime is missing resolver preload", file=sys.stderr)
    sys.exit(1)
if 'pcall(require, "ao.resolver.process")' not in composed:
    print("composed runtime is missing resolver require hook", file=sys.stderr)
    sys.exit(1)
if "\nreturn process" not in composed:
    print("composed runtime is missing final return process", file=sys.stderr)
    sys.exit(1)
print("runtime composition ok")
PY

echo "[3/4] Ensuring resolver config has safe initial_memory"
python3 - <<'PY'
from pathlib import Path
import os
import re
import sys

cfg = Path("dist/resolver/config.yml")
text = cfg.read_text(encoding="utf-8")
minimum = int(os.environ.get("MIN_INITIAL_MEMORY", "8388608"))
match = re.search(r"^initial_memory:\s*(\d+)\s*$", text, flags=re.MULTILINE)
if not match:
    print("config.yml does not contain initial_memory", file=sys.stderr)
    sys.exit(1)
current = int(match.group(1))
if current < minimum:
    text = re.sub(r"^initial_memory:\s*\d+\s*$", f"initial_memory: {minimum}", text, flags=re.MULTILINE)
    cfg.write_text(text, encoding="utf-8")
    print(f"initial_memory raised {current} -> {minimum}")
else:
    print(f"initial_memory kept at {current}")
PY

echo "[4/4] Building resolver WASM via Docker"
RESOLVER_DIST_ABS="$(cd dist/resolver && pwd)"
docker run \
  --platform linux/amd64 \
  -e MIN_INITIAL_MEMORY="${MIN_INITIAL_MEMORY}" \
  -v "$(docker_bind_path "${RESOLVER_DIST_ABS}"):/src" \
  "${DOCKER_IMAGE}" \
  ao-build-module

if [[ ! -f "dist/resolver/process.wasm" ]]; then
  echo "resolver wasm build failed: dist/resolver/process.wasm missing" >&2
  exit 1
fi

echo "Done: dist/resolver/process.wasm"
