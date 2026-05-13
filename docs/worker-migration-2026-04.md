# Worker migration note (AO -> Gateway)

Date: 2026-04-19

Cloudflare worker runtime ownership moved to:
- `blackcat-darkmesh-gateway/workers/secrets-worker`

AO repository remains authoritative only for AO processes/contracts/read model.

## Migration status

- AO-local `worker/` folder has been retired.
- Worker CI/load tests now belong to the gateway repository worker folders.
- Worker-only workflows were removed from this repository.
- Cross-repo E2E uses `docs/docker-compose-e2e.yml` and sibling repo mounts instead of an AO-local worker mirror.
- Do not reintroduce Worker runtime code here; make Cloudflare Worker changes in `blackcat-darkmesh-gateway/workers/secrets-worker`.
