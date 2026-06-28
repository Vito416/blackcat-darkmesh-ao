#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { connect, createSigner } from '@permaweb/aoconnect'

function clean(value) {
  if (value === undefined || value === null) return undefined
  const out = String(value).trim()
  return out === '' || out === 'undefined' || out === 'null' ? undefined : out
}

function argValue(argv, names, fallback) {
  const flags = Array.isArray(names) ? names : [names]
  for (const flag of flags) {
    const idx = argv.indexOf(flag)
    if (idx !== -1) {
      const next = argv[idx + 1]
      if (next !== undefined && !String(next).startsWith('--')) {
        return next
      }
      return true
    }
  }
  return fallback
}

function hasFlag(argv, names) {
  const flags = Array.isArray(names) ? names : [names]
  return flags.some((flag) => argv.includes(flag))
}

function must(value, label) {
  if (!value) throw new Error(`Missing ${label}`)
  return value
}

function readJsonFile(filePath, label) {
  const resolved = path.resolve(filePath)
  if (!fs.existsSync(resolved)) {
    throw new Error(`${label} not found: ${resolved}`)
  }
  return JSON.parse(fs.readFileSync(resolved, 'utf8'))
}

function randomId(prefix) {
  return `${prefix}-${crypto.randomBytes(6).toString('hex')}`
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
}

function unixNow() {
  return Math.floor(Date.now() / 1000)
}

function parseBool(value, label) {
  if (typeof value === 'boolean') return value
  const v = clean(value)
  if (v === undefined) return undefined
  const lower = v.toLowerCase()
  if (['1', 'true', 'yes', 'on'].includes(lower)) return true
  if (['0', 'false', 'no', 'off'].includes(lower)) return false
  throw new Error(`${label} must be boolean-like (true/false/1/0)`)
}

function parseNumber(value, label) {
  const v = clean(value)
  if (v === undefined) return undefined
  const num = Number(v)
  if (!Number.isFinite(num)) {
    throw new Error(`${label} must be numeric`)
  }
  return num
}

function parseList(value, label) {
  const v = clean(value)
  if (v === undefined) return undefined
  if (v.startsWith('[')) {
    const parsed = JSON.parse(v)
    if (!Array.isArray(parsed)) throw new Error(`${label} JSON must be an array`)
    return parsed.map((item) => String(item))
  }
  return v
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

function writeOutput(filePath, value, pretty) {
  if (!filePath) return
  const resolved = path.resolve(filePath)
  fs.mkdirSync(path.dirname(resolved), { recursive: true })
  fs.writeFileSync(resolved, JSON.stringify(value, null, pretty ? 2 : 0))
}

function parseArgs(argv) {
  const args = {
    action: clean(process.env.AO_ACTION) || 'get-root',
    pid: clean(process.env.AO_PID),
    url:
      clean(process.env.HB_URL) ||
      clean(process.env.HYPERBEAM_URL) ||
      clean(process.env.AO_URL) ||
      'http://127.0.0.1:8734',
    scheduler:
      clean(process.env.HB_SCHEDULER) ||
      clean(process.env.HYPERBEAM_SCHEDULER) ||
      clean(process.env.AO_SCHEDULER) ||
      'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
    actorRole: clean(process.env.AO_ACTOR_ROLE) || 'registry-admin',
    componentId: clean(process.env.AO_COMPONENT_ID) || 'gateway',
    requestId: clean(process.env.AO_REQUEST_ID),
    nonce: clean(process.env.AO_NONCE),
    timestamp: clean(process.env.AO_TIMESTAMP),
    schemaVersion: clean(process.env.AO_SCHEMA_VERSION) || '1.0',
    dryRun: hasFlag(argv, ['--dry-run', '--dryRun']),
    pretty: hasFlag(argv, ['--pretty']),
    out:
      clean(process.env.AO_OUT) ||
      `tmp/integrity-registry-${new Date().toISOString().replace(/[:.]/g, '-')}.json`,
    transport: clean(process.env.AO_INGRESS_MODE) || 'request',
  }

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i]
    if (token === '--help' || token === '-h') {
      args.help = true
      return args
    }
    if (!token.startsWith('--')) {
      if (!args._positionalAction) {
        args._positionalAction = token
        continue
      }
      throw new Error(`Unknown positional argument: ${token}`)
    }

    const next = argv[i + 1]
    const take = () => {
      if (next === undefined || String(next).startsWith('--')) {
        throw new Error(`${token} expects a value`)
      }
      i += 1
      return next
    }

    switch (token) {
      case '--action':
        args.action = take()
        break
      case '--pid':
        args.pid = take()
        break
      case '--url':
        args.url = take()
        break
      case '--scheduler':
        args.scheduler = take()
        break
      case '--wallet':
        args.wallet = take()
        break
      case '--variant':
        args.variant = take()
        break
      case '--actor-role':
        args.actorRole = take()
        break
      case '--component-id':
        args.componentId = take()
        break
      case '--request-id':
        args.requestId = take()
        break
      case '--nonce':
        args.nonce = take()
        break
      case '--timestamp':
        args.timestamp = take()
        break
      case '--schema-version':
        args.schemaVersion = take()
        break
      case '--transport':
        args.transport = take()
        break
      case '--out':
        args.out = take()
        break
      case '--activate':
        if (next === undefined || String(next).startsWith('--')) {
          args.activate = true
        } else {
          args.activate = take()
        }
        break
      case '--no-activate':
        args.activate = false
        break
      case '--root':
      case '--version':
      case '--uri-hash':
      case '--meta-hash':
      case '--policy-hash':
      case '--reason':
      case '--upgrade':
      case '--emergency':
      case '--reporter':
      case '--reporter-ref':
      case '--accepted-at':
      case '--merkle-root':
      case '--actor':
      case '--tenant':
      case '--payload-json':
      case '--body':
      case '--seq-from':
      case '--seq-to':
      case '--max-checkin-age-sec':
      case '--signature-refs':
      case '--paused':
        args[token.slice(2).replace(/-/g, '')] = take()
        break
      case '--data':
        args.data = take()
        break
      case '--dry-run':
      case '--pretty':
        args[token.slice(2).replace(/-/g, '')] = true
        break
      default:
        throw new Error(`Unknown arg: ${token}`)
    }
  }

  if (args._positionalAction && !clean(process.env.AO_ACTION)) {
    args.action = args._positionalAction
  }

  return args
}

