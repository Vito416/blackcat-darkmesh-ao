# Cloudflare Worker (Inbox + Thin Trusted Layer)

Purpose
- Thin, low-cost trusted layer (Cloudflare Free) for small/medium sites.
- Short-lived storage of encrypted envelopes (PII) with TTL + delete-on-download.
- Trusted holder of **secrets** that must not live on AO/Arweave (e.g., PSP API keys, OTP secrets, SMTP token).
- Hook for AO `ForgetSubject` to wipe all envelopes for a subject hash.
- Optional notification fan-out (email/webhook) without persisting plaintext.

What it should do (scope)
- Inbox with TTL + delete-on-download.
- Forget endpoint (auth-protected) to purge by subject prefix.
- Secret-backed operations: OTP issuance/verification, PSP webhook verification (shared secrets), signing/HMAC helpers.
- Notification relay: send email/WebPush/Webhook using stored secrets; never store plaintext payload.
- Rate limiting and replay protection for incoming hooks.
- Scheduled janitor to delete expired envelopes and stray items.

What it should NOT do
- No long-term database of PII; only short-lived encrypted blobs.
- No business logic for catalog/orders; that stays in write/AO.
- No heavy compute or large file handling (Cloudflare free limits).

Data model
- KV namespace `INBOX_KV`.
- Key format: `subjectHash:nonce` -> `{ payload, exp }` (payload is already encrypted with admin public key).
- TTL enforced via KV expiration + `exp` field; janitor double-checks.

API (baseline)
- `POST /inbox` body `{ subject, nonce, payload, ttlSeconds? }` → 201; stores + sets TTL.
- `GET /inbox/:subject/:nonce` → 200 `{ payload, exp }`; deletes after read.
- `POST /forget` body `{ subject }` → 202; auth via `Authorization: Bearer <WORKER_AUTH_TOKEN>` (`FORGET_TOKEN` still accepted for legacy configs).
- `POST /notify` (optional) body `{ to, kind, data }` → 202; uses e.g. SENDGRID_KEY / webhook; never persists data.
- `GET /health` — liveness check, returns `{ status: \"ok\" }`.
- `GET /metrics` — Prometheus text; protect via `METRICS_BASIC_USER`/`METRICS_BASIC_PASS` or `METRICS_BEARER_TOKEN`.
- `scheduled` (cron) – deletes expired items, cleans malformed entries.

Secrets to keep here (examples)
- PSP webhook secrets (Stripe/PayPal/GoPay), HMAC salts.
- OTP/TOTP secret for passwordless login.
- SMTP/Sendgrid/WebPush keys.
- Admin public key is used client-side to encrypt; private keys stay offline, **never** here.

Env/config
- `INBOX_TTL_DEFAULT`, `INBOX_TTL_MAX`
- `INBOX_KV` (KV binding)
- `WORKER_AUTH_TOKEN` (Bearer guard for /forget and /notify; `FORGET_TOKEN` still accepted for backward compatibility)
- `METRICS_BASIC_USER`/`METRICS_BASIC_PASS` or `METRICS_BEARER_TOKEN` (protect /metrics)
- `SENDGRID_KEY` / `NOTIFY_WEBHOOK` (optional)
- `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW` (per-IP for inbox/notify)
- `SUBJECT_MAX_ENVELOPES` (max live envelopes per subject)
- `PAYLOAD_MAX_BYTES` (reject oversized payloads)
- `REPLAY_TTL` (seconds; reject resubmission of same subject+nonce)
- `NOTIFY_RATE_MAX`, `NOTIFY_RATE_WINDOW` (per-IP for /notify)
- `INBOX_HMAC_SECRET` (optional HMAC check for /inbox; header `X-Signature`)
- `NOTIFY_HMAC_SECRET` (HMAC check for /notify; set `NOTIFY_HMAC_OPTIONAL=1` only if unsigned allowed)
- `NOTIFY_FROM` (default from address for SendGrid)
- `REQUIRE_SECRETS` (prod: fail fast if WORKER_AUTH_TOKEN/INBOX_HMAC_SECRET/NOTIFY_HMAC_SECRET unset)
- `REQUIRE_METRICS_AUTH` (prod: 500 /metrics if auth secrets not configured)

Build/Deploy
- Fill `worker/wrangler.toml` (copy from `wrangler.toml.example`; set KV id). Fill `ops/env.prod.example` → `/etc/blackcat/worker.env` with real secrets (fail-closed baseline).
- `npm install` in `worker/`
- `wrangler dev` for local/miniflare test
- `wrangler publish --env production` (or use deploy script below)
- Load/perf smoke: `docker run --rm --network host -v $PWD:/repo -w /repo grafana/k6 run ops/loadtest/k6-worker.js` (expects miniflare at :8787 with HMAC secrets).
- CF deploy (WSL):  
  1) `export CLOUDFLARE_API_TOKEN=<token>` (scopes: Workers Scripts Edit, KV Edit, User Details Read).  
  2) `export CLOUDFLARE_ACCOUNT_ID=<your account id>` (CF Dashboard → Workers & Pages → Overview).  
  3) `cp wrangler.toml.example wrangler.toml` (local only, gitignored).  
  4) `./deploy_cf.sh` (creates KV, generates random secrets, deploys with wrangler@4).  
  5) Worker URL and generated secrets are printed at the end—store them in your vault.

Local testing
- Vitest/Miniflare run with in-memory KV/D1 (`TEST_IN_MEMORY_KV=1` in `wrangler.toml`) to avoid local SQLite locks.
- Docker option: `docker compose -f docker-compose.test.yml run --rm worker-test` (installs workerd binaries and runs `npm test`).
- Pen-test (webhook/auth) via Docker without local Node:
  - `docker run --rm -v $(pwd):/app -w /app node:20-alpine sh -c "npm ci && npm test -- --run test/metrics-auth.test.ts"`
- Load test harness (k6) with HMAC + nonce: see `ops/loadtest/README.md`.

Env vars (extra)
- `TEST_IN_MEMORY_KV` — dev/test only; ignored in production (only value `1` enables the in-memory shim).
- Metrics exposed (examples): `worker_inbox_put_total`, `worker_inbox_replay_total`, `worker_rate_limit_blocked_total`, `worker_inbox_expired_total`, `worker_forget_deleted_total`, `worker_notify_rate_blocked_total`, `worker_metrics_auth_blocked_total`, `worker_metrics_auth_ok_total`, `worker_notify_hmac_invalid_total`, `worker_notify_hmac_optional` (gauge).
