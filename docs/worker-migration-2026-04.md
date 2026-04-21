# Worker migration note (AO -> Gateway)

Date: 2026-04-19

Cloudflare worker runtime ownership moved to:
- `blackcat-darkmesh-gateway/workers/site-inbox-worker`

AO repository remains authoritative only for AO processes/contracts/read model.

## Compatibility window

To avoid immediate CI/runbook breakage, `worker/` remains in this repo as a temporary mirror.

## Planned cleanup

- Move worker CI to gateway repo.
- Retire AO-local `worker/` folder after one stable release cycle.
