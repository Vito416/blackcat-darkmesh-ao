# Deploy Scripts

This folder contains reusable publish/spawn helpers copied/adapted from the
`blackcat-darkmesh-write` operational flow so AO deployment can start from a
known working baseline.

## 1) Build Lua bundles

```bash
npm install
node scripts/build-ao-bundles.mjs --all
```

Outputs:
- `dist/registry-bundle.lua`
- `dist/site-bundle.lua`
- `dist/catalog-bundle.lua`
- `dist/access-bundle.lua`
- `dist/ingest-bundle.lua`

## 2) Publish module

```bash
node scripts/deploy/publish_lua_module.mjs \
  --bundle dist/registry-bundle.lua \
  --name blackcat-ao-registry
```

If you need a WASM module (required by current push CUs):

```bash
npm run bundle:ao
npm run build:ao-wasm

# Patch generated runtime (seed + templates fallback)
node scripts/deploy/patch_seed_module.mjs

# Rebuild WASM from patched dist/<target>/process.lua
scripts/deploy/rebuild_wasm_from_runtime.sh registry

node scripts/deploy/publish_wasm_module.mjs \
  --wasm dist/registry/process.wasm \
  --name blackcat-ao-registry
```

Optional:
- `--wallet wallet.json`
- `--out tmp/registry-module.json`
- `--tag key=value` (repeatable)

The script prints JSON with `tx` and `status`.

## 3) Wait for finalization

```bash
scripts/deploy/wait_finalized.sh <TX_ID>
```

Env overrides:
- `TIMEOUT_SEC` (default `3600`)
- `INTERVAL_SEC` (default `30`)

## 4) Spawn process on push

```bash
node scripts/deploy/spawn_process_tn.mjs \
  --module <TX_ID> \
  --name blackcat-ao-registry \
  --url https://push.forward.computer
```

For WASM modules:

```bash
node scripts/deploy/spawn_process_wasm_tn.mjs \
  --module <TX_ID> \
  --name blackcat-ao-registry \
  --url https://push.forward.computer
```

`spawn_process_wasm_tn.mjs` now uses raw `/push` (`ao.request`) with full process tags
(same strategy as `-write`) to avoid `aoconnect.spawn` tag/variant drift.
Default mode is now `extended` (more stable for AO WASM startup), with optional
`auto` fallback order (`extended -> minimal`) for compatibility.

Before spawn, it can also wait until `<module>~module@1.0` is readable on push
to avoid creating PIDs that fail early during resolve.

Optional:
- `--scheduler <SCHEDULER_ID>`
- `--wallet wallet.json`
- `--variant ao.TN.1`
- `--mode extended|minimal|auto` (default `extended`)
- `--wait-module 1|0` (default `1`)
- `--wait-module-timeout-ms 300000`
- `--wait-module-interval-ms 5000`
- `--module-format wasm64-unknown-emscripten-draft_2024_02_15`
- `--memory-limit 1-gb`
- `--compute-limit 9000000000000`
- `--aos-version 2.0.6`
- `--auth-require-signature 1|0`
- `--auth-require-nonce 1|0`
- `--auth-require-timestamp 1|0`
- `--auth-signature-type ed25519|hmac`
- `--auth-signature-public <path-or-inline>`
- `--auth-signature-publics <json-or-map>`
- `--auth-signature-secret <secret>`
- `--out tmp/registry-pid.json`
- `--tag key=value` (repeatable)

The script prints JSON with `pid`, `module`, and endpoint info.

After spawn, verify PID finalization as well:

```bash
scripts/deploy/wait_finalized.sh <PID_TX_ID>
```

## Notes
- Keep module/PID tracking in `AO_DEPLOY_NOTES.md`.
- Use progressive spawn order from the deploy runbook.
- Respect finalization windows to avoid false diagnostics.

## Deep test profiles (scheduler direct)

Use `scripts/cli/deep_test_scheduler_direct.js` for post-spawn sanity checks against push nodes.

```bash
node scripts/cli/deep_test_scheduler_direct.js \
  --profile integrity \
  --pid <REGISTRY_PID> \
  --wallet wallet.json \
  --urls https://push.forward.computer,https://push-1.forward.computer \
  --auth-signature-secret "$AUTH_SIGNATURE_SECRET" \
  --execution-mode strict
```

Available profiles:
- `registry`
- `site`
- `catalog`
- `access`
- `integrity` (trusted release + authority + audit commitment + policy pause + snapshot lifecycle)
- `write` (worker-signed write command probes)

Quick semantic smoke check (detects shell-only output that previously looked like a pass):

```bash
WALLET=wallet.json node scripts/deploy/smoke_push_scheduler.mjs \
  --pid <REGISTRY_PID> \
  --url https://push.forward.computer \
  --action GetSiteByHost \
  --strict-response true
```

`--strict-response true` fails when compute returns only AOS shell/prompt output
instead of a JSON envelope (`{status, code?, data?}`).

## Integrity registry operator CLI

Use `scripts/cli/integrity_registry_cli.js` when you want to send a single
integrity registry action with the same AO request conventions as the rest of
this repo.

Examples:

```bash
node scripts/cli/integrity_registry_cli.js \
  --action publish \
  --pid <REGISTRY_PID> \
  --wallet wallet.json \
  --component-id gateway \
  --version 1.4.0 \
  --root <root> \
  --uri-hash <uri-hash> \
  --meta-hash <meta-hash> \
  --policy-hash <policy-hash>
```

```bash
node scripts/cli/integrity_registry_cli.js \
  --action authority \
  --pid <REGISTRY_PID> \
  --wallet wallet.json \
  --root <authority-root> \
  --upgrade <authority-upgrade> \
  --emergency <authority-emergency> \
  --reporter <authority-reporter> \
  --signature-refs sig-root-1,sig-upgrade-1
```

```bash
node scripts/cli/integrity_registry_cli.js \
  --action audit \
  --pid <REGISTRY_PID> \
  --wallet wallet.json \
  --seq-from 1 \
  --seq-to 9 \
  --merkle-root <merkle-root> \
  --meta-hash <meta-hash> \
  --reporter-ref <reporter-ref>
```

Supported actions:
- `publish`
- `revoke`
- `get-root`
- `policy`
- `authority`
- `audit`
- `snapshot`
- `pause`
- `set-authority`
- `append-audit`

The CLI prints JSON for both successful responses and failures, and supports
`--dry-run` when you only want to inspect the prepared AO request. Use `--out`
to write the same JSON to disk for later comparison.
