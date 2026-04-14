import fs from 'node:fs'
import { createData, ArweaveSigner } from 'arbundles'

function clean(value) {
  if (value === undefined || value === null) return undefined
  const out = String(value).trim()
  return out === '' ? undefined : out
}

function parseBool(value, fallback = false) {
  const normalized = clean(value)
  if (normalized === undefined) return fallback
  const lower = normalized.toLowerCase()
  if (lower === '1' || lower === 'true' || lower === 'yes' || lower === 'on') return true
  if (lower === '0' || lower === 'false' || lower === 'no' || lower === 'off') return false
  return fallback
}

function isShellPromptOutput(value) {
  if (!value || typeof value !== 'object') return false
  const record = value
  const prompt = clean(record.prompt)
  const data = clean(record.data)
  if (!prompt) return false
  if (clean(record['ao-types'])) return true
  return typeof data === 'string' && data.includes('New Message From')
}

function deriveOutputSummary(computeParsed) {
  const raw = computeParsed?.results?.raw || computeParsed?.raw || null
  const outputCandidate =
    raw?.Output ??
    raw?.output ??
    raw?.Data ??
    raw?.data ??
    computeParsed?.Output ??
    computeParsed?.output ??
    null

  let envelope = null
  let outputShape = 'empty'
  if (typeof outputCandidate === 'string') {
    outputShape = 'string'
    if (outputCandidate.trim()) {
      try {
        envelope = JSON.parse(outputCandidate)
        outputShape = 'json_string'
      } catch {
        envelope = null
      }
    }
  } else if (outputCandidate && typeof outputCandidate === 'object') {
    envelope = outputCandidate
    outputShape = 'object'
  }

  const shellOutput = isShellPromptOutput(envelope)
  const status = envelope && typeof envelope === 'object' ? clean(envelope.status) : undefined
  const code = envelope && typeof envelope === 'object' ? clean(envelope.code) : undefined
  const semanticOk = Boolean(status)

  return {
    outputShape,
    shellOutput,
    status: status || null,
    code: code || null,
    semanticOk,
    outputPreview:
      outputShape === 'string'
        ? String(outputCandidate || '').slice(0, 180)
        : JSON.stringify(envelope || {}).slice(0, 180),
  }
}

function parseArgs(argv) {
  const args = {
    pid: clean(process.env.AO_PID),
    url: clean(process.env.AO_URL) || 'https://push.forward.computer',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    action: clean(process.env.AO_ACTION) || 'GetResolverFlags',
    computeTimeoutMs: Number(clean(process.env.AO_COMPUTE_TIMEOUT_MS) || '30000'),
    strictResponse: parseBool(process.env.AO_SMOKE_STRICT_RESPONSE, false),
  }
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--pid') args.pid = clean(argv[++i]) || args.pid
    else if (arg === '--url') args.url = clean(argv[++i]) || args.url
    else if (arg === '--wallet') args.wallet = clean(argv[++i]) || args.wallet
    else if (arg === '--action') args.action = clean(argv[++i]) || args.action
    else if (arg === '--strict-response') args.strictResponse = parseBool(argv[++i], true)
    else if (arg === '--help' || arg === '-h') {
      console.log('Usage: node scripts/deploy/smoke_push_scheduler.mjs --pid <PID> --url https://push.forward.computer --action GetResolverFlags [--strict-response true]')
      process.exit(0)
    } else {
      throw new Error(`Unknown arg: ${arg}`)
    }
  }
  if (!args.pid) throw new Error('Missing --pid / AO_PID')
  return args
}

async function readTextWithTimeout(url, timeoutMs = 30000) {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(new Error(`timeout:${timeoutMs}`)), timeoutMs)
  try {
    const res = await fetch(url, { method: 'GET', signal: ctrl.signal })
    const text = await res.text().catch(() => '')
    return { ok: res.ok, status: res.status, text }
  } finally {
    clearTimeout(timer)
  }
}

