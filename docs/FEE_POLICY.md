# Blackcat Founder Fee Policy (Draft)

Status: draft for legal and business review

This policy describes how the Founder Fee is paid and how compliance is proven for the draft Blackcat Founder Network License.

## 1. Purpose

The Founder Fee is intended to be:

- small enough not to block adoption,
- public and auditable,
- simple to prove,
- and fair as a one-time contribution toward the founder's concept, system design, ecosystem bootstrap, registry maintenance, and continued motivation for future development.

The founder also declares that long-term accessibility is a core policy objective of this fee model: the system should remain practically usable by as broad a class of interested operators as reasonably possible. The fee exists to preserve a fair economic right and future development incentive, not to become a mechanism for exclusionary pressure against smaller or weaker operators.

## 2. Current default model

Until a final commercial schedule is published, the intended baseline is:

- minimum fee target: approximately 2 USD equivalent in AR or Bundlr;
- recipient address: `AR_RECEIVER_ADDRESS_TBD`;
- proof method: Arweave transaction id with required tags;
- fee type: one-time per covered registration event, unless a later revision defines renewal or per-deployment rules.

The final commercial schedule may denominate the Founder Fee in a reference value standard rather than a single mandatory fiat currency. The founder-controlled entity may publish the fee using one or more reference expressions, for example:

- a fiat reference amount;
- a public international unit-of-account-linked reference amount;
- a published basket of major currencies;
- or another public successor value standard described in good faith.

Settlement may then be made in any approved Liquid Settlement Asset whose publicly verifiable value at the time of payment satisfies the published obligation.

The fee policy should also publish:

- the current Founder Signing Key or successor authenticity method;
- the Authorized Notice Channels for fee and succession notices;
- and the current effective version identifier of the fee schedule.

## 2A. Inflation indexation and future-proof adjustment

The founder or founder-controlled entity reserves the explicit right to increase the published Founder Fee prospectively in order to preserve its real value over time.

Default policy intent:

- future fee increases should be no less protective than the cumulative official inflation published since the last applicable fee schedule;
- the benchmark should come from a public official source;
- and any ordinary increase above pure inflation should remain within the fairness guard below unless the update is only a technical preservation step caused by redenomination, successor-currency conversion, or transition to a valid successor value standard.

Default fairness guard for operators:

- ordinary fee updates should not be published more than once in any rolling twelve-month period for the same coverage unit;
- the increase in the published Founder Fee should not exceed cumulative official inflation since the prior published schedule plus 0.5 percentage points;
- and fee updates apply prospectively only.

Recommended benchmark hierarchy:

- first, a public inflation measure published by the authority or official statistical body most closely associated with the current reference unit, settlement unit, or successor value standard;
- second, if no such measure remains sufficiently meaningful, a public international or multi-jurisdiction benchmark designated in the then-current published schedule;
- third, if neither remains sufficiently meaningful, a published operational-cost basket using the method in `docs/AFFORDABILITY_BASELINE.md`, applied in good faith and using public pricing inputs.

Unless a later schedule states a different formula, the intended baseline rule is:

- each future published Founder Fee should be at least the previous published fee adjusted upward by the applicable official inflation measure;
- each ordinary future published Founder Fee should not exceed the previous published fee adjusted by the applicable official inflation measure plus 0.5 percentage points;
- fee updates apply prospectively only;
- and already compliant payments are not retroactively invalidated.

Negative inflation or temporary deflation does not automatically require a fee decrease unless the founder expressly chooses to publish one.

## 2B. Currency replacement, redenomination, and post-fiat continuity

If the reference currency is legally redenominated, replaced, discontinued, or no longer functions as a meaningful unit of account, the founder or founder-controlled entity may continue the fee schedule using a good-faith successor standard intended to preserve substantially equivalent real economic value.

Default succession order:

- the legally recognized successor currency using the official conversion rate or legal redenomination rule;
- if no practical successor currency is available, a public international unit of account, if one is still published and reasonably usable;
- if neither remains practical, a published Successor Value Standard based on publicly verifiable economic benchmarks relevant to the ecosystem, such as energy, storage, bandwidth, compute, or another objective basket published in the repository or a Founder Notice.

Any such transition should:

