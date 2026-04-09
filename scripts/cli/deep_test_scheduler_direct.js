#!/usr/bin/env node
import fs from 'fs'
import crypto from 'crypto'
import { createData, ArweaveSigner } from 'arbundles'
import {
  buildExecutionAssertion,
  formatAssertionStatus,
  probeCompute,
  resolveExecutionMode,
  summarizeAssertions
} from './execution_assertions.js'

function arg(name, fallback) {
  const idx = process.argv.indexOf(`--${name}`)
  if (idx === -1) return fallback
  return process.argv[idx + 1]
}

function must(v, name) {
  if (!v) throw new Error(`Missing --${name}`)
  return v
}

function cleanEnv(v) {
  if (v === undefined || v === null) return undefined
  const s = String(v).trim()
  if (!s || s === 'undefined' || s === 'null') return undefined
  return s
}

async function fetchWithTimeout(url, init = {}, timeoutMs = 20000) {
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), timeoutMs)
  try {
    return await fetch(url, { ...init, signal: ctl.signal })
  } finally {
    clearTimeout(timer)
  }
}

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function loadSecrets(path) {
  if (!path || !fs.existsSync(path)) return {}
  return JSON.parse(fs.readFileSync(path, 'utf8'))
}

function stableStringify(value) {
  if (value === null || value === undefined) return 'null'
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
  if (typeof value === 'object') {
    const keys = Object.keys(value).sort()
    return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

function canonicalValue(val) {
  if (Array.isArray(val)) {
    return `[${val.map(canonicalValue).join(',')}]`
  }
  if (val && typeof val === 'object') {
    const keys = Object.keys(val).sort()
    return `{${keys.map((k) => `${k}=${canonicalValue(val[k])}`).join(',')}}`
  }
  if (typeof val === 'boolean') return val ? 'true' : 'false'
  if (typeof val === 'number') return String(val)
  if (typeof val === 'string') return val
  return ''
}

function canonicalPayload(msg) {
  const cleaned = {}
  for (const [k, v] of Object.entries(msg)) {
    if (k === 'Signature' || k === 'signature' || k === 'Signature-Ref') continue
    cleaned[k] = v
  }
  return canonicalValue(cleaned)
}

function signHmacHex(msg, secret) {
  const payload = canonicalPayload(msg)
  return crypto.createHmac('sha256', secret).update(payload).digest('hex')
}

function attachOptionalSignature(msg, authSignatureSecret) {
  if (!authSignatureSecret) return msg
  return {
    ...msg,
    Signature: signHmacHex(msg, authSignatureSecret)
  }
}

function registryMessages({ authSignatureSecret }) {
  const now = Date.now()
  const siteId = `site-${now}`
  const host = `${siteId}.example.test`
  const role = 'registry-admin'

  const base = (action, idx, extra = {}) => {
    const msg = {
      Action: action,
      'Request-Id': `req-registry-${now}-${idx}`,
      Nonce: `nonce-${Math.random().toString(36).slice(2, 10)}`,
      ts: Math.floor(Date.now() / 1000),
      'Actor-Role': role,
      ...extra
    }
    return attachOptionalSignature(msg, authSignatureSecret)
  }

  const messages = [
    base('RegisterSite', 1, { 'Site-Id': siteId, Config: { version: 'v1' } }),
    base('BindDomain', 2, { 'Site-Id': siteId, Host: host }),
    base('GetSiteByHost', 3, { Host: host })
  ]

  return messages.map((payload) => ({
    envelopeAction: payload.Action,
    action: payload.Action,
    requestId: payload['Request-Id'],
    data: JSON.stringify(payload)
  }))
}

function siteMessages({ authSignatureSecret }) {
  const now = Date.now()
  const siteId = `site-${now}`
  const routePath = '/health'
  const pageId = `page-${now}`
  const role = 'admin'

  const base = (action, idx, extra = {}) => {
    const msg = {
      Action: action,
      'Request-Id': `req-site-${now}-${idx}`,
      'Actor-Role': role,
      'Schema-Version': '1.0',
      ...extra
    }
    return attachOptionalSignature(msg, authSignatureSecret)
  }

  const messages = [
    base('UpsertRoute', 1, { 'Site-Id': siteId, Path: routePath, 'Page-Id': pageId }),
    base('ResolveRoute', 2, { 'Site-Id': siteId, Path: routePath }),
    base('GetPublishStatus', 3, { 'Site-Id': siteId })
  ]

  return messages.map((payload) => ({
    envelopeAction: payload.Action,
    action: payload.Action,
    requestId: payload['Request-Id'],
    data: JSON.stringify(payload)
  }))
}

function catalogMessages({ authSignatureSecret }) {
  const now = Date.now()
  const siteId = `site-${now}`
  const categoryId = `cat-${now}`
  const role = 'catalog-admin'

  const base = (action, idx, extra = {}) => {
    const msg = {
      Action: action,
      'Request-Id': `req-catalog-${now}-${idx}`,
      'Actor-Role': role,
      'Schema-Version': '1.0',
      ...extra
    }
    return attachOptionalSignature(msg, authSignatureSecret)
  }

  const messages = [
    base('UpsertCategory', 1, {
      'Site-Id': siteId,
      'Category-Id': categoryId,
      Payload: { name: 'Diagnostic category' },
      Products: {}
    }),
    base('GetCategory', 2, { 'Site-Id': siteId, 'Category-Id': categoryId }),
    base('ListCategories', 3, { 'Site-Id': siteId, Limit: 10 })
  ]

  return messages.map((payload) => ({
    envelopeAction: payload.Action,
    action: payload.Action,
    requestId: payload['Request-Id'],
    data: JSON.stringify(payload)
  }))
}

function accessMessages({ authSignatureSecret }) {
  const now = Date.now()
  const subject = `subject-${now}`
  const asset = `asset-${now}`
  const role = 'admin'

  const base = (action, idx, extra = {}) => {
    const msg = {
      Action: action,
      'Request-Id': `req-access-${now}-${idx}`,
      'Actor-Role': role,
      'Schema-Version': '1.0',
      ...extra
    }
    return attachOptionalSignature(msg, authSignatureSecret)
  }

  const messages = [
    base('PutProtectedAssetRef', 1, {
      Asset: asset,
      Ref: `ar://${'a'.repeat(43)}`,
      Visibility: 'protected'
    }),
    base('GrantEntitlement', 2, { Subject: subject, Asset: asset, Policy: 'read' }),
    base('HasEntitlement', 3, { Subject: subject, Asset: asset }),
    base('GetProtectedAssetRef', 4, { Asset: asset })
  ]

  return messages.map((payload) => ({
    envelopeAction: payload.Action,
    action: payload.Action,
    requestId: payload['Request-Id'],
    data: JSON.stringify(payload)
  }))
}

function integrityMessages({ authSignatureSecret }) {
  const now = Date.now()
  const role = 'registry-admin'
  const componentId = 'gateway'
  const version = `1.2.${String(now).slice(-4)}`
  const root = `root-${now}`
  const rootNext = `root-${now + 1}`

  const base = (action, idx, extra = {}) => {
    const msg = {
      Action: action,
      'Request-Id': `req-integrity-${now}-${idx}`,
      Nonce: `nonce-${Math.random().toString(36).slice(2, 10)}`,
      ts: Math.floor(Date.now() / 1000),
      'Actor-Role': role,
      ...extra
    }
    return attachOptionalSignature(msg, authSignatureSecret)
  }

  const messages = [
    base('PublishTrustedRelease', 1, {
      'Component-Id': componentId,
      Version: version,
      Root: root,
      'Uri-Hash': `uri-${now}`,
      'Meta-Hash': `meta-${now}`,
      'Policy-Hash': `policy-${now}`,
      Activate: true
    }),
    base('GetTrustedRoot', 2, { 'Component-Id': componentId }),
    base('GetIntegritySnapshot', 3),
    base('SetIntegrityPolicyPause', 4, {
      Paused: true,
      Reason: 'deep-test-maintenance'
    }),
    base('GetIntegrityPolicy', 5),
    base('RevokeTrustedRelease', 6, {
      Root: root,
      Reason: 'deep-test-revocation'
    }),
    base('PublishTrustedRelease', 7, {
      'Component-Id': componentId,
      Version: `${version}-next`,
      Root: rootNext,
      'Uri-Hash': `uri-${now + 1}`,
      'Meta-Hash': `meta-${now + 1}`,
      'Policy-Hash': `policy-${now + 1}`,
      Activate: true
    }),
    base('GetTrustedReleaseByRoot', 8, { Root: rootNext }),
    base('GetIntegritySnapshot', 9)
  ]

  return messages.map((payload) => ({
    envelopeAction: payload.Action,
    action: payload.Action,
    requestId: payload['Request-Id'],
    data: JSON.stringify(payload)
  }))
}

function detachedWriteMessage(cmd) {
  const parts = [
    cmd.action || '',
    cmd.tenant || '',
    cmd.actor || '',
    cmd.timestamp || '',
    cmd.nonce || '',
    stableStringify(cmd.payload || {}),
    cmd.requestId || ''
  ]
  return parts.join('|')
}

async function signWriteCommand(cmd, signUrl, token) {
  const res = await fetchWithTimeout(
    signUrl,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${token}`
      },
      body: JSON.stringify(cmd)
    },
    25000
  )
  const text = await res.text()
  if (!res.ok) {
    throw new Error(`worker_sign_failed:${res.status}:${text.slice(0, 240)}`)
  }
  const json = JSON.parse(text)
  return {
    ...cmd,
    signature: json.signature,
    signatureRef: json.signatureRef || cmd.signatureRef
  }
}

function writeMessages() {
  const actions = ['Ping', 'GetOpsHealth', 'RuntimeSignal']
  return actions.map((action, index) => ({
    action,
    requestId: `req-write-${Date.now()}-${index + 1}`,
    actor: 'worker-test',
    tenant: 'blackcat',
    role: 'admin',
    timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    nonce: `nonce-${Math.random().toString(36).slice(2, 10)}`,
    signatureRef: 'worker-ed25519',
    payload:
      action === 'RuntimeSignal'
        ? { marker: `runtime-signal-${Date.now()}` }
        : action === 'Ping'
          ? { ping: true }
          : {}
  }))
}

async function sendSchedulerMessage({ baseUrl, pid, jwk, envelopeAction, action, requestId, data, variant }) {
  const signer = new ArweaveSigner(jwk)
  const endpoint = `${baseUrl}/~scheduler@1.0/schedule?target=${pid}`
  const tags = [
    { name: 'Action', value: envelopeAction },
    { name: 'Reply-To', value: pid },
    { name: 'Content-Type', value: 'application/json' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
    { name: 'signing-format', value: 'ans104' },
    { name: 'accept-bundle', value: 'true' },
    { name: 'require-codec', value: 'application/json' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Type', value: 'Message' },
    { name: 'Variant', value: variant }
  ]

  const maxAttempts = 3
  let lastResponse = null
  let lastError = null
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const item = createData(data, signer, { target: pid, tags })
    await item.sign(signer)
    try {
      const res = await fetchWithTimeout(
        endpoint,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/ans104',
            'codec-device': 'ans104@1.0'
          },
          body: item.getRaw()
        },
        30000
      )
      const text = await res.text().catch(() => '')
      const headers = {}
      res.headers.forEach((v, k) => {
        headers[k] = v
      })
      let parsedBody = null
      try {
        parsedBody = JSON.parse(text)
      } catch {
        parsedBody = null
      }
      lastResponse = {
        endpoint,
        envelopeAction,
        action,
        requestId: requestId || null,
        dataItemId: item.id,
        txDataLength: Buffer.byteLength(data),
        status: res.status,
        ok: res.ok,
        headers,
        bodyPreview: text.slice(0, 800),
        parsedAction: parsedBody?.body?.action || null,
        parsedSlot: parsedBody?.slot || null,
        attempts: attempt,
        retryCount: attempt - 1
      }
      if (res.status >= 500 && attempt < maxAttempts) {
        await sleep(600 * attempt)
        continue
      }
      return lastResponse
    } catch (err) {
      lastError = err
      if (attempt < maxAttempts) {
        await sleep(600 * attempt)
        continue
      }
    }
  }

  return (
    lastResponse || {
      endpoint,
      envelopeAction,
      action,
      requestId: requestId || null,
      dataItemId: null,
      txDataLength: Buffer.byteLength(data),
      status: 'error',
      ok: false,
      headers: {},
      bodyPreview: String(lastError?.message || lastError || 'send_error'),
      parsedAction: null,
      parsedSlot: null,
      attempts: maxAttempts,
      retryCount: maxAttempts - 1
    }
  )
}

async function probeSlotCurrent(baseUrl, pid) {
  const primaryUrl = `${baseUrl}/${pid}~process@1.0/slot/current?accept-bundle=true`
  const fallbackUrl = `${baseUrl}/${pid}/slot/current`
  const attempts = [
    { name: 'process', url: primaryUrl },
    { name: 'legacy', url: fallbackUrl }
  ]
  let last = null
  for (const attempt of attempts) {
    try {
      const res = await fetchWithTimeout(attempt.url, { method: 'GET' }, 12000)
      const text = await res.text().catch(() => '')
      const body = text.trim().slice(0, 200)
      const out = {
        route: attempt.name,
        url: attempt.url,
        status: res.status,
        ok: res.ok,
        body
      }
      if (res.ok) return out
      last = out
    } catch (err) {
      last = {
        route: attempt.name,
        url: attempt.url,
        status: 'error',
        ok: false,
        body: err?.message || String(err)
      }
    }
  }
  return last
}

async function main() {
  const pid = must(arg('pid'), 'pid')
  const walletPath = arg('wallet', 'wallet.json')
  const urls = String(arg('urls', 'https://push.forward.computer,https://push-1.forward.computer'))
    .split(',')
    .map((u) => u.trim().replace(/\/$/, ''))
    .filter(Boolean)
  const variant = arg('variant', 'ao.TN.1')
  const profile = arg('profile', 'registry')
  const secretsPath = arg('secrets')
  const out = arg(
    'out',
    `tmp/deep-test-scheduler-direct-${profile}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`
  )

  if (!['registry', 'write', 'site', 'catalog', 'access', 'integrity'].includes(profile)) {
    throw new Error(
      `Unsupported --profile "${profile}" (use registry|write|site|catalog|access|integrity)`
    )
  }

  const jwk = JSON.parse(fs.readFileSync(walletPath, 'utf8'))
  const secrets = loadSecrets(secretsPath)
  const executionMode = resolveExecutionMode(process.argv, process.env)

  let sendPayloads = []
  let signUrl = null
  if (profile === 'write') {
    signUrl =
      cleanEnv(arg('sign-url', process.env.WORKER_SIGN_URL)) ||
      'https://blackcat-inbox-production.vitek-pasek.workers.dev/sign'
    const token =
      cleanEnv(arg('worker-auth-token', process.env.WORKER_AUTH_TOKEN)) ||
      cleanEnv(secrets.WORKER_AUTH_TOKEN)
    if (!token) {
      throw new Error('WORKER_AUTH_TOKEN is required for --profile write')
    }
    const commands = writeMessages()
    for (const cmd of commands) {
      const signed = await signWriteCommand(cmd, signUrl, token)
      sendPayloads.push({
        envelopeAction: 'Write-Command',
        action: cmd.action,
        requestId: cmd.requestId,
        data: JSON.stringify(signed),
        detachedMessage: detachedWriteMessage(signed)
      })
    }
    fs.writeFileSync('tmp/writecmd-signed-live.json', JSON.stringify(sendPayloads, null, 2))
  } else if (profile === 'registry') {
    const authSignatureSecret =
      cleanEnv(arg('auth-signature-secret', process.env.AUTH_SIGNATURE_SECRET)) ||
      cleanEnv(secrets.AUTH_SIGNATURE_SECRET)
    sendPayloads = registryMessages({ authSignatureSecret })
  } else {
    const authSignatureSecret =
      cleanEnv(arg('auth-signature-secret', process.env.AUTH_SIGNATURE_SECRET)) ||
      cleanEnv(secrets.AUTH_SIGNATURE_SECRET)
    if (profile === 'site') sendPayloads = siteMessages({ authSignatureSecret })
    else if (profile === 'catalog') sendPayloads = catalogMessages({ authSignatureSecret })
    else if (profile === 'access') sendPayloads = accessMessages({ authSignatureSecret })
    else sendPayloads = integrityMessages({ authSignatureSecret })
  }

  const report = {
    generatedAt: new Date().toISOString(),
    pid,
    urls,
    variant,
    profile,
    signUrl,
    commandActions: sendPayloads.map((s) => s.action),
    execution: {
      mode: executionMode,
      enforced: executionMode === 'strict'
    },
    steps: []
  }

  for (const baseUrl of urls) {
    const step = {
      baseUrl,
      sends: [],
      slotCurrent: null,
      computeChecks: [],
      assertions: []
    }
    for (const payload of sendPayloads) {
      step.sends.push(
        await sendSchedulerMessage({
          baseUrl,
          pid,
          jwk,
          envelopeAction: payload.envelopeAction,
          action: payload.action,
          requestId: payload.requestId,
          data: payload.data,
          variant
        })
      )
    }

    step.slotCurrent = await probeSlotCurrent(baseUrl, pid)

    for (const send of step.sends) {
      const slot = Number(send.headers.slot || send.parsedSlot || '')
      if (!Number.isFinite(slot)) continue
      try {
        const compute = await probeCompute(baseUrl, pid, slot, fetchWithTimeout)
        step.computeChecks.push(compute)
        send.compute = compute
      } catch (e) {
        const failedCompute = {
          url: `${baseUrl}/${pid}~process@1.0/compute=${slot}`,
          status: 'error',
          error: e?.message || String(e)
        }
        step.computeChecks.push(failedCompute)
        send.compute = failedCompute
      }
    }

    for (const send of step.sends) {
      send.assertion = {
        action: send.action,
        requestId: send.requestId || null,
        ...buildExecutionAssertion({
          mode: executionMode,
          transportOk: send.ok === true,
          computeProbe: send.compute
        })
      }
      step.assertions.push(send.assertion)
    }
    step.summary = {
      mode: executionMode,
      enforced: executionMode === 'strict',
      assertions: summarizeAssertions(step.assertions),
      failedAssertions: step.assertions
        .filter((assertion) => assertion.passed === false)
        .map((assertion) => ({
          action: assertion.action || 'unknown',
          requestId: assertion.requestId || null,
          failures: assertion.failures || []
        }))
    }
    report.steps.push(step)
  }

  const allAssertions = report.steps.flatMap((step) => step.assertions || [])
  report.summary = {
    mode: executionMode,
    enforced: executionMode === 'strict',
    assertions: summarizeAssertions(allAssertions),
    steps: report.steps.length,
    actionAssertions: allAssertions.length,
    failedAssertions: report.steps.flatMap((step) => step.summary.failedAssertions || [])
  }

  fs.writeFileSync(out, JSON.stringify(report, null, 2))

  console.log(`saved=${out}`)
  for (const step of report.steps) {
    console.log(`\n[${step.baseUrl}]`)
    for (const send of step.sends) {
      const assertionLabel = send.assertion ? ` assert=${formatAssertionStatus(send.assertion)}` : ''
      console.log(
        `${send.action}: status=${send.status} slot=${send.headers.slot || send.parsedSlot || ''} envelope=${send.envelopeAction || ''} action_echo=${send.parsedAction || ''}${assertionLabel}`
      )
    }
    console.log(`slot/current: status=${step.slotCurrent.status} body=${step.slotCurrent.body}`)
    for (const cmp of step.computeChecks) {
      const p = cmp.parsed || {}
      console.log(
        `compute: status=${cmp.status} slot=${p.atSlot ?? ''} output=${p.output ?? ''} messages=${p.messagesCount ?? ''} error=${p.hasError === true ? 'yes' : p.hasError === false ? 'no' : ''}`
      )
    }
    console.log(
      `assertions: mode=${step.summary.mode} passed=${step.summary.assertions.passed} failed=${step.summary.assertions.failed} runtime_ok=${step.summary.assertions.runtimeOk} transport_ok=${step.summary.assertions.transportOk}`
    )
  }

  console.log(
    `assertion_summary: mode=${report.summary.mode} enforced=${report.summary.enforced ? 'yes' : 'no'} passed=${report.summary.assertions.passed} failed=${report.summary.assertions.failed} runtime_ok=${report.summary.assertions.runtimeOk} transport_ok=${report.summary.assertions.transportOk}`
  )

  if (executionMode === 'strict' && report.summary.assertions.failed > 0) {
    throw new Error(`execution_assertions_failed:${report.summary.assertions.failed}`)
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err)
    process.exit(1)
  })
