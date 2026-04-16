#!/usr/bin/env node
import http from 'node:http'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { connect } from '@permaweb/aoconnect'

const DEFAULT_HB_URL = 'https://push.forward.computer'
const DEFAULT_SCHEDULER = 'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo'
const DEFAULT_PORT = 8788
const DEFAULT_RESULT_TIMEOUT_MS = 45000
const DEFAULT_SITE_ACTION_TIMEOUT_MS = 30000
const DEFAULT_RESULT_RETRIES = 4
const SAFE_TRACE_ID_RE = /^[A-Za-z0-9._-]{8,128}$/
const CORS_ALLOW_HEADERS = 'content-type,authorization,x-api-token,x-request-id,x-trace-id'

const env = {
  port: positiveInt(process.env.PORT, DEFAULT_PORT),
  host: clean(process.env.HOST) || '0.0.0.0',
  hbUrl: clean(process.env.AO_HB_URL) || clean(process.env.HB_URL) || DEFAULT_HB_URL,
  scheduler: clean(process.env.AO_HB_SCHEDULER) || clean(process.env.HB_SCHEDULER) || DEFAULT_SCHEDULER,
  sitePid: clean(process.env.AO_SITE_PROCESS_ID) || clean(process.env.SITE_PID) || '',
  registryPid: clean(process.env.AO_REGISTRY_PROCESS_ID) || clean(process.env.REGISTRY_PID) || '',
  authToken: clean(process.env.AO_PUBLIC_API_TOKEN) || '',
  allowOrigin: clean(process.env.AO_PUBLIC_API_ALLOW_ORIGIN) || '*',
  mode: clean(process.env.AO_MODE) || 'mainnet',
  actionTimeoutMs: positiveInt(process.env.AO_SITE_ACTION_TIMEOUT_MS, DEFAULT_SITE_ACTION_TIMEOUT_MS),
  resultTimeoutMs: positiveInt(process.env.AO_RESULT_TIMEOUT_MS, DEFAULT_RESULT_TIMEOUT_MS),
  resultRetries: positiveInt(process.env.AO_RESULT_RETRIES, DEFAULT_RESULT_RETRIES),
  // dryrun is the preferred non-mutating path.
  disableDryrun: isTrue(process.env.AO_DISABLE_DRYRUN),
  // Optional fallback when dryrun is unavailable on the selected transport.
  fallbackToScheduler: isTrue(process.env.AO_READ_FALLBACK_TO_SCHEDULER),
  walletPath: clean(process.env.AO_WALLET_PATH) || clean(process.env.WALLET_PATH) || 'wallet.json',
  debug: isTrue(process.env.AO_PUBLIC_API_DEBUG),
}

const ao = connect({
  MODE: env.mode,
  URL: env.hbUrl,
  SCHEDULER: env.scheduler,
})

let fallbackWallet = null
let fallbackSigner = null
let arbundlesApi = null

function clean(value) {
  if (!value) return ''
  const next = String(value).trim()
  return next === '' || next === 'undefined' || next === 'null' ? '' : next
}

function isTrue(value) {
  const next = clean(value).toLowerCase()
  return next === '1' || next === 'true' || next === 'yes' || next === 'on'
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || ''), 10)
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback
  return parsed
}

function nowIso() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
}

function json(res, status, body, meta = {}) {
  const payload = JSON.stringify(body)
  res.statusCode = status
  res.setHeader('content-type', 'application/json; charset=utf-8')
  res.setHeader('cache-control', 'no-store')
  res.setHeader('x-content-type-options', 'nosniff')
  res.setHeader('x-frame-options', 'DENY')
  res.setHeader('referrer-policy', 'no-referrer')
  res.setHeader('access-control-allow-origin', env.allowOrigin)
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS')
  res.setHeader('access-control-allow-headers', CORS_ALLOW_HEADERS)
  const requestId = trimString(meta.requestId || body?.requestId)
  if (requestId) res.setHeader('x-request-id', requestId)
  const traceId = resolveTraceId(meta.traceId || body?.traceId)
  if (traceId) res.setHeader('x-trace-id', traceId)
  res.end(payload)
}

