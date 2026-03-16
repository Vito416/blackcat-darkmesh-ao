export interface Env {
  INBOX_KV: KVNamespace
  INBOX_TTL_DEFAULT?: string
  INBOX_TTL_MAX?: string
  FORGET_TOKEN?: string
  RATE_LIMIT_MAX?: string
  RATE_LIMIT_WINDOW?: string
  REPLAY_TTL?: string
  SUBJECT_MAX_ENVELOPES?: string
  PAYLOAD_MAX_BYTES?: string
  NOTIFY_RATE_MAX?: string
  NOTIFY_RATE_WINDOW?: string
  INBOX_HMAC_SECRET?: string
  NOTIFY_FROM?: string
  NOTIFY_WEBHOOK?: string
  SENDGRID_KEY?: string
}
