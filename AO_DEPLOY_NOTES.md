# AO Deploy Notes — blackcat-darkmesh-ao

Last updated: 2026-04-08

This file is the operational source of truth for shipping `blackcat-darkmesh-ao`
to AO push endpoints (`push.forward.computer`, `push-1.forward.computer`).

---

## 4.10) 2026-04-08 — Post-limit continuation (new module/PID matrix)

Tooling/code updates in this run:
- `scripts/cli/deep_test_scheduler_direct.js`
  - `slot/current` probe now prefers process path
    `/<PID>~process@1.0/slot/current?accept-bundle=true`
    and only then falls back to legacy `/<PID>/slot/current`.
- `scripts/cli/diagnose_cu_readback.js`
  - same process-first slot probe strategy added for consistency.
- `scripts/deploy/patch_seed_module.mjs`
  - now patches both legacy seed expression and eager templates load:
    - seed: `msg.Owner .. msg.Module .. msg.Id` -> nil-safe tags fallback path
    - templates: `require("templates")` -> `pcall(require, "templates")` with `{}` fallback
  - script made idempotent (no false warning when already patched).
- New helper added:
  - `scripts/deploy/rebuild_wasm_from_runtime.sh`
  - deterministic Docker rebuild from patched `dist/<target>/process.lua`.

New deploy artifacts created:
- Module: `n6kD3aibbIMn-zOaH9gYIMkxDjp1p9-aVPM3NQMzGMI` (publish status `200`, current arweave tx status: `Accepted`).
- PID (extended / `ao.TN.1`): `yokrgdeojqERqLewE8yNL50YUd-BEFBCEeR-57RXdZA`.
- PID (minimal / `ao.N.1`): `As9sJWuYQcbXF7RronbIDUPqAenGKUvzld4xlN75fcM`.

Observed runtime/compute matrix:
- `bbPTfslH...` and `eLcYKlQa...`:
  - scheduler send + compute path reachable on `push` and `push-1`;
  - compute error is now consistently:
    `module 'templates' not found` (line ~2099 in `.process`).
- Fresh PIDs from module `n6kD3...`:
  - `slot/current` and `compute` return `500` with `details: {badmap,failure}`.
  - scheduler ingress may still assign slots on `push`, but compute/readback path fails at resolve stage.
  - same behavior reproduced for both spawn styles (`extended/TN` and `minimal/N`).

Current interpretation:
- Two separate failure classes are confirmed:
  1. Historical/finalized PIDs: process executes but fails at runtime (`templates` load path).
  2. Freshly spawned PIDs from latest module: upstream resolve-stage failure (`badmap,failure`) on compute/readback.
- This means fresh `badmap` is not yet proven as process business-logic regression; treat as deployment-readiness/readback path blocker until maturation/retest window completes.

---

## 4.11) 2026-04-08 — Deep tests after finalization window (current status)

Retested targets:
- Module: `n6kD3aibbIMn-zOaH9gYIMkxDjp1p9-aVPM3NQMzGMI`
- PID #1: `yokrgdeojqERqLewE8yNL50YUd-BEFBCEeR-57RXdZA`
- PID #2: `As9sJWuYQcbXF7RronbIDUPqAenGKUvzld4xlN75fcM`

Arweave status at test time:
- module tx => finalized (`22 confirmations` at check time)
- both pid tx ids still `Not Found` on `arweave.net/tx/<PID>/status`
  (push execution still works despite this, consistent with bundled/indexing behavior).

Deep test results:
- `tmp/deep-yokrgd-finalized.json`
  - pass `6/6` assertions (transport/runtime) across both:
    - `https://push.forward.computer`
    - `https://push-1.forward.computer`
- `tmp/deep-as9s-finalized.json`
  - had one transient transport failure on `push` for `BindDomain`:
    - `details: {necessary_message_not_found,...}` from HB cache/link resolution
- `tmp/deep-as9s-finalized-rerun.json`
  - clean rerun pass `6/6` (same actions/endpoints).

Readback diagnostics:
- `tmp/diag-yokrgd-finalized.json`
  - `slot/current` and `compute` are `200` on both push endpoints.
  - scheduler message probes `200`.
  - `ao.result` mostly resolves (`aoconnect.result`) with one transient invalid-json on earlier pass.
- `tmp/diag-as9s-finalized-rerun.json`
  - stable `200` for compute + scheduler message on all actions.
  - `ao.result` on primary push resolves for all tested actions.