function unauthorized(res, traceId = '') {
  json(res, 401, { ok: false, error: 'unauthorized', traceId: traceId || undefined }, { traceId })
}

function readJsonBody(req, maxBytes = 128 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let total = 0
    req.on('data', (chunk) => {
      total += chunk.length
      if (total > maxBytes) {
        reject(new Error('payload_too_large'))
        req.destroy()
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8')
        const parsed = raw ? JSON.parse(raw) : {}
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          reject(new Error('invalid_json'))
          return
        }
        resolve(parsed)
      } catch {
        reject(new Error('invalid_json'))
      }
    })
    req.on('error', reject)
  })
}

function trimString(value) {
  return typeof value === 'string' ? value.trim() : ''
}

function resolveTraceId(value) {
  const normalized = trimString(value)
  if (!normalized) return ''
  return SAFE_TRACE_ID_RE.test(normalized) ? normalized : ''
}

function normalizePath(pathValue) {
  const path = trimString(pathValue)
  if (!path) return '/'
  return path.startsWith('/') ? path : `/${path}`
}

function normalizeHost(hostValue) {
  const normalized = trimString(hostValue).toLowerCase()
  if (!normalized) return ''
  const withoutProtocol = normalized.replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
  const withoutPath = withoutProtocol.split('/')[0]
  const withoutPort = withoutPath.split(':')[0]
  return withoutPort.replace(/\.$/, '')
}

function requestIdFrom(req, body) {
  const headerValue = trimString(req.headers['x-request-id'])
  if (headerValue) return headerValue.slice(0, 128)
  const bodyValue = trimString(body.requestId || body['request-id'])
  if (bodyValue) return bodyValue.slice(0, 128)
  return `gw-read-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`
}

function traceIdFrom(req, body = {}) {
  return resolveTraceId(req.headers['x-trace-id'] || body.traceId || body['trace-id'])
}

function requireAuth(req) {
  if (!env.authToken) return true
  const authHeader = trimString(req.headers.authorization)
  const tokenHeader = trimString(req.headers['x-api-token'])
  const bearer = authHeader.toLowerCase().startsWith('bearer ') ? authHeader.slice(7).trim() : ''
  return bearer === env.authToken || tokenHeader === env.authToken
}

