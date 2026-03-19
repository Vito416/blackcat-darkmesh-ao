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
- **Fairness statement**: the Founder Fee should be described as a fair, minimal, one-time contribution for access to the founder-created concept, system design, network model, public registry, and continued motivation for future development. It is not presented as an investment product or speculative asset, but as a practical participation fee for using the official production ecosystem.
- **Inflation protection**: the founder-controlled entity should retain the express right to adjust the Founder Fee prospectively, with future increases anchored at least to official inflation from public sources so the fee does not lose real value over time.
- **Counterparty protection**: ordinary fee increases should be capped for fairness, for example at no more than cumulative official inflation since the prior published schedule plus 0.5 percentage points, and ordinarily no more than once in a rolling twelve-month period.
- **Continuity across currency failure**: if fiat currencies or the chosen benchmark cease to function, the founder or lawful successor should be allowed to preserve the same real economic burden by moving to a published successor currency, official conversion, IMF SDR, or another public and objective successor value standard.
- **Proof by equivalent value**: the operator should be allowed to prove payment using any sufficiently liquid settlement asset that satisfies the same published economic value, rather than being locked to one named fiat currency forever.
- **Valuation rule**: the fee policy should define the settlement timestamp and a public valuation method hierarchy so equivalent-value payments can actually be proved in a repeatable way.
- **Accessibility guardrail**: the founder fee should not be increased beyond a level that materially harms accessibility of the solution for typical hosting operators, website operators, e-shop operators, and comparable SMEs.
- **Founder intent on successors**: lawful successors may enforce valid rights, but ambiguous monetization or enforcement questions should be resolved in a way that does not disproportionately suppress smaller or weaker participants in the ecosystem.
- **Non-exclusionary enforcement covenant**: enforcement should be good-faith and proportional, with cure-first treatment for smaller operators acting in substantial good faith, while preserving strong remedies for fraud or willful evasion.
- **Default affordability threshold**: ordinary schedules should be tied to a concrete affordability ceiling, for example no more than 5% of the publicly observable first-year baseline operating cost of a comparable small operator for the relevant deployment class.
- **Integrated system scope**: all official repositories and future internal packages that make up the same Covered System should be treated as one integrated licensing surface for ordinary deployment classes, not as automatic separate fee events.
- **Anti-capture dependency rule**: future internal packages should not be made both materially necessary and separately unavoidable in a way that bypasses the Accessibility Principle or recreates duplicative hidden fees.
- **Order of precedence**: the final package should explicitly say which document controls on conflict between the license, fee policy, registry terms, trademark policy, contributor terms, and signed waivers.
- **Authenticated notices**: Founder Notices and successor notices should use a published signing key and authorized publication channels so future disputes about fake notices are easier to defeat.
- **Succession proof chain**: any lawful successor should have to publish a public succession notice and proof chain before gaining authority to redirect fees, change schedules, or designate stewards.
- **Alternative proof rail**: if Arweave is temporarily unavailable, the policy should allow another public and auditable proof rail with later anchoring back to the primary record.
- **Registry appeal path**: registry suspension and delisting should have a lightweight review path and public transparency log where practical.
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
6. `NOTICE_CHANNELS.md`
   Defines authentic public notice rails, signing authority, and succession notice expectations.
7. `DISPUTE_RESOLUTION.md`
   Defines the intended forum, language, cure-first posture, and evidence hierarchy for disputes.
8. `SYSTEM_SCOPE.md`
   Defines system-wide fee coverage across repositories and blocks anti-accessibility modular fragmentation.
9. `AFFORDABILITY_BASELINE.md`
   Defines the method for measuring first-year baseline cost and affordability thresholds.

## Core clauses to include
- Definitions:
  - Production Use
  - Network Use
  - Gateway
  - Verified Listing
  - Founder Fee
  - Covered System
  - Reference Inflation Index
  - Lawful Successor
  - Liquid Settlement Asset
  - Accessibility Principle
  - Founder Accessibility Declaration
  - Non-Exclusionary Enforcement Covenant
  - Mandatory Internal Component
  - Founder Signing Key
  - Authorized Notice Channel
  - Successor Value Standard
  - Founder Concept and Network Contribution
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