Conclusion:
- Current fresh deployment line is now operational for registry deep-test actions (`RegisterSite`, `BindDomain`, `GetSiteByHost`) on both push endpoints.
- Prior `badmap,failure` / runtime crash behavior was not reproduced in this finalized rerun window.

---

## 4.12) 2026-04-08 — Strict gate matrix + transport retry hardening

Goal:
- run strict execution assertions repeatedly to verify whether remaining failures are process/runtime or transient transport.

Code hardening applied:
- `scripts/cli/deep_test_scheduler_direct.js`
  - scheduler send now retries up to 3 attempts on transport timeout/5xx before failing the action.
  - this keeps strict mode sensitive to real failures while reducing false negatives from one-off infra spikes.

Strict matrix results:
- `run1` (before retry hardening):
  - `yokrgd...` => pass `6/6`
  - `As9s...` => pass `6/6`
- `run2` (before retry hardening):
  - `yokrgd...` => pass `4/6` (2 transport failures)
  - `As9s...` => pass `5/6` (1 transport failure)
- `run3` (before retry hardening):
  - `yokrgd...` => pass `5/6` (1 transport failure)
  - `As9s...` => pass `5/6` (1 transport failure)
- `run4` (after retry hardening):
  - `yokrgd...` => pass `6/6`
  - `As9s...` => pass `6/6`

Readback/diagnose for strict run4:
- `tmp/diag-yokrgd-strict-run4-retrysend.json`:
  - `slot/current`, scheduler message probe, and `compute` all `200` on both push endpoints.
  - primary push `ao.result` resolves for all three actions.
- `tmp/diag-as9s-strict-run4-retrysend.json`:
  - same stable `200` behavior for transport + compute + scheduler message probes.
  - primary push `ao.result` resolves for all three actions.

Interpretation:
- Current registry deployment line is strict-testable and operational.
- Remaining instability observed in earlier runs is consistent with transient scheduler/push transport flakiness, not deterministic process logic failures.
- For release gate, keep strict assertions and retain send retry behavior.

---

## 0) Baseline helper import from `blackcat-darkmesh-write`

Added reusable helper set (adapted, not 1:1 copied):
- `scripts/build-ao-bundles.mjs`
- `scripts/deploy/publish_lua_module.mjs`
- `scripts/deploy/spawn_process_tn.mjs`
- `scripts/deploy/wait_finalized.sh`
- `package.json` + `package-lock.json` (dependencies: `arweave`, `@permaweb/aoconnect`)

Fresh bundle build executed successfully:
- `node scripts/build-ao-bundles.mjs --all`
- outputs:
  - `dist/registry-bundle.lua`
  - `dist/site-bundle.lua`
  - `dist/catalog-bundle.lua`
  - `dist/access-bundle.lua`
  - `dist/ingest-bundle.lua`

### First live bootstrap (registry only)
- Published:
  - bundle: `dist/registry-bundle.lua`
  - module tx: `b9SGF1Dz8kaygAaw0P08-66BUyGMa3naSI2XleD-Qz0`
  - arweave status at publish time: `Accepted`
- Spawned:
  - pid: `a1zzNSLK85-I9C_NfCUkQPb-vsgLgaGy96Q6_qF7lBk`
  - endpoint: `https://push.forward.computer`
  - scheduler: `n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo`
  - variant: `ao.TN.1`
- Immediate post-spawn probe:
  - `slot/current` returned transient `500` (`details: {badmap,failure}`), expected while module/pid are not fully finalized/indexed.
  - Do not treat this as code regression before full finalization window.

### 2026-04-08 — post-finalization deep test result (critical blocker closed)
- Re-tested finalized PID:
  - module: `b9SGF1Dz8kaygAaw0P08-66BUyGMa3naSI2XleD-Qz0`
  - pid: `a1zzNSLK85-I9C_NfCUkQPb-vsgLgaGy96Q6_qF7lBk`
  - endpoints:
    - `https://push.forward.computer`
    - `https://push-1.forward.computer`
- Scheduler ingress is healthy:
  - `schedule?target=<PID>` returns `200` and assigns slots.
  - `slot/current` increments (observed up to slot `6`).
- Compute is failing from genesis (`compute=0`) on both push endpoints with same explicit error body:
  - `{"error":"Module-Format for module \"b9SGF1Dz8kaygAaw0P08-66BUyGMa3naSI2XleD-Qz0\" is not supported"}`
