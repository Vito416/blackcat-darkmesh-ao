# End-to-end Flows (AO / Write / Gateway / Worker)

Goal: cover 99%+ web/eshop use-cases with PII kept offline/TTL.

Implementation status note (2026-04-14):
- Implemented adapter routes today: `POST /api/public/resolve-route`,
  `POST /api/public/page`, `POST /api/checkout/order`,
  `POST /api/checkout/payment-intent`.
- The worker endpoints `/inbox`, `/forget`, and `/notify` are implemented.
- Flows below marked as "planned" describe target-state orchestration not yet
  exposed as full adapter route coverage.

## Legend
- **Browser** – user client
- **Gateway** – edge/API gateway
- **Worker** – Cloudflare Worker (TTL inbox, notify)
- **Write AO** – command AO (truth source, emits outbox)
- **AO** – public/read AO (ingests outbox, public state)
- **Admin** – offline operator with private keys/offline DB

## Checkout & Payment (partially implemented)
```mermaid
sequenceDiagram
  participant B as Browser
  participant G as Gateway
  participant W as Worker (optional for PII)
  participant WR as Write AO
  participant AO as AO (catalog)
  participant PSP as PSP/Webhook
  B->>G: Add to cart / Start checkout
  G->>WR: CreateOrder / CreatePaymentIntent (implemented)
  WR-->>AO: outbox events (OrderCreated, PaymentIntentCreated)
  AO-->>G: public state (order status pending)
  PSP-->>G: payment webhook
  G->>WR: HandlePaymentProviderWebhook (planned adapter route)
  WR-->>AO: outbox (PaymentStatusChanged, OrderStatusUpdated)
  AO-->>G: order status paid
  G-->>B: confirmation
```

## Passwordless / OTP Login (planned)
```mermaid
sequenceDiagram
  participant B as Browser
  participant G as Gateway
  participant W as Worker
  participant Admin as Admin (offline)
  participant WR as Write AO
  participant AO as AO
  B->>G: Request OTP (public-key encrypted)
  G->>W: POST /inbox (TTL)
  Admin->>W: GET /inbox -> decrypt offline
  Admin->>WR: IssueSession
  WR-->>AO: outbox (SessionStarted)
  AO-->>G: session info
  G-->>B: session cookie/token
```

## PII Upload (address/docs)
```mermaid
sequenceDiagram
  participant B as Browser
  participant G as Gateway
  participant W as Worker
  participant Admin as Admin (offline)
  B->>G: Send PII (encrypted with admin pubkey)
  G->>W: POST /inbox (TTL)
  Admin->>W: GET /inbox -> decrypt & store in offline DB
  note over AO,WR: Only subject hashes/pseudonyms kept in AO/Write
```

## Forget / GDPR (planned orchestration, worker endpoint exists)
```mermaid
sequenceDiagram
  participant B as Browser
  participant G as Gateway
  participant AO as AO
  participant W as Worker
  B->>G: Forget me
  G->>AO: ForgetSubject(subject hash) (direct AO call)
  AO-->>W: POST /forget (deployment hook, Bearer token)
  W-->>W: Delete subject:* + replay keys
  note over Admin: Admin offline DB must also delete PII
```

## Notifications (email/webhook)
```mermaid
sequenceDiagram
  participant WR as Write AO
  participant G as Gateway
  participant W as Worker
  participant Dest as Email/Webhook
  WR-->>G: event (e.g., order paid, otp issued)
  G->>W: POST /notify (token)
  W->>Dest: webhook or SendGrid
```

## Reliability & Data-Safety Notes
- **Persistence path**: AO/Write emit PII-scrubbed state snapshots and WAL/outbox/idempotency into the WeaveDB export log; operators bundle this into WeaveDB for durable, immutable public state. Local snapshots (`AO_STATE_DIR` / `WRITE_STATE_DIR`) are only restart aids.
- **TTL/Cache**: Gateway keeps encrypted envelopes only within a bounded TTL window; cache hit/miss metrics + wipe-on-expire are required for deployment readiness. Expired entries must be wiped proactively; cache TTL is configurable per merchant and must never exceed worker inbox TTL.
- **Worker guarantees**: HMAC-verified inbox, rate limit + replay window, delete-on-download + scheduled janitor, auth-protected forget/notify endpoints.
- **PSP/webhooks**: Write AO can emit payment status events; adapter routes for webhook/status forwarding are still planned.
- **GDPR split**: No PII is stored on AO/Write/WeaveDB; sensitive blobs live only in Worker TTL cache and the administrator’s offline DB (delete-on-download + ForgetSubject hook).

## Gateway Cache Policy (encrypted envelopes)
- TTL window = min(worker inbox TTL, merchant-configured max); default 15–60 minutes.
- On expiry: wipe cache entry and emit cache_expired metric.
- Metrics: cache_hit, cache_miss, cache_expired, cache_wipe_error.
- ForgetSubject-triggered cache wipe is target-state and should be wired during deployment.

## PSP/Webhook Reliability
- Retry/backoff with jitter (e.g., 3–5 attempts, 1s→32s).
- Signature verify and cert cache (e.g., PayPal) with periodic refresh.
- Circuit breaker per PSP endpoint; metrics: breaker_open, breaker_half_open, retry_lag_seconds.
- Webhook status changes emitted to AO ingest (`PaymentStatusChanged`, `OrderStatusUpdated`).

## Observability / Alerts
- Ingest apply failures (AO and Write) — alert on error rate > 0 over 5m.
- Outbox/queue lag (write) — alert on lag > N seconds.
- PSP breaker open ratio — alert if breaker_open > threshold.
- Webhook retry backlog — alert on retry queue length/age.
- Gateway cache hit ratio — monitor; alert on miss spike if upstream healthy.
- Worker inbox janitor failures and rate-limit overage spikes (429s).
