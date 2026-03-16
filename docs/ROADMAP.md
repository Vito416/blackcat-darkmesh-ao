# AO / Write roadmap (aligned to v2 architecture)

## AO (public truth)
- Registry/router hardening: domains ↔ site mapping, active version pointers,
  resolver allowlist, cache keys.
- Public state ingestion: apply publish events from `blackcat-darkmesh-write`,
  enforce schema + size caps, append-only history.
- Public read surface: page/layout/navigation/catalog reads; locale + SEO
  metadata; deterministic responses for gateway caching.
- Audit receipts: store only hashes/refs for mailbox/forms; expose audit queries
  without leaking payloads.
- Trust/keys: public key registry + rotation metadata; optional signature
  requirements on resolver calls.
- Resilience: stale-if-error cache hints, single-flight on cold misses,
  per-tenant rate limits, health/metrics.

## Write (command layer)
- Command catalog: create/update/publish/archive, rotate-key, link-domain,
  create-receipt, permission updates.
- Validation/policy: schema, role/capability checks, tenant scoping.
- Idempotency/anti-replay: `Request-Id` registry, nonce/timestamp window,
  deterministic replay responses.
- Publish orchestration: build publish event, pin manifests/refs, emit to AO.
- Audit + receipts: append-only WAL/outbox, HMAC/signature on emitted events.
- Bridge hooks: minimal HTTP/queue adapters for delivering events to AO; no
  SMTP/PSP/OTP integrations inside the repo.

## Delivery order (suggested)
1) AO ingestion + publish history + resolver allowlist.
2) Write command validation/idempotency + publish orchestration.
3) Public read surface completeness (pages/layout/navigation/catalog + locale/SEO).
4) Audit/receipts exposure and ops metrics.
5) Performance + cache hardening.

## Next TODO (gateway/worker alignment)
- Verify HMAC on outbox/apply events from Write (OUTBOX_HMAC_SECRET) before mutating public state.
- Expose Prom metrics matching gateway expectations (webhook retry queue, PSP breaker, outbox size) via METRICS_PROM_PATH.
- CI: run `scripts/verify/ingest_smoke.lua` + `scripts/export/bundle_export.lua` on every change; publish bundle artifact.
- Keep AO secretless: ensure export/persist scrub PII; add regression test for PII keys.
