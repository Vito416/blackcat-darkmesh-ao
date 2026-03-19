# Licensing proposal

Goal: publicly auditable source code, wide adoption, and a legally reserved payment flow to the founder for production/network use.

## Recommended model
Use a **custom source-available network-use license**, not an Open Source license.

Why:
- An OSI-compliant Open Source license cannot require a royalty or mandatory fee for use or redistribution.
- A permanent founder fee for production operation is therefore incompatible with Apache, MIT, GPL, AGPL, or similar licenses.
- BSL is a useful reference, but it is still not enough here because your requirement is stronger: the founder fee should remain reserved and non-optional unless expressly waived.

Suggested working title:
- **Blackcat Founder Network License (BFNL) 1.0**

## What BFNL should do
- Allow source inspection, audit, local development, testing, security research, and non-production forks.
- Allow modification of the code for evaluation and internal engineering work.
- **Forbid production or network operation** of the software, gateways, derivatives, managed instances, hosted services, or public websites built on it unless the required founder fee has been paid.
- Define proof of payment as an Arweave transaction with required tags and a published recipient address.
- Make the production right conditional on maintaining valid proof of payment.
- Extend the same production-fee obligation to modified or forked versions that still use this codebase.

## Founder fee and successor stewards
If your actual goal is "money must continue flowing to me," the license should say that explicitly.

Recommended clause design:
- **Founder Fee**: each production deployment, gateway, hosted service, or public site using the software must pay the Founder Fee to the founder-designated Arweave address.
- **Proof of Payment**: a valid Arweave txid with required tags is the evidence of compliance.
- **Non-waivable by default**: no operator may run the software in production without paying the Founder Fee unless the founder (or founder-controlled entity) publishes an explicit written waiver.
- **Successor Steward option**: the founder may designate a future steward or governing entity by a signed notice. That steward may impose an additional maintenance or registry fee for future development.
- **Founder priority preserved**: the steward's right to collect additional fees must not remove the founder's reserved fee unless the founder explicitly waives or transfers that right in writing.

This gives you what you asked for:
- future maintainers can be funded,
- but they do not get the power to erase your fee unless you expressly allow it.

## Required companion documents
This should not live in one file alone. The defensible package is:

1. `LICENSE`
   A custom source-available production-restricted license.
2. `FEE_POLICY.md`
   Defines the fee, tags, accepted payment rails, cure period, and proof rules.
3. `TRADEMARKS.md`
   Prevents forks from presenting themselves as the official Blackcat system.
4. `REGISTRY_TERMS.md`
   Covers verified listing, support eligibility, and delisting for non-payment.
5. `CONTRIBUTOR_TERMS.md` or CLA
   Keeps relicensing authority centralized in the founder-controlled entity.

## Core clauses to include
- Definitions:
  - Production Use
  - Network Use
  - Gateway
  - Verified Listing
  - Founder Fee
  - Steward Fee
  - Founder Notice
- Grant:
  - read, audit, modify, build, and test rights
  - no production/network-use right without fee compliance
- Restrictions:
  - no production deployment without payment
  - no public hosted service without payment
  - no offering as a managed service without payment
  - no removal of fee-enforcement notices from official distributions
- Derivatives:
  - derivatives remain subject to the same production-fee rule if they are based on this code
- Termination:
  - automatic termination on non-payment, with a short cure period if you want
- Trademark separation:
  - no right to name, logo, certification marks, or official registry status
- Governing updates:
  - founder can publish updated fee addresses, successor steward designations, or waivers by signed notice

## Hard truth: what the license cannot do
No license is bulletproof in the absolute sense.

It can protect:
- your code,
- your brand,
- your official registry,
- your official support channel,
- your production-use permission model.

It cannot fully protect:
- the underlying idea,
- an independent clean-room rewrite,
- a similar business model built from scratch.

If you want the strongest practical control, combine the license with:
- centralized copyright ownership,
- trademark ownership,
- contributor terms/CLA,
- official registry and signed trust-manifest control,
- and operational value that only the official network can provide.

## Recommendation
For your goals, I would not recommend Apache-2.0, AGPL, or plain BSL.

I would recommend:
- keep the code **source-available**,
- use a **custom founder-fee production license**,
- keep the **Arweave registration fee** as the proof of compliance,
- and protect the official ecosystem with trademark + registry terms.

This is the closest fit to:
- auditability,
- public trust,
- broad visibility,
- and a legally reserved payment stream to you.

## Next drafting step
If you want, the next practical move is:
1. replace the current proposal with a concrete `BFNL-1.0` license draft,
2. add `FEE_POLICY.md`,
3. add `TRADEMARKS.md`,
4. wire the README to those documents.

_This document is a product and licensing recommendation, not legal advice. Before publishing a final license, have counsel review the final text in your target jurisdictions._