- Final diagnosis:
  - The current published **Lua module bundle** is accepted by scheduler, but CU rejects it at compute time due to unsupported module format.
  - This is why readback/compute stays at `422` (`attempted-slot: 0`) even after full finalization.
- Required fix path:
  1. Build/publish a **WASM module** (WASP pipeline) with supported AO tags (including `Module-Format`, `Variant=ao.TN.1`, `Type=Module`).
  2. Spawn new PID from that WASM module.
  3. Wait full finalization, then rerun deep tests (`schedule`, `slot/current`, `compute`, `result`).

### 2026-04-08 — registry WASM rebuild + spawn (current live)
- Built registry WASM via `ao-dev build` in `dist/registry` after hyperengine bundle.
- Published WASM module:
  - module tx: `s0XDJRz9ynXoLDnsKW0MNXfeU42R-3CFdBFG1U-ttQs`
  - tags include `Module-Format=wasm64-unknown-emscripten-draft_2024_02_15`, `Variant=ao.TN.1`, `Content-Type=application/wasm`
- Spawned new registry PID (push):
  - pid: `MBgg1UDxVwW6YXUGwV_aY4xrT77QPVX5pxlR0kMXkTU`
  - url: `https://push.forward.computer`
  - scheduler: `n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo`
- Next: wait finalization window, then run deep tests against this PID.

---

## 1) Current Audit Snapshot (what is done vs missing)

### Verified now (local)
- `scripts/verify/preflight.sh` passes.
- `scripts/verify/ingest_smoke.lua` passes.
- Core integration/security tests pass:
  - `tests/integration/ingest_apply_spec.lua`
  - `tests/integration/schema_validation_spec.lua`
  - `tests/security/rate_limit_replay_spec.lua`
  - `tests/security/pii_regression_spec.lua`

### Deployment gaps found (blockers for reliable push rollout)
- AO push pipeline was previously missing; baseline helper tooling is now added:
  - `scripts/build-ao-bundles.mjs`
  - `scripts/deploy/publish_lua_module.mjs`
  - `scripts/deploy/spawn_process_tn.mjs`
  - `scripts/deploy/wait_finalized.sh`
- Runbook placeholders are now replaced with concrete deployment steps.
- Process files (`ao/registry/process.lua`, `ao/site/process.lua`,
  `ao/catalog/process.lua`, `ao/access/process.lua`) export `route` functions for
  tests, but there is no explicit production runtime wrapper documented here for
  push scheduler/deep-test flows.

Bottom line: business/domain logic is testable and deployment baseline is now in
place; remaining work is process-level deep test/runtime contract alignment.

---

## 2) Work Scope to Complete (P0/P1/P2)

## P0 — Must finish before first official AO rollout
1. Define runtime envelope contract for AO ingress/read:
   - Exact expected message shape (tags/data/body).
   - Canonical response shape and error codes.
2. Complete deployment pipeline scripts:
   - module publish (added),
   - process spawn (added),
   - tx finalization checks (added),
   - post-spawn smoke checks on push endpoints (still to add).
3. Add strict AO deep test gate for this repo (similar to `-write` strict gate):
   - send,
   - slot/current,
   - compute,
   - readback/result behavior.
4. Replace placeholder deploy runbook with executable steps.

## P1 — Should finish before v1.3.0
1. Add CI job for scheduler-direct deep tests (gated or nightly).
2. Add deploy manifest output (`module tx`, `pid`, `scheduler`, `variant`) as build artifact.
3. Add rollback guide with concrete last-known-good process set and re-point flow.

## P2 — Hardening / operational quality
1. Add on-call canary checks (`slot/current`, message echo, result readback).
2. Add release checklist template tied to tags/releases.
3. Add audit export signing (integrity chain for ops evidence).

---

## 3) Spawn Strategy (progressive rollout on push)

Use progressive rollout to isolate failures:

1. Publish module(s).
2. Spawn processes one-by-one (recommended order):
   - `registry`
   - `site`
   - `catalog`
   - `access`
   - ingest/apply coordinator (if split as separate process)
3. After each spawn:
   - verify scheduler slot endpoint,
   - wait finalization window,
   - run minimal smoke for that process only.
4. Only after all core processes pass, run full multi-process deep tests.

Recommended tracking table (fill every run):