async function main() {
  const args = parseArgs(process.argv)
  const wallet = JSON.parse(fs.readFileSync(args.wallet, 'utf8'))
  const signer = new ArweaveSigner(wallet)

  const ts = Math.floor(Date.now() / 1000).toString()
  const rid = `ao-smoke-${Date.now()}`
  const nonce = `nonce-${Math.random().toString(36).slice(2, 10)}`

  const tags = [
    { name: 'Action', value: args.action },
    { name: 'Request-Id', value: rid },
    { name: 'Nonce', value: nonce },
    { name: 'ts', value: ts },
    // Dummy signature to exercise process auth path. Whether this passes depends on runtime env.
    { name: 'Signature', value: '00' },
    { name: 'Content-Type', value: 'application/json' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Type', value: 'Message' },
    { name: 'Variant', value: 'ao.TN.1' },
    { name: 'accept-bundle', value: 'true' },
    { name: 'require-codec', value: 'application/json' }
  ]

  const payload = JSON.stringify({
    Action: args.action,
    'Request-Id': rid,
    Nonce: nonce,
    ts,
    Signature: '00'
  })

  const item = createData(payload, signer, { target: args.pid, tags })
  await item.sign(signer)

  const baseUrl = args.url.replace(/\/$/, '')
  const endpoint = `${baseUrl}/~scheduler@1.0/schedule?target=${args.pid}`
  const sendRes = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/ans104',
      'codec-device': 'ans104@1.0'
    },
    body: item.getRaw()
  })
  const sendText = await sendRes.text().catch(() => '')
  const slot = Number(sendRes.headers.get('slot') || '')

  if (!sendRes.ok) {
    console.log(
      JSON.stringify(
        {
          ok: false,
          phase: 'send',
          status: sendRes.status,
          body: sendText.slice(0, 400),
          endpoint
        },
        null,
        2
      )
    )
    process.exit(1)
  }

  const slotCurrent = await readTextWithTimeout(
    `${baseUrl}/${args.pid}~process@1.0/slot/current?accept-bundle=true`,
    args.computeTimeoutMs
  )
  const compute = Number.isFinite(slot)
    ? await readTextWithTimeout(
        `${baseUrl}/${args.pid}~process@1.0/compute=${slot}?accept-bundle=true&require-codec=application/json`,
        args.computeTimeoutMs
      )
    : { ok: false, status: 'na', text: 'missing_slot' }

  let computeParsed = null
  try {
    computeParsed = JSON.parse(compute.text || '')
  } catch {
    computeParsed = null
  }

  const outputSummary = computeParsed ? deriveOutputSummary(computeParsed) : null
  const strictFailure =
    args.strictResponse &&
    (!computeParsed || !outputSummary?.semanticOk || outputSummary?.shellOutput === true)

  const report = {
    ok: !strictFailure,
    action: args.action,
    endpoint,
    dataItemId: item.id,
    slot,
    strictResponse: args.strictResponse,
    send: { status: sendRes.status, body: sendText.slice(0, 240) },
    slotCurrent: { status: slotCurrent.status, body: (slotCurrent.text || '').slice(0, 120) },
    compute: {
      status: compute.status,
      body: (compute.text || '').slice(0, 500),
      parsedSummary: computeParsed
        ? {
            atSlot: computeParsed['at-slot'] ?? null,
            hasResults: Boolean(computeParsed.results || computeParsed.raw),
            hasError: Boolean(
              (computeParsed.results?.raw?.Error &&
                Object.keys(computeParsed.results.raw.Error).length > 0) ||
                (computeParsed.raw?.Error && Object.keys(computeParsed.raw.Error).length > 0)
            ),
          }
        : null,
      outputSummary,
    },
  }

  if (strictFailure) {
    report.ok = false
    report.error = 'semantic_output_check_failed'
  }

  console.log(
    JSON.stringify(report, null, 2)
  )

  if (strictFailure) {
    process.exit(1)
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err)
    process.exit(1)
  })
