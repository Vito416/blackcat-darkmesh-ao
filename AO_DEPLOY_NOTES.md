# AO Deploy Notes

Last updated: 2026-05-13

This file is the current operational source of truth for `blackcat-darkmesh-ao` deploys.
Older worker-runtime deployment notes were intentionally removed from the working tree during the AO/Gateway split; Git history remains the audit trail if archaeology is needed.

## Repository ownership after migration

- AO repo owns AO processes, schemas, Arweave manifests, deploy helpers, verification scripts, and AO runbooks.
- Write mutations are owned by `blackcat-darkmesh-write`.
- Gateway and Cloudflare Worker runtime are owned by `blackcat-darkmesh-gateway`, especially `workers/secrets-worker`.
- AO must stay secretless: no wallet files, HMAC secrets, API keys, PII payloads, or worker inbox contents belong in this repo.

## Current process families

- `registry` — domain/site routing, trusted release registry, integrity policy, gateway directory, HB policy contract state.
- `site` — page/layout/navigation/public site state.
- `catalog` — product/category/search-facing public catalog state.
- `access` — entitlement/public permission state.
- `ingest` — apply-only public-state ingestion from Write events.
- `resolver` — host decision contract and cache/policy envelope for HB-style routing.

## Local preflight checklist

Run from this repo root before publishing or opening a release PR:

```bash
scripts/verify/preflight.sh
npm run bundle:ao
node --test tests/http/public_api_server.contract.test.mjs
RESOLVER_ALLOW_CENTRALIZED_BUNDLE_WRITES=1 LUA_PATH='?.lua;?/init.lua;ao/?.lua;ao/?/init.lua' lua5.4 tests/integration/resolver_process_spec.lua
LUA_PATH='?.lua;?/init.lua;ao/?.lua;ao/?/init.lua' lua5.4 tests/integration/registry_policy_contract_spec.lua
```

Optional compose smoke, when sibling repos are present:

```bash
OUTBOX_HMAC_SECRET=test \
WRITE_WEBHOOK_HMAC_SECRET=test \
WRITE_KEEP_ALIVE=0 \
docker compose -f docs/docker-compose-e2e.yml config >/tmp/darkmesh-ao-compose-config.txt
```

## Publish order

1. Review `docs/runbooks/publish.md` and confirm wallet/secrets are outside git.
2. Build AO Lua bundles with `npm run bundle:ao`.
3. Publish/spawn only the process family being changed.
4. Wait for module/process finalization.
5. Smoke the exact action surface changed.
6. Only then update external gateway/resolver/write configuration pointers.
7. Record tx/process ids in the release note or PR description.

## Last migration cleanup

- AO-local `worker/` source tree removed from this repo.
- Worker-only workflows removed from this repo.
- Embedded write/worker no-op workflow removed; cross-repo compose smoke now clones sibling repos explicitly.
- Worker env lint now checks the canonical gateway worker path when it exists and skips gracefully otherwise.
- Resolver bundle/build/test path added to AO bundle tooling and CI.

## Open release notes

- Keep `docs/GATEWAY.md` limited to AO-local adapter surface plus pointers to external gateway worker ownership.
- If a new public AO action is added, update README message contracts, tests, and `scripts/verify/preflight.sh` in the same change.
- Do not reintroduce AO-local Cloudflare Worker runtime files; add those changes in `blackcat-darkmesh-gateway` instead.
