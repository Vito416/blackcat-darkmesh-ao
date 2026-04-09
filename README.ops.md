# Ops Quick Guide (AO + Write + Worker)

## Local test commands
- AO preflight: `scripts/verify/preflight.sh`
  - Runs schema checks, luacheck, and AO verification scripts.
- AO smoke (minimal): `lua5.4 scripts/verify/ingest_smoke.lua`
- Worker tests (in-memory): `cd worker && npm ci --ignore-scripts && TEST_IN_MEMORY_KV=1 MINIFLARE_KV_PERSIST=false MINIFLARE_D1_PERSIST=:memory: npm test -- --testTimeout=30000 --reporter=basic --pool=forks --maxConcurrency=1 --run test/metrics-auth.test.ts test/security-pen.test.ts test/notify.test.ts`
- End-to-end compose smoke (Write → Gateway → Worker):
  - `DOCKER_CONFIG=/tmp docker compose -f docs/docker-compose-e2e.yml up --build`
  - Uses sibling repos (`blackcat-darkmesh-write`, `blackcat-darkmesh-gateway`, `worker`) and runs outbox HMAC smoke, gateway auth/webhook checks, and worker auth/notify checks.
  - Logs stay in compose output; the run stops on the first failing service.
- End-to-end notify smoke (optional):
  - Extend `docs/docker-compose-e2e.yml` with an explicit Write `/notify` emit and Gateway→Worker forward flow using a test webhook URL or stub fetch.
  - Set `NOTIFY_HMAC_SECRET` and `NOTIFY_RATE_MAX=1` in worker env for strict validation.

## CI
- `.github/workflows/ci.yml` — main AO workflow (lint/verify flow).
- `.github/workflows/darkmesh-worker-tests.yml` — dedicated worker Vitest suite.
- `.github/workflows/darkmesh-ao-write.yml` — optional AO/Write embedded test flow; this job now auto-skips when the embedded write test layout is not present in this repo.

## Bundler/export
- Set env paths before running exports:
  - `AO_WEAVEDB_EXPORT_PATH` for AO public export (e.g., `/tmp/ao-export.ndjson`).
  - `WRITE_OUTBOX_EXPORT_PATH` for write outbox/WAL export (e.g., `/tmp/write-export.ndjson`).
- Example (already in compose): `LUA_PATH=$LUA_PATH LUA_CPATH=$LUA_CPATH AO_WEAVEDB_EXPORT_PATH=/tmp/write-export.ndjson lua5.4 scripts/export/bundle_export.lua`
- Sitemap: `BASE_URL=https://example.com LUA_PATH=... lua5.4 scripts/export/sitemap.lua` → outputs `sitemap.xml`.
- Catalog feed: `CATALOG_FEED_PATH=/tmp/catalog.ndjson LUA_PATH=... lua5.4 scripts/export/catalog_feed.lua`.

## Environment highlights
- AO/Write exports: set `AO_WEAVEDB_EXPORT_PATH`, `WRITE_OUTBOX_EXPORT_PATH` for bundler/snapshots.
- Worker: `TEST_IN_MEMORY_KV=1` for dev/test; ignored in production. `FORGET_TOKEN` protects `/forget`.
- Gateway: cache TTL must not exceed Worker inbox TTL; ensure ForgetSubject triggers cache wipe.
- PSP/webhooks: keep breaker metrics and retry/backoff enabled; signature/cert cache must be configured (e.g., PayPal).

## Docker housekeeping
- Remove test images after runs (optional): `docker rmi node:20-bookworm-slim` and `docker image prune -f`.

## Troubleshooting
- `SQLITE_BUSY` during worker tests: ensure `TEST_IN_MEMORY_KV=1` is set (default in `worker/wrangler.toml`), or run tests with in-memory D1/KV env overrides.