| Component | Module TX | PID | Push URL | Spawn Time (UTC) | Finalized? | Smoke |
|---|---|---|---|---|---|---|
| registry |  |  |  |  |  |  |
| site |  |  |  |  |  |  |
| catalog |  |  |  |  |  |  |
| access |  |  |  |  |  |  |
| ingest/apply |  |  |  |  |  |  |

---

## 4) Finalization Policy (critical to avoid false debugging)

Do not treat early failures as code regressions until chain/indexing is mature.

Observed pattern in this ecosystem:
- first 5-10 minutes: transaction URL may return `404`,
- then `Pending`,
- full reliability can require ~30+ minutes.

Required checks:
- Arweave status:
  - `curl -s https://arweave.net/tx/<TX>/status`
- Viewblock manual check:
  - `https://viewblock.io/arweave/tx/<TX>`
- Push scheduler slot:
  - `curl -s "https://push.forward.computer/<PID>~process@1.0/slot/current?accept-bundle=true"`
  - `curl -s "https://push-1.forward.computer/<PID>~process@1.0/slot/current?accept-bundle=true"`

Rule:
- If tx is still `404`/early `Pending`, pause deep triage.
- Begin hard debugging only after finalization window and stable slot/current.

---

## 4.3) 2026-04-08 — Registry WASM status + blockers (s0XDJ… / MBgg1…)

- Module TX `s0XDJRz9ynXoLDnsKW0MNXfeU42R-3CFdBFG1U-ttQs` finalized (88 confirmations).
- PID TX `MBgg1UDxVwW6YXUGwV_aY4xrT77QPVX5pxlR0kMXkTU` still `Not Found` on arweave.net (likely not mined / bundled only).
- Push compute (slot=2) returns **runtime error** on both `push` and `push-1`:
  - `[string ".process"]:567: attempt to concatenate a nil value (field 'Module')`
  - Output shows `module` field present in process state, so likely a code-path in `.process` expects a message/env `Module` that is nil.
- slot/current returns `2` on both push endpoints, so the process is reachable, but compute fails in the process logic.

Blockers:
- PID not finalized on L1 (arweave.net 404).
- Compute error indicates a **nil Module** access in `.process` at line 567.

Next:
- Inspect `.process` around line ~567 in the wasm build source and guard against missing `Module` in the message/env.
- Confirm whether the runtime expects `Module` in the **message tags** vs in **state** and align accordingly.

---

## 4.4) 2026-04-08 — Fix for nil `Module` in seed

- Root cause: AOS seed used `msg.Owner .. msg.Module .. msg.Id`; scheduler messages can omit `Module`, so concat crashes.
- Added `scripts/deploy/patch_seed_module.mjs` to patch `dist/*/process.lua` so it falls back to `env.Process.Tags` and empty strings.
- Patch applied to `dist/registry/process.lua`; rebuild WASM (`ao-dev build`) is required before publish.

---

## 4.5) 2026-04-08 — Registry WASM republish with seed fix

- Module TX: `BcwDxWcPuMznS5zgPpJDDzigwY-Td4qcZrLhoeYzgVA`
- PID TX: `bbPTfslHZBPRmWlI6pWETAGc8i4dAyoXwP66aK9VKZ0`
- Spawn URL: `https://push.forward.computer`
- Variant: `ao.TN.1`

---

## 5) Practical Pre-Deploy Checklist

- [ ] Repo clean (`git status`).
- [ ] `scripts/verify/preflight.sh` green.
- [ ] Integration/security tests green.
- [ ] Runtime envelope contract frozen (no unresolved TODOs).
- [ ] Deploy scripts present and executable.
- [ ] Ops env prepared (`ops/env.prod.example` derived secure env).
- [ ] Signing/JWT/HMAC secrets sourced from secret manager (never repo).
- [ ] Rollback target documented before rollout.

---

## 6) Post-Deploy Checklist

- [ ] All module TXs and PIDs recorded in this file.
- [ ] All TXs finalized (not only spawned).
- [ ] Per-process smoke checks pass.
- [ ] Cross-process deep tests pass on `push` and `push-1`.
- [ ] `docs/runbooks/deploy.md` updated with exact IDs + timestamps.
- [ ] Release tag/changelog references this deployment set.

---

## 7) Immediate Next Execution Plan (recommended)

1. Implement P0 deploy tooling + runtime contract docs in this repo.
2. Do one dry-run deployment to testnet/dev push path.
3. Validate finalization + deep tests.
4. Promote same flow to production push with frozen commit SHA.

