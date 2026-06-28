import fs from 'node:fs'
import { resolve } from 'node:path'
import { connect, createSigner } from '@permaweb/aoconnect'

function clean(value) {
  if (value === undefined || value === null) return undefined
  const out = String(value).trim()
  return out === '' ? undefined : out
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
      'http://127.0.0.1:8734',
    scheduler:
      clean(process.env.HB_SCHEDULER) ||
      clean(process.env.HYPERBEAM_SCHEDULER) ||
      clean(process.env.AO_SCHEDULER) ||
      'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo',
    variant: clean(process.env.AO_VARIANT) || 'ao.TN.1',
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
    else if (arg === '--data') args.data = clean(argv[++i]) || args.data
    else if (arg === '--out') args.out = clean(argv[++i]) || args.out
    else if (arg === '--tag') {
      const pair = clean(argv[++i])
      if (!pair || !pair.includes('=')) throw new Error('--tag expects key=value')
      const idx = pair.indexOf('=')
      extraTags.push({ name: pair.slice(0, idx), value: pair.slice(idx + 1) })
    } else if (arg === '-h' || arg === '--help') {
      console.log('Usage: node scripts/deploy/spawn_process_tn.mjs --module <TX> --name blackcat-ao-registry --url http://127.0.0.1:8734')
      process.exit(0)
    } else {
      throw new Error(`Unknown arg: ${arg}`)
    }
  }

  if (!args.module) throw new Error('Missing AO module tx. Provide --module or AO_MODULE.')
  return { args, extraTags }
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

  const tags = [
    { name: 'Variant', value: args.variant },
    { name: 'Name', value: args.name },
    { name: 'Content-Type', value: 'text/lua' },
    { name: 'Data-Protocol', value: 'ao' },
    { name: 'Input-Encoding', value: 'JSON-1' },
    { name: 'Output-Encoding', value: 'JSON-1' },
    { name: 'signing-format', value: 'ans104' },
    { name: 'accept-bundle', value: 'true' },
    { name: 'accept-codec', value: 'httpsig@1.0' },
    ...extraTags
  ]

  const pid = await ao.spawn({
    module: args.module,
    scheduler: args.scheduler,
    data: args.data,
    tags
  })

  const out = {
    pid,
    module: args.module,
    name: args.name,
    url: args.url,
    scheduler: args.scheduler,
    variant: args.variant
  }
  console.log(JSON.stringify(out, null, 2))
  if (args.out) fs.writeFileSync(resolve(args.out), JSON.stringify(out, null, 2))
}

main()
  .then(() => {
    // Keep CLI deterministic: close even if downstream libs keep handles open.
    process.exit(0)
  })
  .catch((err) => {
    console.error(err)
    process.exit(1)
  })
