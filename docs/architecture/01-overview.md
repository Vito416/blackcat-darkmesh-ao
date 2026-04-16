# Architecture Overview

blackcat-darkmesh-ao is the **public, canonical AO layer** for Darkmesh. It carries only
data that may be published without secrets: site registry, routing, public page
metadata, SEO/navigation, catalog payload references, audit receipts, and the
public key/permission registry.

- **Responsibility:** serve resolvers/gateways with a stable public read model and
append-only audit metadata. Apply only the publish events emitted by
`blackcat-darkmesh-write`.
- **Boundary:** no draft content, no SMTP/OTP/PSP secrets, no mailbox payloads, no
template renderer or gateway runtime. Those live in `-write`, `-gateway`, or
`-web`.
- **Durability:** immutable payloads live on Arweave; AO stores hashes, tx IDs, and
lightweight normalized JSON for fast lookup.
- **Interoperability:** any gateway can read AO over HTTP; the Wedos-style gateway
  remains a thin cache/decoder, not a source of truth. Current adapter routes in
  this repo are intentionally minimal: `ResolveRoute`, `GetPage`, `CreateOrder`,
  and `CreatePaymentIntent` only.

See the companion briefs `blackcat-darkmesh-write-architecture-v2.docx`,
`blackcat-darkmesh-gateway-architecture-v2.docx`, and
`blackcat-darkmesh-web-architecture-v2.docx` for the surrounding layers.