## Suggested policy wording
The fee policy should say something close to this:

"The Founder Fee is a fair and minimal one-time contribution required for production participation in the Blackcat network. It is charged in recognition of the founder's original concept, architectural design, ecosystem bootstrap, registry maintenance, and continued motivation to improve and secure the system. The fee is intended to be small enough not to block adoption, while ensuring that commercial or operational use of the official ecosystem is not entirely free of contribution."

And for successor stewardship:

"The founder may authorize a future steward to collect an additional development or maintenance fee for the continued operation of the ecosystem. Such authorization does not remove or replace the founder's reserved Founder Fee unless the founder expressly states so in a signed notice."

And for inflation indexation:

"The founder or founder-controlled entity may update the Founder Fee prospectively to preserve its real value. Unless a more specific schedule is published, future fee increases should be no less protective than official consumer inflation published by a public official source designated in the fee policy or Founder Notice. Previously compliant payments remain valid for the scope they originally covered and are not retroactively invalidated by later fee increases."

And for capped fairness and continuity:

"To protect operators and preserve good-faith fairness, ordinary Founder Fee increases should not be published more than once in a rolling twelve-month period and should not exceed cumulative official inflation since the previous published schedule plus 0.5 percentage points. If the reference currency, official inflation benchmark, or practical fiat settlement system ceases to exist or to function meaningfully, the founder or lawful successor may preserve substantially equivalent real economic value by adopting a publicly documented successor currency, official legal conversion, IMF SDR, or another objective and publicly described successor value standard."

And for settlement flexibility:

"Unless the current fee policy expressly requires a narrower method, the Founder Fee may be satisfied using any sufficiently liquid and publicly verifiable settlement asset whose value at the time of payment is no less than the published economic obligation. The validity of payment should depend on equivalent economic satisfaction, not on permanent dependence on any one specific fiat currency."

And for accessibility:

"The Founder Fee is intended to remain a minor participation charge and must not be increased above a level that materially impairs practical accessibility of the Software for typical hosting providers, web operators, e-shop operators, or similarly situated SMEs. Real-value preservation is permitted, but exclusionary pricing is not the policy objective of this model."

And for successor enforcement:

"The founder expressly declares that this model is intended to preserve accessibility for the broadest reasonable class of interested operators. Lawful successors may enforce valid fee rights and may seek lawful compensation, but ambiguous fee, remedy, or enforcement questions should be interpreted in a manner that does not disproportionately burden, suppress, or price out smaller or economically weaker participants if such participants form part of the relevant ecosystem at that time."

And for non-exclusionary enforcement:

"Except in cases of fraud, willful evasion, repeated refusal to cure, abuse of official marks, or malicious conduct, enforcement of the Founder Fee should ordinarily proceed through notice, cure, prospective compliance, or another proportional remedy before exclusionary measures are sought. The licensing model is intended to protect valid founder economics, not to weaponize ambiguity or fee pressure against smaller operators acting in substantial good faith."

And for notice authenticity:

"A Founder Notice or succession notice should be effective only if published through an authorized public channel and authenticated by the currently recognized founder signing key or successor authenticity method. This is intended to reduce ambiguity, impersonation risk, and future disputes over fee redirection or authority."

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
The first concrete drafts now live in:
1. `docs/BFNL-1.0-draft.md`
2. `docs/FEE_POLICY.md`
3. `docs/TRADEMARKS.md`
4. `docs/REGISTRY_TERMS.md`
5. `docs/CONTRIBUTOR_TERMS.md`
6. `docs/NOTICE_CHANNELS.md`
7. `docs/DISPUTE_RESOLUTION.md`
8. `docs/SYSTEM_SCOPE.md`
9. `docs/AFFORDABILITY_BASELINE.md`

The next practical move is:
1. review the draft license line by line,
2. review trademark and registry terms,
3. review contributor terms or CLA language,
4. replace the root `LICENSE` only after legal review.

_This document is a product and licensing recommendation, not legal advice. Before publishing a final license, have counsel review the final text in your target jurisdictions._
