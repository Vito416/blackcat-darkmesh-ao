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
- `POST /forget` body `{ subject }` → 202; auth via `Authorization: Bearer <FORGET_TOKEN>`.
- `POST /notify` (optional) body `{ to, kind, data }` → 202; uses e.g. SENDGRID_KEY / webhook; never persists data.
- `scheduled` (cron) – deletes expired items, cleans malformed entries.

Secrets to keep here (examples)
- PSP webhook secrets (Stripe/PayPal/GoPay), HMAC salts.
- OTP/TOTP secret for passwordless login.
- SMTP/Sendgrid/WebPush keys.
- Admin public key is used client-side to encrypt; private keys stay offline, **never** here.

Env/config
- `INBOX_TTL_DEFAULT`, `INBOX_TTL_MAX`
- `INBOX_KV` (KV binding)
- `FORGET_TOKEN` (Bearer guard for forget)
- `SENDGRID_KEY` / `NOTIFY_WEBHOOK` (optional)
- `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW` (per-IP for inbox/notify)
- `SUBJECT_MAX_ENVELOPES` (max live envelopes per subject)
- `PAYLOAD_MAX_BYTES` (reject oversized payloads)
- `REPLAY_TTL` (seconds; reject resubmission of same subject+nonce)
- `NOTIFY_RATE_MAX`, `NOTIFY_RATE_WINDOW` (per-IP for /notify)
- `INBOX_HMAC_SECRET` (optional HMAC check for /inbox; header `X-Signature`)
- `NOTIFY_FROM` (default from address for SendGrid)

Build/Deploy
- Fill `worker/wrangler.toml` (KV id; secrets via `wrangler secret put FORGET_TOKEN` etc.)
- `npm install` in `worker/`
- `wrangler dev` for local/miniflare test
- `wrangler publish --env production`

Local testing
- Vitest/Miniflare run with in-memory KV/D1 (`TEST_IN_MEMORY_KV=1` in `wrangler.toml`) to avoid local SQLite locks.
- Docker option: `docker compose -f docker-compose.test.yml run --rm worker-test` (installs workerd binaries and runs `npm test`).

Env vars (extra)
- `TEST_IN_MEMORY_KV` — dev/test only; ignored in production.
