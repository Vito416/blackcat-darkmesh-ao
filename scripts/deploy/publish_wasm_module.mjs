import fs from 'node:fs'
import { basename, resolve } from 'node:path'
import Arweave from 'arweave'

function clean(value) {
  if (value === undefined || value === null) return undefined
  const out = String(value).trim()
  return out === '' ? undefined : out
}

function parseArgs(argv) {
  const args = {
    wasm: clean(process.env.AO_WASM) || clean(process.env.WASM_PATH) || 'dist/registry/process.wasm',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    host: clean(process.env.AR_HOST) || 'arweave.net',
    protocol: clean(process.env.AR_PROTOCOL) || 'https',
    port: Number(clean(process.env.AR_PORT) || '443'),
    name: clean(process.env.AO_NAME),
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
    moduleFormat:
      clean(process.env.AO_MODULE_FORMAT) || 'wasm64-unknown-emscripten-draft_2024_02_15',
    memoryLimit: clean(process.env.AO_MEMORY_LIMIT) || '1-gb',
    computeLimit: clean(process.env.AO_COMPUTE_LIMIT) || '9000000000000',
    aosVersion: clean(process.env.AOS_VERSION) || '2.0.6',
    out: clean(process.env.AO_MODULE_OUT)
  }
  const extraTags = []
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--wasm') args.wasm = clean(argv[++i]) || args.wasm
    else if (arg === '--wallet') args.wallet = clean(argv[++i]) || args.wallet
    else if (arg === '--name') args.name = clean(argv[++i]) || args.name
    else if (arg === '--variant') args.variant = clean(argv[++i]) || args.variant
    else if (arg === '--module-format') args.moduleFormat = clean(argv[++i]) || args.moduleFormat
    else if (arg === '--memory-limit') args.memoryLimit = clean(argv[++i]) || args.memoryLimit
    else if (arg === '--compute-limit') args.computeLimit = clean(argv[++i]) || args.computeLimit
    else if (arg === '--aos-version') args.aosVersion = clean(argv[++i]) || args.aosVersion
    else if (arg === '--host') args.host = clean(argv[++i]) || args.host
    else if (arg === '--protocol') args.protocol = clean(argv[++i]) || args.protocol
    else if (arg === '--port') args.port = Number(clean(argv[++i]) || args.port)
    else if (arg === '--out') args.out = clean(argv[++i]) || args.out
    else if (arg === '--tag') {
      const pair = clean(argv[++i])
      if (!pair || !pair.includes('=')) throw new Error('--tag expects key=value')
      const idx = pair.indexOf('=')
      extraTags.push([pair.slice(0, idx), pair.slice(idx + 1)])
    } else if (arg === '-h' || arg === '--help') {
      console.log(
        'Usage: node scripts/deploy/publish_wasm_module.mjs --wasm dist/registry/process.wasm --name blackcat-ao-registry'
      )
      process.exit(0)
    } else {
      throw new Error(`Unknown arg: ${arg}`)
    }
  }
  if (!args.name) {
    const base = basename(args.wasm, '.wasm').replace(/process$/, 'process')
    args.name = `blackcat-ao-${base.replace(/^dist\//, '').replace(/\//g, '-')}`
  }
  return { args, extraTags }
}

async function main() {
  const { args, extraTags } = parseArgs(process.argv)
  const wasmPath = resolve(args.wasm)
  const walletPath = resolve(args.wallet)

  if (!fs.existsSync(wasmPath)) throw new Error(`WASM not found: ${wasmPath}`)
  if (!fs.existsSync(walletPath)) throw new Error(`Wallet not found: ${walletPath}`)

  const wallet = JSON.parse(fs.readFileSync(walletPath, 'utf8'))
  const data = fs.readFileSync(wasmPath)

  const arweave = Arweave.init({
    host: args.host,
    port: args.port,
    protocol: args.protocol
  })

  const tags = [
    ['Content-Type', 'application/wasm'],
    ['Module-Format', args.moduleFormat],
    ['Variant', args.variant],
    ['Data-Protocol', 'ao'],
    ['Input-Encoding', 'JSON-1'],
    ['Output-Encoding', 'JSON-1'],
    ['Memory-Limit', args.memoryLimit],
    ['Compute-Limit', args.computeLimit],
    ['AOS-Version', args.aosVersion],
    ['Type', 'Module'],
    ['Name', args.name],
    ['signing-format', 'ans104'],
    ['accept-bundle', 'true'],
    ['accept-codec', 'httpsig@1.0'],
    ...extraTags
  ]

  const tx = await arweave.createTransaction({ data }, wallet)
  for (const [name, value] of tags) {
    tx.addTag(name, value)
  }
  await arweave.transactions.sign(tx, wallet)
  const res = await arweave.transactions.post(tx)

  const out = {
    wasm: args.wasm,
    name: args.name,
    tx: tx.id,
    status: res.status,
    variant: args.variant,
    moduleFormat: args.moduleFormat
  }
  console.log(JSON.stringify(out, null, 2))
  if (args.out) {
    fs.writeFileSync(resolve(args.out), JSON.stringify(out, null, 2))
  }
  if (![200, 202].includes(res.status)) process.exit(1)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
