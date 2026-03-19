# Blackcat Founder Fee Policy (Draft)

Status: draft for legal and business review

This policy describes how the Founder Fee is paid and how compliance is proven for the draft Blackcat Founder Network License.

## 1. Purpose

The Founder Fee is intended to be:

- small enough not to block adoption,
- public and auditable,
- simple to prove,
- and fair as a one-time contribution toward the founder's concept, system design, ecosystem bootstrap, registry maintenance, and continued motivation for future development.

## 2. Current default model

Until a final commercial schedule is published, the intended baseline is:

- minimum fee target: approximately 2 USD equivalent in AR or Bundlr;
- recipient address: `AR_RECEIVER_ADDRESS_TBD`;
- proof method: Arweave transaction id with required tags;
- fee type: one-time per covered registration event, unless a later revision defines renewal or per-deployment rules.

The final commercial schedule may denominate the Founder Fee in a reference fiat currency such as EUR, CZK, or USD, with settlement permitted in AR or Bundlr equivalent at the time of payment according to the published instructions.

## 2A. Inflation indexation and future-proof adjustment

The founder or founder-controlled entity reserves the explicit right to increase the published Founder Fee prospectively in order to preserve its real value over time.

Default policy intent:

- future fee increases should be no less protective than the cumulative official inflation published since the last applicable fee schedule;
- the benchmark should come from a public official source;
- and the founder may publish a higher schedule than inflation alone if justified by product, support, registry, or ecosystem costs.

Recommended benchmark hierarchy:

- for EUR-denominated schedules: Eurostat HICP;
- for CZK-denominated schedules: Czech Statistical Office CPI or HICP;
- for USD-denominated schedules: U.S. Bureau of Labor Statistics CPI-U;
- if a benchmark is discontinued, materially changed, or unavailable, the founder may designate a reasonable successor official benchmark by published revision or Founder Notice.

Unless a later schedule states a different formula, the intended baseline rule is:

- each future published Founder Fee should be at least the previous published fee adjusted upward by the applicable official inflation measure;
- fee updates apply prospectively only;
- and already compliant payments are not retroactively invalidated.

Negative inflation or temporary deflation does not automatically require a fee decrease unless the founder expressly chooses to publish one.

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
