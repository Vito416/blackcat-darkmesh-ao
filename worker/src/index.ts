import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import type { Env } from './types'
import { gauge, inc, toProm } from './metrics'
import { Buffer } from 'node:buffer'
import * as ed25519 from '@noble/ed25519'
import { sha512 } from '@noble/hashes/sha512'
import { hexToBytes, normalizeHmacSignature } from './runtime/crypto/hmac'

type InboxItem = {
  payload: string
  exp: number
}

type GatewayTemplateCallInput = {
  action?: string
  payload?: Record<string, unknown>
  requestId?: string
  siteId?: string
  actor?: string
  role?: string
  tenant?: string
  timestamp?: string | number
  nonce?: string
  signature?: string
  signatureRef?: string
}

type GatewayTokenMap = Record<string, string>

const encoder = new TextEncoder()
// noble/ed25519 requires a SHA-512 implementation to be wired explicitly.
ed25519.etc.sha512Sync = (msg) => sha512(msg)

const DEFAULT_AO_HB_URL = 'https://push.forward.computer'
const DEFAULT_AO_SCHEDULER = 'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo'
const DEFAULT_AO_MODE = 'mainnet'
const DEFAULT_READ_TIMEOUT_MS = 30000
const DEFAULT_WRITE_TIMEOUT_MS = 45000
const DEFAULT_WRITE_RETRIES = 4

// Cache imported HMAC keys to avoid re-importing on every request (saves CPU on free tier)
let inboxKey: CryptoKey | null = null
let inboxSecretCached: string | null = null
let notifyKey: CryptoKey | null = null
let notifySecretCached: string | null = null

const LOG_LEVEL =
  (globalThis as any).LOG_LEVEL ||
  (typeof process !== 'undefined' && process.env?.LOG_LEVEL) ||
  'info' // info|error|debug
const LITE_MODE = (typeof process !== 'undefined' && process.env?.LITE_MODE === '1') || false

const app = new Hono<{ Bindings: Env }>()

app.onError((err, c) => {
  if (err instanceof HTTPException) {
    return err.getResponse()
  }
  const message = err instanceof Error ? err.message : String(err)
  const stack = err instanceof Error ? err.stack || '' : ''
  const causeRaw = err instanceof Error ? (err as any).cause : null
  const causeMessage =
    causeRaw instanceof Error
      ? causeRaw.message
      : typeof causeRaw === 'string'
        ? causeRaw
        : causeRaw && typeof causeRaw === 'object'
          ? JSON.stringify(causeRaw)
          : ''
  const causeStack = causeRaw instanceof Error ? causeRaw.stack || '' : ''
  logEvent('unhandled_error', { message, stack }, 'error')
  return c.json(
    {
      ok: false,
      error: 'internal_error',
      message,
      stack: stack ? stack.slice(0, 400) : '',
      cause: causeMessage || '',
      causeStack: causeStack ? causeStack.slice(0, 400) : '',
    },
    500,
  )
})

// Simple in-memory KV shim for tests to avoid SQLite locks in Miniflare
type KvEntry = { value: string; exp?: number }
const memoryKv = new Map<string, KvEntry>()

function nowSeconds() {
  return Math.floor(Date.now() / 1000)
}

function useMemoryKv(env: any) {
  const flag = env?.TEST_IN_MEMORY_KV
  if (flag === 1 || flag === '1' || flag === true) return true
  if (flag === 0 || flag === '0' || flag === false) return false
  return !!flag
}

function kvFor(c: any) {
  const testFlag =
    useMemoryKv(c.env) || (typeof process !== 'undefined' && process.env && useMemoryKv(process.env))
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
      async list(params?: { prefix?: string; limit?: number; cursor?: string }) {
        const prefix = params?.prefix || ''
        const limit = params?.limit ?? memoryKv.size
        const start = params?.cursor ? parseInt(params.cursor, 10) || 0 : 0
        const allKeys = Array.from(memoryKv.keys())
        const filtered = [] as string[]
        for (const key of allKeys) {
          if (!key.startsWith(prefix)) continue
          const entry = cleanExpired(key)
          if (!entry) continue
          filtered.push(key)
        }
        const slice = filtered.slice(start, start + limit)
        const nextCursor = start + slice.length < filtered.length ? String(start + slice.length) : undefined
        return { keys: slice.map((k) => ({ name: k })), list_complete: !nextCursor, cursor: nextCursor }
      },
    }
  }
  return c.env.INBOX_KV
}

function secretsEnforced(env: Env) {
  // Fail-closed by default unless explicitly running with the in-memory test shim
  return env.REQUIRE_SECRETS === '1' || !useMemoryKv(env)
}

function isPlaceholderSecret(val?: string) {
  if (!val) return true
  const lower = val.trim().toLowerCase()
  return ['change-me', 'changeme', 'placeholder', 'example', 'sample', 'setme'].some((p) => lower.includes(p))
}

function requireSecret(env: Env, key: keyof Env | string, message?: string) {
  if (!secretsEnforced(env)) return
  const value = (env as any)[key]
  if (!value || isPlaceholderSecret(String(value))) {
    throw new HTTPException(500, { message: message || `missing_secret:${String(key)}` })
  }
}

function ensureProdSecrets(env: Env) {
  const prodLike =
    env.CF_ENV === 'production' ||
    env.ENVIRONMENT === 'production' ||
    env.NODE_ENV === 'production' ||
    env.DEPLOY_ENV === 'production'
  if (!secretsEnforced(env)) {
    if (prodLike) {
      throw new HTTPException(500, { message: 'secrets_not_enforced_in_prod' })
    }
    return
  }
  requireSecret(env, 'INBOX_HMAC_SECRET', 'missing_secret:INBOX_HMAC_SECRET')
  if (env.NOTIFY_HMAC_OPTIONAL !== '1') {
    requireSecret(env, 'NOTIFY_HMAC_SECRET', 'missing_secret:NOTIFY_HMAC_SECRET')
  }
  if (prodLike && useMemoryKv(env)) {
    throw new HTTPException(500, { message: 'memory_kv_not_allowed_in_prod' })
  }
}

// Provide safe defaults for tests/stress when optional auth is allowed
function normalizeTestEnv(env: Env) {
  if (!env.FORGET_TOKEN && env.WORKER_AUTH_TOKEN) env.FORGET_TOKEN = env.WORKER_AUTH_TOKEN
  if (!env.WORKER_AUTH_TOKEN && env.FORGET_TOKEN) env.WORKER_AUTH_TOKEN = env.FORGET_TOKEN
  if (!env.INBOX_HMAC_SECRET && env.INBOX_HMAC_OPTIONAL === '1') {
    env.INBOX_HMAC_SECRET = 'stress-secret'
  }
  if (env.NOTIFY_HMAC_OPTIONAL === undefined) {
    // Prefer HMAC required; allow optional only when explicitly requested
    env.NOTIFY_HMAC_OPTIONAL = env.NOTIFY_HMAC_SECRET ? '0' : '0'
  }
  if (!useMemoryKv(env)) {
    if (!env.AUTH_REQUIRE_SIGNATURE) env.AUTH_REQUIRE_SIGNATURE = '1'
    if (!env.AUTH_REQUIRE_NONCE) env.AUTH_REQUIRE_NONCE = '1'
  } else {
    if (!env.AUTH_REQUIRE_SIGNATURE) env.AUTH_REQUIRE_SIGNATURE = '0'
    if (!env.AUTH_REQUIRE_NONCE) env.AUTH_REQUIRE_NONCE = '0'
  }
}

// Basic CORS (tighten origin in production)
app.use('*', async (c, next) => {
  normalizeTestEnv(c.env as any)
  ensureProdSecrets(c.env as any)
  c.header('Access-Control-Allow-Origin', '*')
  c.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
  c.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Signature')
  if (c.req.method === 'OPTIONS') {
    return c.text('', 204)
  }
  await next()
})

app.get('/health', (c) => c.json({ status: 'ok', now: new Date().toISOString() }))

type LogLevel = 'debug' | 'info' | 'error'
function logAllowed(level: LogLevel) {
  if (LOG_LEVEL === 'debug') return true
  if (LOG_LEVEL === 'info') return level !== 'debug'
  return level === 'error'
}

