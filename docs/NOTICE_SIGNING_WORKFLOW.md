# Notice Signing Workflow

Status: active companion operational workflow for BFNL 1.0

This document defines the practical workflow for publishing and verifying Founder Notices and related governance notices.

## 1. Purpose

The workflow exists to make public notices:

- inspectable,
- reproducible,
- auditable,
- and usable with the current Ledger-backed Arweave identity.

## 2. Current bootstrap model

Until a later valid Founder Notice publishes a separate governance-signing identity, the current bootstrap model is:

- the Founder Fee receiving address and the Founder Notice authenticity reference use the same Ledger-backed Arweave identity;
- the current authenticity reference is `SRNyOyOGqC5xSekIZeuy1T3Fho14U3-NerC_jeDwn78`;
- notices are published through the canonical repository and `docs/notices/`;
- and authenticity is strengthened by an associated Arweave proof record whenever practical.

## 3. Standard notice files

Each notice should normally include:

- a `*.notice.md` file containing the human-readable notice text;
- and, where practical, a sibling `*.notice.sig.json` file containing the machine-readable proof record.

Example:

- `2026-03-19-founder-identity.notice.md`
- `2026-03-19-founder-identity.notice.sig.json`

## 4. Notice hash

Before publishing a proof record, compute the SHA-256 hash of the final `*.notice.md` file.

The proof record should treat that SHA-256 value as the canonical content digest for the notice.

## 5. Arweave proof record

Where practical, publish an Arweave transaction from the current Founder authenticity reference or another currently valid Founder Notice authority.

Recommended minimum tags:

- `App: blackcat`
- `Type: founder-notice`
- `Notice-ID: <notice-id>`
- `Notice-Path: <repository-path>`
- `Notice-SHA256: <sha256>`
- `Notice-Version: <version-identifier>`
- `Authority: founder`

The transaction may carry empty or minimal data if the tags and originating authority are sufficient to prove the notice linkage.

## 6. `.sig.json` record format

Where a sibling proof file is used, the recommended minimum structure is:

```json
{
  "notice_id": "2026-03-19-founder-identity-v1",
  "notice_path": "docs/notices/2026-03-19-founder-identity.notice.md",
  "notice_sha256": "<sha256>",
  "authenticity_method": "ledger-backed-arweave-identity",
  "authenticity_reference": "SRNyOyOGqC5xSekIZeuy1T3Fho14U3-NerC_jeDwn78",
  "proof_txid": "<arweave_txid>",
  "proof_tags_version": "blackcat-founder-notice-v1",
  "published_at": "2026-03-19T00:00:00Z"
}
```

## 7. Verification rule

An operator should treat a notice as operationally authentic when all of the following are true:

- the `*.notice.md` file is published through an Authorized Notice Channel;
- the file hash matches the `notice_sha256` recorded in the proof record;
- the Arweave proof transaction is publicly visible;
- the proof transaction tags match the notice metadata;
- and the originating authority matches the currently published Founder authenticity reference or another later valid authority.

## 8. Bootstrap fallback

If an Arweave proof transaction is temporarily unavailable, the repository-published notice may still be treated as the current operational notice during the bootstrap phase if:

- it is published in the canonical repository;
- it is consistent with the current `FEE_POLICY.md` and `NOTICE_CHANNELS.md`;
- and no conflicting later valid notice has been published.

This fallback is meant to preserve operability, not to replace signed proof forever.

## 9. Future separation of identities

When a later valid Founder Notice separates the payment identity from the governance-signing identity, later notices should:

- publish the new governance authenticity reference;
- preserve historical verification of older notices;
- and keep older valid payments and notices intact for their original time period.
