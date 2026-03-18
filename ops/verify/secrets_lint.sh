#!/usr/bin/env bash
set -euo pipefail

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
fail=0

check_kv() {
  local file=$1 key=$2 expected=$3
  local got
  got="$(grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- || true)"
  if [[ "$got" != "$expected" ]]; then
    red "FAIL ${file}: ${key} expected ${expected}, got '${got:-<missing>}'"
    fail=1
  fi
}

echo "Linting env templates..."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

check_kv "$ROOT/ops/env.prod.example" AUTH_REQUIRE_SIGNATURE 1
check_kv "$ROOT/ops/env.prod.example" AUTH_REQUIRE_NONCE 1
check_kv "$ROOT/ops/env.prod.example" AUTH_REQUIRE_JWT 1

check_kv "$ROOT/worker/ops/env.prod.example" REQUIRE_SECRETS 1
check_kv "$ROOT/worker/ops/env.prod.example" REQUIRE_METRICS_AUTH 1
check_kv "$ROOT/worker/ops/env.prod.example" INBOX_HMAC_OPTIONAL 0
check_kv "$ROOT/worker/ops/env.prod.example" NOTIFY_HMAC_OPTIONAL 0

if [[ $fail -ne 0 ]]; then
  exit 1
fi
green "secrets lint OK"
