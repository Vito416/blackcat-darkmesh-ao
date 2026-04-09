# Contributing

This repository is source-available under `BFNL-1.0` (it is not an OSI open-source project). By submitting a contribution, you agree to the active contributor terms in `docs/CONTRIBUTOR_TERMS.md`.

## Working model
- Branches: `main` (releasable), `develop` (integration), `feature/*`, `adr/*`, `release/*`.
- Keep changes scoped: one process/contract per PR when possible.
- Message contracts and schemas are treated as public API; prefer additive changes over breaking ones.

## Prerequisites
- `lua5.4` (or `luac`) for AO process code.
- `python3` for schema validation.

## Pre-flight checks
Run before opening a PR:

```bash
scripts/verify/preflight.sh
```

This validates JSON schemas and runs Lua syntax checks.

## Pull requests
- Describe the change and affected process (registry/site/catalog/access).
- Update docs and fixtures when changing contracts or schemas.
- Add or update tests once the test harness is in place (integration, message-contract, snapshots, security).

## Reporting issues
- Non-security bugs and feature requests: GitHub Issues using the provided templates.
- Security issues: follow `SECURITY.md` and report privately.