- be documented publicly;
- preserve the same general economic burden in good faith rather than serve as a disguised arbitrary increase;
- remain subject, where reasonably measurable, to the same baseline fairness guard of inflation preservation plus no more than an additional 0.5 percentage points for ordinary increases;
- and preserve the founder's and any lawful successor's ability to receive valid settlement even if prior fiat systems materially fail.

## 2C. Proof by any sufficiently liquid settlement asset

The policy intent is that payment should remain provable even if today's dominant world currencies change materially in the future.

Accordingly, unless a narrower rule is published for a specific period, the Founder Fee may be satisfied using any Liquid Settlement Asset that is:

- widely traded or otherwise publicly and reliably valued;
- reasonably convertible into the then-current reference value standard or successor value standard;
- and objectively sufficient to satisfy the required economic value at the time of settlement.

Illustrative examples may include:

- major fiat currencies;
- AR or other sufficiently liquid digital assets;
- assets priced through a public reserve or basket benchmark;
- or another publicly documented payment asset accepted by published policy.

Proof should be based on publicly verifiable evidence available at the time of payment, such as:

- an on-chain transaction id;
- a public exchange rate or market reference;
- a published conversion methodology;
- and the tags or metadata required by the current policy.

The intended rule is economic equivalence, not formal dependence on any single currency name. If the payer proves that the transferred asset satisfied the then-current published economic value in a sufficiently liquid and publicly verifiable form, the payment should be treated as valid even if historical fiat references later disappear, are redenominated, or lose global relevance.

## 2D. Valuation method and settlement timestamp

Unless a narrower method is published for a given period, the following baseline valuation method applies:

- the relevant valuation time is the timestamp at which the payment transaction becomes publicly final or is otherwise irrevocably credited under the applicable payment rail;
- if the payment rail has an objective on-chain timestamp, that timestamp should control;
- if the payment rail does not have an on-chain timestamp, the earliest reliable public or provider-confirmed completion timestamp should be used.

Value determination should then follow this order:

- if the settlement asset is directly denominated in the current published reference value standard, its face amount controls;
- if an official public reference rate exists for the conversion, that official rate should be used;
- if no official rate exists, the value should be determined using a publicly documented median or equivalent robust measure from multiple liquid public markets reasonably close to the settlement timestamp;
- if market fragmentation, illiquidity, or abnormal conditions make the usual method unreliable, the founder or founder-controlled entity may publish a fallback conversion method in good faith, and any disputed valuation should be resolved in favor of the method that best preserves substantially equivalent real economic value.

The proof package should normally include:

- the transaction identifier or equivalent payment proof;
- the settlement timestamp;
- the conversion source or sources used;
- the resulting calculated value;
- and the required policy tags or metadata.

Where practical, the policy should also identify a default public source hierarchy for valuation, for example:

- official public reference rates where available;
- central-bank or similarly authoritative public reference sources;
- and only then a robust multi-market public median methodology.

## 2E. Accessibility and non-exclusion guardrail

The Founder Fee is intended to remain a small participation contribution, not a barrier that prices out the target ecosystem.

Accordingly, ordinary fee schedules and ordinary fee increases should not be set above a level that materially impairs practical accessibility for typical:

- independent hosting operators;
- website operators;
- e-shop operators;
- gateway operators;
- and other comparable ordinary non-enterprise operators.

In applying this guardrail, the founder or founder-controlled entity should act in good faith and may consider publicly observable indicators such as:

- typical entry-level hosting or gateway operating costs;
- basic domain, TLS, storage, and bandwidth costs;
- ordinary onboarding and maintenance costs faced by ordinary operators;
- and the policy objective that the Founder Fee remain a minor ecosystem participation charge rather than a dominant cost component.

The intent of this clause is not to prevent preservation of real economic value, but to prevent the Founder Fee from being increased into a level that would make the solution materially less reachable for the kinds of operators the project is meant to serve.

Where lawful successors later interpret, enforce, litigate, or renegotiate fee rights, this policy should be read as preserving their ability to seek valid payment and lawful compensation, but not as authorizing a strategy whose practical effect is to crush accessibility for smaller or economically weaker participants. The intended balance is enforceable founder economics without turning the fee model into a disproportionate burden on the weakest viable layer of the ecosystem.

## 2F. Default affordability threshold

Unless a narrower or more protective schedule is published, an ordinary Founder Fee for a standard single site, single shop, single gateway, or similarly ordinary deployment should be presumed materially inconsistent with the Accessibility Principle if it exceeds 5% of the publicly observable baseline first-year direct operating cost of a comparable ordinary non-enterprise operator in the relevant market.

