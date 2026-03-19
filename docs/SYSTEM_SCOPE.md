# Blackcat System Scope and Modularization Policy

Status: active companion policy text for BFNL 1.0

This document explains how the founder-fee licensing model is intended to apply across the Blackcat system when the system is split across multiple repositories, packages, services, or internal components for operational reasons.

## 1. Purpose

The Blackcat ecosystem may be maintained across multiple repositories and packages for:

- easier maintenance,
- clearer boundaries,
- safer deployments,
- language-specific tooling,
- or operational scalability.

That modular structure is not intended to multiply founder-fee obligations merely because the system is split into several repositories.

## 1A. NEXUS workspace presumption

Unless a signed public Founder Notice expressly excludes a component, every official repository and internal workspace directory currently maintained inside the top-level `BLACKCAT_MESH_NEXUS` workspace should be presumed part of the same Covered System. That presumption applies even when a component is not separately versioned as its own repository, so shared tests, supporting tooling, migration material, internal manifests, and other internal workspace materials are not excluded merely because they live as directories rather than standalone repositories.

## 2. Integrated system intent

The intended rule is that the following should be treated as parts of one integrated system when they are published or maintained as interoperating official components of the Blackcat ecosystem:

- core runtime repositories,
- AO or write-side repositories,
- gateway and web-facing repositories,
- installer and configuration repositories,
- official manifests, schemas, contracts, and support tooling,
- and future internal packages published as official system components.

Repository separation is understood as a maintenance and delivery choice, not as proof that each repository creates an independent founder-fee event.

## 3. No per-repository multiplication by default

Unless a published fee schedule expressly defines a genuinely separate coverage class, the founder-fee model should not be interpreted as requiring a separate mandatory payment merely because:

- an operator clones more than one official repository,
- an official deployment depends on multiple official system repositories,
- or a function is split into several internal packages for engineering reasons.

The intended billing unit remains the covered deployment, operator class, gateway, site, shop, or other defined operational scope described by the fee policy.

## 4. Ordinary deployment rule

For ordinary deployments, the intended rule is:

- one covered deployment should pay according to its coverage class;
- all official repositories and internal components reasonably necessary for that same ordinary deployment should be treated as part of the same integrated licensing surface;
- and the founder fee should not be multiplied simply because the internal implementation is modular.

## 5. Anti-fragmentation rule

The founder-fee model should not be circumvented or expanded through artificial modular fragmentation.

Accordingly, the Licensor, founder-controlled entity, Steward, or Lawful Successor should not:

- split a function previously understood as part of the ordinary system into a new mandatory internal repository or package solely to create an additional unavoidable fee layer;
- relabel an essential internal dependency as a separate product if the practical effect is to bypass the Accessibility Principle;
- or structure ordinary system operation so that a smaller operator must buy multiple mandatory internal components merely to obtain baseline functionality that the system was reasonably expected to provide as part of the integrated deployment.

## 6. Mandatory vs optional components

The intended distinction is:

- `Mandatory Internal Component`: a component without which the relevant ordinary deployment class cannot practically function as intended.
- `Optional Component`: an enhancement, premium add-on, enterprise feature, or specialized tool that is not required for a standard deployment class to operate in its intended baseline mode.

Mandatory internal components for an ordinary coverage class should be treated as part of the same integrated licensing surface unless a clearly differentiated coverage class is published in good faith.

Optional components may be offered under separate commercial terms if:

- their optional nature is genuine and not pretextual;
- the standard deployment class remains practically operable without them;
- and their pricing does not nullify the Accessibility Principle through indirect compulsion.

## 7. No dependency capture

The system should not be future-fragmented in a way that creates dependency capture.

The intended non-capture rule is that no future official internal package should be made both:

- materially necessary for ordinary system operation,
- and separately unavoidable at a price that would make the integrated system materially less accessible than the founder-fee model originally intended.

