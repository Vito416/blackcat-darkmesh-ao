# AO Incident Response Runbook

Use this for production incidents involving AO reads, resolver policy decisions, deploy artefacts, or gateway-facing AO state.

## Triage

1. Classify impact: public read outage, stale data, wrong route decision, deploy failure, or suspected key/secret exposure.
2. Capture safe evidence: request id, action, process id, module tx, scheduler URL, timestamp, public status/body shape, and relevant logs.
3. Do not paste wallets, private keys, HMAC secrets, seed phrases, or raw customer payloads into notes.
4. Check current branch/commit and compare with the last known-good deployment entry.

## Immediate containment

- For wrong route/policy decisions, switch consumers back to the last known-good process id or policy bundle.
- For stale AO state, pause promotion and verify whether write/outbox ingestion is delayed before respawning.
- For scheduler or HyperBEAM reachability issues, test an alternate endpoint before changing module code.
- For suspected secret exposure, rotate the affected gateway/write/worker secret in its owning repo; AO should not store sensitive plaintext.

## Recovery

- Run `scripts/verify/preflight.sh` and the targeted integration test before publishing a fix.
- Publish/spawn using `docs/runbooks/publish.md`.
- Smoke the exact action that failed and one adjacent happy path.
- Add a concise incident entry to `AO_DEPLOY_NOTES.md` with root cause, mitigation, and follow-up task.
