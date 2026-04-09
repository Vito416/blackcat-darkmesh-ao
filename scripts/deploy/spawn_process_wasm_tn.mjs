import fs from 'node:fs'
import { resolve } from 'node:path'
import { connect, createSigner } from '@permaweb/aoconnect'

const EXT_DEFAULTS = {
  moduleFormat: 'wasm64-unknown-emscripten-draft_2024_02_15',
  memoryLimit: '1-gb',
  computeLimit: '9000000000000',
  aosVersion: '2.0.6'
}

function clean(value) {
  if (value === undefined || value === null) return undefined
  const out = String(value).trim()
  return out === '' ? undefined : out
}

function parseBoolFlag(value, defaultValue) {
  const v = clean(value)
  if (v === undefined) return defaultValue
  if (v === '1' || v.toLowerCase() === 'true') return true
  if (v === '0' || v.toLowerCase() === 'false') return false
  return defaultValue
}

function parseArgs(argv) {
  const args = {
    module: clean(process.env.AO_MODULE),
    name: clean(process.env.AO_NAME) || 'blackcat-ao',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    url:
      clean(process.env.HB_URL) ||
      clean(process.env.HYPERBEAM_URL) ||
      clean(process.env.AO_URL) ||
      'https://push.forward.computer',
    scheduler:
      clean(process.env.HB_SCHEDULER) ||
      clean(process.env.HYPERBEAM_SCHEDULER) ||
      clean(process.env.AO_SCHEDULER) ||
      'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo',
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
    mode: clean(process.env.AO_SPAWN_MODE) || 'extended',
    waitModule: parseBoolFlag(process.env.AO_WAIT_MODULE, true),
    waitModuleTimeoutMs: Number(clean(process.env.AO_WAIT_MODULE_TIMEOUT_MS) || '300000'),
    waitModuleIntervalMs: Number(clean(process.env.AO_WAIT_MODULE_INTERVAL_MS) || '5000'),
    moduleFormat: clean(process.env.AO_MODULE_FORMAT),
    memoryLimit: clean(process.env.AO_MEMORY_LIMIT),
    computeLimit: clean(process.env.AO_COMPUTE_LIMIT),
    aosVersion: clean(process.env.AO_AOS_VERSION),
    authRequireSignature:
      clean(process.env.AUTH_REQUIRE_SIGNATURE) || clean(process.env.WRITE_REQUIRE_SIGNATURE),
    authRequireNonce: clean(process.env.AUTH_REQUIRE_NONCE) || clean(process.env.WRITE_REQUIRE_NONCE),
    authRequireTimestamp:
      clean(process.env.AUTH_REQUIRE_TIMESTAMP) || clean(process.env.WRITE_REQUIRE_TIMESTAMP),
    authSignatureType:
      clean(process.env.AUTH_SIGNATURE_TYPE) ||
      clean(process.env.AUTH_SIG_TYPE) ||
      clean(process.env.WRITE_SIG_TYPE),
    authSignaturePublic:
      clean(process.env.AUTH_SIGNATURE_PUBLIC) ||
      clean(process.env.AUTH_SIG_PUBLIC) ||
      clean(process.env.WRITE_SIG_PUBLIC),
    authSignaturePublics:
      clean(process.env.AUTH_SIGNATURE_PUBLICS) ||
      clean(process.env.AUTH_SIG_PUBLICS) ||
      clean(process.env.WRITE_SIG_PUBLICS),
    authSignatureSecret:
      clean(process.env.AUTH_SIGNATURE_SECRET) ||
      clean(process.env.AUTH_SIG_SECRET) ||
      clean(process.env.WRITE_SIG_SECRET),
    data: clean(process.env.AO_SPAWN_DATA) || '1984',
    out: clean(process.env.AO_PID_OUT)
  }
  const extraTags = []

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--module') args.module = clean(argv[++i]) || args.module
    else if (arg === '--name') args.name = clean(argv[++i]) || args.name
    else if (arg === '--wallet') args.wallet = clean(argv[++i]) || args.wallet
    else if (arg === '--url') args.url = clean(argv[++i]) || args.url
    else if (arg === '--scheduler') args.scheduler = clean(argv[++i]) || args.scheduler
    else if (arg === '--variant') args.variant = clean(argv[++i]) || args.variant
    else if (arg === '--mode') args.mode = clean(argv[++i]) || args.mode
    else if (arg === '--wait-module') args.waitModule = parseBoolFlag(argv[++i], args.waitModule)
    else if (arg === '--wait-module-timeout-ms') {
      args.waitModuleTimeoutMs = Number(clean(argv[++i]) || args.waitModuleTimeoutMs)
    }
    else if (arg === '--wait-module-interval-ms') {
      args.waitModuleIntervalMs = Number(clean(argv[++i]) || args.waitModuleIntervalMs)
    }
    else if (arg === '--module-format') args.moduleFormat = clean(argv[++i]) || args.moduleFormat
    else if (arg === '--memory-limit') args.memoryLimit = clean(argv[++i]) || args.memoryLimit
    else if (arg === '--compute-limit') args.computeLimit = clean(argv[++i]) || args.computeLimit
    else if (arg === '--aos-version') args.aosVersion = clean(argv[++i]) || args.aosVersion
    else if (arg === '--auth-require-signature') {
      args.authRequireSignature = clean(argv[++i]) || args.authRequireSignature
    }
    else if (arg === '--auth-require-nonce') {
      args.authRequireNonce = clean(argv[++i]) || args.authRequireNonce
    }
    else if (arg === '--auth-require-timestamp') {
      args.authRequireTimestamp = clean(argv[++i]) || args.authRequireTimestamp
    }
    else if (arg === '--auth-signature-type') {
      args.authSignatureType = clean(argv[++i]) || args.authSignatureType
    }
    else if (arg === '--auth-signature-public') {
      args.authSignaturePublic = clean(argv[++i]) || args.authSignaturePublic
    }
    else if (arg === '--auth-signature-publics') {
      args.authSignaturePublics = clean(argv[++i]) || args.authSignaturePublics
    }
    else if (arg === '--auth-signature-secret') {
      args.authSignatureSecret = clean(argv[++i]) || args.authSignatureSecret
    }
    else if (arg === '--data') args.data = clean(argv[++i]) || args.data
    else if (arg === '--out') args.out = clean(argv[++i]) || args.out
    else if (arg === '--tag') {
      const pair = clean(argv[++i])
      if (!pair || !pair.includes('=')) throw new Error('--tag expects key=value')
      const idx = pair.indexOf('=')
      extraTags.push({ name: pair.slice(0, idx), value: pair.slice(idx + 1) })
    } else if (arg === '-h' || arg === '--help') {
      console.log(
        'Usage: node scripts/deploy/spawn_process_wasm_tn.mjs --module <TX> --name blackcat-ao-registry --url https://push.forward.computer'
      )
      process.exit(0)
    } else {
      throw new Error(`Unknown arg: ${arg}`)
    }
  }

  if (!args.module) throw new Error('Missing AO module tx. Provide --module or AO_MODULE.')
  if (!['auto', 'minimal', 'extended'].includes(args.mode)) {
    throw new Error(`Invalid --mode "${args.mode}". Use auto|minimal|extended.`)
  }
  return { args, extraTags }
}

