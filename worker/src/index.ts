import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import type { Env } from './types'
import { inc, toProm } from './metrics'
import { Buffer } from 'buffer'

type InboxItem = {
  payload: string
  exp: number
}

const encoder = new TextEncoder()

const app = new Hono<{ Bindings: Env }>()

// Simple in-memory KV shim for tests to avoid SQLite locks in Miniflare
type KvEntry = { value: string; exp?: number }
const memoryKv = new Map<string, KvEntry>()

function nowSeconds() {
  return Math.floor(Date.now() / 1000)
}

function kvFor(c: any) {
  const testFlag =
    (c.env && c.env.TEST_IN_MEMORY_KV) ||
    (typeof process !== 'undefined' && process.env && process.env.TEST_IN_MEMORY_KV)
  if (testFlag) {
    const cleanExpired = (key: string) => {
      const entry = memoryKv.get(key)
      if (entry && entry.exp && entry.exp < nowSeconds()) {
        memoryKv.delete(key)
        return null
      }
      return entry
    }
    return {
      async get(key: string) {
        return cleanExpired(key)?.value ?? null
      },
      async put(key: string, value: string, opts?: { expiration?: number; expirationTtl?: number }) {
        let exp = opts?.expiration
        if (!exp && opts?.expirationTtl) {
          exp = nowSeconds() + opts.expirationTtl
        }
        memoryKv.set(key, { value, exp })
      },
      async delete(key: string) {
        memoryKv.delete(key)
      },
      async list(params?: { prefix?: string; limit?: number }) {
        const prefix = params?.prefix || ''
        const limit = params?.limit ?? memoryKv.size
        const keys = []
        for (const key of memoryKv.keys()) {
          if (!key.startsWith(prefix)) continue
          const entry = cleanExpired(key)
          if (!entry) continue
          keys.push({ name: key })
          if (keys.length >= limit) break
        }
        return { keys }
      },
    }
  }
  return c.env.INBOX_KV
}

// Basic CORS (tighten origin in production)
app.use('*', async (c, next) => {
  c.header('Access-Control-Allow-Origin', '*')
  c.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
  c.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Signature')
  if (c.req.method === 'OPTIONS') {
    return c.text('', 204)
  }
  await next()
})

function logEvent(name: string, extra?: Record<string, any>) {
  const payload = { ts: new Date().toISOString(), event: name, ...extra }
  try {
    console.log(JSON.stringify(payload))
  } catch (_e) {
    console.log(name)
  }
}

function ttlSeconds(env: Env, reqTtl?: number) {
  const defTtl = parseInt(env.INBOX_TTL_DEFAULT || '3600', 10)
  const maxTtl = parseInt(env.INBOX_TTL_MAX || '86400', 10)
  let ttl = reqTtl || defTtl
  if (ttl < 60) ttl = 60
  if (ttl > maxTtl) ttl = maxTtl
  return ttl
}

function key(subject: string, nonce: string) {
  return `${subject}:${nonce}`
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function isSqliteBusy(err: any) {
  const msg = typeof err === 'string' ? err : err?.message || ''
  return msg.toLowerCase().includes('database is locked') || msg.toLowerCase().includes('sqlite_busy')
}

function clientIp(c: any) {
  return c.req.header('CF-Connecting-IP') || c.req.header('x-forwarded-for') || 'unknown'
}

async function rateLimit(c: any) {
  const max = parseInt(c.env.RATE_LIMIT_MAX || '50', 10)
  const windowSec = parseInt(c.env.RATE_LIMIT_WINDOW || '60', 10)
  if (max <= 0) return
  const ip = clientIp(c)
  const rk = `rl:${ip}`
  const kv = kvFor(c)
  const ttl = windowSec + 5
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const raw = await kv.get(rk)
      const now = nowSeconds()
      if (raw) {
        const { count, reset } = JSON.parse(raw) as { count: number; reset: number }
        if (reset && now < reset && count >= max) {
          inc('worker_rate_limit_blocked')
          throw new HTTPException(429, { message: 'rate_limited' })
        }
        const next = {
          count: reset && now < reset ? count + 1 : 1,
          reset: reset && now < reset ? reset : now + ttl,
        }
        await kv.put(rk, JSON.stringify(next), { expirationTtl: ttl })
      } else {
        await kv.put(rk, JSON.stringify({ count: 1, reset: now + ttl }), { expirationTtl: ttl })
      }
      return
    } catch (e) {
      if (!isSqliteBusy(e) || attempt === 2) throw e
      await sleep(5 * (attempt + 1))
    }
  }
}

