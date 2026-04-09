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
    bundle: clean(process.env.AO_BUNDLE) || clean(process.env.BUNDLE) || 'dist/registry-bundle.lua',
    wallet: clean(process.env.WALLET) || clean(process.env.WALLET_PATH) || 'wallet.json',
    host: clean(process.env.AR_HOST) || 'arweave.net',
    protocol: clean(process.env.AR_PROTOCOL) || 'https',
    port: Number(clean(process.env.AR_PORT) || '443'),
    name: clean(process.env.AO_NAME),
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
    out: clean(process.env.AO_MODULE_OUT)
  }
  const extraTags = []
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--bundle') args.bundle = clean(argv[++i]) || args.bundle
    else if (arg === '--wallet') args.wallet = clean(argv[++i]) || args.wallet
    else if (arg === '--name') args.name = clean(argv[++i]) || args.name
    else if (arg === '--variant') args.variant = clean(argv[++i]) || args.variant
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
      console.log('Usage: node scripts/deploy/publish_lua_module.mjs --bundle dist/registry-bundle.lua --name blackcat-ao-registry')
      process.exit(0)
    } else {
      throw new Error(`Unknown arg: ${arg}`)
    }
  }
  if (!args.name) {
    args.name = `blackcat-ao-${basename(args.bundle, '.lua').replace(/-bundle$/, '')}`
  }
  return { args, extraTags }
}

async function main() {
  const { args, extraTags } = parseArgs(process.argv)
  const bundlePath = resolve(args.bundle)
  const walletPath = resolve(args.wallet)

  if (!fs.existsSync(bundlePath)) throw new Error(`Bundle not found: ${bundlePath}`)
  if (!fs.existsSync(walletPath)) throw new Error(`Wallet not found: ${walletPath}`)

  const wallet = JSON.parse(fs.readFileSync(walletPath, 'utf8'))
  const data = fs.readFileSync(bundlePath)

  const arweave = Arweave.init({
    host: args.host,
    port: args.port,
    protocol: args.protocol
  })

  const tags = [
    ['Content-Type', 'text/lua'],
    ['Module-Format', 'lua'],
    ['Variant', args.variant],
    ['Data-Protocol', 'ao'],
    ['Input-Encoding', 'JSON-1'],
    ['Output-Encoding', 'JSON-1'],
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

  const out = { bundle: args.bundle, name: args.name, tx: tx.id, status: res.status, variant: args.variant }
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
