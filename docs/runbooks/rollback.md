# AO Rollback Runbook

Rollback should prefer pointer/config changes over deleting immutable artefacts. AO module txs and process ids remain historical evidence.

## Preconditions

- Identify the last known-good module tx and process id from `AO_DEPLOY_NOTES.md` or deployment artefacts under `tmp/`.
- Confirm whether the issue is module code, process config, scheduler reachability, or gateway pointer projection.
- Preserve failing artefacts and smoke output for follow-up.

## Steps

1. Stop promoting the new tx/process id in gateway/resolver config.
2. Restore the previous known-good AO process id in the consuming gateway/worker/resolver environment.
3. Re-run the same public read smoke that detected the issue.
4. If the process itself is healthy but routing is wrong, rollback only the route/policy pointer instead of respawning.
5. If the new module tx is bad, publish a fixed module and spawn a replacement process; do not overwrite history.
6. Record the rollback reason, old/new process ids, operator, and verification result in `AO_DEPLOY_NOTES.md`.

## Verification

- Public reads return the expected deterministic payload.
- Gateway/resolver health checks no longer reference the failed process id.
- No secret material appears in rollback notes or logs committed to git.