function normalizeAction(action) {
  const key = clean(action) || 'get-root'
  const lowered = key.toLowerCase()
  const map = {
    publish: 'PublishTrustedRelease',
    revoke: 'RevokeTrustedRelease',
    'get-root': 'GetTrustedRoot',
    root: 'GetTrustedRoot',
    policy: 'GetIntegrityPolicy',
    authority: 'GetIntegrityAuthority',
    audit: 'GetIntegrityAuditState',
    snapshot: 'GetIntegritySnapshot',
    pause: 'SetIntegrityPolicyPause',
    'set-authority': 'SetIntegrityAuthority',
    'append-audit': 'AppendIntegrityAuditCommitment',
  }
  return map[lowered] || key
}

function buildActionPayload(action, args) {
  const payload = {}
  switch (action) {
    case 'PublishTrustedRelease': {
      payload.componentId = clean(args.componentid) || args.componentId || 'gateway'
      payload.version = must(clean(args.version), '--version')
      payload.root = must(clean(args.root), '--root')
      payload.uriHash = must(clean(args.urihash), '--uri-hash')
      payload.metaHash = must(clean(args.metahash), '--meta-hash')
      payload.policyHash = clean(args.policyhash)
      payload.activate = parseBool(args.activate, '--activate')
      if (payload.activate === undefined) payload.activate = true
      const maxAge = parseNumber(args.maxcheckinagesec, '--max-checkin-age-sec')
      if (maxAge !== undefined) payload.maxCheckInAgeSec = maxAge
      break
    }
    case 'RevokeTrustedRelease': {
      const root = clean(args.root)
      const version = clean(args.version)
      if (!root && !version) {
        throw new Error('Provide --root or --version for revoke')
      }
      if (root) payload.root = root
      if (version) payload.version = version
      payload.reason = clean(args.reason)
      break
    }
    case 'GetTrustedRoot':
      payload.componentId = clean(args.componentid) || args.componentId || 'gateway'
      break
    case 'GetIntegrityPolicy':
    case 'GetIntegrityAuthority':
    case 'GetIntegrityAuditState':
    case 'GetIntegritySnapshot':
      break
    case 'SetIntegrityPolicyPause':
      payload.paused = parseBool(must(clean(args.paused), '--paused'), '--paused')
      payload.reason = clean(args.reason)
      payload.policyHash = clean(args.policyhash)
      {
        const maxAge = parseNumber(args.maxcheckinagesec, '--max-checkin-age-sec')
        if (maxAge !== undefined) payload.maxCheckInAgeSec = maxAge
      }
      break
    case 'SetIntegrityAuthority': {
      payload.root = must(clean(args.root), '--root')
      payload.upgrade = must(clean(args.upgrade), '--upgrade')
      payload.emergency = must(clean(args.emergency), '--emergency')
      payload.reporter = must(clean(args.reporter), '--reporter')
      const refs = parseList(args.signaturerefs, '--signature-refs')
      if (refs !== undefined) payload.signatureRefs = refs
      break
    }
    case 'AppendIntegrityAuditCommitment': {
      payload.seqFrom = parseNumber(must(clean(args.seqfrom), '--seq-from'), '--seq-from')
      payload.seqTo = parseNumber(must(clean(args.seqto), '--seq-to'), '--seq-to')
      payload.merkleRoot = must(clean(args.merkleroot), '--merkle-root')
      payload.metaHash = must(clean(args.metahash), '--meta-hash')
      payload.reporterRef = must(clean(args.reporterref), '--reporter-ref')
      payload.acceptedAt = clean(args.acceptedat)
      break
    }
    default:
      throw new Error(`Unsupported integrity action: ${action}`)
  }
  return payload
}

