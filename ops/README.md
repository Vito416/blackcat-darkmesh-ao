# Ops Overview (AO)

What this repo is
- Public, secretless AO state: site registry, routing, published pages/layouts,
  navigation/SEO, catalog public payload refs, permission registry, audit
  receipts (hashes/refs only).
- Ingests only signed publish/apply events from `blackcat-darkmesh-write`.
- Serves read-only APIs to gateways/resolvers; no drafts, no mailbox payloads,
  no PSP/SMTP/OTP secrets.

What you deploy
- AO processes (`registry`, `router/public_state`, `catalog`, `permissions`)
  plus shared libs.
- Systemd services: see `ops/checksum-daemon.service` for checksum monitoring;
  set env via `/etc/blackcat/ao.env`.
- Metrics/health: write Prom text to `METRICS_PROM_PATH` and expose it via the
  sidecar `ops/systemd/ao-http.service` (`/metrics`, `/health`). Configure
  scrape target to `http://<host>:${AO_HTTP_PORT:-9100}/metrics`.
- Metrics seed: `ops/systemd/ao-metrics-seed.service` (+ timer) ensures the
  prom file exists at boot; enable `ao-metrics-seed.timer` alongside `ao-http`.
- Optional immutable export: set `AO_WEAVEDB_EXPORT_PATH` to append PII-scrubbed
  public snapshots/WAL for bundling to WeaveDB; local restart snapshots via
  `AO_STATE_DIR`.

Key files
- `ops/runbook.md` — procedures (key rotation, checksums, incidents).
- `ops/env.prod.example` — baseline env (no real secrets).
- `ops/alerts.md` — Prometheus alert suggestions.
- `ops/rocks.lock` — pinned Lua rocks for deployment images.

Guard rails
- Keep AO secretless; only public keys and hashes are allowed.
- Enforce signature + replay window on ingest; reject direct writes from
  gateways/clients.
- Set size caps (`AO_WAL_MAX_BYTES`, `AO_QUEUE_MAX_BYTES`) and monitor.
- WeaveDB (Arweave) is immutable: never persist PII or erasable data here.
  Store only hashed/pseudonymous identifiers; route deletable PII to the
  offline admin inbox/worker where “delete on download/TTL” is enforced.
