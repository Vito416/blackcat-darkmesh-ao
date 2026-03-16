# Ops Runbook (AO)

Scope reminder: AO is public state only. No secrets, no PSP/OTP/SMTP keys, no
mailbox payloads. Ingests signed publish/apply events from
`blackcat-darkmesh-write`; serves read-only state to gateways/resolvers.

## Key rotation (ed25519)
- Keys live at `/etc/ao/keys/*.pub` (private keys in secure store only).
- Record checksum: `sha256sum /etc/ao/keys/ao-ed25519.pub` (store in ops notes).
- Rotation steps:
  1) Generate new keypair (keep old active): `ssh-keygen -t ed25519 -f /etc/ao/keys/ao-ed25519-new -N ''`.
  2) Update env: `AUTH_SIGNATURE_PUBLIC` to new pub; deploy AO.
  3) Verify libsodium/openssl present; run `scripts/verify/libsodium_strict.sh` and `scripts/verify/preflight.sh`.
  4) After validation, retire old key (remove from env, archive private securely).
- HMAC secrets (e.g., OUTBOX_HMAC_SECRET used to verify incoming events) rotate
  by adding new, deploy, then deprecate old once all emitters updated.

## Checksums / WAL / queue
- Queue/WAL paths: `AO_WAL_PATH`, `AO_QUEUE_PATH`. (Write-side WAL/outbox are
  managed in the write repo.)
- Health: `scripts/verify/checksum_alert.sh` warns on size/hash drift.
- Daemon: `ops/checksum-daemon.service` runs `scripts/verify/checksum_daemon.sh` with `CHECKSUM_INTERVAL_SEC`.
- Set alerts when WAL/queue exceed thresholds (`AO_WAL_MAX_BYTES`, `AO_QUEUE_MAX_BYTES`).

## Secrets handling
- AO should remain secretless. CI uses org-level secrets only for signing key
  verification; gitleaks runs in CI (fail on detection). Avoid echoing any
  material in logs.
- Keep `ops/env.prod.example` free of real keys; use vault/secret manager for
  production env files.

## Start/stop
- AO health: `LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" lua scripts/verify/health.lua`
- Check metrics flush: `METRICS_PROM_PATH`, `METRICS_FLUSH_INTERVAL_SEC`.
- Run checksum daemon under systemd: `ops/checksum-daemon.service` (set env file `/etc/blackcat/ao.env`).

## Incident: replay/rollback
- Use WAL hashes to detect tamper. Re-run AO fixtures/contracts if present and
  compare.
- For resolver trust issues: rotate trusted resolvers manifest
  (`UpdateTrustResolvers`) and flags file (`AO_FLAGS_PATH`).

## Dependency pinning
- Rocks pinned via `ops/rocks.lock`. CI installs from lockfile; ensure updates go through `luarocks` + lock refresh.
- No npm/pip runtime deps today; if added, pin versions and add lock files to
  ops/ (package-lock.json/pip-tools).

## Immutable data / WeaveDB exports
- Arweave/WeaveDB je nemazatelný: do AO neukládej PII ani něco, co může být
  předmětem výmazu. Používej pouze hash/pseudonymy.
- Citlivá data patří do worker/inbox s TTL/delete-on-download; AO je nikdy
  nevidí.
- Pokud chceš publikovat veřejný stav do WeaveDB, zapni `AO_WEAVEDB_EXPORT_PATH`
  (append-only NDJSON už PII-scrub) a převeď na bundle:
  `lua5.4 scripts/export/bundle_export.lua > bundle.json` a ten nahraj.