async function notifyRateLimit(c: any) {
  const max = parseInt(c.env.NOTIFY_RATE_MAX || c.env.RATE_LIMIT_MAX || '50', 10)
  const windowSec = parseInt(c.env.NOTIFY_RATE_WINDOW || c.env.RATE_LIMIT_WINDOW || '60', 10)
  if (max <= 0) return
  const ip = clientIp(c)
  const rk = `rl:notify:${ip}`
  const kv = kvFor(c)
  const raw = await kv.get(rk)
  const now = nowSeconds()
  const ttl = windowSec + 5
  if (raw) {
    const { count, reset } = JSON.parse(raw) as { count: number; reset: number }
    if (reset && now < reset && count >= max) {
      inc('worker_notify_rate_blocked')
      throw new HTTPException(429, { message: 'notify_rate_limited' })
    }
    const next = {
      count: reset && now < reset ? count + 1 : 1,
      reset: reset && now < reset ? reset : now + ttl,
    }
    await kv.put(rk, JSON.stringify(next), { expirationTtl: ttl })
  } else {
    await kv.put(rk, JSON.stringify({ count: 1, reset: now + ttl }), { expirationTtl: ttl })
  }
}

function replayWindow(c: any) {
  return parseInt(c.env.REPLAY_TTL || '600', 10)
}

async function checkReplay(c: any, subj: string, nonce: string) {
  const ttl = replayWindow(c)
  if (ttl <= 0) return
  const replayKey = `replay:${subj}:${nonce}`
  const kv = kvFor(c)
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const existing = await kv.get(replayKey)
      if (existing) {
        throw new HTTPException(409, { message: 'replay' })
      }
      await kv.put(replayKey, '1', { expirationTtl: ttl })
      return
    } catch (e) {
      if (!isSqliteBusy(e) || attempt === 2) throw e
      await sleep(5 * (attempt + 1))
    }
  }
}

// simple token check for forget/notify
function requireToken(c: any) {
  const token = c.req.header('Authorization') || c.req.header('authorization') || ''
  if (c.env.FORGET_TOKEN && token !== `Bearer ${c.env.FORGET_TOKEN}`) {
    throw new HTTPException(401, { message: 'unauthorized' })
  }
}

function subjectLimit(c: any, count: number) {
  const max = parseInt(c.env.SUBJECT_MAX_ENVELOPES || '10', 10)
  if (max > 0 && count >= max) {
    throw new HTTPException(429, { message: 'subject_limit' })
  }
}

async function currentSubjectCount(c: any, subj: string) {
  const kv = kvFor(c)
  const list = await kv.list({ prefix: `${subj}:`, limit: 50 })
  return list.keys.length
}

function validatePayloadSize(c: any, payload: string) {
  const maxBytes = parseInt(c.env.PAYLOAD_MAX_BYTES || '65536', 10)
  if (maxBytes > 0 && new TextEncoder().encode(payload).length > maxBytes) {
    throw new HTTPException(413, { message: 'payload_too_large' })
  }
}

function validateEmail(email?: string) {
  if (!email) return false
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)
}

function validateUrl(url?: string) {
  if (!url) return false
  try {
    const u = new URL(url)
    return u.protocol === 'http:' || u.protocol === 'https:'
  } catch {
    return false
  }
}

