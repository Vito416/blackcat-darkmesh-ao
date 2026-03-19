# Blackcat licensing model

Status: active project licensing guide for the Blackcat Covered System

This document explains the licensing model currently adopted across the official Blackcat repositories kept in `BLACKCAT_MESH_NEXUS`.

## 1. Active model

The active model is a **custom source-available network-use license** called **Blackcat Founder Network License 1.0 (BFNL 1.0)**.

Why this model exists:
- keep the code publicly auditable;
- keep adoption friction low for reading, testing, and internal development;
- reserve production and network-use monetization rights to the founder;
- keep future steward or development fees possible without allowing them to erase the founder fee;
- and prevent future governance from turning the system into a fragmented, exclusionary, dependency-captured monetization trap.

BFNL 1.0 is **not** an OSI open-source license. It is an intentionally custom covered-system license for a founder-fee and future-steward-fee model.

## 2. Covered System scope

The intended scope is the full Blackcat Covered System, not a single repository viewed in isolation.

Current workspace presumption:
- every official repository currently present under the top-level `BLACKCAT_MESH_NEXUS` workspace is part of the Covered System;
- every current internal top-level workspace directory in that same workspace is also presumed part of the Covered System unless a signed public notice expressly excludes it;
- repository separation exists for maintenance, safety, delivery, auditability, language boundaries, and operational clarity;
- repository separation does **not** by itself create a separate unavoidable founder-fee or steward/development-fee event for the same ordinary covered deployment.

## 3. Core economic rules

BFNL 1.0 and its companion documents are built around these rules:
- production use and network use are not free rights;
- a founder fee is reserved unless explicitly waived or transferred by signed public notice;
- future steward or development fees may exist, but they inherit the same accessibility and anti-capture guardrails as the founder fee;
- fee updates are prospective-only and bounded by the published fairness guard;
- equivalent-value settlement can be proven using sufficiently liquid publicly valued assets;
- the fee model should stay practically reachable for ordinary hosts, web operators, e-shop operators, gateway operators, and similar non-enterprise deployments;
- and no future maintainer should be able to sidestep those limits through repo splits, mandatory package capture, maintenance neglect, forced control planes, class resets, or similar tactics.

## 4. Authoritative documents

The active licensing bundle lives in `blackcat-darkmesh-ao/docs/`:

1. `BFNL-1.0.md`
2. `FEE_POLICY.md`
3. `TRADEMARKS.md`
4. `REGISTRY_TERMS.md`
5. `CONTRIBUTOR_TERMS.md`
6. `NOTICE_CHANNELS.md`
7. `DISPUTE_RESOLUTION.md`
8. `SYSTEM_SCOPE.md`
9. `AFFORDABILITY_BASELINE.md`
10. `ANTI_CIRCUMVENTION.md`
11. `LICENSING_SYSTEM_NOTICE.md`

Those files are intended to be read as one coordinated licensing system.

Current operational note:
- the current Founder Fee receiving address and the current Founder Notice authenticity reference temporarily use the same Ledger-backed Arweave identity;
- that shared identity is currently `SRNyOyOGqC5xSekIZeuy1T3Fho14U3-NerC_jeDwn78`;
- and the roles are intended to be separated later by valid Founder Notice without disturbing already valid payments.

## 5. Repository-local LICENSE files

Every official git repository currently present under `BLACKCAT_MESH_NEXUS` should carry the same active BFNL 1.0 text in its root `LICENSE` file.

That repository-local `LICENSE` file is the direct license notice for that repository. The companion documents in `blackcat-darkmesh-ao/docs/` provide the system-wide rules for fees, scope, succession, notices, registry treatment, affordability, and anti-circumvention.

## 6. GitHub metadata note

Because BFNL 1.0 is a custom license, GitHub may not display it like a standard SPDX-recognized open-source license. The authoritative licensing state therefore lives in:
- the committed `LICENSE` files in each official repository;
- the active BFNL 1.0 text;
- and the system notice for the Covered System.

GitHub repository metadata can still reinforce the model through topics and public repository descriptions, but the legal text itself lives in the repository files.

## 7. Contact

Licensing and permissions contact:
- `blackcatacademy@protonmail.com`

_This document is a project licensing guide, not legal advice. External legal review remains recommended._