function logEvent(name: string, extra?: Record<string, any>, level: LogLevel = 'info') {
  if (!logAllowed(level)) return
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
          inc('worker_rate_limit_blocked_total')
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
      inc('worker_notify_rate_blocked_total')
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

// Guard against subject spray per IP: count unique subjects per window
async function subjectSprayGuard(c: any, ip: string, subject: string) {
  const max = parseInt(c.env.UNIQUE_SUBJECT_MAX_PER_IP || '20', 10)
  const windowSec = parseInt(c.env.UNIQUE_SUBJECT_WINDOW || c.env.RATE_LIMIT_WINDOW || '60', 10)
  if (max <= 0) return
  const kv = kvFor(c)
  const subjectKey = `rlsub:${ip}:${subject}`
  const counterKey = `rlsubcount:${ip}`
  const ttl = windowSec + 5
  const now = nowSeconds()
  const seen = await kv.get(subjectKey)
  if (!seen) {
    const rawCnt = await kv.get(counterKey)
    let count = 0
    if (rawCnt) {
      const parsed = JSON.parse(rawCnt) as { count: number; reset: number }
      if (parsed.reset && now < parsed.reset) {
        count = parsed.count || 0
      }
    }
    if (count >= max) {
      inc('worker_notify_subject_blocked_total')
      throw new HTTPException(429, { message: 'notify_subject_spray' })
    }
    await kv.put(subjectKey, '1', { expirationTtl: ttl })
    await kv.put(counterKey, JSON.stringify({ count: count + 1, reset: now + ttl }), { expirationTtl: ttl })
  }
}

function replayWindow(c: any) {
  const ttl = parseInt(c.env.REPLAY_TTL || '600', 10)
  if (!Number.isFinite(ttl) || ttl <= 0) {
    throw new HTTPException(500, { message: 'invalid_replay_ttl' })
  }
  return ttl
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

async function signRateLimit(c: any) {
  const max = parseInt(c.env.SIGN_RATE_LIMIT_MAX || c.env.RATE_LIMIT_MAX || '20', 10)
  const windowSec = parseInt(c.env.SIGN_RATE_LIMIT_WINDOW || c.env.RATE_LIMIT_WINDOW || '60', 10)
  if (max <= 0) return
  const ip = clientIp(c)
  const rk = `rl:sign:${ip}`
  const kv = kvFor(c)
  const ttl = windowSec + 5
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const raw = await kv.get(rk)
      const now = nowSeconds()
      if (raw) {
        const { count, reset } = JSON.parse(raw) as { count: number; reset: number }
        if (reset && now < reset && count >= max) {
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

// simple token check for forget/notify
function requireToken(c: any) {
  const tokenEnv = c.env.WORKER_AUTH_TOKEN || c.env.FORGET_TOKEN
  if (!tokenEnv) {
    requireSecret(c.env, 'WORKER_AUTH_TOKEN', 'missing_auth_token')
  }
  const token = c.req.header('Authorization') || c.req.header('authorization') || ''
  if (tokenEnv && token !== `Bearer ${tokenEnv}`) {
    throw new HTTPException(401, { message: 'unauthorized' })
  }
}

function requireSignToken(c: any) {
  const tokenEnv = c.env.WORKER_SIGN_TOKEN || c.env.WORKER_AUTH_TOKEN
  if (!tokenEnv) {
    requireSecret(c.env, 'WORKER_SIGN_TOKEN', 'missing_sign_token')
  }
  const token = c.req.header('Authorization') || c.req.header('authorization') || ''
  if (tokenEnv && token !== `Bearer ${tokenEnv}`) {
    throw new HTTPException(401, { message: 'unauthorized' })
  }
}

function subjectLimit(c: any, count: number) {
  const max = parseInt(c.env.SUBJECT_MAX_ENVELOPES || '10', 10)
  if (max > 0 && count >= max) {
    throw new HTTPException(429, { message: 'subject_limit' })
  }
}

async function notifySubjectLimit(c: any, subjectKey: string) {
  const max = parseInt(c.env.NOTIFY_SUBJECT_MAX || '20', 10)
  const windowSec = parseInt(c.env.NOTIFY_SUBJECT_WINDOW || c.env.NOTIFY_RATE_WINDOW || '60', 10)
  if (max <= 0) return
  const kv = kvFor(c)
  const rk = `notify:subj:${subjectKey}`
  const ttl = windowSec + 5
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const raw = await kv.get(rk)
      const now = nowSeconds()
      if (raw) {
        const { count, reset } = JSON.parse(raw) as { count: number; reset: number }
        if (reset && now < reset && count >= max) {
          inc('worker_notify_subject_blocked_total')
          throw new HTTPException(429, { message: 'notify_subject_limit' })
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

async function currentSubjectCount(c: any, subj: string) {
  const kv = kvFor(c)
  const list = await kv.list({ prefix: `${subj}:`, limit: 50 })
  return list.keys.length
}

function validatePayloadSize(c: any, payload: string) {
  const maxBytes = parseInt(c.env.PAYLOAD_MAX_BYTES || '16384', 10)
  if (maxBytes > 0 && new TextEncoder().encode(payload).length > maxBytes) {
    throw new HTTPException(413, { message: 'payload_too_large' })
  }
}

function webhookTimeoutMs(env: Env) {
  const val = parseInt(env.HTTP_TIMEOUT_MS || '8000', 10)
  return val > 0 ? val : 8000
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

// basic SSRF guard: host allowlist + private-range deny
function hostAllowed(u: URL, allowlistRaw?: string) {
  const host = u.hostname.toLowerCase()
  const allow = (allowlistRaw || '')
    .split(',')
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean)
  // deny obvious internal/metadata ranges by hostname
  const denyHosts = ['localhost', '127.0.0.1', '0.0.0.0', '::1', 'metadata.google.internal']
  if (denyHosts.includes(host)) return false
  const isPrivateIp =
    /^10\./.test(host) ||
    /^192\.168\./.test(host) ||
    /^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(host) ||
    /^169\.254\./.test(host) ||
    /^127\./.test(host)
  if (isPrivateIp) return false
  if (allow.length === 0) return false // fail closed: allowlist required
  if (allow.includes('*')) return true
  return allow.some((a) => host === a || host.endsWith('.' + a))
}

function trimString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function cleanEnv(value: unknown): string {
  const next = trimString(value)
  if (!next) return ''
  if (next === 'undefined' || next === 'null') return ''
  return next
}

function boolEnv(value: unknown, fallback = false): boolean {
  const normalized = cleanEnv(value).toLowerCase()
  if (!normalized) return fallback
  return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on'
}

function positiveIntEnv(value: unknown, fallback: number): number {
  const parsed = Number.parseInt(cleanEnv(value), 10)
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback
  return parsed
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  return value as Record<string, unknown>
}

function normalizePath(pathValue: unknown): string {
  const path = trimString(pathValue)
  if (!path) return '/'
  return path.startsWith('/') ? path : `/${path}`
}

function firstNonEmptyString(...values: unknown[]): string {
  for (const value of values) {
    const next = trimString(value)
    if (next) return next
  }
  return ''
}

function randomId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`
}

function parseTokenMap(raw: string): GatewayTokenMap | null {
  try {
    const parsed = JSON.parse(raw)
    const record = asRecord(parsed)
    if (!record) return null
    const map: GatewayTokenMap = {}
    for (const [k, v] of Object.entries(record)) {
      const key = trimString(k)
      const token = trimString(v)
      if (!key || !token) return null
      map[key] = token
    }
    return map
  } catch {
    return null
  }
}

function expectedTemplateToken(env: Env, siteId: string): string {
  const mapRaw = cleanEnv(env.GATEWAY_TEMPLATE_TOKEN_MAP)
  if (mapRaw) {
    const parsed = parseTokenMap(mapRaw)
    if (!parsed) {
      throw new HTTPException(500, { message: 'invalid_template_token_map' })
    }
    if (siteId && parsed[siteId]) return parsed[siteId]
  }
  return cleanEnv(env.GATEWAY_TEMPLATE_TOKEN)
}

function requireTemplateApiToken(c: any, siteId: string) {
  const optional = boolEnv(c.env.GATEWAY_TEMPLATE_TOKEN_OPTIONAL, false)
  const expected = expectedTemplateToken(c.env, siteId)
  if (!expected) {
    if (optional) return
    throw new HTTPException(500, { message: 'missing_template_token' })
  }
  const auth = cleanEnv(c.req.header('authorization'))
  const bearer = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : ''
  const presented = firstNonEmptyString(
    c.req.header('x-template-token'),
    c.req.header('x-api-token'),
    bearer,
  )
  if (!presented || presented !== expected) {
    throw new HTTPException(401, { message: 'unauthorized' })
  }
}

let aoReadCache: { key: string; client: any } | null = null
let aoConnectModulePromise: Promise<any> | null = null
let arbundlesModulePromise: Promise<any> | null = null

async function loadAoConnect() {
  if (!aoConnectModulePromise) {
    const g = globalThis as any
    if (!g.process) g.process = { env: {} }
    if (!g.process.env) g.process.env = {}
    if (!g.Buffer) g.Buffer = Buffer
    aoConnectModulePromise = import('@permaweb/aoconnect')
  }
  return aoConnectModulePromise
}

async function loadArbundles() {
  if (!arbundlesModulePromise) {
    arbundlesModulePromise = import('@dha-team/arbundles')
  }
  return arbundlesModulePromise
}

function hbUrlFromEnv(env: Env): string {
  return cleanEnv(env.AO_HB_URL) || DEFAULT_AO_HB_URL
}

function schedulerFromEnv(env: Env): string {
  return cleanEnv(env.AO_HB_SCHEDULER) || DEFAULT_AO_SCHEDULER
}

function aoModeFromEnv(env: Env): string {
  return cleanEnv(env.AO_MODE) || DEFAULT_AO_MODE
}

function resolveSitePid(env: Env): string {
  return cleanEnv(env.AO_SITE_PROCESS_ID)
}

function resolveWritePid(env: Env): string {
  return cleanEnv(env.WRITE_PROCESS_ID)
}

function base64UrlToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  return new Uint8Array(Buffer.from(padded, 'base64'))
}

function bytesToBase64Url(input: ArrayBuffer | Uint8Array): string {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input)
  return Buffer.from(bytes)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')
}

function normalizeSignatureInput(value: unknown): Uint8Array {
  if (value instanceof Uint8Array) return value
  if (value instanceof ArrayBuffer) return new Uint8Array(value)
  throw new HTTPException(500, { message: 'invalid_signer_input' })
}

function walletShape(env: Env) {
  const raw = cleanEnv(env.AO_WALLET_JSON)
  if (!raw) return { present: false }
  try {
    const parsed = JSON.parse(raw)
    const record = asRecord(parsed)
    if (!record) {
      return { present: true, parsed: typeof parsed }
    }
    return {
      present: true,
      parsed: 'object',
      keyCount: Object.keys(record).length,
      kty: trimString(record.kty),
      hasConnectFunction: typeof (record as any).connect === 'function',
      hasN: typeof record.n === 'string' && record.n.length > 0,
    }
  } catch {
    return { present: true, parsed: 'invalid_json' }
  }
}

type Ans104Passthrough = {
  data?: unknown
  tags?: Array<{ name: string; value: string }>
  target?: string
  anchor?: string
}

async function buildAns104DataItem(
  publicKeyBytes: Uint8Array,
  passthrough: Ans104Passthrough,
  signFn: (signatureData: Uint8Array) => Promise<Uint8Array>,
): Promise<{ id: string; raw: Uint8Array }> {
  const module = await loadArbundles()
  const root = (module as any).default || module
  const createData = root.createData || module.createData
  const sigConfig = root.SIG_CONFIG || module.SIG_CONFIG
  if (typeof createData !== 'function' || !sigConfig || !sigConfig[1]) {
    throw new Error('arbundles_ans104_missing')
  }

  const signerMeta = { ...sigConfig[1] }
  signerMeta.signatureType = 1
  signerMeta.ownerLength = signerMeta.pubLength
  signerMeta.signatureLength = signerMeta.sigLength
  signerMeta.publicKey = Buffer.from(publicKeyBytes)

  const item = createData(passthrough.data ?? '', signerMeta, {
    target: passthrough.target ?? '',
    tags: passthrough.tags ?? [],
    anchor: passthrough.anchor ?? '',
  })
  const signatureDataRaw = await item.getSignatureData()
  const signatureData =
    signatureDataRaw instanceof Uint8Array
      ? signatureDataRaw
      : signatureDataRaw instanceof ArrayBuffer
        ? new Uint8Array(signatureDataRaw)
        : new Uint8Array(signatureDataRaw.buffer, signatureDataRaw.byteOffset, signatureDataRaw.byteLength)

  const signature = await signFn(signatureData)
  const raw = item.getRaw()
  raw.set(signature, 2)
  const idDigest = await crypto.subtle.digest('SHA-256', signature)
  return {
    id: base64UrlNoPad(idDigest),
    raw,
  }
}

async function createWebWalletSigner(wallet: Record<string, unknown>) {
  const modulus = trimString(wallet.n)
  if (!modulus) {
    throw new HTTPException(500, { message: 'invalid_ao_wallet_json_missing_n' })
  }
  const publicKeyBytes = base64UrlToBytes(modulus)
  const addressDigest = await crypto.subtle.digest('SHA-256', publicKeyBytes)
  const address = bytesToBase64Url(addressDigest)
  const baseJwk = {
    ...(wallet as unknown as JsonWebKey),
    key_ops: ['sign'],
    ext: true,
  } as JsonWebKey
  let ansKey: CryptoKey | null = null
  let httpsigKey: CryptoKey | null = null

  const getKey = async (hashName: 'SHA-256' | 'SHA-512') => {
    if (hashName === 'SHA-256' && ansKey) return ansKey
    if (hashName === 'SHA-512' && httpsigKey) return httpsigKey
    const jwk =
      hashName === 'SHA-256'
        ? ({ ...baseJwk, alg: 'PS256' } as JsonWebKey)
        : ({ ...baseJwk, alg: 'PS512' } as JsonWebKey)
    let key: CryptoKey
    try {
      key = await crypto.subtle.importKey(
        'jwk',
        jwk,
        { name: 'RSA-PSS', hash: { name: hashName } },
        false,
        ['sign'],
      )
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      throw new Error(`jwk_import_failed:${hashName}:${message}`)
    }
    if (hashName === 'SHA-256') ansKey = key
    else httpsigKey = key
    return key
  }

  return async (getSignatureData: any, signerKind: string) => {
    if (typeof getSignatureData !== 'function') {
      throw new Error('invalid_signer_callback')
    }
    if (signerKind !== 'ans104' && signerKind !== 'httpsig') {
      throw new Error(`unsupported_signer_kind:${signerKind}`)
    }
    if (signerKind === 'ans104') {
      const passthrough = (await getSignatureData({
        type: 1,
        publicKey: publicKeyBytes,
        alg: 'rsa-v1_5-sha256',
        address,
        passthrough: true,
      })) as Ans104Passthrough
      if (passthrough && typeof passthrough === 'object') {
        return buildAns104DataItem(publicKeyBytes, passthrough, async (signatureData) => {
          const key = await getKey('SHA-256')
          const signature = await crypto.subtle.sign(
            { name: 'RSA-PSS', saltLength: 32 },
            key,
            signatureData,
          )
          return new Uint8Array(signature)
        })
      }
      throw new Error('ans104_passthrough_missing')
    }

    const signatureInput = normalizeSignatureInput(
      await getSignatureData({ type: 1, publicKey: publicKeyBytes, alg: 'rsa-pss-sha512', address }),
    )
    const key = await getKey('SHA-512')
    const signature = await crypto.subtle.sign({ name: 'RSA-PSS', saltLength: 64 }, key, signatureInput)
    return { signature: new Uint8Array(signature), address }
  }
}

async function createPkcs8WalletSigner(wallet: Record<string, unknown>, pkcs8Base64: string) {
  const modulus = trimString(wallet.n)
  if (!modulus) {
    throw new HTTPException(500, { message: 'invalid_ao_wallet_json_missing_n' })
  }
  const pkcs8 = trimString(pkcs8Base64)
  if (!pkcs8) {
    throw new HTTPException(500, { message: 'invalid_ao_wallet_pkcs8' })
  }
  const publicKeyBytes = base64UrlToBytes(modulus)
  const addressDigest = await crypto.subtle.digest('SHA-256', publicKeyBytes)
  const address = bytesToBase64Url(addressDigest)
  const pkcs8Bytes = new Uint8Array(Buffer.from(pkcs8, 'base64'))
  const pkcs8Buffer = pkcs8Bytes.buffer.slice(
    pkcs8Bytes.byteOffset,
    pkcs8Bytes.byteOffset + pkcs8Bytes.byteLength,
  )
  let ansKey: CryptoKey | null = null
  let httpsigKey: CryptoKey | null = null

  const getKey = async (hashName: 'SHA-256' | 'SHA-512') => {
    if (hashName === 'SHA-256' && ansKey) return ansKey
    if (hashName === 'SHA-512' && httpsigKey) return httpsigKey
    let key: CryptoKey
    try {
      key = await crypto.subtle.importKey(
        'pkcs8',
        pkcs8Buffer,
        { name: 'RSA-PSS', hash: { name: hashName } },
        false,
        ['sign'],
      )
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      throw new Error(`pkcs8_import_failed:${hashName}:${message}`)
    }
    if (hashName === 'SHA-256') ansKey = key
    else httpsigKey = key
    return key
  }

  return async (getSignatureData: any, signerKind: string) => {
    if (typeof getSignatureData !== 'function') {
      throw new Error('invalid_signer_callback')
    }
    if (signerKind !== 'ans104' && signerKind !== 'httpsig') {
      throw new Error(`unsupported_signer_kind:${signerKind}`)
    }
    if (signerKind === 'ans104') {
      const passthrough = (await getSignatureData({
        type: 1,
        publicKey: publicKeyBytes,
        alg: 'rsa-v1_5-sha256',
        address,
        passthrough: true,
      })) as Ans104Passthrough
      if (passthrough && typeof passthrough === 'object') {
        return buildAns104DataItem(publicKeyBytes, passthrough, async (signatureData) => {
          const key = await getKey('SHA-256')
          const signature = await crypto.subtle.sign(
            { name: 'RSA-PSS', saltLength: 32 },
            key,
            signatureData,
          )
          return new Uint8Array(signature)
        })
      }
      throw new Error('ans104_passthrough_missing')
    }

    const signatureInput = normalizeSignatureInput(
      await getSignatureData({ type: 1, publicKey: publicKeyBytes, alg: 'rsa-pss-sha512', address }),
    )
    const key = await getKey('SHA-512')
    const signature = await crypto.subtle.sign({ name: 'RSA-PSS', saltLength: 64 }, key, signatureInput)
    return { signature: new Uint8Array(signature), address }
  }
}

async function readGatewaySigner(env: Env) {
  const raw = cleanEnv(env.AO_WALLET_JSON)
  if (!raw) throw new HTTPException(500, { message: 'missing_ao_wallet_json' })
  const pkcs8 = cleanEnv((env as any).AO_WALLET_PKCS8_B64)
  let wallet: unknown
  try {
    wallet = JSON.parse(raw)
  } catch {
    throw new HTTPException(500, { message: 'invalid_ao_wallet_json' })
  }
  let signer: any = null
  const record = asRecord(wallet)
  if (record && pkcs8) {
    try {
      signer = await createPkcs8WalletSigner(record, pkcs8)
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      throw new HTTPException(500, { message: `pkcs8_signer_init_failed:${message}` })
    }
  }
  if (!signer && record) {
    try {
      signer = await createWebWalletSigner(record)
    } catch {
      signer = null
    }
  }
  if (typeof signer !== 'function') {
    const module = await loadAoConnect()
    const root = (module as any).default || module
    const createSigner = root.createSigner
    const createDataItemSigner = root.createDataItemSigner
    if (typeof createDataItemSigner === 'function') {
      signer = createDataItemSigner(wallet as any)
    } else if (typeof createSigner === 'function') {
      signer = createSigner(wallet as any)
    }
  }
  if (typeof signer !== 'function') {
    throw new HTTPException(500, { message: 'aoconnect_create_signer_missing' })
  }
  return signer
}

async function readAoClient(env: Env) {
  const key = `${aoModeFromEnv(env)}|${hbUrlFromEnv(env)}|${schedulerFromEnv(env)}`
  if (aoReadCache && aoReadCache.key === key) return aoReadCache.client
  const module = await loadAoConnect()
  const root = (module as any).default || module
  const connect = root.connect
  if (typeof connect !== 'function') {
    throw new HTTPException(500, { message: 'aoconnect_connect_missing' })
  }
  const client = connect({
    MODE: aoModeFromEnv(env),
    URL: hbUrlFromEnv(env),
    SCHEDULER: schedulerFromEnv(env),
  })
  aoReadCache = { key, client }
  return client
}

async function writeAoClient(env: Env) {
  const module = await loadAoConnect()
  const root = (module as any).default || module
  const connect = root.connect
  if (typeof connect !== 'function') {
    throw new HTTPException(500, { message: 'aoconnect_connect_missing' })
  }
  const signer = await readGatewaySigner(env)
  const client = connect({
    MODE: aoModeFromEnv(env),
    URL: hbUrlFromEnv(env),
    SCHEDULER: schedulerFromEnv(env),
    signer,
  })
  return client
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  const clamped = Math.max(1000, timeoutMs)
  return Promise.race([
    promise,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout_${label}_${clamped}ms`)), clamped)),
  ])
}

function stableStringify(value: any): string {
  if (value === null || value === undefined) return 'null'
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
  if (typeof value === 'object') {
    const keys = Object.keys(value).sort()
    return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

function canonicalDetachedMessage(cmd: any): string {
  const parts = [
    cmd.action || cmd.Action || '',
    cmd.tenant || cmd.Tenant || '',
    cmd.actor || cmd.Actor || '',
    cmd.timestamp || cmd.ts || '',
    cmd.nonce || cmd.Nonce || '',
    cmd.role || cmd.Role || cmd['Actor-Role'] || '',
    stableStringify(cmd.payload || cmd.Payload || {}),
    cmd.requestId || cmd['Request-Id'] || ''
  ]
  return parts.join('|')
}

async function signCommand(env: Env, cmd: any) {
  const privHex = env.WORKER_ED25519_PRIV_HEX
  requireSecret(env, 'WORKER_ED25519_PRIV_HEX', 'missing_secret:WORKER_ED25519_PRIV_HEX')
  if (!privHex) throw new HTTPException(500, { message: 'missing_secret:WORKER_ED25519_PRIV_HEX' })
  const message = canonicalDetachedMessage(cmd)
  const sig = await ed25519.sign(Buffer.from(message), hexToBytes(privHex))
  return Buffer.from(sig).toString('hex')
}

function buildReadTags(
  action: string,
  requestId: string,
  siteId: string,
  sitePid: string,
  payload: Record<string, unknown>,
) {
  const tags = [
    { name: 'Action', value: action },
    { name: 'Request-Id', value: requestId },
    { name: 'Site-Id', value: siteId },
    { name: 'Reply-To', value: sitePid },
    { name: 'signing-format', value: 'ans104' },
    { name: 'accept-bundle', value: 'true' },
    { name: 'require-codec', value: 'application/json' },
    { name: 'Type', value: 'Message' },
    { name: 'Variant', value: 'ao.TN.1' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Content-Type', value: 'application/json' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
  ] as Array<{ name: string; value: string }>

  if (action === 'ResolveRoute') {
    const routePath = normalizePath(payload.path)
    tags.push({ name: 'Path', value: routePath })
    const locale = trimString(payload.locale)
    if (locale) tags.push({ name: 'Locale', value: locale })
  } else if (action === 'GetPage') {
    const pageId = trimString(payload.pageId)
    const slug = firstNonEmptyString(payload.slug, payload.path)
    if (pageId) tags.push({ name: 'Page-Id', value: pageId })
    if (slug) tags.push({ name: 'Slug', value: slug })
    const locale = trimString(payload.locale)
    const version = trimString(payload.version)
    if (locale) tags.push({ name: 'Locale', value: locale })
    if (version) tags.push({ name: 'Version', value: version })
  }

  return tags
}

function buildReadData(action: string, requestId: string, siteId: string, payload: Record<string, unknown>): string {
  const body: Record<string, unknown> = {
    Action: action,
    'Request-Id': requestId,
    'Site-Id': siteId,
  }
  if (action === 'ResolveRoute') {
    body.Path = normalizePath(payload.path)
    const locale = trimString(payload.locale)
    if (locale) body.Locale = locale
  } else if (action === 'GetPage') {
    const pageId = trimString(payload.pageId)
    const slug = firstNonEmptyString(payload.slug, payload.path)
    if (pageId) body['Page-Id'] = pageId
    if (slug) body.Slug = slug
    const locale = trimString(payload.locale)
    const version = trimString(payload.version)
    if (locale) body.Locale = locale
    if (version) body.Version = version
  }
  return JSON.stringify(body)
}

function normalizeReadEnvelope(raw: any, action: string): { status: number; body: Record<string, unknown> } {
  const normalized = raw?.results?.raw || raw?.raw || raw || {}
  const outputCandidate =
    normalized?.Output ??
    normalized?.output ??
    normalized?.Data ??
    normalized?.data ??
    raw?.Output ??
    raw?.output ??
    null

  let envelope: any = null
  if (typeof outputCandidate === 'string') {
    if (outputCandidate.trim()) {
      try {
        envelope = JSON.parse(outputCandidate)
      } catch {
        envelope = { status: 'ERROR', code: 'INVALID_OUTPUT', message: outputCandidate }
      }
    }
  } else if (outputCandidate && typeof outputCandidate === 'object') {
    envelope = outputCandidate
  } else if (normalized && typeof normalized === 'object' && typeof normalized.status === 'string') {
    envelope = normalized
  }

  if (!envelope) {
    const maybeError = normalized?.Error
    const hasRuntimeError = maybeError && typeof maybeError === 'object' && Object.keys(maybeError).length > 0
    if (!hasRuntimeError && (action === 'ResolveRoute' || action === 'GetPage')) {
      return {
        status: 404,
        body: {
          status: 'ERROR',
          code: 'NOT_FOUND',
          message: 'not_found_or_empty_result',
        },
      }
    }
    return {
      status: 502,
      body: {
        ok: false,
        error: 'invalid_ao_response',
      },
    }
  }

  if (String(envelope.status || '').toUpperCase() === 'OK') {
    return { status: 200, body: envelope }
  }

  const code = trimString(envelope.code).toUpperCase()
  const status =
    code === 'NOT_FOUND'
      ? 404
      : code === 'INVALID_INPUT' || code === 'UNSUPPORTED_FIELD' || code === 'MISSING_TAGS'
        ? 400
        : code === 'FORBIDDEN'
          ? 403
          : code === 'UNAUTHORIZED'
            ? 401
            : 422
  return { status, body: envelope }
}

async function executeReadAction(c: any, action: 'ResolveRoute' | 'GetPage', input: GatewayTemplateCallInput) {
  const sitePid = resolveSitePid(c.env)
  if (!sitePid) throw new HTTPException(500, { message: 'missing_ao_site_process_id' })

  const payload = asRecord(input.payload) || asRecord(input) || {}
  const siteId = firstNonEmptyString(input.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  if (!siteId) throw new HTTPException(400, { message: 'site_id_required' })
  const requestId = firstNonEmptyString(
    input.requestId,
    c.req.header('x-request-id'),
    randomId('gw-read'),
  )
  const tags = buildReadTags(action, requestId, siteId, sitePid, payload)
  const data = buildReadData(action, requestId, siteId, payload)
  const timeoutMs = positiveIntEnv(c.env.GATEWAY_READ_TIMEOUT_MS, DEFAULT_READ_TIMEOUT_MS)
  const ao = await writeAoClient(c.env)
  const slotOrMessage = await withTimeout(
    ao.message({
      process: sitePid,
      tags,
      data,
    }),
    timeoutMs,
    'ao_read_message',
  )
  let result: any = null
  try {
    result = await withTimeout(
      ao.result({
        process: sitePid,
        message: String(slotOrMessage),
      }),
      timeoutMs,
      'ao_read_result',
    )
  } catch {
    result = await fetchComputeFallback(c.env, sitePid, String(slotOrMessage), timeoutMs)
  }
  return normalizeReadEnvelope(result, action)
}

function buildWritePayload(input: GatewayTemplateCallInput): Record<string, unknown> {
  const payload = asRecord(input.payload) || {}
  return { ...payload }
}

function expectedWriteAction(pathname: string): 'CreateOrder' | 'CreatePaymentIntent' {
  if (pathname.endsWith('/api/checkout/order')) return 'CreateOrder'
  return 'CreatePaymentIntent'
}

function validateWriteRouteAction(bodyAction: unknown, expected: string): void {
  const normalized = trimString(bodyAction)
  if (!normalized) return
  if (normalized === expected) return
  if (normalized === 'checkout.create-order' && expected === 'CreateOrder') return
  if (normalized === 'checkout.create-payment-intent' && expected === 'CreatePaymentIntent') return
  throw new HTTPException(400, { message: 'action_route_mismatch' })
}

function buildWriteCommand(c: any, input: GatewayTemplateCallInput, expected: string) {
  validateWriteRouteAction(input.action, expected)
  const payload = buildWritePayload(input)
  const siteId = firstNonEmptyString(input.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  if (siteId && !payload.siteId) payload.siteId = siteId

  const requestId = firstNonEmptyString(input.requestId, c.req.header('x-request-id'), randomId('gw-write'))
  const actor = firstNonEmptyString(input.actor, 'gateway-template')
  const role = firstNonEmptyString(input.role, 'admin')
  const tenant = firstNonEmptyString(input.tenant, payload.siteId)
  if (!tenant) throw new HTTPException(400, { message: 'tenant_required' })

  const command: Record<string, unknown> = {
    action: expected,
    requestId,
    actor,
    role,
    tenant,
    timestamp: firstNonEmptyString(input.timestamp, new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')),
    nonce: firstNonEmptyString(input.nonce, randomId('nonce')),
    payload,
  }

  const signature = trimString(input.signature)
  const signatureRef = trimString(input.signatureRef)
  if (signature) command.signature = signature
  if (signatureRef) command.signatureRef = signatureRef

  return command
}

async function maybeSignWriteCommand(env: Env, command: Record<string, unknown>) {
  if (trimString(command.signature) && trimString(command.signatureRef)) return command
  const autoSign = boolEnv(env.GATEWAY_WRITE_AUTO_SIGN, true)
  if (!autoSign) throw new HTTPException(401, { message: 'signature_required' })
  const signature = await signCommand(env, command)
  return {
    ...command,
    signature,
    signatureRef: cleanEnv(env.WORKER_SIGNATURE_REF) || 'worker-ed25519',
  }
}

function writeMessageTags() {
  return [
    { name: 'Action', value: 'Write-Command' },
    { name: 'Variant', value: 'ao.TN.1' },
    { name: 'Content-Type', value: 'application/json' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Type', value: 'Message' },
  ]
}

function base64UrlNoPad(input: ArrayBuffer | Uint8Array): string {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input)
  return Buffer.from(bytes)
    .toString('base64url')
    .replace(/=+$/g, '')
}

async function fetchComputeFallback(env: Env, pid: string, slotOrMessage: string, timeoutMs: number) {
  const endpoint =
    `${hbUrlFromEnv(env).replace(/\/$/, '')}/${pid}~process@1.0/compute=${slotOrMessage}` +
    '?accept-bundle=true&require-codec=application/json'
  const response = await withTimeout(fetch(endpoint, { method: 'GET' }), timeoutMs, 'compute_fetch')
  const text = await response.text().catch(() => '')
  if (!response.ok) {
    throw new Error(`compute_http_${response.status}:${text.slice(0, 180)}`)
  }
  try {
    return text ? JSON.parse(text) : {}
  } catch {
    throw new Error('compute_invalid_json')
  }
}

function extractSlotOrMessage(value: unknown, depth = 0): string | undefined {
  if (depth > 4 || value === null || value === undefined) return undefined
  if (typeof value === 'string') {
    const direct = trimString(value)
    if (!direct) return undefined
    try {
      const parsed = JSON.parse(direct)
      return extractSlotOrMessage(parsed, depth + 1) || direct
    } catch {
      return /^[A-Za-z0-9_-]{20,}$/.test(direct) ? direct : undefined
    }
  }
  const record = asRecord(value)
  if (!record) return undefined
  const numericDirect = [record.slot, record.Slot, record.message, record.Message, record.id, record.Id]
    .map((v) => (typeof v === 'number' && Number.isFinite(v) ? String(v) : ''))
    .find((v) => !!v)
  if (numericDirect) return numericDirect
  const direct = firstNonEmptyString(
    record.slot,
    record.Slot,
    record.message,
    record.Message,
    record.id,
    record.Id,
    record.cursor,
    record.Cursor,
  )
  if (direct) return direct

  const nestedKeys = ['raw', 'data', 'body', 'result', 'results', 'output', 'node', 'value']
  for (const key of nestedKeys) {
    const nested = extractSlotOrMessage(record[key], depth + 1)
    if (nested) return nested
  }
  return undefined
}

async function sendWriteCommand(c: any, command: Record<string, unknown>) {
  const pid = resolveWritePid(c.env)
  if (!pid) throw new HTTPException(500, { message: 'missing_write_process_id' })
  const timeoutMs = positiveIntEnv(c.env.GATEWAY_WRITE_TIMEOUT_MS, DEFAULT_WRITE_TIMEOUT_MS)
  const retries = positiveIntEnv(c.env.GATEWAY_WRITE_RETRIES, DEFAULT_WRITE_RETRIES)
  const ao = await writeAoClient(c.env)

  let lastError: Error | null = null
  for (let attempt = 0; attempt < retries; attempt += 1) {
    try {
      const pushResponse = await withTimeout(
        ao.request({
          path: `/${pid}~process@1.0/push`,
          target: pid,
          tags: writeMessageTags(),
          data: JSON.stringify(command),
          method: 'POST',
          'signing-format': 'ans104',
          'accept-bundle': 'true',
          'require-codec': 'application/json',
        }),
        timeoutMs,
        'ao_push_request',
      )
      const pushText = await pushResponse.text().catch(() => '')
      if (!pushResponse.ok) {
        throw new Error(`ao_push_http_${pushResponse.status}:${pushText.slice(0, 320)}`)
      }
      let pushJson: any = {}
      try {
        pushJson = pushText ? JSON.parse(pushText) : {}
      } catch {
        throw new Error('ao_push_invalid_json')
      }
      const slotOrMessage = firstNonEmptyString(
        extractSlotOrMessage(pushJson),
        extractSlotOrMessage(pushJson?.body),
        extractSlotOrMessage(pushJson?.raw),
        extractSlotOrMessage(pushJson?.data),
      )
      if (!slotOrMessage) {
        throw new Error(`ao_push_missing_slot:${pushText.slice(0, 1200)}`)
      }

      let raw: any = null
      try {
        raw = await withTimeout(ao.result({ process: pid, message: slotOrMessage }), timeoutMs, 'ao_result')
      } catch {
        raw = await fetchComputeFallback(c.env, pid, slotOrMessage, timeoutMs)
      }
      return { raw, slotOrMessage }
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error))
      if (attempt + 1 >= retries) break
      await sleep(500 * (attempt + 1))
    }
  }

  throw lastError || new Error('write_command_failed')
}

function normalizeWriteEnvelope(env: Env, rawResult: any, context: { requestId?: string; action?: string }) {
  const normalized = rawResult?.results?.raw || rawResult?.raw || rawResult || {}
  const output = normalized?.Output ?? normalized?.output ?? null
  let envelope: any = null
  if (typeof output === 'string') {
    if (output.trim()) {
      try {
        envelope = JSON.parse(output)
      } catch {
        envelope = { status: 'ERROR', code: 'INVALID_OUTPUT', message: output }
      }
    }
  } else if (output && typeof output === 'object') {
    envelope = output
  } else if (normalized && typeof normalized === 'object' && typeof normalized.status === 'string') {
    envelope = normalized
  }

  if (!envelope) {
    const maybeError = normalized?.Error
    const hasRuntimeError = maybeError && typeof maybeError === 'object' && Object.keys(maybeError).length > 0
    const acceptEmpty = boolEnv(env.GATEWAY_WRITE_ACCEPT_EMPTY_RESULT, true)
    if (!hasRuntimeError && acceptEmpty) {
      return {
        status: 202,
        body: {
          status: 'OK',
          code: 'ACCEPTED_ASYNC',
          message: 'command accepted; result envelope unavailable',
          requestId: context.requestId || null,
          action: context.action || null,
        },
      }
    }
    return {
      status: 502,
      body: {
        ok: false,
        error: 'invalid_write_response',
      },
    }
  }

  const statusText = trimString(envelope.status).toUpperCase()
  if (statusText === 'OK') {
    return { status: 200, body: envelope }
  }

  const code = trimString(envelope.code).toUpperCase()
  const status =
    code === 'INVALID_INPUT' || code === 'PAYLOAD_TOO_LARGE'
      ? 400
      : code === 'UNAUTHORIZED'
        ? 401
        : code === 'FORBIDDEN'
          ? 403
          : code === 'NOT_FOUND'
            ? 404
            : code === 'CONFLICT'
              ? 409
              : code === 'RATE_LIMITED'
                ? 429
                : 422
  return { status, body: envelope }
}

async function verifyInboxSignature(c: any, body: string) {
  const secret = c.env.INBOX_HMAC_SECRET
  const optional = c.env.INBOX_HMAC_OPTIONAL === '1'
  requireSecret(c.env, 'INBOX_HMAC_SECRET', 'missing_inbox_hmac_secret')
  if (!secret) return
  const sig = c.req.header('x-signature') || c.req.header('X-Signature')
  if (!sig) {
    if (optional) return
    throw new HTTPException(401, { message: 'missing_signature' })
  }
  try {
    if (!inboxKey || secret !== inboxSecretCached) {
      inboxKey = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
      inboxSecretCached = secret
    }
    const signatureBytes = hexToBytes(normalizeHmacSignature(sig))
    const ok = await crypto.subtle.verify('HMAC', inboxKey, signatureBytes, encoder.encode(body))
    if (!ok) {
      throw new HTTPException(401, { message: 'invalid_signature' })
    }
  } catch (_e) {
    throw new HTTPException(401, { message: 'invalid_signature' })
  }
}

async function verifyNotifySignature(c: any, body: string) {
  const secret = c.env.NOTIFY_HMAC_SECRET
  const optional = c.env.NOTIFY_HMAC_OPTIONAL === '1'
  requireSecret(c.env, 'NOTIFY_HMAC_SECRET', 'missing_notify_hmac_secret')
  if (!secret) {
    if (optional) return
    return
  }
  const sig = c.req.header('x-signature') || c.req.header('X-Signature')
  if (!sig) {
    if (optional) return
    inc('worker_notify_hmac_invalid_total')
    throw new HTTPException(401, { message: 'missing_signature' })
  }
  try {
    if (!notifyKey || secret !== notifySecretCached) {
      notifyKey = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
      notifySecretCached = secret
    }
    const signatureBytes = hexToBytes(normalizeHmacSignature(sig))
    const ok = await crypto.subtle.verify('HMAC', notifyKey, signatureBytes, encoder.encode(body))
    if (!ok) {
      inc('worker_notify_hmac_invalid_total')
      throw new HTTPException(401, { message: 'invalid_signature' })
    }
  } catch (_e) {
    inc('worker_notify_hmac_invalid_total')
    throw new HTTPException(401, { message: 'invalid_signature' })
  }
}

app.post('/inbox', async (c) => {
  const raw = await c.req.text()
  await verifyInboxSignature(c, raw)
  const body = JSON.parse(raw || '{}') as { subject: string; nonce: string; payload: string; ttlSeconds?: number }
  if (!body.subject || !body.nonce || !body.payload) {
    throw new HTTPException(400, { message: 'missing_fields' })
  }
  const kv = kvFor(c)
  await rateLimit(c)
  await subjectSprayGuard(c, clientIp(c), body.subject)
  try {
    await checkReplay(c, body.subject, body.nonce)
  } catch (e) {
    inc('worker_inbox_replay_total')
    throw e
  }
  validatePayloadSize(c, body.payload)
  const subjCount = await currentSubjectCount(c, body.subject)
  subjectLimit(c, subjCount)
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds(c.env, body.ttlSeconds)
  const item: InboxItem = { payload: body.payload, exp }
  await kv.put(key(body.subject, body.nonce), JSON.stringify(item), { expiration: exp })
  logEvent('inbox_put', { subject: body.subject })
  inc('worker_inbox_put_total')
  return c.json({ status: 'OK', exp }, 201)
})

// Sign a write command using the worker's Ed25519 key (for AO verification).
// Requires Authorization token and WORKER_ED25519_PRIV_HEX secret set.
app.post('/sign', async (c) => {
  requireSignToken(c)
  await signRateLimit(c)
  const body = await c.req.json<any>()
  if (!body || typeof body !== 'object') {
    throw new HTTPException(400, { message: 'invalid_body' })
  }
  const allowedKeys = new Set([
    'action',
    'Action',
    'tenant',
    'Tenant',
    'actor',
    'Actor',
    'timestamp',
    'ts',
    'nonce',
    'Nonce',
    'role',
    'Role',
    'Actor-Role',
    'payload',
    'Payload',
    'requestId',
    'Request-Id',
  ])
  for (const key of Object.keys(body)) {
    if (!allowedKeys.has(key)) {
      throw new HTTPException(400, { message: 'unknown_field' })
    }
  }
  const nonce = body.nonce || body.Nonce
  if (!nonce || typeof nonce !== 'string' || nonce.length > 128) {
    throw new HTTPException(400, { message: 'missing_nonce' })
  }
  const ts = body.timestamp || body.ts
  const tsNum = typeof ts === 'string' ? parseInt(ts, 10) : ts
  const windowSec = parseInt(c.env.SIGN_TS_WINDOW || '300', 10)
  const now = Math.floor(Date.now() / 1000)
  if (!tsNum || Math.abs(now - tsNum) > windowSec) {
    throw new HTTPException(400, { message: 'stale_timestamp' })
  }
  await checkReplay(c, `sign:${nonce}`, windowSec + 30)
  const payloadBytes = new TextEncoder().encode(JSON.stringify(body))
  const maxBytes = parseInt(c.env.SIGN_MAX_BYTES || '4096', 10)
  if (maxBytes > 0 && payloadBytes.length > maxBytes) {
    throw new HTTPException(413, { message: 'payload_too_large' })
  }
  const signature = await signCommand(c.env, body)
  const signatureRef = c.env.WORKER_SIGNATURE_REF || 'worker-ed25519'
  return c.json({ signature, signatureRef })
})

app.get('/api/health', async (c) => {
  const aoModule = await loadAoConnect().catch(() => null)
  const aoRoot = aoModule ? (aoModule as any).default || aoModule : null
  return c.json({
    ok: true,
    service: 'blackcat-inbox',
    now: new Date().toISOString(),
    ao: {
      mode: aoModeFromEnv(c.env),
      hbUrl: hbUrlFromEnv(c.env),
      scheduler: schedulerFromEnv(c.env),
      sitePidConfigured: Boolean(resolveSitePid(c.env)),
      writePidConfigured: Boolean(resolveWritePid(c.env)),
      walletConfigured: Boolean(cleanEnv(c.env.AO_WALLET_JSON)),
      walletPkcs8Configured: Boolean(cleanEnv((c.env as any).AO_WALLET_PKCS8_B64)),
      walletShape: walletShape(c.env),
      signerFactories: {
        createSigner: typeof aoRoot?.createSigner === 'function',
        createDataItemSigner: typeof aoRoot?.createDataItemSigner === 'function',
      },
    },
  })
})

app.post('/api/public/resolve-route', async (c) => {
  const body = await c.req.json<GatewayTemplateCallInput>().catch(() => null)
  if (!body || typeof body !== 'object') throw new HTTPException(400, { message: 'invalid_body' })
  const payload = asRecord(body.payload) || {}
  const siteId = firstNonEmptyString(body.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  requireTemplateApiToken(c, siteId)
  const out = await executeReadAction(c, 'ResolveRoute', body)
  return c.json(out.body, out.status)
})

app.post('/api/public/page', async (c) => {
  const body = await c.req.json<GatewayTemplateCallInput>().catch(() => null)
  if (!body || typeof body !== 'object') throw new HTTPException(400, { message: 'invalid_body' })
  const payload = asRecord(body.payload) || {}
  const siteId = firstNonEmptyString(body.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  requireTemplateApiToken(c, siteId)
  const out = await executeReadAction(c, 'GetPage', body)
  return c.json(out.body, out.status)
})

app.post('/api/checkout/order', async (c) => {
  const body = await c.req.json<GatewayTemplateCallInput>().catch(() => null)
  if (!body || typeof body !== 'object') throw new HTTPException(400, { message: 'invalid_body' })
  const payload = asRecord(body.payload) || {}
  const siteId = firstNonEmptyString(body.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  requireTemplateApiToken(c, siteId)
  const command = buildWriteCommand(c, body, expectedWriteAction('/api/checkout/order'))
  const signed = await maybeSignWriteCommand(c.env, command)
  const transport = await sendWriteCommand(c, signed)
  const normalized = normalizeWriteEnvelope(c.env, transport.raw, {
    requestId: trimString(signed.requestId),
    action: trimString(signed.action),
  })
  return c.json(normalized.body, normalized.status)
})

app.post('/api/checkout/payment-intent', async (c) => {
  const body = await c.req.json<GatewayTemplateCallInput>().catch(() => null)
  if (!body || typeof body !== 'object') throw new HTTPException(400, { message: 'invalid_body' })
  const payload = asRecord(body.payload) || {}
  const siteId = firstNonEmptyString(body.siteId, payload.siteId, c.req.header('x-bridge-site-id'))
  requireTemplateApiToken(c, siteId)
  const command = buildWriteCommand(c, body, expectedWriteAction('/api/checkout/payment-intent'))
  const signed = await maybeSignWriteCommand(c.env, command)
  const transport = await sendWriteCommand(c, signed)
  const normalized = normalizeWriteEnvelope(c.env, transport.raw, {
    requestId: trimString(signed.requestId),
    action: trimString(signed.action),
  })
  return c.json(normalized.body, normalized.status)
})

app.get('/inbox/:subject/:nonce', async (c) => {
  const subj = c.req.param('subject')
  const nonce = c.req.param('nonce')
  const kv = kvFor(c)
  await rateLimit(c)
  const raw = await kv.get(key(subj, nonce))
  if (!raw) throw new HTTPException(404, { message: 'not_found' })
  const item = JSON.parse(raw) as InboxItem
  await kv.delete(key(subj, nonce))
  logEvent('inbox_get', { subject: subj })
  inc('worker_inbox_get_total')
  return c.json({ status: 'OK', payload: item.payload, exp: item.exp })
})

app.post('/forget', async (c) => {
  requireToken(c)
  const body = await c.req.json<{ subject: string }>()
  if (!body.subject) throw new HTTPException(400, { message: 'missing_subject' })
  const prefix = `${body.subject}:`
  const replayPrefix = `replay:${body.subject}:`
  const kv = kvFor(c)
  const maxKeys = parseInt(c.env.FORGET_MAX_KEYS || '500', 10)
  const list = await kv.list({ prefix, limit: maxKeys + 1 })
  const replayList = await kv.list({ prefix: replayPrefix, limit: maxKeys + 1 })
  const canWait = c.executionCtx && typeof c.executionCtx.waitUntil === 'function'
  const overflow = list.keys.length > maxKeys || replayList.keys.length > maxKeys
  const inboxKeys = overflow ? list.keys.slice(0, maxKeys) : list.keys
  const replayKeys = overflow ? replayList.keys.slice(0, maxKeys) : replayList.keys
  const deleted = inboxKeys.length
  const replayDeleted = replayKeys.length
  const deleteKeys = async (keys: { name: string }[]) => {
    for (const k of keys) {
      if (canWait) c.executionCtx.waitUntil(kv.delete(k.name))
      else await kv.delete(k.name)
    }
  }
  const runDeletes = async () => {
    await deleteKeys(inboxKeys)
    await deleteKeys(replayKeys)
  }
  if (overflow) {
    await runDeletes()
    logEvent('forget_overflow', {
      subject: body.subject,
      deleted,
      replayDeleted,
      seen: list.keys.length,
      replaySeen: replayList.keys.length,
      maxKeys,
    })
    inc('worker_forget_deleted_total', deleted)
    inc('worker_forget_replay_deleted_total', replayDeleted)
    return c.json({ status: 'error', message: 'forget_too_many_keys', deleted, replayDeleted }, 429)
  }
  await runDeletes()
  logEvent('forget', { subject: body.subject, deleted, replayDeleted })
  inc('worker_forget_deleted_total', deleted)
  inc('worker_forget_replay_deleted_total', replayDeleted)
  return c.json({ status: 'OK', deleted, replayDeleted })
})

app.get('/metrics', async (c) => {
  const needBasic = !!(c.env.METRICS_BASIC_USER && c.env.METRICS_BASIC_PASS)
  const bearerToken = isPlaceholderSecret(c.env.METRICS_BEARER_TOKEN) ? '' : c.env.METRICS_BEARER_TOKEN || ''
  const needBearer = !!bearerToken
  const mustGuard = c.env.REQUIRE_METRICS_AUTH === '1' || secretsEnforced(c.env)
  if (!needBasic && !needBearer && mustGuard) {
    throw new HTTPException(500, { message: 'metrics_auth_not_configured' })
  }
  if (needBasic || needBearer) {
    const auth = c.req.header('authorization') || ''
    const alt = c.req.header('x-metrics-token') || ''
    let ok = false
    let method: 'basic' | 'bearer' | null = null
    if (needBearer && alt === bearerToken) {
      ok = true
      method = 'bearer'
    }
    if (!ok && needBearer && /^Bearer\s+/i.test(auth)) {
      ok = auth.replace(/^Bearer\s+/i, '').trim() === bearerToken
      if (ok) method = 'bearer'
    }
    if (!ok && needBasic && /^Basic\s+/i.test(auth)) {
      const b64 = auth.replace(/^Basic\s+/i, '')
      try {
        const decoded = Buffer.from(b64, 'base64').toString()
        const [u, p] = decoded.split(':')
        if (u === c.env.METRICS_BASIC_USER && p === c.env.METRICS_BASIC_PASS) {
          ok = true
          method = 'basic'
        }
      } catch (_) {}
    }
    if (!ok) {
      inc('worker_metrics_auth_blocked_total')
      throw new HTTPException(401, { message: 'unauthorized' })
    }
    inc('worker_metrics_auth_ok_total')
    if (method === 'bearer') inc('worker_metrics_auth_ok_bearer_total')
    if (method === 'basic') inc('worker_metrics_auth_ok_basic_total')
  }
  gauge('worker_notify_hmac_optional', c.env.NOTIFY_HMAC_OPTIONAL === '1' ? 1 : 0)
  // surfacing janitor/list pressure for alerting
  gauge('worker_inbox_janitor_enabled', c.env.DISABLE_JANITOR === '1' ? 0 : 1)
  return c.text(toProm(), 200, { 'content-type': 'text/plain; version=0.0.4' })
})

app.post('/notify', async (c) => {
  requireToken(c)
  const raw = await c.req.text()
  gauge('worker_notify_hmac_optional', c.env.NOTIFY_HMAC_OPTIONAL === '1' ? 1 : 0)
  await verifyNotifySignature(c, raw)
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
  if (webhook) {
    const u = new URL(webhook)
    if (!hostAllowed(u, c.env.NOTIFY_WEBHOOK_ALLOWLIST)) {
      inc('worker_notify_host_blocked_total')
      throw new HTTPException(403, { message: 'webhook_host_not_allowed' })
    }
  }
  const hashKey = `${body.to || webhook || raw}|${webhook ? 'webhook' : body.to ? 'email' : 'notify'}`
  const dedupeTtl = LITE_MODE ? 0 : parseInt(c.env.NOTIFY_DEDUPE_TTL || '300', 10)
  if (dedupeTtl > 0 && hashKey) {
    const hash = await crypto.subtle.digest('SHA-256', encoder.encode(hashKey))
    const hex = Array.from(new Uint8Array(hash))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')
    const kv = kvFor(c)
    const seen = await kv.get(`notify:hash:${hex}`)
    if (seen) {
      inc('worker_notify_deduped_total')
      return c.json({ status: 'OK', deduped: true })
    }
    await kv.put(`notify:hash:${hex}`, '1', { expirationTtl: dedupeTtl })
  }
  const kv = kvFor(c)
  const subjectKey = body.to || webhook || clientIp(c)
  const sprayKey = body.subject || subjectKey
  await subjectSprayGuard(c, clientIp(c), sprayKey)
  await notifySubjectLimit(c, subjectKey)
  const maxRetry = parseInt(c.env.NOTIFY_RETRY_MAX || '3', 10)
  const backoffMs = parseInt(c.env.NOTIFY_RETRY_BACKOFF_MS || '300', 10)
  const timeoutMs = webhookTimeoutMs(c.env as any)
  const breakerThreshold = parseInt(c.env.NOTIFY_BREAKER_THRESHOLD || '5', 10)
  const breakerCooldown = parseInt(c.env.NOTIFY_BREAKER_COOLDOWN || '300', 10)
  const headerBreakerKey = c.req.header('x-breaker-key')?.trim()
  const allowedBreakerKeys = ['stripe', 'paypal', 'gopay', 'webhook', 'sendgrid', 'notify']
  const breakerKey =
    headerBreakerKey && headerBreakerKey.length > 0 && allowedBreakerKeys.includes(headerBreakerKey)
      ? headerBreakerKey
      : webhook
        ? 'webhook'
        : body.to
          ? 'sendgrid'
          : 'notify'
  async function breakerState() {
    const rawState = await kv.get(`notify:breaker:${breakerKey}`)
    if (rawState) {
      try {
        const parsed = JSON.parse(rawState) as { count: number; openUntil?: number }
        logEvent('breaker_state_load', { key: breakerKey, state: parsed })
        return parsed
      } catch {
        return { count: 0, openUntil: 0 }
      }
    }
    return { count: 0, openUntil: 0 }
  }

  async function breakerAllows() {
    const st = await breakerState()
    const now = Math.floor(Date.now() / 1000)
    if (st.openUntil && st.openUntil > now) {
      inc('worker_notify_breaker_blocked_total')
      if (breakerKey === 'stripe') inc('worker_notify_breaker_blocked_total_stripe')
      if (breakerKey === 'paypal') inc('worker_notify_breaker_blocked_total_paypal')
      if (breakerKey === 'gopay') inc('worker_notify_breaker_blocked_total_gopay')
      throw new HTTPException(429, { message: 'notify_breaker_open' })
    }
    if (st.count >= breakerThreshold) {
      const updated = {
        count: st.count,
        openUntil: st.openUntil && st.openUntil > now ? st.openUntil : now + breakerCooldown,
      }
      await kv.put(`notify:breaker:${breakerKey}`, JSON.stringify(updated), { expirationTtl: breakerCooldown * 2 })
      logEvent('breaker_block', { key: breakerKey, state: updated })
      inc('worker_notify_breaker_blocked_total')
      if (breakerKey === 'stripe') inc('worker_notify_breaker_blocked_total_stripe')
      if (breakerKey === 'paypal') inc('worker_notify_breaker_blocked_total_paypal')
      if (breakerKey === 'gopay') inc('worker_notify_breaker_blocked_total_gopay')
      throw new HTTPException(429, { message: 'notify_breaker_open' })
    }
  }

  async function breakerNote(success: boolean) {
    const st = await breakerState()
    const now = Math.floor(Date.now() / 1000)
    if (success) {
      st.count = 0
      st.openUntil = 0
    } else {
      st.count = (st.count || 0) + 1
      if (st.count >= breakerThreshold) {
        st.openUntil = now + breakerCooldown
      } else {
        st.openUntil = st.openUntil && st.openUntil > now ? st.openUntil : 0
      }
    }
    await kv.put(`notify:breaker:${breakerKey}`, JSON.stringify(st), { expirationTtl: breakerCooldown * 2 })
    logEvent('breaker_state_save', { key: breakerKey, state: st })
    if (st.openUntil && st.openUntil > now) {
      inc('worker_notify_breaker_open_total')
      if (breakerKey === 'stripe') inc('worker_notify_breaker_open_total_stripe')
      if (breakerKey === 'paypal') inc('worker_notify_breaker_open_total_paypal')
      if (breakerKey === 'gopay') inc('worker_notify_breaker_open_total_gopay')
    }
  }

  await notifySubjectLimit(c, subjectKey)
  await breakerAllows()
  async function sendWithRetry(fn: (signal: AbortSignal) => Promise<Response>, label: string) {
    let attempt = 0
    const maxAttempts = Math.max(1, maxRetry)
    while (attempt < maxAttempts) {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), timeoutMs)
      let resp: Response
      try {
        resp = await fn(controller.signal)
      } catch (e) {
        if ((e as any).name === 'AbortError') {
          resp = new Response('', { status: 599 })
        } else {
          clearTimeout(timer)
          throw e
        }
      } finally {
        clearTimeout(timer)
      }
      if (resp.ok) return resp
      attempt++
      if (attempt < maxRetry) {
        inc('worker_notify_retry_total')
        await sleep(backoffMs * attempt)
      } else {
        inc('worker_notify_failed_total')
        await breakerNote(false)
        throw new HTTPException(502, { message: `${label}_failed` })
      }
    }
    throw new HTTPException(502, { message: `${label}_failed` })
  }
  // webhook first (either body.webhookUrl or env NOTIFY_WEBHOOK)
  if (webhook) {
    const resp = await sendWithRetry(
      (signal) =>
        fetch(webhook, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ to: body.to, subject: body.subject, text: body.text, html: body.html, data: body.data }),
          signal,
        }),
      'notify_webhook'
    )
    logEvent('notify', { via: 'webhook' })
    inc('worker_notify_sent_total')
    await breakerNote(true)
    return c.json({ status: 'OK', delivered: 'webhook' })
  }
  // SendGrid fallback
  if (c.env.SENDGRID_KEY && body.to) {
    const resp = await sendWithRetry(
      (signal) =>
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
          signal,
        }),
      'notify_sendgrid'
    )
    logEvent('notify', { via: 'sendgrid' })
    inc('worker_notify_sent_total')
    await breakerNote(true)
    return c.json({ status: 'OK', delivered: 'sendgrid' })
  }
  throw new HTTPException(400, { message: 'notify_unconfigured' })
})

// Cron/cleanup: bind route for Cloudflare scheduled event
export default {
  fetch: app.fetch,
  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    if (env.DISABLE_JANITOR === '1') {
      logEvent('janitor_skip', { reason: 'disabled' })
      return
    }
    const now = Math.floor(Date.now() / 1000)
    const kv = useMemoryKv(env) ? kvFor({ env }) : env.INBOX_KV
    const prefixes = ['', 'replay:']
    let deleted = 0
  for (const prefix of prefixes) {
    let cursor: string | undefined
    let processed = 0
    do {
      const page = await kv.list({ prefix, cursor, limit: 1000 })
      for (const k of page.keys) {
        processed++
        if (processed > parseInt((env.MAX_JANITOR_KEYS as any) || '2000', 10)) {
          logEvent('janitor_cap_reached', { prefix, cursor, processed })
          return
        }
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
        cursor = page.cursor
        if (page.list_complete === true || !cursor) break
      } while (true)
    }
    if (deleted > 0) inc('worker_inbox_expired_total', deleted)
    logEvent('janitor', { ts: now, deleted })
  },
}
