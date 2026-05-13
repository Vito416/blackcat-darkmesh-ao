import fs from 'node:fs'
import { resolve } from 'node:path'
import { connect, createSigner } from '@permaweb/aoconnect'

const DEFAULT_PUBLIC_SCHEDULER = 'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo'
const DEFAULT_PUBLIC_SCHEDULER_LOCATION = 'https://push.forward.computer'

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
  const envDataFile = clean(process.env.AO_SPAWN_DATA_FILE)
  let dataFromFile = undefined
  if (envDataFile) {
    const resolvedDataPath = resolve(envDataFile)
    if (!fs.existsSync(resolvedDataPath)) {
      throw new Error(`AO_SPAWN_DATA_FILE not found: ${resolvedDataPath}`)
    }
    dataFromFile = fs.readFileSync(resolvedDataPath, 'utf8')
  }
  const args = {
    module: clean(process.env.AO_MODULE),
    name: clean(process.env.AO_NAME) || 'blackcat-ao',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    url:
      clean(process.env.HB_URL) ||
      clean(process.env.HYPERBEAM_URL) ||
      clean(process.env.AO_URL) ||
      'http://127.0.0.1:8734',
    scheduler:
      clean(process.env.HB_SCHEDULER) ||
      clean(process.env.HYPERBEAM_SCHEDULER) ||
      clean(process.env.AO_SCHEDULER),
    schedulerLocation:
      clean(process.env.HB_SCHEDULER_LOCATION) ||
      clean(process.env.HYPERBEAM_SCHEDULER_LOCATION) ||
      clean(process.env.AO_SCHEDULER_LOCATION),
    productionScheduler: parseBoolFlag(
      process.env.AO_PRODUCTION_SCHEDULER || process.env.AO_PROD_SCHEDULER,
      false
    ),
    enforceSchedulerParity: parseBoolFlag(
      process.env.AO_ENFORCE_SCHEDULER_PARITY,
      true
    ),
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
    mode: clean(process.env.AO_SPAWN_MODE) || 'extended',
    waitModule: parseBoolFlag(process.env.AO_WAIT_MODULE, true),
    waitModuleTimeoutMs: Number(clean(process.env.AO_WAIT_MODULE_TIMEOUT_MS) || '300000'),
    waitModuleIntervalMs: Number(clean(process.env.AO_WAIT_MODULE_INTERVAL_MS) || '5000'),
    moduleFormat: clean(process.env.AO_MODULE_FORMAT),
    executionDevice:
      clean(process.env.AO_EXECUTION_DEVICE) || clean(process.env.AO_PROCESS_EXECUTION_DEVICE),
    contentType: clean(process.env.AO_CONTENT_TYPE) || clean(process.env.AO_PROCESS_CONTENT_TYPE),
    inferModuleProfile: parseBoolFlag(process.env.AO_INFER_MODULE_PROFILE, true),
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
    spawnPath: clean(process.env.AO_SPAWN_PATH),
    data: dataFromFile ?? clean(process.env.AO_SPAWN_DATA) ?? '1984',
    dataFile: envDataFile ? resolve(envDataFile) : undefined,
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
    else if (arg === '--scheduler-location') {
      args.schedulerLocation = clean(argv[++i]) || args.schedulerLocation
    }
    else if (arg === '--production-scheduler') {
      args.productionScheduler = parseBoolFlag(argv[++i], args.productionScheduler)
    }
    else if (arg === '--enforce-scheduler-parity') {
      args.enforceSchedulerParity = parseBoolFlag(argv[++i], args.enforceSchedulerParity)
    }
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
    else if (arg === '--execution-device') {
      args.executionDevice = clean(argv[++i]) || args.executionDevice
    }
    else if (arg === '--content-type') args.contentType = clean(argv[++i]) || args.contentType
    else if (arg === '--infer-module-profile') {
      args.inferModuleProfile = parseBoolFlag(argv[++i], args.inferModuleProfile)
    }
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
    else if (arg === '--spawn-path') args.spawnPath = clean(argv[++i]) || args.spawnPath
    else if (arg === '--data') args.data = clean(argv[++i]) || args.data
    else if (arg === '--data-file') {
      const dataPath = clean(argv[++i])
      if (!dataPath) throw new Error('--data-file requires a path')
      const resolvedDataPath = resolve(dataPath)
      if (!fs.existsSync(resolvedDataPath)) {
        throw new Error(`Data file not found: ${resolvedDataPath}`)
      }
      args.dataFile = resolvedDataPath
      args.data = fs.readFileSync(resolvedDataPath, 'utf8')
    }
    else if (arg === '--out') args.out = clean(argv[++i]) || args.out
    else if (arg === '--tag') {
      const pair = clean(argv[++i])
      if (!pair || !pair.includes('=')) throw new Error('--tag expects key=value')
      const idx = pair.indexOf('=')
      extraTags.push({ name: pair.slice(0, idx), value: pair.slice(idx + 1) })
    } else if (arg === '-h' || arg === '--help') {
      console.log(
        'Usage: node scripts/deploy/spawn_process_wasm_tn.mjs --module <TX> --name blackcat-ao-registry --url http://127.0.0.1:8734 [--data-file dist/resolver/process.lua] [--spawn-path /push] [--scheduler-location https://write.darkmesh.fun] [--production-scheduler 1] [--enforce-scheduler-parity 1] [--execution-device genesis-wasm@1.0|lua@5.3a] [--content-type application/wasm|text/lua]'
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

function normalizeSpawnPath(value) {
  const v = clean(value)
  if (!v) return undefined
  return v.startsWith('/') ? v : `/${v}`
}

function resolveSpawnPaths({ url, explicitPath }) {
  const manual = normalizeSpawnPath(explicitPath)
  if (manual) return [manual]
  try {
    const parsed = new URL(url)
    const pathname = (parsed.pathname || '/').replace(/\/+$/, '') || '/'
    if (pathname.includes('~process@1.0')) return ['/push']
  } catch {
    // no-op
  }
  // Generic resilient order:
  // - `/push` is canonical.
  // - some ingress/router profiles require explicit process route.
  return ['/push', '/~process@1.0/push']
}

function resolveModuleProbeBaseUrl(url) {
  const raw = clean(url) || ''
  const fallback = raw
    .replace(/\/+$/, '')
    .replace(/\/~process@1\.0$/, '')
    .replace(/\/push$/, '')

  try {
    const parsed = new URL(raw)
    let pathname = (parsed.pathname || '/').replace(/\/+$/, '') || '/'
    if (pathname.endsWith('/~process@1.0')) {
      pathname = pathname.replace(/\/~process@1\.0$/, '') || '/'
    }
    if (pathname.endsWith('/push')) {
      pathname = pathname.replace(/\/push$/, '') || '/'
    }
    parsed.pathname = pathname
    return parsed.toString().replace(/\/$/, '')
  } catch {
    return fallback || raw
  }
}


function resolveSchedulerLocation(url) {
  try {
    const parsed = new URL(url)
    let pathname = (parsed.pathname || '/').replace(/\/+$/, '') || '/'
    if (pathname.endsWith('/~process@1.0')) {
      pathname = pathname.replace(/\/~process@1\.0$/, '') || '/'
    }
    if (pathname.endsWith('/push')) {
      pathname = pathname.replace(/\/push$/, '') || '/'
    }
    parsed.pathname = pathname
    parsed.search = ''
    parsed.hash = ''
    return parsed.toString().replace(/\/$/, '')
  } catch {
    return undefined
  }
}

function isLocalOrPrivateHost(hostname) {
  const host = String(hostname || '').toLowerCase().trim()
  if (!host) return true
  if (
    host === 'localhost' ||
    host === '::1' ||
    host === '[::1]' ||
    host.endsWith('.local') ||
    host.endsWith('.internal')
  ) {
    return true
  }
  if (/^127\./.test(host)) return true
  if (/^10\./.test(host)) return true
  if (/^192\.168\./.test(host)) return true
  if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(host)) return true
  return false
}

function assertPublicSchedulerLocation(location) {
  const normalized = clean(location)
  if (!normalized) {
    throw new Error(
      'production_scheduler_requires_public_scheduler_location: missing --scheduler-location (or set AO_SCHEDULER_LOCATION)'
    )
  }

  let parsed
  try {
    parsed = new URL(normalized)
  } catch {
    throw new Error(
      `production_scheduler_requires_public_scheduler_location: invalid URL "${normalized}"`
    )
  }

  if (!['https:', 'http:'].includes(parsed.protocol)) {
    throw new Error(
      `production_scheduler_requires_public_scheduler_location: unsupported protocol "${parsed.protocol}"`
    )
  }
  if (isLocalOrPrivateHost(parsed.hostname)) {
    throw new Error(
      `production_scheduler_requires_public_scheduler_location: "${normalized}" resolves to local/private host`
    )
  }
}

async function fetchSchedulerAddressFromMeta(location) {
  const normalized = clean(location)
  if (!normalized) return null
  const endpoint = `${normalized.replace(/\/$/, '')}/~meta@1.0/info/address`
  const res = await fetch(endpoint, { method: 'GET' }).catch(() => null)
  if (!res || !res.ok) return null
  const body = clean(await res.text().catch(() => ''))
  if (!body) return null
  if (!/^[A-Za-z0-9_-]{43,64}$/.test(body)) return null
  return body
}

async function sleep(ms) {
  return new Promise((resolveFn) => setTimeout(resolveFn, ms))
}

async function waitForModuleReady({ url, moduleTx, timeoutMs, intervalMs }) {
  const probeBaseUrl = resolveModuleProbeBaseUrl(url)
  const endpoint = `${probeBaseUrl.replace(/\/$/, '')}/${moduleTx}~module@1.0?accept-bundle=true`
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
      return (
        parsed?.process ||
        parsed?.Process ||
        parsed?.pid ||
        parsed?.PID ||
        parsed?.['process-id'] ||
        parsed?.processId ||
        null
      )
    } catch {
      // no-op
    }
  }
  const m =
    body.match(/process(?:-id)?["'\s:=]+([A-Za-z0-9_-]{43,64})/i) ||
    body.match(/pid["'\s:=]+([A-Za-z0-9_-]{43,64})/i)
  return m ? m[1] : null
}

function getTagValue(tags, name) {
  const wanted = String(name || '').toLowerCase()
  for (const tag of tags || []) {
    const tagName = clean(tag?.name)
    if (!tagName) continue
    if (tagName.toLowerCase() === wanted) return clean(tag?.value)
  }
  return undefined
}

async function fetchModuleMetadata(moduleTx) {
  const query = {
    query:
      'query($ids:[ID!]){transactions(ids:$ids){edges{node{id tags{name value}}}}}',
    variables: { ids: [moduleTx] }
  }

  try {
    const res = await fetch('https://arweave.net/graphql', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(query)
    })
    if (!res.ok) return null
    const payload = await res.json().catch(() => null)
    const node = payload?.data?.transactions?.edges?.[0]?.node
    if (!node) return null
    const tags = Array.isArray(node.tags) ? node.tags : []
    return {
      moduleFormat: getTagValue(tags, 'Module-Format'),
      contentType: getTagValue(tags, 'Content-Type'),
      executionDevice:
        getTagValue(tags, 'Execution-Device') || getTagValue(tags, 'execution-device')
    }
  } catch {
    return null
  }
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

  const moduleMeta = args.inferModuleProfile ? await fetchModuleMetadata(args.module) : null
  const schedulerLocation =
    args.schedulerLocation ||
    resolveSchedulerLocation(args.url) ||
    (args.productionScheduler ? DEFAULT_PUBLIC_SCHEDULER_LOCATION : undefined)

  if (args.productionScheduler) {
    assertPublicSchedulerLocation(schedulerLocation)
  }
  const schedulerFromMeta = await fetchSchedulerAddressFromMeta(schedulerLocation)
  const scheduler = args.scheduler || schedulerFromMeta || DEFAULT_PUBLIC_SCHEDULER

  if (
    args.enforceSchedulerParity &&
    schedulerFromMeta &&
    scheduler !== schedulerFromMeta
  ) {
    throw new Error(
      `scheduler_url_parity_mismatch: scheduler=${scheduler} but ${schedulerLocation}/~meta@1.0/info/address=${schedulerFromMeta}`
    )
  }
  const inferredModuleFormat = args.moduleFormat || moduleMeta?.moduleFormat
  const inferredContentType =
    args.contentType ||
    moduleMeta?.contentType ||
    (inferredModuleFormat && inferredModuleFormat.toLowerCase() === 'lua'
      ? 'text/lua'
      : 'application/wasm')
  const inferredExecutionDevice =
    args.executionDevice ||
    moduleMeta?.executionDevice ||
    (inferredContentType === 'text/lua' ? 'lua@5.3a' : 'genesis-wasm@1.0')
  const isWasmProfile =
    inferredExecutionDevice === 'genesis-wasm@1.0' ||
    inferredContentType === 'application/wasm' ||
    (inferredModuleFormat || '').toLowerCase().startsWith('wasm')

  const baseParams = {
    device: 'process@1.0',
    'scheduler-device': 'scheduler@1.0',
    'push-device': 'push@1.0',
    'execution-device': inferredExecutionDevice,
    Authority: scheduler,
    Scheduler: scheduler,
    'Scheduler-Location': schedulerLocation,
    Module: args.module,
    Type: 'Process',
    Variant: args.variant,
    'Data-Protocol': 'ao',
    'Content-Type': inferredContentType,
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
  const extendedParams = isWasmProfile
    ? {
        ...baseParams,
        'Module-Format': inferredModuleFormat || EXT_DEFAULTS.moduleFormat,
        'Memory-Limit': args.memoryLimit || EXT_DEFAULTS.memoryLimit,
        'Compute-Limit': args.computeLimit || EXT_DEFAULTS.computeLimit,
        'AOS-Version': args.aosVersion || EXT_DEFAULTS.aosVersion
      }
    : { ...baseParams }

  const modeOrder =
    args.mode === 'minimal'
      ? ['minimal']
      : args.mode === 'extended'
        ? ['extended']
        : ['extended', 'minimal']

  const trySpawn = async (params, mode, path) => {
    const res = await ao.request(params)
    const body = await res.text().catch(() => '')
    const pidFromHeader = res?.headers?.get('process') || res?.headers?.get('Process')
    return {
      mode,
      path,
      res,
      body,
      pidFromHeader,
      pid: pidFromHeader || parsePidFromBody(body)
    }
  }

  let attempt = null
  const spawnPaths = resolveSpawnPaths({ url: args.url, explicitPath: args.spawnPath })
  for (const path of spawnPaths) {
    for (const mode of modeOrder) {
      const base = mode === 'extended' ? extendedParams : minimalParams
      const candidate = await trySpawn({ ...base, path }, mode, path)
      attempt = candidate
      if (candidate.res.ok && candidate.pid) break
    }
    if (attempt?.res?.ok && attempt?.pid) break
  }

  if (!attempt || !attempt.res.ok || !attempt.pid) {
    throw new Error(
      `spawn_failed: path=${attempt?.path || 'na'} mode=${attempt?.mode || 'na'} status=${attempt?.res?.status || 'na'} pid=${attempt?.pid || 'missing'} body=${(attempt?.body || '').slice(0, 400)}`
    )
  }

  const out = {
    pid: attempt.pid,
    module: args.module,
    name: args.name,
    url: args.url,
    scheduler,
    schedulerInput: args.scheduler || null,
    schedulerResolved: scheduler,
    schedulerFromMeta: schedulerFromMeta || null,
    schedulerLocation,
    productionScheduler: args.productionScheduler,
    spawnPath: attempt.path,
    variant: args.variant,
    executionDevice: inferredExecutionDevice,
    contentType: inferredContentType,
    moduleFormat: inferredModuleFormat || null,
    wasmProfile: isWasmProfile,
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
