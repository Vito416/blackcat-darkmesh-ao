import http from 'k6/http'
import crypto from 'k6/crypto'
import { check, sleep } from 'k6'

// Lite profile tuned for Cloudflare free limits
const BASE = __ENV.WORKER_BASE_URL || 'https://blackcat-inbox-production.vitek-pasek.workers.dev'
const INBOX_HMAC_SECRET = __ENV.INBOX_HMAC_SECRET || ''
const NOTIFY_HMAC_SECRET = __ENV.NOTIFY_HMAC_SECRET || ''
const WORKER_AUTH_TOKEN = __ENV.WORKER_AUTH_TOKEN || ''
const LITE = __ENV.LITE_MODE || '1' // default to lite

export const options = {
  scenarios: {
    inbox: {
      executor: 'constant-arrival-rate',
      rate: 10, // req/s
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 5,
      maxVUs: 20,
    },
    notify: {
      executor: 'constant-arrival-rate',
      rate: 5, // req/s
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 3,
      maxVUs: 10,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'], // tolerate up to 5% failures (429/502 acceptable)
  },
}

function hmac(secret, body) {
  if (!secret) return ''
  return crypto.hmac('sha256', body, secret, 'hex')
}

export function inbox() {
  const nonce = `lite-${__VU}-${Date.now()}-${Math.random()}`
  const subj = 'k6-lite'
  const payload = JSON.stringify({ subject: subj, nonce, payload: 'x' })
  const sig = hmac(INBOX_HMAC_SECRET, payload)
  const res = http.post(`${BASE}/inbox`, payload, {
    headers: { 'content-type': 'application/json', 'x-signature': sig },
  })
  check(res, { 'inbox ok/replay/ratelimit': (r) => [200, 201, 409, 429].includes(r.status) })
  sleep(0.1)
}

export function notify() {
  const body = JSON.stringify({
    webhookUrl: 'https://httpbin.org/status/200',
    data: { msg: 'lite' },
  })
  const sig = hmac(NOTIFY_HMAC_SECRET, body)
  const res = http.post(`${BASE}/notify`, body, {
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${WORKER_AUTH_TOKEN}`,
      'x-signature': sig,
      'x-lite-mode': LITE,
    },
  })
  check(res, { 'notify ok/allowed errors': (r) => [200, 202, 429, 502].includes(r.status) })
  sleep(0.2)
}