## 4.6) 2026-04-08 — Registry WASM republish with templates stub

- Added `ao/templates.lua` stub to satisfy `require("templates")`.
- Module TX: `NPF6RrNWQDmJaj93qwR-GcKbLpCsNavTa6KWbfbaW-o`
- PID TX: `eLcYKlQaoLtr-OjqFj9oumciaJOOBK1pbmdcIfOl0tk`
- Spawn URL: `https://push.forward.computer`
- Variant: `ao.TN.1`
- Deep test (scheduler direct) run immediately after spawn:
  - `slot/current` and `compute` return **HTTP 500** on both `push` and `push-1`.
  - Reported as **finalized**, but **500 persists**, so this is now treated as a **code/runtime blocker** to investigate.
  - At the time of our automated check, arweave.net showed `Accepted` (module) and `Not Found` (PID); re-verify if needed.

Blockers:
- **HTTP 500 on slot/current + compute** despite claimed finalization → investigate process/runtime error.

Next:
- Re-run deep tests and capture **exact compute error body** for code-level fix.

---

## 4.7) 2026-04-08 — Local HB + local CU diagnostics

- Local HB image: `hyperbeam-docker-hyperbeam-edge-release-ephemeral:latest` (recreated container to fix bind mount).
- Local CU image: `hyperbeam-docker-local-cu:latest` (started with `NODE_CONFIG_ENV=development`).
- Local CU running on `http://localhost:6363` (logs in `tmp/local-cu-last.log`).
- Local HB running on `http://localhost:8734` (logs in `tmp/local-hb-last.log`).

Local HB test:
- `hb_push_httpsig.js` to `http://localhost:8734/<PID>~process@1.0/push` returned **400 "Message is not valid."**
- HB logs show scheduler forward to `schedule.forward.computer/<PID>/schedule` returned **400**, then HB propagated 400.

Mainnet compute error (finalized PID):
- `compute` returns **500** with `details: {badmap,failure}` and stacktrace in `hb_maps:merge/3` → `hb_ao:resolve_stage`.
- This indicates a **resolver/metadata map merge failure** before the process executes.

Blockers:
- Scheduler is rejecting HTTPSIG message format (400).
- HB resolve stage fails with `{badmap,failure}` on compute (likely malformed metadata structure).

Next:
- Use `scheduler_shape_diff.js` / `push_shape_diff.js` to compare expected schema vs current message.
- Capture scheduler expected map by mirroring `dev_scheduler:http_post_schedule_sign` behavior.
- Align message format to resolve-stage expected map (fix source of `badmap`).

---

## 4.8) 2026-04-08 — Scheduler shape diff (mainnet scheduler)

- Ran `scripts/cli/scheduler_shape_diff.js` against `https://schedule.forward.computer`.
- **All tested shapes returned 400 "Message is not valid."** (plain lower/upper, tags+data, with scheduler/module, base64/base64url keyid).
- This confirms the scheduler expects a **committed AO envelope**, not raw JSON bodies.
- Report saved: `tmp/scheduler-shape-report.json`.

Blocker:
- We need to generate a fully committed AO message (commitments + committed keys) matching scheduler expectations.

---

## 4.9) 2026-04-08 — Hard fixes applied + current blocker state

Implemented now in this repo:
- `scripts/deploy/spawn_process_wasm_tn.mjs`
  - added `--mode` (`extended|minimal|auto`, default `extended`);
  - added module readiness gate (`--wait-module`, timeout/interval flags);
  - added auth tag passthrough (`AUTH_*` and `WRITE_*`) for signature/nonces/timestamps and key config;
  - improved PID extraction (header + body fallback).
- `scripts/cli/deep_test_scheduler_direct.js`
  - now supports `--profile registry|write` (default `registry`);
  - registry profile sends native AO registry actions (`RegisterSite`, `BindDomain`, `GetSiteByHost`) instead of write-only payloads;
  - slot/current probe no longer crashes on timeout (returns structured error in report).
- `scripts/cli/execution_assertions.js`
  - compute parser now includes `errorPreview`, so reports clearly show runtime error root cause.
- `ao/shared/analytics.lua`
  - removed hard dependency on `require("cjson")`; now tolerates missing cjson and skips log write safely instead of crashing.

Verified diagnostics (mainnet, push):
- Legacy PID `MBgg1UDx...` still computes with runtime error:
  - `[string ".process"]:567: attempt to concatenate a nil value (field 'Module')`