function buildRequestEnvelope(action, args, payload) {
  const nowIso = args.timestamp || isoNow()
  const nowTs = unixNow().toString()
  const requestId = args.requestId || randomId(`req-${action.toLowerCase()}`)
  const nonce = args.nonce || randomId('nonce')
  const body = {
    Action: action,
    'Request-Id': requestId,
    Nonce: nonce,
    ts: nowTs,
    Timestamp: nowIso,
    'Actor-Role': args.actorRole,
    'Schema-Version': args.schemaVersion,
    'Component-Id': payload.componentId || args.componentId || 'gateway',
    Variant: args.variant
  }

  const params = {
    path: `/${args.pid}~process@1.0/push`,
    target: args.pid,
    data: JSON.stringify(body),
    Action: action,
    'Request-Id': requestId,
    Nonce: nonce,
    ts: nowTs,
    Timestamp: nowIso,
    'Actor-Role': args.actorRole,
    'Schema-Version': args.schemaVersion,
    'Component-Id': payload.componentId || args.componentId || 'gateway',
    Variant: args.variant,
    'Data-Protocol': 'ao',
    Type: 'Message',
    'Content-Type': 'application/json',
    'Input-Encoding': 'JSON-1',
    'Output-Encoding': 'JSON-1',
    'signing-format': 'ans104',
    'accept-bundle': 'true',
    'require-codec': 'application/json'
  }

  for (const [key, value] of Object.entries(payload)) {
    if (value === undefined || value === null) continue
    switch (key) {
      case 'componentId':
        params['Component-Id'] = value
        body['Component-Id'] = value
        break
      case 'policyHash':
        params['Policy-Hash'] = value
        body['Policy-Hash'] = value
        break
      case 'maxCheckInAgeSec':
        params['Max-CheckIn-Age-Sec'] = String(value)
        body['Max-CheckIn-Age-Sec'] = String(value)
        break
      case 'uriHash':
        params['Uri-Hash'] = value
        body['Uri-Hash'] = value
        break
      case 'metaHash':
        params['Meta-Hash'] = value
        body['Meta-Hash'] = value
        break
      case 'activePolicyHash':
        params['Policy-Hash'] = value
        body['Policy-Hash'] = value
        break
      case 'paused':
        params.Paused = String(value)
        body.Paused = String(value)
        break
      case 'reason':
        params.Reason = value
        body.Reason = value
        break
      case 'root':
        params.Root = value
        body.Root = value
        break
      case 'version':
        params.Version = value
        body.Version = value
        break
      case 'upgrade':
        params.Upgrade = value
        body.Upgrade = value
        break
      case 'emergency':
        params.Emergency = value
        body.Emergency = value
        break
      case 'reporter':
        params.Reporter = value
        body.Reporter = value
        break
      case 'signatureRefs':
        params['Signature-Refs'] = Array.isArray(value) ? value : String(value)
        body['Signature-Refs'] = Array.isArray(value) ? value : [String(value)]
        break
      case 'seqFrom':
        params['Seq-From'] = String(value)
        body['Seq-From'] = String(value)
        break
      case 'seqTo':
        params['Seq-To'] = String(value)
        body['Seq-To'] = String(value)
        break
      case 'merkleRoot':
        params['Merkle-Root'] = value
        body['Merkle-Root'] = value
        break
      case 'reporterRef':
        params['Reporter-Ref'] = value
        body['Reporter-Ref'] = value
        break
      case 'acceptedAt':
        params['Accepted-At'] = value
        body['Accepted-At'] = value
        break
      case 'activate':
        params.Activate = String(Boolean(value))
        body.Activate = String(Boolean(value))
        break
      default:
        break
    }
  }

  return { body, params }
}