For this purpose, baseline first-year direct operating cost may be estimated in good faith from public market data for items such as:

- entry-level hosting or gateway capacity;
- domain registration;
- TLS or certificate cost where applicable;
- ordinary storage and bandwidth;
- and comparable unavoidable base operational costs for a minimal production deployment.

This default affordability threshold is intended as a rebuttable ceiling for ordinary schedules, not as a floor. It may be adjusted downward by published policy, but should not be adjusted upward for ordinary schedules unless a separately negotiated enterprise arrangement or a clearly differentiated coverage class justifies different treatment.

Any attempt to publish an ordinary fee above that default affordability threshold should be presumed inconsistent with the Founder Accessibility Declaration and the Non-Exclusionary Enforcement Covenant.

## 2G. Good-faith and proportional enforcement

Where an operator appears to be acting in substantial good faith and is reasonably capable of cure, the preferred enforcement path should ordinarily be:

- notice;
- cure opportunity;
- correction of proof or metadata;
- prospective compliance;
- or a reasonable path to payment rather than immediate exclusion.

This preference does not limit strong remedies against fraud, willful non-payment, deliberate evasion, or repeated refusal to cure.

## 2H. Arweave unavailability or public-proof fallback

If Arweave is temporarily unavailable, materially impaired, or practically unusable for timely proof publication, interim proof of payment may be established using another publicly verifiable payment or notice rail designated in a valid Founder Notice or published fee schedule, provided that:

- the interim method is publicly auditable;
- the proof remains reasonably tamper-evident;
- the economic value can still be verified under the valuation rules;
- and the proof can be anchored or mirrored to the primary long-term record once normal publication becomes practical again.

An operator acting in substantial good faith should not be treated as non-compliant solely because the preferred public proof rail is temporarily unavailable, if substantially equivalent public proof is provided through an approved fallback method.

## 2I. Annual affordability and schedule review

Ordinary fee schedules should be reviewed periodically in light of the Accessibility Principle, public market conditions, and the stated affordability threshold.

Where practical, each ordinary schedule revision should be accompanied by a short public note stating:

- the prior fee;
- the updated fee;
- the inflation or value-preservation basis used;
- and the good-faith accessibility rationale for concluding that the new fee does not materially impair the intended operator base.

## 2J. Hardship, public-interest, and micro-operator path

The final commercial model should consider publishing a narrow hardship or micro-operator path for cases where:

- the operator is acting in substantial good faith;
- the deployment is genuinely small or public-interest in nature;
- and immediate full payment would likely create a disproportionate barrier relative to the founder's legitimate economic interest.

Such a path may take the form of a temporary waiver, delayed payment, staged payment, capped micro-operator tier, or another narrowly tailored accommodation published in good faith.

## 2K. Maintenance continuity and anti-decay rule

Ordinary fee schedules, package structures, and successor monetization changes should not be combined with Maintenance Capture.

Accordingly, the policy intent is that no Licensor, founder-controlled entity, Steward, or Lawful Successor should:

- intentionally or through unreasonable neglect allow a Mandatory Internal Component for an ordinary deployment class to decay so that a separately priced replacement becomes practically unavoidable;
- withhold baseline security maintenance, migration information, interface documentation, interoperability information, build instructions, or ordinary support materials in a way that materially pressures ordinary operators toward a separately monetized path;
- declare a baseline component obsolete while failing to provide either a reasonable transition period or a compatible successor inside the same integrated fee surface;
- or convert ordinary maintenance continuity into a disguised second payment surface.

If an official baseline component is replaced, the preferred path should be:

- maintain a reasonably usable compatibility and security path for a reasonable transition period;
- or provide a compatible successor inside the same ordinary covered deployment class;
- and preserve already-earned fee compliance for the covered deployment scope unless a clearly published prospective renewal model already applied.

## 2L. No forced control-plane, version-reset, or reclassification capture

Already validly paid rights for an ordinary covered deployment should not be made practically unusable merely because the official ecosystem later introduces:

