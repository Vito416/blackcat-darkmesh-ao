# Deploy Runbook (AO)

This runbook describes the minimum safe sequence for AO deployments from this
repository.

For active deployment tracking, use `AO_DEPLOY_NOTES.md`.

## 1) Preconditions

- Clean branch and pinned commit SHA.
- Production env derived from `ops/env.prod.example`.
- Secrets loaded from vault (not repo):
  - signature/JWT/HMAC inputs,
  - any scheduler/push auth material.
- Finalization policy acknowledged:
  - expect early `404` then `Pending` before stable results.

## 2) Local quality gate

Run before every rollout:

```bash
bash scripts/verify/preflight.sh
lua5.4 scripts/verify/ingest_smoke.lua
lua5.4 tests/integration/ingest_apply_spec.lua
lua5.4 tests/integration/schema_validation_spec.lua
lua5.4 tests/security/rate_limit_replay_spec.lua
lua5.4 tests/security/pii_regression_spec.lua
```

## 3) Publish + spawn strategy

Deploy progressively, not all-at-once:

1. Publish module(s).
2. Spawn processes in order:
   - registry
   - site
   - catalog
   - access
   - ingest/apply coordinator (if separate PID)
3. After each spawn:
   - check `slot/current`,
   - wait finalization,
   - run targeted smoke for that process.

Record every ID into `AO_DEPLOY_NOTES.md`.

If compute returns `Module-Format ... is not supported`, you must publish WASM modules:

```bash
npm run bundle:ao
npm run build:ao-wasm
node scripts/deploy/publish_wasm_module.mjs --wasm dist/registry/process.wasm --name blackcat-ao-registry
node scripts/deploy/spawn_process_wasm_tn.mjs --module <TX> --name blackcat-ao-registry
```

## 4) Finalization checks

```bash
curl -s https://arweave.net/tx/<TX>/status
curl -s "https://push.forward.computer/<PID>~process@1.0/slot/current?accept-bundle=true"
curl -s "https://push-1.forward.computer/<PID>~process@1.0/slot/current?accept-bundle=true"
```

Manual explorer check:

- `https://viewblock.io/arweave/tx/<TX>`

Do not start hard RCA until IDs are finalized and slot endpoints are stable.

## 5) Post-deploy acceptance

- Per-process smoke checks are green.
- Cross-process deep tests are green on both push endpoints.
- Deployment table in `AO_DEPLOY_NOTES.md` is filled.
- Release note includes module/PID set and commit SHA.
