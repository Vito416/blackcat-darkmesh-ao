# Anti-Circumvention and Future Abuse Model (Draft)

Status: draft for legal, product, and governance review

This document lists the main ways the founder-fee model could be weakened, bypassed, or turned into an exclusionary monetization system in the future. It is intended to help reviewers read the rest of the licensing bundle as a coordinated anti-circumvention package rather than as isolated documents.

## 1. Purpose

The founder's intent is not only to reserve a fair production-use payment right, but also to prevent future governance from:

- multiplying unavoidable fees through architecture games,
- degrading accessibility for ordinary operators,
- or converting the system into a dependency-captured ecosystem that contradicts the project's stated mission.

## 2. Core abuse patterns this bundle is intended to resist

### 2.1 Repository-split multiplication

Risk:
- split one practical system into many repositories or packages and claim that each one creates a fresh unavoidable fee event.

Response:
- `Covered System` definition in the license;
- integrated-system treatment in `SYSTEM_SCOPE.md`;
- fee-scope rule in `FEE_POLICY.md`.

### 2.2 Mandatory internal package capture

Risk:
- introduce a new internal package, make it materially necessary for ordinary operation, and then charge for it separately.

Response:
- `Mandatory Internal Component` definition;
- anti-capture and integrated-fee rules in `SYSTEM_SCOPE.md`;
- affordability treatment in `AFFORDABILITY_BASELINE.md`.

### 2.3 Maintenance neglect capture

Risk:
- stop maintaining a baseline module so that operators are pushed into a separately monetized replacement.

Response:
- `Maintenance Capture` definition in the license;
- maintenance continuity rules in `SYSTEM_SCOPE.md`;
- anti-decay rules in `FEE_POLICY.md`.

### 2.4 Security-patch withholding

Risk:
- keep the free or baseline path nominally available, but withhold security fixes so that paid migration becomes the only safe choice.

Response:
- no-decay and baseline maintenance language in the license, fee policy, and system-scope policy.

### 2.5 Artificial incompatibility or protocol capture

Risk:
- change formats, manifests, schemas, trust anchors, or interoperability behavior in a way that strands ordinary operators unless they buy a paid bridge, hosted translation service, or managed gateway.

Response:
- no artificial incompatibility rule in `SYSTEM_SCOPE.md`;
- anti-decay and migration-path expectations in `FEE_POLICY.md`.

### 2.6 Version-reset monetization

Risk:
- release a new major version or platform split and treat the same ordinary deployment as a wholly new fee event without a clearly pre-published renewal model.

Response:
- no forced version-reset capture in `FEE_POLICY.md`;
- continuity language in the license.

### 2.7 Abusive reclassification

Risk:
- relabel an ordinary site, shop, or gateway as enterprise or premium without a genuine operational distinction, just to bypass accessibility limits.

Response:
- `Ordinary Deployment Class` definition;
- anti-reclassification rules in `SYSTEM_SCOPE.md`;
- affordability baseline and threshold in `AFFORDABILITY_BASELINE.md` and `FEE_POLICY.md`.

### 2.8 Mandatory control-plane capture

Risk:
- require a new always-online proprietary license server, entitlement service, or hosted control plane for operators who already validly paid.

Response:
- no mandatory control-plane rule in the license and `SYSTEM_SCOPE.md`;
- public/offline/self-hostable proof preference in `FEE_POLICY.md`.

### 2.9 Hidden recurring charges

Risk:
- keep the founder fee small, but make registry access, trust manifests, compatibility updates, or baseline support quietly dependent on new unavoidable recurring payments.

Response:
- order-of-precedence rule in the license;
- registry separation in `REGISTRY_TERMS.md`;
- integrated-system and anti-capture rules in `SYSTEM_SCOPE.md`.

### 2.9A Steward-fee asymmetry

Risk:
- promise accessibility limits for the founder fee, but let a future steward or development fee bypass those same limits in practice.

Response:
- steward-fee symmetry language in the license and `FEE_POLICY.md`;
- integrated-system and non-exclusionary rules applied to both fee surfaces.

### 2.10 Opaque valuation manipulation