- a mandatory proprietary control plane or always-online entitlement service;
- a mandatory private artifact feed, package feed, trust feed, or hosted distribution channel where a public or self-build path remains reasonably possible;
- a major-version reset that treats the same ordinary deployment as a wholly new payment event without a clearly pre-published renewal model;
- an artificial platform, runtime, repository, or package split used to recreate duplicate unavoidable charges;
- or a relabeling of an ordinary deployment as premium or enterprise without a genuine operational distinction.

Where a public proof rail, offline-verifiable proof path, or self-hostable verification path remains reasonably possible, the official ecosystem should prefer that path over a newly mandatory closed control dependency for ordinary operators.

## 3. Required tags

Each payment transaction should include, at minimum:

- `App: blackcat-mesh`
- `Type: gateway|site|shop`
- `Domain: your-domain.tld`
- `Contact: email_or_pgp`

Additional tags may be required in the future, for example:

- `Operator-Id`
- `Deployment-Id`
- `Version`
- `Founder-Fee-Version`

## 4. Scope of coverage

The final commercial schedule should define what one payment covers. Recommended default:

- one gateway registration covers one production gateway;
- one site or shop registration covers one production domain or storefront;
- materially separate production deployments require separate payment unless grouped in an announced plan.

The default interpretation is system-wide for the covered deployment class, not repository-by-repository. If an ordinary deployment depends on multiple official Blackcat repositories or Mandatory Internal Components that form part of the same Covered System, that dependency should not by itself create duplicative Founder Fee obligations.

Once a payment validly covered a stated deployment class under the then-current published schedule, that covered scope should not be retroactively narrowed merely because of later repository splits, version lines, support-plan changes, build pipeline changes, packaging changes, or other internal restructuring of the Covered System.

## 4A. Integrated system and anti-capture rule

Official repository separation is presumed to exist for maintenance, safety, delivery, or architectural reasons, not to multiply unavoidable fees.

Accordingly:

- ordinary baseline functionality should remain operable without forcing an operator into multiple separately unavoidable internal package charges;
- a Mandatory Internal Component for an ordinary deployment class should ordinarily be treated as part of the same integrated fee surface for that class;
- and optional premium or enterprise components may be separately priced only where their optional nature is genuine and their pricing does not nullify the Accessibility Principle in practice.

If a future internal package becomes materially necessary for ordinary operation, the default presumption should be that it falls within the same integrated system treatment unless a clearly differentiated and non-exclusionary coverage class is published in good faith.

## 5. Proof of payment

Proof of payment means:

- the transaction is visible on Arweave;
- the recipient address matches the currently published founder address;
- the transaction contains the required tags;
- and the amount satisfies the policy in force at the time of the payment.

The txid may be used as:

- compliance evidence,
- proof-of-listing input,
- or proof-of-domain challenge material.

## 6. Optional proof-of-domain

To prevent registry abuse or domain squatting, the operator may be asked to prove domain control through one of:

- DNS TXT record: `blackcat-verify=<txid>`
- a signed challenge served from the domain
- or another published verification method

## 7. Cure period

Recommended default cure period:

- 14 calendar days from written notice of non-compliance

If payment or valid proof is not provided within the cure period, production rights under the final license may terminate automatically.

## 8. Successor steward fees

If a future Steward is designated by a valid Founder Notice, the Steward may publish an additional Steward Fee schedule.

Default principle:

- Founder Fee remains payable unless the founder expressly waives or transfers it;
- Steward Fee may be added for ecosystem maintenance, support, or future development.

Unless a more protective rule is published, any Steward Fee or future development fee should be interpreted and administered under the same baseline accessibility, anti-capture, anti-decay, integrated-system, and non-exclusionary enforcement rules that apply to the Founder Fee for the same ordinary deployment class.

Accordingly, a Steward Fee should not be used to:

- recreate a duplicate unavoidable payment surface for the same ordinary covered deployment;
- bypass the affordability threshold through support, maintenance, package, control-plane, or compatibility capture;
- or convert ordinary continued operation into a premium-only path without a genuine differentiated coverage class published in good faith.

## 9. Good-faith exceptions

The final commercial policy may include discretionary waiver programs, for example:

- security research,
- public-interest deployments,
- educational use,
- or emergency humanitarian use.

Unless expressly granted in writing, no waiver should be presumed.

## 10. Revision policy

This fee policy may be updated prospectively by:

- a published repository revision,
- or a Founder Notice signed by the founder or founder-controlled entity.

Changes should not retroactively invalidate a payment that was compliant when made.
