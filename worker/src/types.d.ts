export interface Env {
  INBOX_KV: KVNamespace
  INBOX_TTL_DEFAULT?: string
  INBOX_TTL_MAX?: string
  WORKER_AUTH_TOKEN?: string
  FORGET_TOKEN?: string
  RATE_LIMIT_MAX?: string
  RATE_LIMIT_WINDOW?: string
  REPLAY_TTL?: string
  SUBJECT_MAX_ENVELOPES?: string
  PAYLOAD_MAX_BYTES?: string
  NOTIFY_RATE_MAX?: string
  NOTIFY_RATE_WINDOW?: string
  INBOX_HMAC_SECRET?: string
  NOTIFY_HMAC_SECRET?: string
  NOTIFY_HMAC_OPTIONAL?: string
  NOTIFY_FROM?: string
  NOTIFY_WEBHOOK?: string
  SENDGRID_KEY?: string
  NOTIFY_DEDUPE_TTL?: string
  NOTIFY_RETRY_MAX?: string
  NOTIFY_RETRY_BACKOFF_MS?: string
  NOTIFY_BREAKER_THRESHOLD?: string
  NOTIFY_BREAKER_COOLDOWN?: string
  METRICS_BASIC_USER?: string
  METRICS_BASIC_PASS?: string
  METRICS_BEARER_TOKEN?: string
  TEST_IN_MEMORY_KV?: number | string
  REQUIRE_SECRETS?: string
  REQUIRE_METRICS_AUTH?: string
}
