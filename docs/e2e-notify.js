// Simple end-to-end notify smoke: send webhook to gateway, expect worker /notify to log and return 202
import crypto from 'crypto'

const target = process.env.GATEWAY_NOTIFY_URL || 'http://gateway:8787/webhook/demo-forward'
const hmacSecret = process.env.GATEWAY_NOTIFY_HMAC || process.env.WORKER_NOTIFY_HMAC || ''
const body = JSON.stringify({ webhookUrl: 'https://example.com/webhook', data: { hello: 'world' } })
const headers = { 'Content-Type': 'application/json' }
if (hmacSecret) {
  headers['X-Signature'] = crypto.createHmac('sha256', hmacSecret).update(body).digest('hex')
}

const res = await fetch(target, { method: 'POST', body, headers })
if (!res.ok) {
  console.error('e2e notify failed', res.status)
  process.exit(1)
}
console.log('e2e notify ok', res.status)
process.exit(0)