- Legacy PID `eLcYKlQa...` still computes with runtime error:
  - `module 'templates' not found`
- Freshly spawned PIDs from latest module (`tCyHZGJ...`) currently show:
  - `/slot/current` => HTTP 500
  - `/compute=<slot>` => HTTP 500 with `{badmap,failure}` stacktrace in HB resolve stage.

Interpretation:
- Existing process-level runtime bugs are confirmed and isolated (`Module` nil / missing `templates`) on old PIDs.
- New spawn path currently hits an upstream resolve-stage failure (`badmap,failure`) on push for fresh PIDs, even with corrected spawn tooling. This is the active blocker for deep tests against new deployments.

Local verification status after fixes:
- `luacheck ao scripts` => `0 warnings / 0 errors`
- passing checks:
  - `scripts/verify/ingest_smoke.lua`
  - `scripts/verify/publish_outbox_ingest.lua`
  - `scripts/verify/pii_scrub.lua`
  - `tests/integration/ingest_apply_spec.lua`
  - `tests/integration/schema_validation_spec.lua`
- `tests/security/rate_limit_replay_spec.lua`
- `tests/security/pii_regression_spec.lua`

---

## 4.13) 2026-04-08 — Option 1+2 execution (commit + strict gate expansion)

Completed `1)`:
- Committed strict-gate stability work:
  - commit: `c70d6ba`
  - files:
    - `AO_DEPLOY_NOTES.md`
    - `scripts/cli/deep_test_scheduler_direct.js`

Completed `2)` (strict gate expansion runbook execution):
- Extended `deep_test_scheduler_direct.js` profiles:
  - added `site`, `catalog`, `access` profiles
  - each profile now sends process-native actions (scheduler-direct ANS104 path)

- Built + published WASM modules:
  - `blackcat-ao-site` -> module `NXj_vpBKQ4OPZmE_bKsUVZhrdYaeFZg4WyXx4NYxSmE`
  - `blackcat-ao-catalog` -> module `EL5Gx_PSoKQuGvekB0sG1kZcGaoHF7euze4IU5e89rQ`
  - `blackcat-ao-access` -> module `j29e0kyr7ylMAuVc379kL39fM4qr_sZsob28sOgH9kw`

- Spawned fresh PIDs:
  - site PID: `lqOQgjj1NCGwJdv5_d2OZF1XoZuqYATt9aKt6YTLqzE`
  - catalog PID: `u8UTjPaLZtneZ1q6fRYEKpFVXJQ5cTfTFudyhtgqn98`
  - access PID: `Ae389A8v75E_BKJvD_tYZdD-XHqmJ3Biq9Y1knIFXOM`

- Deep tests executed:
  - `tmp/deep-site-strict.json` (strict)
  - `tmp/deep-catalog-info.json` (info)
  - `tmp/deep-access-info.json` (info)
  - all new PIDs currently fail compute/readback

Observed blocker signature (consistent across new PIDs):
- `/compute=<slot>` -> HTTP 500
- response details: `{badmap,failure}`
- stacktrace starts in:
  - `hb_maps:merge/3`
  - `hb_ao:resolve_stage/4`
- `slot/current` on new PIDs is also 500

Control checks:
- Legacy mature registry PID still passes:
  - `As9sJWuYQcbXF7RronbIDUPqAenGKUvzld4xlN75fcM`
  - report: `tmp/deep-registry-now-info.json` (all pass)
- Fresh spawn from known-good module also fails:
  - module `n6kD3aibbIMn-zOaH9gYIMkxDjp1p9-aVPM3NQMzGMI`
  - PID `tXFXLeFN9I4VbohJ0xmq0VsznVpNIhikE70F10zZ_zM`
  - report: `tmp/deep-registry-ref-info.json` (compute 500)

Interpretation:
- This is currently a **fresh-spawn readback/resolve-stage blocker** on push/CU path.
- It is not isolated to one process family (`site/catalog/access`), and reproduces even on fresh registry spawns.

Current state of L1 confirmation:
- New module TXs already show arweave status `200`.
- New PID TXs currently still `404` on `arweave.net/tx/<PID>/status`.

Immediate next step (required before hard code conclusions):
1. wait for PID finalization/index maturity;
2. rerun strict deep tests against the same PIDs;
3. only if `{badmap,failure}` persists after PID finalization, treat as code/protocol defect and continue deep RCA.

---