Risk:
- use obscure, thin, or manipulated pricing sources to argue that an equivalent-value payment was insufficient.

Response:
- valuation hierarchy in `FEE_POLICY.md`;
- public-source and public-proof requirements;
- benchmark fallback rules that do not depend permanently on any one currency bloc.

### 2.11 Fake notices or fake successors

Risk:
- impersonate the founder or a successor to redirect fees, change addresses, or appoint a hostile steward.

Response:
- signed notice framework in `NOTICE_CHANNELS.md`;
- succession proof chain in the license;
- authenticated notice requirements in `licensing.md`.

### 2.12 Registry pressure as a substitute for license change

Risk:
- leave the license text alone but use registry, trust, or verified-status rules to force operators into new monetization terms.

Response:
- registry appeal and transparency expectations in `REGISTRY_TERMS.md`;
- order-of-precedence clause in the license.

### 2.13 Data-hostage or migration-hostage tactics

Risk:
- keep operators nominally licensed but withhold migration data, export paths, or operational documentation so that only the official paid path remains practical.

Response:
- no artificial incompatibility rule in `SYSTEM_SCOPE.md`;
- maintenance continuity and documentation language in the license and fee policy.

### 2.14 Artificial affordability distortion

Risk:
- claim the fee is still affordable by excluding mandatory replacement modules, mandatory support subscriptions, or baseline managed dependencies from the affordability calculation.

Response:
- mandatory-component treatment in `AFFORDABILITY_BASELINE.md`;
- integrated-system and anti-capture rules across the bundle.

### 2.15 Build-chain or package-feed capture

Risk:
- move required binaries, packages, trust feeds, or update channels behind a separately paid private service so that the source remains public but the practical baseline operation does not.

Response:
- no mandatory control-plane rule in `SYSTEM_SCOPE.md`;
- no forced control-plane or package-feed capture in `FEE_POLICY.md`.

### 2.16 Support-gating capture

Risk:
- keep code nominally available, but make ordinary baseline security fixes, migration guidance, or operational support available only through a premium support path.

Response:
- maintenance continuity and anti-decay language in the license and `FEE_POLICY.md`;
- affordability baseline includes mandatory support-like costs if they become unavoidable.

### 2.17 Retroactive scope shrink

Risk:
- accept a one-time fee, then later argue that the covered scope silently shrank because of a repo split, version split, or support-plan change.

Response:
- prospective-only fee-update logic in the license;
- no retroactive narrowing of covered scope in `FEE_POLICY.md`;
- order-of-precedence rule across the bundle.

### 2.18 Verified-status capture

Risk:
- leave the code-license scope untouched on paper, but move practical trust, discovery, or ecosystem participation behind a newly mandatory verified-only gate.

Response:
- registry separation and appeal path in `REGISTRY_TERMS.md`;
- rule that registry terms should not retroactively narrow code-license scope.

### 2.19 Data, export, or migration hostage tactics

Risk:
- withhold baseline export, migration, compatibility, or recovery material so that a separately monetized official path becomes the only realistic path.

Response:
- no artificial incompatibility rule in `SYSTEM_SCOPE.md`;
- anti-decay and documentation continuity in the license and `FEE_POLICY.md`.

## 3. Remaining limits

This bundle is intended to close many practical governance and monetization loopholes, but it still cannot fully prevent:

- an independent clean-room reimplementation,
- future litigation risk in hostile jurisdictions,
- or bad-faith actors ignoring the license until forced to respond.

It is therefore still important to combine the license with:

- centralized copyright control,
- trademark control,
- signed notices,
- public payment rails,
- and practical ecosystem value that is hard to fake.

## 4. Reading rule

If a future ambiguity appears between revenue protection and accessibility protection, the intended reading is:

- preserve the founder's valid economic right,
- preserve the integrated-system scope,
- preserve accessibility for ordinary operators where reasonably possible,
- and reject interpretations that turn maintenance, modularization, or compatibility into disguised exclusionary monetization.

## 5. Contact

Questions about anti-circumvention intent and future abuse scenarios may be directed to:

- `blackcatacademy@protonmail.com`
