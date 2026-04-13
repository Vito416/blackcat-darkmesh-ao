# AO public endpoint adapter

This adapter exposes gateway-compatible read endpoints:

- `POST /api/public/resolve-route`
- `POST /api/public/page`
- `GET /healthz`

## Run

```bash
AO_SITE_PROCESS_ID=<site_pid> \
AO_HB_URL=https://push.forward.computer \
AO_HB_SCHEDULER=n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo \
AO_PUBLIC_API_TOKEN=<optional_bearer_token> \
node scripts/http/public_api_server.mjs
```

## Request examples

```bash
curl -sS -X POST http://127.0.0.1:8788/api/public/resolve-route \
  -H 'content-type: application/json' \
  --data '{"siteId":"site-main","path":"/"}'

curl -sS -X POST http://127.0.0.1:8788/api/public/page \
  -H 'content-type: application/json' \
  --data '{"siteId":"site-main","slug":"/"}'
```

## Notes

- Preferred transport is `ao.dryrun` (non-mutating).
- If dryrun is unavailable on the selected route, enable fallback:
  - `AO_READ_FALLBACK_TO_SCHEDULER=1`
  - and provide a wallet (`AO_WALLET_PATH`).