function buildCommonTags(action, requestId, traceId = '', replyTo = env.sitePid) {
  const tags = [
    { name: 'Action', value: action },
    { name: 'Request-Id', value: requestId },
    { name: 'Reply-To', value: replyTo },
    { name: 'signing-format', value: 'ans104' },
    { name: 'accept-bundle', value: 'true' },
    { name: 'require-codec', value: 'application/json' },
    { name: 'Type', value: 'Message' },
    { name: 'Variant', value: 'ao.TN.1' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Content-Type', value: 'application/json' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
  ]
  if (traceId) tags.push({ name: 'Trace-Id', value: traceId })
  return tags
}

function processPidForAction(action) {
  if (action === 'GetSiteByHost') {
    return env.registryPid
  }
  return env.sitePid
}

function buildReadData(action, requestId, payload) {
  const data = {
    Action: action,
    'Request-Id': requestId,
  }
  const siteId = trimString(payload.siteId)
  if (siteId) data['Site-Id'] = siteId

  if (action === 'GetSiteByHost') {
    const host = normalizeHost(payload.host || payload.hostname)
    if (host) data.Host = host
  } else if (action === 'ResolveRoute') {
    const routePath = normalizePath(payload.path)
    data.Path = routePath
    const locale = trimString(payload.locale)
    if (locale) data.Locale = locale
  } else if (action === 'GetPage') {
    const pageId = trimString(payload.pageId)
    const slug = trimString(payload.slug || payload.path)
    if (pageId) data['Page-Id'] = pageId
    if (slug) data.Slug = slug
    const version = trimString(payload.version)
    const locale = trimString(payload.locale)
    if (version) data.Version = version
    if (locale) data.Locale = locale
  }

  return JSON.stringify(data)
}

function addTag(tags, name, value) {
  const normalized = trimString(value)
  if (normalized) tags.push({ name, value: normalized })
}

function normalizeAoEnvelope(rawResult, context = {}) {
  const normalized = rawResult?.results?.raw || rawResult?.raw || rawResult || {}
  const outputCandidate =
    normalized?.Output ??
    normalized?.output ??
    normalized?.Data ??
    normalized?.data ??
    rawResult?.Output ??
    rawResult?.output ??
    null

  let envelope = null
  if (typeof outputCandidate === 'string') {
    if (outputCandidate.trim() !== '') {
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
  } else if (rawResult && typeof rawResult === 'object' && typeof rawResult.status === 'string') {
    envelope = rawResult
  }

  if (!envelope) {
    const runtimeError = normalized?.Error
    const hasRuntimeError =
      runtimeError &&
      typeof runtimeError === 'object' &&
      Object.keys(runtimeError).length > 0
    if (
      !hasRuntimeError &&
      (context.action === 'ResolveRoute' || context.action === 'GetSiteByHost' || context.action === 'GetPage')
    ) {
      return {
        ok: false,
        status: 404,
        body: {
          status: 'ERROR',
          code: 'NOT_FOUND',
          message: 'not_found_or_empty_result',
        },
      }
    }
    return {
      ok: false,
      status: 502,
      body: {
        ok: false,
        error: 'invalid_ao_response',
        details: 'Could not normalize AO response envelope',
        raw: env.debug ? rawResult : undefined,
      },
    }
  }

  if (String(envelope.status || '').toUpperCase() === 'OK') {
    return {
      ok: true,
      status: 200,
      body: envelope,
    }
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

  return {
    ok: false,
    status,
    body: envelope,
  }
}

function timeoutPromise(label, ms) {
  return new Promise((_, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout_${label}_${ms}ms`)), ms)
    timer.unref?.()
  })
}

async function runWithTimeout(label, promiseFactory, ms) {
  return Promise.race([promiseFactory(), timeoutPromise(label, ms)])
}

async function tryDryrun(processPid, tags, data) {
  const output = await runWithTimeout(
    'dryrun',
    () =>
      ao.dryrun({
        process: processPid,
        tags,
        data,
      }),
    env.actionTimeoutMs,
  )
  return { mode: 'dryrun', output }
}

async function loadArbundles() {
  if (arbundlesApi) return arbundlesApi
  try {
    const mod = await import('arbundles')
    if (typeof mod?.createData !== 'function' || typeof mod?.ArweaveSigner !== 'function') {
      throw new Error('arbundles_exports_invalid')
    }
    arbundlesApi = {
      createData: mod.createData,
      ArweaveSigner: mod.ArweaveSigner,
    }
    return arbundlesApi
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error)
    throw new Error(`arbundles_unavailable:${msg}`)
  }
}

async function loadFallbackWallet() {
  if (fallbackWallet && fallbackSigner) {
    return { wallet: fallbackWallet, signer: fallbackSigner }
  }
  if (!env.walletPath || !fs.existsSync(env.walletPath)) {
    throw new Error(`fallback_wallet_missing:${env.walletPath}`)
  }
  const { ArweaveSigner } = await loadArbundles()
  fallbackWallet = JSON.parse(fs.readFileSync(env.walletPath, 'utf8'))
  fallbackSigner = new ArweaveSigner(fallbackWallet)
  return { wallet: fallbackWallet, signer: fallbackSigner }
}

async function sendSchedulerMessage(processPid, tags, data) {
  const { createData } = await loadArbundles()
  const { signer } = await loadFallbackWallet()
  const item = createData(data, signer, {
    target: processPid,
    tags,
  })
  await item.sign(signer)
  const endpoint = `${env.hbUrl.replace(/\/$/, '')}/~scheduler@1.0/schedule?target=${processPid}`
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/ans104',
      'codec-device': 'ans104@1.0',
    },
    body: item.getRaw(),
  })
  const text = await response.text().catch(() => '')
  let parsed = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = null
  }
  const slot = Number(response.headers.get('slot') || parsed?.slot || '')
  return {
    ok: response.ok,
    status: response.status,
    slot: Number.isFinite(slot) ? slot : null,
    messageId: item.id,
    parsed,
    text,
  }
}

async function fetchCompute(processPid, slot) {
  const endpoint =
    `${env.hbUrl.replace(/\/$/, '')}/${processPid}~process@1.0/compute=${slot}` +
    '?accept-bundle=true&require-codec=application/json'
  const response = await fetch(endpoint, { method: 'GET' })
  const text = await response.text().catch(() => '')
  if (!response.ok) {
    throw new Error(`compute_failed:${response.status}:${text.slice(0, 220)}`)
  }
  try {
    return text ? JSON.parse(text) : {}
  } catch {
    throw new Error('compute_invalid_json')
  }
}

async function schedulerFallback(processPid, tags, data) {
  const sent = await sendSchedulerMessage(processPid, tags, data)
  if (!sent.ok || !Number.isFinite(sent.slot)) {
    const parsedBody = sent?.parsed?.body
    const parsedBodyText = typeof parsedBody === 'string' ? parsedBody : ''
    const lowerText = String(sent.text || '').toLowerCase()
    if (
      sent.status === 404 ||
      parsedBodyText.toLowerCase() === 'not_found' ||
      parsedBodyText.toLowerCase().includes('empty message sequence') ||
      lowerText.includes('necessary_message_not_found') ||
      lowerText.includes('not_found')
    ) {
      return {
        mode: 'scheduler-direct',
        output: {
          status: 'ERROR',
          code: 'NOT_FOUND',
          message: parsedBodyText || 'not_found',
        },
        slot: null,
        messageId: sent.messageId,
      }
    }
    if (sent.ok && sent.parsed && typeof sent.parsed === 'object') {
      return {
        mode: 'scheduler-direct',
        output: sent.parsed,
        slot: null,
        messageId: sent.messageId,
      }
    }
    throw new Error(`scheduler_send_failed:${sent.status}:${String(sent.text || '').slice(0, 220)}`)
  }
  let lastErr = null
  for (let i = 0; i < env.resultRetries; i += 1) {
    try {
      const output = await runWithTimeout(
        'compute',
        () => fetchCompute(processPid, sent.slot),
        env.resultTimeoutMs,
      )
      return { mode: 'scheduler', output, slot: sent.slot, messageId: sent.messageId }
    } catch (error) {
      lastErr = error
      await new Promise((resolve) => setTimeout(resolve, 700 * (i + 1)))
    }
  }
  throw lastErr || new Error('compute_failed')
}

async function executeRead(action, req, body) {
  const processPid = processPidForAction(action)
  if (!processPid) {
    return {
      status: 503,
      body: {
        ok: false,
        error: action === 'GetSiteByHost' ? 'ao_registry_pid_missing' : 'ao_site_pid_missing',
      },
    }
  }
  const requestId = requestIdFrom(req, body)
  const traceId = traceIdFrom(req, body)

  const payload = body.payload && typeof body.payload === 'object' ? body.payload : body
  const siteId = trimString(body.siteId || payload.siteId)
  const host = normalizeHost(body.host || body.hostname || payload.host || payload.hostname)

  if (action !== 'GetSiteByHost' && !siteId) {
    return {
      status: 400,
      body: { ok: false, error: 'site_id_required', traceId: traceId || undefined },
      meta: { requestId, traceId },
    }
  }

  const tags = buildCommonTags(action, requestId, traceId, processPid)
  addTag(tags, 'Site-Id', siteId)

  if (action === 'GetSiteByHost') {
    if (!host) {
      return {
        status: 400,
        body: { ok: false, error: 'host_required', traceId: traceId || undefined },
        meta: { requestId, traceId },
      }
    }
    addTag(tags, 'Host', host)
  } else if (action === 'ResolveRoute') {
    const routePath = normalizePath(payload.path)
    addTag(tags, 'Path', routePath)
    addTag(tags, 'Locale', payload.locale)
  } else if (action === 'GetPage') {
    const pageId = trimString(payload.pageId)
    const slug = trimString(payload.slug || payload.path)
    if (!pageId && !slug) {
      return {
        status: 400,
        body: { ok: false, error: 'page_id_or_slug_required', traceId: traceId || undefined },
        meta: { requestId, traceId },
      }
    }
    addTag(tags, 'Page-Id', pageId)
    addTag(tags, 'Slug', slug)
    addTag(tags, 'Version', payload.version)
    addTag(tags, 'Locale', payload.locale)
  }

  const data = buildReadData(action, requestId, {
    siteId,
    host,
    path: payload.path,
    pageId: payload.pageId,
    slug: payload.slug,
    version: payload.version,
    locale: payload.locale,
  })

  try {
    let transport = null
    let aoOutput = null

    if (!env.disableDryrun) {
      try {
        transport = await tryDryrun(processPid, tags, data)
        aoOutput = transport.output
      } catch (error) {
        if (!env.fallbackToScheduler) throw error
      }
    }

    if (!aoOutput) {
      if (!env.fallbackToScheduler) {
        throw new Error('dryrun_failed_no_fallback')
      }
      transport = await schedulerFallback(processPid, tags, data)
      aoOutput = transport.output
    }

    const normalized = normalizeAoEnvelope(aoOutput, { action })
    if (env.debug) {
      normalized.body.transport = {
        mode: transport?.mode || 'unknown',
        slot: transport?.slot || null,
        messageId: transport?.messageId || null,
      }
    }
    if (traceId) normalized.body.traceId = traceId
    return { status: normalized.status, body: normalized.body, meta: { requestId, traceId } }
  } catch (error) {
    return {
      status: 502,
      body: {
        ok: false,
        error: 'ao_read_failed',
        message: error instanceof Error ? error.message : String(error),
        traceId: traceId || undefined,
      },
      meta: { requestId, traceId },
    }
  }
}

const server = http.createServer(async (req, res) => {
  const method = (req.method || 'GET').toUpperCase()
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`)
  const traceId = traceIdFrom(req, {})

  if (method === 'OPTIONS') {
    res.statusCode = 204
    res.setHeader('access-control-allow-origin', env.allowOrigin)
    res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS')
    res.setHeader('access-control-allow-headers', CORS_ALLOW_HEADERS)
    if (traceId) res.setHeader('x-trace-id', traceId)
    res.end('')
    return
  }

  if (url.pathname === '/healthz' && method === 'GET') {
    json(res, 200, {
      ok: true,
      service: 'ao-public-api',
      sitePidConfigured: Boolean(env.sitePid),
      registryPidConfigured: Boolean(env.registryPid),
      hbUrl: env.hbUrl,
      scheduler: env.scheduler,
      dryrunEnabled: !env.disableDryrun,
      schedulerFallback: env.fallbackToScheduler,
      now: nowIso(),
    })
    return
  }

  if (!requireAuth(req)) {
    unauthorized(res, traceId)
    return
  }

  if (method !== 'POST') {
    json(res, 405, { ok: false, error: 'method_not_allowed', traceId: traceId || undefined }, { traceId })
    return
  }

  if (
    url.pathname !== '/api/public/resolve-route' &&
    url.pathname !== '/api/public/site-by-host' &&
    url.pathname !== '/api/public/page'
  ) {
    json(res, 404, { ok: false, error: 'not_found', traceId: traceId || undefined }, { traceId })
    return
  }

  let body = {}
  try {
    body = await readJsonBody(req)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (message === 'payload_too_large') {
      json(res, 413, { ok: false, error: 'payload_too_large', traceId: traceId || undefined }, { traceId })
      return
    }
    json(res, 400, { ok: false, error: 'invalid_json', traceId: traceId || undefined }, { traceId })
    return
  }

  const action =
    url.pathname === '/api/public/resolve-route'
      ? 'ResolveRoute'
      : url.pathname === '/api/public/site-by-host'
        ? 'GetSiteByHost'
        : 'GetPage'
  const out = await executeRead(action, req, body)
  json(res, out.status, out.body, out.meta || { traceId })
})

server.listen(env.port, env.host, () => {
  console.log(
    JSON.stringify({
      event: 'ao_public_api_started',
      host: env.host,
      port: env.port,
      hbUrl: env.hbUrl,
      scheduler: env.scheduler,
      sitePidConfigured: Boolean(env.sitePid),
      registryPidConfigured: Boolean(env.registryPid),
      dryrunEnabled: !env.disableDryrun,
      schedulerFallback: env.fallbackToScheduler,
      startedAt: nowIso(),
    }),
  )
})
