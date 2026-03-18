# E2E staging smoke (Write → Gateway → Worker → AO)

Goal: validate signing/HMAC chain end-to-end with test secrets before prod.

## Prereqs
- Test secrets (env, no literals in repo):
  - OUTBOX_HMAC_SECRET=<your_outbox_hmac_secret>
  - WRITE_REQUIRE_SIGNATURE=1, WRITE_REQUIRE_NONCE=1
  - GATEWAY_METRICS_* (basic/bearer) and webhook secrets
  - WORKER METRICS/NOTIFY tokens, INBOX/NOTIFY HMAC secrets
- Prom target: staging Prom server scraping gateway/write/worker.

## Steps
1. **Write**: run `lua scripts/verify/publish_outbox_mock_ao.lua` with OUTBOX_HMAC_SECRET set. Confirms outbox emits HMAC.
2. **Gateway**: mock ingress of PSP webhook → forward to Write; check metrics (`gateway_webhook_*`, breakers if propagated).
3. **Worker**: send /notify with correct HMAC; ensure metrics (`worker_notify_sent_total`) increments.
4. **AO ingest**: run `lua scripts/verify/publish_outbox_ingest.lua` to apply Publish/Order/Shipment/Payment events.
5. **Dashboards**: import/write PSP breaker, gateway metrics, worker metrics dashboards; verify panels update.
6. **Alerts sanity**: temporarily lower thresholds to trigger (breaker_open, verify_fail, DLQ>0, WAL>50MB, inbox_expired spike, notify_fail).

## Optional docker-compose
- Compose services: write (lua), gateway (node/ts), worker (node), fake PSP/webhook mock.
- Mount test env files; expose /metrics for Prom.
- Run scripts above inside compose to validate HMAC/signature chain.
