# Ops Quick Guide (AO + Write + Worker)

## Local test commands
- AO/Write smoke: `docker compose -f docker-compose.test.yml run --rm ao-write-test`
  - Runs luacheck, `scripts/verify/ingest_smoke.lua`, and bundler export.
- Worker tests: `docker compose -f docker-compose.test.yml run --rm worker-test`
  - Uses in-memory KV/D1 (`TEST_IN_MEMORY_KV=1`) to avoid SQLite locks.

## CI
- `.github/workflows/darkmesh-worker-tests.yml` — Vitest suite for the worker. Badge: `![Worker Tests](https://github.com/blackcatacademy/blackcat-darkmesh-ao/actions/workflows/darkmesh-worker-tests.yml/badge.svg)`
- `.github/workflows/darkmesh-ao-write.yml` — luacheck + ingest_smoke + bundler for AO/Write. Badge: `![AO Write Tests](https://github.com/blackcatacademy/blackcat-darkmesh-ao/actions/workflows/darkmesh-ao-write.yml/badge.svg)`

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
- `SQLITE_BUSY` during worker tests: ensure `TEST_IN_MEMORY_KV=1` is set (default in `wrangler.toml`), or rerun via Docker compose which sets it automatically.
