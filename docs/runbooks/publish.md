# AO Publish Runbook

Use this before publishing a new AO module/process. Keep wallet material outside git and record resulting tx/process ids in deployment notes.

## Preconditions

- Working tree reviewed; no unrelated generated artefacts staged.
- `scripts/verify/preflight.sh` passes.
- `npm run bundle:ao` passes and produces the expected `dist/*-bundle.lua` files.
- For resolver deploys, `RESOLVER_ALLOW_CENTRALIZED_BUNDLE_WRITES=1 lua5.4 tests/integration/resolver_process_spec.lua` passes.
- Wallet path is supplied via env or CLI; never commit wallets or secrets.

## Lua module flow

```bash
npm run bundle:ao
node scripts/deploy/publish_lua_module.mjs \
  --bundle dist/registry-bundle.lua \
  --name blackcat-ao-registry \
  --out tmp/registry-module.json
scripts/deploy/wait_finalized.sh "$(jq -r .tx tmp/registry-module.json)"
node scripts/deploy/spawn_process_tn.mjs \
  --module "$(jq -r .tx tmp/registry-module.json)" \
  --name blackcat-ao-registry \
  --out tmp/registry-spawn.json
```

## Resolver WASM flow

```bash
npm run bundle:ao:resolver
npm run build:ao-wasm
node scripts/deploy/patch_seed_module.mjs
scripts/deploy/rebuild_wasm_from_runtime.sh resolver
node scripts/deploy/publish_wasm_module.mjs \
  --wasm dist/resolver/process.wasm \
  --name blackcat-ao-darkmesh-resolver-v1 \
  --out tmp/resolver-module.json
scripts/deploy/wait_finalized.sh "$(jq -r .tx tmp/resolver-module.json)"
node scripts/deploy/spawn_process_wasm_tn.mjs \
  --module "$(jq -r .tx tmp/resolver-module.json)" \
  --name darkmesh-resolver \
  --production-scheduler 1 \
  --out tmp/resolver-spawn.json
```

## Post-publish checks

- Run the relevant smoke action with `scripts/deploy/smoke_push_scheduler.mjs`.
- Verify public read shape before pointing gateway/resolver config at a new process id.
- Record module tx, process id, scheduler, URL, commit hash, and smoke result in `AO_DEPLOY_NOTES.md`.
- Only update external gateway/worker config after smoke checks pass.