function hexToBytes(hex: string): Uint8Array {
  if (!hex || hex.length % 2 !== 0) {
    throw new HTTPException(401, { message: 'invalid_signature' })
  }
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16)
  }
  return bytes
}

async function verifyInboxSignature(c: any, body: string) {
  const secret = c.env.INBOX_HMAC_SECRET
  if (!secret) return
  const sig = c.req.header('x-signature') || c.req.header('X-Signature')
  if (!sig) {
    throw new HTTPException(401, { message: 'missing_signature' })
  }
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const signatureBytes = hexToBytes(sig.trim().toLowerCase())
  const ok = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(body))
  if (!ok) {
    throw new HTTPException(401, { message: 'invalid_signature' })
  }
}

async function verifyNotifySignature(c: any, body: string) {
  const secret = c.env.NOTIFY_HMAC_SECRET
  if (!secret) {
    if (c.env.NOTIFY_HMAC_OPTIONAL === '1') return
    return
  }
  const sig = c.req.header('x-signature') || c.req.header('X-Signature')
  if (!sig) {
    if (c.env.NOTIFY_HMAC_OPTIONAL === '1') return
    throw new HTTPException(401, { message: 'missing_signature' })
  }
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const signatureBytes = hexToBytes(sig.trim().toLowerCase())
  const ok = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(body))
  if (!ok) {
    throw new HTTPException(401, { message: 'invalid_signature' })
  }
}

app.post('/inbox', async (c) => {
  const raw = await c.req.text()
  await verifyInboxSignature(c, raw)
  const body = JSON.parse(raw) as { subject: string; nonce: string; payload: string; ttlSeconds?: number }
  if (!body.subject || !body.nonce || !body.payload) {
    throw new HTTPException(400, { message: 'missing_fields' })
  }
  const kv = kvFor(c)
  await rateLimit(c)
  try {
    await checkReplay(c, body.subject, body.nonce)
  } catch (e) {
    inc('worker_inbox_replay')
    throw e
  }
  validatePayloadSize(c, body.payload)
  const subjCount = await currentSubjectCount(c, body.subject)
  subjectLimit(c, subjCount)
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds(c.env, body.ttlSeconds)
  const item: InboxItem = { payload: body.payload, exp }
  await kv.put(key(body.subject, body.nonce), JSON.stringify(item), { expiration: exp })
  logEvent('inbox_put', { subject: body.subject })
  inc('worker_inbox_put')
  return c.json({ status: 'OK', exp }, 201)
})

app.get('/inbox/:subject/:nonce', async (c) => {
  const subj = c.req.param('subject')
  const nonce = c.req.param('nonce')
  const kv = kvFor(c)
  const raw = await kv.get(key(subj, nonce))
  if (!raw) throw new HTTPException(404, { message: 'not_found' })
  const item = JSON.parse(raw) as InboxItem
  await kv.delete(key(subj, nonce))
  logEvent('inbox_get', { subject: subj })
  inc('worker_inbox_get')
  return c.json({ status: 'OK', payload: item.payload, exp: item.exp })
})

app.post('/forget', async (c) => {
  requireToken(c)
  const body = await c.req.json<{ subject: string }>()
  if (!body.subject) throw new HTTPException(400, { message: 'missing_subject' })
  const prefix = `${body.subject}:`
  const replayPrefix = `replay:${body.subject}:`
  const kv = kvFor(c)
  const list = await kv.list({ prefix })
  const replayList = await kv.list({ prefix: replayPrefix })
  const deleted = list.keys.length
  const replayDeleted = replayList.keys.length
  await Promise.all(list.keys.map((k) => kv.delete(k.name)))
  await Promise.all(replayList.keys.map((k) => kv.delete(k.name)))
  logEvent('forget', { subject: body.subject, deleted, replayDeleted })
  inc('worker_forget_deleted', deleted)
  inc('worker_forget_replay_deleted', replayDeleted)
  return c.json({ status: 'OK', deleted, replayDeleted })
})

