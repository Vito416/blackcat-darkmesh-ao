# Ops Runbook (AO)

## Start / Stop
- Load env from `ops/env.prod.example` (signature/rate-limit/metrics paths).
- Process modules in `ao/*/process.lua` currently expose `route` for test/runtime
  embedding; they are not a complete push scheduler deployment wrapper by
  themselves.
- Use the deployment flow in `docs/runbooks/deploy.md` and track concrete module
  and PID rollout in `AO_DEPLOY_NOTES.md`.
- Ensure `METRICS_PROM_PATH` and `AUTH_RATE_LIMIT_SQLITE` paths are writable.
- The write command layer runs from the `blackcat-darkmesh-write` repo. See that
  repo’s runbook for its start/stop steps.

## Health Checks
- AO health:  
  `LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" lua scripts/verify/health.lua`
  (checks rate-limit store, metrics flush, audit size, deps).
- Dep check in CI: `RUN_DEPS_CHECK=1 scripts/verify/preflight.sh`.

## Key Management
- Store public keys under `/etc/ao/keys`; record `sha256sum /etc/ao/keys/*.pub`
  in your vault.
- Rotate on schedule: deploy new pubkey, restart AO with updated
  `AUTH_SIGNATURE_PUBLIC`, then retire the old key once signatures verify.
- Never commit private keys or print them in CI logs.

## Rate-Limit Store
- AO uses `AUTH_RATE_LIMIT_SQLITE`; health check performs RW test on boot.
  Persist it on durable storage and back it up if required.

## Periodic checksum monitoring (AO)
Example systemd unit:
```
[Unit]
Description=AO checksum monitor
After=network.target

[Service]
WorkingDirectory=/opt/blackcat-darkmesh-ao
Environment=CHECKSUM_INTERVAL_SEC=300
Environment=AO_QUEUE_PATH=/var/lib/ao/outbox-queue.ndjson
Environment=AO_WAL_PATH=/var/lib/ao/registry-wal.ndjson
Environment=AUDIT_LOG_DIR=/var/log/ao/audit
ExecStart=/opt/blackcat-darkmesh-ao/scripts/verify/checksum_daemon.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

## Publish ingest integrity
- AO accepts only signed events from `blackcat-darkmesh-write`.
- If you run the write bridge, enable HMAC verification on outbox events
  (`OUTBOX_HMAC_SECRET`) before applying them.
- Size guards: set `AO_QUEUE_MAX_BYTES` and monitor via health script.

## Arweave Deploy Verification
- After `arkb` deploy, compute local SHA256 and compare to fetched tx:  
  `sha256sum dev/schema-bundles/your.tar.gz`  
  `curl -sL https://arweave.net/<txid> | sha256sum`
- Record txid + hash in ops journal.

## Incident Response
- Replay/rollback: use WAL hashes to detect tampering; re-run AO fixtures to
  confirm determinism.
- Rate-limit exhaustion: inspect `AUTH_RATE_LIMIT_SQLITE`; adjust
  `AUTH_RATE_LIMIT_WINDOW_SECONDS` / `AUTH_RATE_LIMIT_MAX_REQUESTS` or block the
  offending resolver.
- Trust manifest failure: keep last-good manifest for grace window, then fail
  closed if signatures/expiry are invalid.

## v1.4.0 Integrity Rollout

### Prechecks
- Confirm the registry module and PID are both finalized before deep tests.
- Verify the registry exposes the integrity actions expected by the gateway:
  `GetTrustedRoot`, `GetIntegrityPolicy`, `GetIntegrityAuthority`,
  `GetIntegrityAuditState`, `GetIntegritySnapshot`.
- Run the local contract suite with the current integrity actions:
  `AUTH_REQUIRE_SIGNATURE=0 AUTH_REQUIRE_NONCE=0 lua5.4 scripts/verify/contracts.lua`
  (use strict signature-on verification in CI or on hosts with Lua crypto deps).

### Spawn / Finalization checkpoints
- Publish the registry module.
- Wait for the module tx to finalize before spawning the PID.
- Spawn the PID and wait for finalization again before running any deep tests.
- After finalization, confirm the PID returns a valid trusted-root snapshot and
  the integrity policy is not paused unless that pause is intentional.

### Deep test gates
- Run the integrity deep profile:
  `node scripts/cli/deep_test_scheduler_direct.js --profile integrity ...`
- Require the following to pass before rollout continues:
  - trusted release publish/query
  - authority rotation query/update
  - audit commitment append/query
  - policy pause/resume
  - revoked-root rejection
  - snapshot availability after republish
- Only move to gateway rollout after both push nodes show the same integrity
  snapshot shape and deep-profile assertions pass.

### Rollback trigger points
- Stop the rollout if `GetIntegritySnapshot` returns `NOT_FOUND` after finalization.
- Stop the rollout if the active root is revoked unexpectedly or policy remains
  paused after the expected maintenance window.
- Stop the rollout if the integrity deep profile fails on either push node in a
  reproducible way (one-off propagation flukes can be retried once).
- Use `SetIntegrityPolicyPause` to fail closed while investigating, then
  republish the last known good release/root once the issue is resolved.

### Troubleshooting
- `policy paused`: check `GetIntegrityPolicy`; if the pause is intentional, wait
  for the maintenance window. If not, resume with `SetIntegrityPolicyPause`.
- `snapshot not found`: confirm the PID finalized, then verify the active root
  exists via `GetTrustedRoot` and `GetTrustedReleaseByRoot`.
- `revoked root transition`: expect `GetIntegritySnapshot` to fail closed after a
  revoke; republish a new trusted release/root before re-enabling traffic.

## Secret Scanning
- Run `gitleaks detect --no-git -v` locally before releases; keep CI secrets at
  org level; do not print secrets in workflows.

## Lint/Supply Chain
- Pin Lua rocks in your deploy image; run `luacheck`/`stylua` if available. Use
  `RUN_DEPS_CHECK=1` preflight to fail when critical rocks are missing.

## Key rotation SOP (ed25519)
- Rotate every 90 days or on incident.
- Generate: `openssl genpkey -algorithm ed25519 -out /secure/ao-ed25519.key`
  and `openssl pkey -in ... -pubout -out /etc/ao/keys/ao-ed25519.pub`.
- Record `sha256sum /etc/ao/keys/*.pub` with date in the ops vault.
- Deploy new pubkey, restart AO, validate signatures, then retire the old key.
- Never store private keys in repo/CI; keep in secure KMS or offline.
