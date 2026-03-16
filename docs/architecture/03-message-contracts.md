# Message Contracts

## Read surface (AO)
- `GetSiteByHost`
- `ResolveRoute`
- `GetPage`
- `GetLayout`
- `GetNavigation`
- `GetProduct`
- `ListCategoryProducts`
- `HasEntitlement`
- `GetPublishedVersion`

Tags on responses: `Action`, `Site-Id`, `Version`, `Locale`, `Request-Id`,
`Schema-Version`, optional `Nonce` for cache-busting hints.

## Ingest surface (from `blackcat-darkmesh-write` only)
- `PublishVersionApplied`
- `LinkDomainApplied`
- `RotateKeyApplied`
- `PermissionUpdated`
- `AuditReceiptRecorded`

Required tags: `Action`, `Site-Id`, `Publish-Id`, `Version`, `Schema-Version`,
`Timestamp`, `Request-Id`, `Signature-Ref`, hash/tx refs for immutable payloads.
Gateways/clients **must not** call these; they flow only from the write process.