app.get('/metrics', async (c) => {
  const needBasic = !!(c.env.METRICS_BASIC_USER && c.env.METRICS_BASIC_PASS)
  const needBearer = !!c.env.METRICS_BEARER_TOKEN
  if (needBasic || needBearer) {
    const auth = c.req.header('authorization') || ''
    const alt = c.req.header('x-metrics-token') || ''
    let ok = false
    if (needBearer && alt === c.env.METRICS_BEARER_TOKEN) ok = true
    if (!ok && needBearer && /^Bearer\s+/i.test(auth)) {
      ok = auth.replace(/^Bearer\s+/i, '').trim() === c.env.METRICS_BEARER_TOKEN
    }
    if (!ok && needBasic && /^Basic\s+/i.test(auth)) {
      const b64 = auth.replace(/^Basic\s+/i, '')
      try {
        const decoded = Buffer.from(b64, 'base64').toString()
        const [u, p] = decoded.split(':')
        if (u === c.env.METRICS_BASIC_USER && p === c.env.METRICS_BASIC_PASS) ok = true
      } catch (_) {}
    }
    if (!ok) {
      inc('worker_metrics_auth_blocked')
      throw new HTTPException(401, { message: 'unauthorized' })
    }
  }
  return c.text(toProm(), 200, { 'content-type': 'text/plain; version=0.0.4' })
})