async function sendIntegrityRequest(args, params) {
  const wallet = readJsonFile(args.wallet, 'wallet')
  const ao = connect({
    MODE: 'mainnet',
    URL: args.url,
    SCHEDULER: args.scheduler,
    signer: createSigner(wallet)
  })
  if (args.transport !== 'request' && args.transport !== 'auto' && args.transport !== 'push') {
    throw new Error('AO transport must be request|auto|push')
  }
  return ao.request(params)
}

async function main() {
  const args = parseArgs(process.argv)
  if (args.help) {
    console.log(`Usage: node scripts/cli/integrity_registry_cli.js --action <publish|revoke|get-root|policy|authority|audit|snapshot|pause|set-authority|append-audit> --pid <PID> [options]`)
    console.log('')
    console.log('Common options:')
    console.log('  --pid <PID>                 AO registry process id')
    console.log('  --wallet <path>             wallet.json path (default: wallet.json)')
    console.log('  --url <url>                 AO push URL (default: http://127.0.0.1:8734)')
    console.log('  --scheduler <id>            scheduler id (default: mainnet scheduler)')
    console.log('  --actor-role <role>         Actor-Role tag (default: registry-admin)')
    console.log('  --dry-run                    print the prepared request without sending')
    console.log('')
    console.log('Publish:')
    console.log('  --component-id gateway --version 1.4.0 --root <root> --uri-hash <hash> --meta-hash <hash> [--policy-hash <hash>]')
    console.log('Authority:')
    console.log('  --root <root> --upgrade <upgrade> --emergency <emergency> --reporter <reporter> [--signature-refs a,b]')
    console.log('Audit:')
    console.log('  --seq-from 1 --seq-to 9 --merkle-root <root> --meta-hash <hash> --reporter-ref <ref>')
    console.log('')
    console.log('Outputs JSON on success.')
    return
  }

  const pid = must(clean(args.pid), '--pid')
  const action = normalizeAction(args.action)
  const payload = buildActionPayload(action, args)
  const { body, params } = buildRequestEnvelope(action, { ...args, pid }, payload)

  const out = {
    action,
    pid,
    requestId: params['Request-Id'],
    nonce: params.Nonce,
    transport: args.transport,
    url: args.url,
    scheduler: args.scheduler,
    dryRun: args.dryRun === true,
    request: {
      path: params.path,
      tags: {
        Action: params.Action,
        'Request-Id': params['Request-Id'],
        Nonce: params.Nonce,
        Timestamp: params.Timestamp,
        'Actor-Role': params['Actor-Role'],
        'Schema-Version': params['Schema-Version'],
        'Component-Id': params['Component-Id']
      },
      body
    }
  }

  if (args.dryRun) {
    const text = JSON.stringify(out, null, args.pretty ? 2 : 0)
    console.log(text)
    writeOutput(args.out, out, args.pretty)
    return
  }

  let response
  try {
    response = await sendIntegrityRequest(args, params)
  } catch (error) {
    out.ok = false
    out.error = error instanceof Error ? error.message : String(error)
    const outputText = JSON.stringify(out, null, args.pretty ? 2 : 0)
    console.log(outputText)
    writeOutput(args.out, out, args.pretty)
    process.exit(1)
  }

  const responseText = await response.text().catch(() => '')
  const headers = {}
  response.headers.forEach((value, key) => {
    headers[key] = value
  })
  let parsed = null
  try {
    parsed = responseText ? JSON.parse(responseText) : null
  } catch {
    parsed = null
  }

  out.ok = response.ok
  out.status = response.status
  out.response = {
    headers,
    body: responseText,
    json: parsed
  }

  const outputText = JSON.stringify(out, null, args.pretty ? 2 : 0)
  console.log(outputText)
  writeOutput(args.out, out, args.pretty)
  if (!response.ok) {
    process.exit(1)
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(
      JSON.stringify(
        {
          ok: false,
          error: error instanceof Error ? error.message : String(error)
        },
        null,
        2
      )
    )
    process.exit(1)
  })
