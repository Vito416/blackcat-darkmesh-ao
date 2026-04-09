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