async function sleep(ms) {
  return new Promise((resolveFn) => setTimeout(resolveFn, ms))
}

async function waitForModuleReady({ url, moduleTx, timeoutMs, intervalMs }) {
  const endpoint = `${url.replace(/\/$/, '')}/${moduleTx}~module@1.0?accept-bundle=true`
  const deadline = Date.now() + timeoutMs
  let lastStatus = null
  while (Date.now() < deadline) {
    const res = await fetch(endpoint, { method: 'GET' }).catch(() => null)
    const status = res?.status ?? 0
    if (status === 200) {
      return { ok: true, endpoint, status }
    }
    lastStatus = status
    await sleep(intervalMs)
  }
  return { ok: false, endpoint, status: lastStatus ?? 0 }
}

function parsePidFromBody(body) {
  if (!body) return null
  const jsonStart = body.indexOf('{')
  if (jsonStart >= 0) {
    try {
      const parsed = JSON.parse(body.slice(jsonStart))
      return parsed?.process || parsed?.Process || parsed?.pid || parsed?.id || null
    } catch {
      // no-op
    }
  }
  const m = body.match(/process:\s*([A-Za-z0-9_-]{43,64})/i)
  return m ? m[1] : null
}

async function main() {
  const { args, extraTags } = parseArgs(process.argv)
  const walletPath = resolve(args.wallet)
  if (!fs.existsSync(walletPath)) throw new Error(`Wallet not found: ${walletPath}`)

  const wallet = JSON.parse(fs.readFileSync(walletPath, 'utf8'))
  const signer = createSigner(wallet)
  const ao = connect({
    MODE: 'mainnet',
    URL: args.url,
    SCHEDULER: args.scheduler,
    signer
  })

  if (args.waitModule) {
    const readiness = await waitForModuleReady({
      url: args.url,
      moduleTx: args.module,
      timeoutMs: args.waitModuleTimeoutMs,
      intervalMs: args.waitModuleIntervalMs
    })
    if (!readiness.ok) {
      throw new Error(
        `module_not_ready: status=${readiness.status} endpoint=${readiness.endpoint} (disable with --wait-module 0)`
      )
    }
  }

  const baseParams = {
    path: '/push',
    device: 'process@1.0',
    'scheduler-device': 'scheduler@1.0',
    'push-device': 'push@1.0',
    'execution-device': 'genesis-wasm@1.0',
    Authority: args.scheduler,
    Scheduler: args.scheduler,
    Module: args.module,
    Type: 'Process',
    Variant: args.variant,
    'Data-Protocol': 'ao',
    'Content-Type': 'application/wasm',
    'Input-Encoding': 'JSON-1',
    'Output-Encoding': 'JSON-1',
    Name: args.name,
    'accept-bundle': 'true',
    'accept-codec': 'httpsig@1.0',
    'signing-format': 'ans104',
    data: args.data
  }

  const authTags = [
    ['AUTH_REQUIRE_SIGNATURE', args.authRequireSignature],
    ['AUTH_REQUIRE_NONCE', args.authRequireNonce],
    ['AUTH_REQUIRE_TIMESTAMP', args.authRequireTimestamp],
    ['AUTH_SIGNATURE_TYPE', args.authSignatureType],
    ['AUTH_SIGNATURE_PUBLIC', args.authSignaturePublic],
    ['AUTH_SIGNATURE_PUBLICS', args.authSignaturePublics],
    ['AUTH_SIGNATURE_SECRET', args.authSignatureSecret],
    ['WRITE_REQUIRE_SIGNATURE', args.authRequireSignature],
    ['WRITE_REQUIRE_NONCE', args.authRequireNonce],
    ['WRITE_REQUIRE_TIMESTAMP', args.authRequireTimestamp],
    ['WRITE_SIG_TYPE', args.authSignatureType],
    ['WRITE_SIG_PUBLIC', args.authSignaturePublic],
    ['WRITE_SIG_PUBLICS', args.authSignaturePublics],
    ['WRITE_SIG_SECRET', args.authSignatureSecret]
  ]
  for (const [name, value] of authTags) {
    if (value !== undefined) baseParams[name] = value
  }
  for (const tag of extraTags) baseParams[tag.name] = tag.value

  const minimalParams = { ...baseParams }
  const extendedParams = {
    ...baseParams,
    'Module-Format': args.moduleFormat || EXT_DEFAULTS.moduleFormat,
    'Memory-Limit': args.memoryLimit || EXT_DEFAULTS.memoryLimit,
    'Compute-Limit': args.computeLimit || EXT_DEFAULTS.computeLimit,
    'AOS-Version': args.aosVersion || EXT_DEFAULTS.aosVersion
  }

  const modeOrder =
    args.mode === 'minimal'
      ? ['minimal']
      : args.mode === 'extended'
        ? ['extended']
        : ['extended', 'minimal']

  const trySpawn = async (params, mode) => {
    const res = await ao.request(params)
    const body = await res.text().catch(() => '')
    const pidFromHeader = res?.headers?.get('process') || res?.headers?.get('Process')
    return {
      mode,
      res,
      body,
      pidFromHeader,
      pid: pidFromHeader || parsePidFromBody(body)
    }
  }

  let attempt = null
  for (const mode of modeOrder) {
    const params = mode === 'extended' ? extendedParams : minimalParams
    const candidate = await trySpawn(params, mode)
    attempt = candidate
    if (candidate.res.ok && candidate.pid) break
  }

  if (!attempt || !attempt.res.ok || !attempt.pid) {
    throw new Error(
      `spawn_failed: mode=${attempt?.mode || 'na'} status=${attempt?.res?.status || 'na'} pid=${attempt?.pid || 'missing'} body=${(attempt?.body || '').slice(0, 400)}`
    )
  }

  const out = {
    pid: attempt.pid,
    module: args.module,
    name: args.name,
    url: args.url,
    scheduler: args.scheduler,
    variant: args.variant,
    status: attempt.res.status,
    mode: attempt.mode,
    pidFromHeader: attempt.pidFromHeader || null
  }
  console.log(JSON.stringify(out, null, 2))
  if (args.out) fs.writeFileSync(resolve(args.out), JSON.stringify(out, null, 2))
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err)
    process.exit(1)
  })