app.post('/notify', async (c) => {
  requireToken(c)
  const raw = await c.req.text()
  await verifyNotifySignature(c, raw)
  if (c.env.NOTIFY_HMAC_OPTIONAL === '1') inc('worker_notify_hmac_optional', 1)
  const body = JSON.parse(raw || '{}') as {
    to?: string
    subject?: string
    text?: string
    html?: string
    data?: any
    webhookUrl?: string
  }
  if (!body.to && !body.webhookUrl && !c.env.NOTIFY_WEBHOOK) {
    throw new HTTPException(400, { message: 'missing_destination' })
  }
  await notifyRateLimit(c)
  if (body.to && !validateEmail(body.to)) {
    throw new HTTPException(400, { message: 'invalid_email' })
  }
  const webhook = body.webhookUrl || c.env.NOTIFY_WEBHOOK
  if (webhook && !validateUrl(webhook)) {
    throw new HTTPException(400, { message: 'invalid_webhook_url' })
  }
  const hashKey = body.to || webhook || raw
  const dedupeTtl = parseInt(c.env.NOTIFY_DEDUPE_TTL || '300', 10)
  if (dedupeTtl > 0 && hashKey) {
    const hash = await crypto.subtle.digest('SHA-256', encoder.encode(hashKey))
    const hex = Array.from(new Uint8Array(hash))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')
    const kv = kvFor(c)
    const seen = await kv.get(`notify:hash:${hex}`)
    if (seen) {
      inc('worker_notify_deduped')
      return c.json({ status: 'OK', deduped: true })
    }
    await kv.put(`notify:hash:${hex}`, '1', { expirationTtl: dedupeTtl })
  }
  const maxRetry = parseInt(c.env.NOTIFY_RETRY_MAX || '3', 10)
  const backoffMs = parseInt(c.env.NOTIFY_RETRY_BACKOFF_MS || '300', 10)
  const breakerThreshold = parseInt(c.env.NOTIFY_BREAKER_THRESHOLD || '5', 10)
  const breakerCooldown = parseInt(c.env.NOTIFY_BREAKER_COOLDOWN || '300', 10)
  const breakerKey = webhook ? 'webhook' : body.to ? 'sendgrid' : 'notify'
  const kv = kvFor(c)

  async function breakerState() {
    const rawState = await kv.get(`notify:breaker:${breakerKey}`)
    if (rawState) {
      try {
        return JSON.parse(rawState) as { count: number; openUntil?: number }
      } catch {
        return { count: 0 }
      }
    }
    return { count: 0 }
  }

  async function breakerAllows() {
    const st = await breakerState()
    const now = Math.floor(Date.now() / 1000)
    if (st.openUntil && now < st.openUntil) {
      inc('worker_notify_breaker_blocked')
      throw new HTTPException(429, { message: 'notify_breaker_open' })
    }
  }

  async function breakerNote(success: boolean) {
    const st = await breakerState()
    const now = Math.floor(Date.now() / 1000)
    if (success) {
      st.count = 0
      st.openUntil = nil
    } else {
      st.count = (st.count || 0) + 1
      if (st.count >= breakerThreshold) {
        st.openUntil = now + breakerCooldown
      }
    }
    await kv.put(`notify:breaker:${breakerKey}`, JSON.stringify(st), { expirationTtl: breakerCooldown * 2 })
    if (st.openUntil && st.openUntil > now) {
      inc('worker_notify_breaker_open')
    }
  }

  await breakerAllows()
  async function sendWithRetry(fn: () => Promise<Response>, label: string) {
    let attempt = 0
    while (attempt < Math.max(1, maxRetry)) {
      const resp = await fn()
      if (resp.ok) return resp
      attempt++
      if (attempt < maxRetry) {
        inc('worker_notify_retry')
        await sleep(backoffMs * attempt)
      } else {
        inc('worker_notify_failed')
        await breakerNote(false)
        throw new HTTPException(502, { message: `${label}_failed` })
      }
    }
    throw new HTTPException(502, { message: `${label}_failed` })
  }
  // webhook first (either body.webhookUrl or env NOTIFY_WEBHOOK)
  if (webhook) {
    const resp = await sendWithRetry(
      () =>
        fetch(webhook, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ to: body.to, subject: body.subject, text: body.text, html: body.html, data: body.data }),
        }),
      'notify_webhook'
    )
    logEvent('notify', { via: 'webhook' })
    inc('worker_notify_sent')
    await breakerNote(true)
    return c.json({ status: 'OK', delivered: 'webhook' })
  }
  // SendGrid fallback
  if (c.env.SENDGRID_KEY && body.to) {
    const resp = await sendWithRetry(
      () =>
        fetch('https://api.sendgrid.com/v3/mail/send', {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            authorization: `Bearer ${c.env.SENDGRID_KEY}`,
          },
          body: JSON.stringify({
            personalizations: [{ to: [{ email: body.to }] }],
            from: { email: 'no-reply@example.com' },
            subject: body.subject || 'Notification',
            content: [{ type: body.html ? 'text/html' : 'text/plain', value: body.html || body.text || '' }],
          }),
        }),
      'notify_sendgrid'
    )
    logEvent('notify', { via: 'sendgrid' })
    inc('worker_notify_sent')
    await breakerNote(true)
    return c.json({ status: 'OK', delivered: 'sendgrid' })
  }
  throw new HTTPException(400, { message: 'notify_unconfigured' })
})

// Cron/cleanup: bind route for Cloudflare scheduled event
export default {
  fetch: app.fetch,
  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    const now = Math.floor(Date.now() / 1000)
    const kv = env.TEST_IN_MEMORY_KV ? kvFor({ env }) : env.INBOX_KV
    const prefixes = ['', 'replay:']
    let deleted = 0
    for (const prefix of prefixes) {
      const list = await kv.list({ prefix })
      for (const k of list.keys) {
        const raw = await kv.get(k.name)
        if (!raw) continue
        try {
          const item = JSON.parse(raw) as InboxItem
          if (item.exp && item.exp < now) {
            ctx.waitUntil(kv.delete(k.name))
            deleted++
          }
        } catch (_e) {
          ctx.waitUntil(kv.delete(k.name))
          deleted++
        }
      }
    }
    if (deleted > 0) inc('worker_inbox_expired', deleted)
    logEvent('janitor', { ts: now, deleted })
  },
}