If an internal package becomes materially necessary for ordinary operation, the default presumption should be that it belongs inside the same integrated founder-fee surface for that deployment class unless a clearly justified and non-exclusionary distinction is published.

## 8. Future packages and successor governance

Any future Steward or Lawful Successor should interpret modularization consistently with:

- the Accessibility Principle,
- the Founder Accessibility Declaration,
- the Non-Exclusionary Enforcement Covenant,
- and the anti-fragmentation intent of this policy.

Lawful successors may create new products, premium tiers, enterprise offerings, or optional commercial services, but should not use repository splits or mandatory internal dependencies as a disguised method of imposing duplicative founder-fee equivalents on ordinary operators.

## 9. Maintenance continuity and no-decay capture

The integrated-system rule also applies over time, not only at the moment a package is introduced.

Accordingly, the Licensor, founder-controlled entity, Steward, or Lawful Successor should not:

- intentionally or through unreasonable neglect allow a Mandatory Internal Component for an ordinary deployment class to decay into insecurity, incompatibility, or practical unusability so that a separately priced replacement becomes the only realistic path;
- withhold ordinary maintenance, migration notes, security fixes, or minimal interoperability information as a disguised monetization lever;
- or deprecate baseline functionality without either a reasonable transition path or a compatible successor inside the same integrated fee surface for the same ordinary deployment class.

Ordinary operators who have already satisfied the applicable founder-fee obligation should not be forced into a new unavoidable payment surface merely because a baseline module was later renamed, replaced, split out, or commercially repositioned.

## 10. No artificial incompatibility or protocol capture

The official ecosystem should not use avoidable compatibility breakage as a monetization tactic.

Accordingly, public manifests, schemas, trust material, migration instructions, interoperability formats, and baseline protocol behaviors reasonably necessary for ordinary operation should remain publicly documented and reasonably stable, subject to ordinary security updates and good-faith technical evolution.

The Licensor, founder-controlled entity, Steward, or Lawful Successor should not:

- introduce artificial incompatibilities whose practical effect is to strand ordinary operators on unsupported paths unless they buy a separately monetized bridge, translation layer, or managed service;
- withhold baseline export, migration, or compatibility information needed to keep a covered ordinary deployment functioning;
- or use closed compatibility shims as the only practical path for a class previously treated as an ordinary deployment class.

## 11. No mandatory control-plane capture

Already validly paid rights for an ordinary deployment class should not be made dependent on a new mandatory always-online proprietary control service, entitlement server, or centrally hosted management dependency if a public, offline-verifiable, or self-hostable verification path remains reasonably possible.

Centralized services may be offered for convenience, security, support, or premium operations, but ordinary baseline operation should not be silently converted into a dependency-captured service model.

The same rule applies to private artifact feeds, package feeds, trust feeds, update channels, or hosted build/distribution paths. Such channels may exist as convenience or premium services, but they should not become the only practical way for an already covered ordinary deployment class to remain functional where a public or self-build path remains reasonably possible.

## 12. No abusive reclassification of ordinary deployments

An Ordinary Deployment Class should not be reclassified into a premium, enterprise, or special paid class merely because of:

- repository or package restructuring;
- a version-line change;
- a runtime or language split;
- a documentation or tooling reorganization;
- or another internal architectural change that does not itself create a genuinely different operational burden.

If a dispute arises, the default presumption should favor continuity of ordinary deployment treatment unless a clearly differentiated operational basis is published in good faith.

## 13. Relationship to fee policy

The fee policy should define:

- the ordinary coverage classes,
- what one payment covers,
- and whether any component class is optional, enterprise-only, or separately priced.

If a dispute arises, ambiguity should be resolved in favor of integrated treatment for ordinary mandatory system components unless the published policy clearly and non-pretextually states otherwise.

## 14. Contact

Questions about system scope, modularization, and integrated fee coverage may be directed to:

- `blackcatacademy@protonmail.com`
