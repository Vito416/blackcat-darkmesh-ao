# Notice Channels and Signing Authority (Draft)

Status: active companion policy text for BFNL 1.0

This document describes the public channels and authenticity rules for Founder Notices, succession notices, fee notices, and other governance notices referenced by Blackcat Founder Network License 1.0.

## 1. Purpose

The purpose of this document is to reduce ambiguity, impersonation risk, and future disputes over:

- fee updates,
- payment destination changes,
- successor authority,
- steward designations,
- emergency operational notices,
- and any waiver or transfer that the governing license permits to be published by notice.

## 2. Default Authorized Notice Channels

Unless a later valid notice says otherwise, the intended default Authorized Notice Channels are:

- the canonical public Git repository of the project;
- a designated path within that repository for signed notices;
- the official registry or project website, if one is published;
- and an Arweave record, manifest, or equivalent public permanent record, where practical.

The intended operational rule is redundancy:

- important notices should be published through more than one channel where reasonably possible;
- at least one channel should be easy for ordinary operators to inspect;
- and at least one channel should be durable enough to support later audit.

## 3. Default notice path

Recommended repository path:

- `docs/notices/`

Recommended notice filename pattern:

- `YYYY-MM-DD-topic.notice.md`
- `YYYY-MM-DD-topic.notice.sig`

Examples:

- `2026-03-19-founder-fee-v2.notice.md`
- `2026-03-19-founder-fee-v2.notice.sig`
- `2027-01-10-successor-designation.notice.md`

## 4. Founder Signing Key

The governing fee policy or a valid notice should publish:

- the current Founder Signing Key fingerprint;
- the signature method;
- the date from which that key is authoritative;
- and any superseded key history needed for verification of older notices.

Recommended minimum publication format:

- key id / fingerprint,
- signature algorithm,
- effective-from date,
- and the channel where revocations or rotations will be announced.

## 5. Key rotation and revocation

The notice framework should support key rotation without breaking trust in prior valid notices.

Recommended default rule:

- a new signing key becomes authoritative only after publication through the previously recognized Authorized Notice Channel;
- if compromise is suspected, an emergency revocation notice may be issued through all reasonably available channels;
- old notices remain valid if they were properly signed at the time they were published, unless specifically revoked for fraud or compromise.

## 6. Types of notice

The following notices are expected to be authenticated:

- Founder Fee schedule changes;
- payment destination updates;
- waiver or transfer notices;
- successor designation notices;
- steward designation notices;
- emergency anti-fraud or anti-impersonation notices;
- alternate proof-rail notices;
- and any material governance notice that affects production rights.

## 7. Notice content requirements

An ordinary notice should, where reasonably possible, contain:

- a unique notice title;
- the effective date;
- the scope of the notice;
- the document or policy version being changed;
- the full text of the change or a precise pointer to it;
- the signing key identity;
- and a signature or equivalent authenticity proof.

## 8. Emergency notices

If immediate action is reasonably necessary to address:

- key compromise,
- payment-address compromise,
- impersonation,
- active fraud,
- or material ecosystem security harm,

an emergency notice may take effect immediately or on a shortened timetable.

However, the issuing authority should still:

- document the emergency basis in good faith;
- publish through all reasonably available channels;
- and follow up with a normal-form notice as soon as practical.

## 9. Succession notices

A succession notice should be treated as materially important and should be published through at least:

- one durable public channel,
- and one operationally current channel.

It should identify:

- the claimed successor,
- the legal or organizational basis of succession,
- the claimed scope of authority,
- the currently valid signing method for future notices,
- and where supporting proof, attestation, or redacted proof can be reviewed.

## 10. Conflict handling

If two notices appear to conflict, operators should prefer:

1. the notice authenticated by the currently recognized valid signing key,
2. the notice issued through the more authoritative Authorized Notice Channel,
3. the more recent notice, if authenticity is otherwise equal,
4. and the interpretation most consistent with the governing license and fee policy.

## 11. No silent governance changes

No fee redirection, successor claim, waiver, or governance change should be treated as effective merely because it appears in:

- a social post,
- an unsigned blog post,
- a third-party relay,
- or an unauthenticated message.

The policy intent is that governance changes should be public, signed, and auditable.

## 12. Contact

Questions about signing authority and public notices may be directed to:

- `blackcatacademy@protonmail.com`
