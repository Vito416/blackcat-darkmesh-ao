# Message Contracts

## Read surface (AO actions, direct message calls)
- `GetSiteByHost`
- `GetSiteConfig`
- `ResolveRoute`
- `GetPage`
- `GetLayout`
- `GetNavigation`
- `GetProduct`
- `ListCategoryProducts`
- `SearchCatalog`
- `FacetSearch`
- `GetCategory`
- `ListCategories`
- `RelatedProducts`
- `RecentlyViewed`
- `GetRecommendations`
- `GetOrder`
- `ListOrders`
- `GetTrustedResolvers`
- `GetResolverFlags`
- `HasEntitlement`

Tags on responses: `Action`, `Site-Id`, `Version`, `Locale`, `Request-Id`,
`Schema-Version`, optional `Nonce` for cache-busting hints.

## Gateway HTTP adapter surface (implemented now)
- `POST /api/public/resolve-route` -> `ResolveRoute`
- `POST /api/public/page` -> `GetPage`
- `POST /api/checkout/order` -> `CreateOrder`
- `POST /api/checkout/payment-intent` -> `CreatePaymentIntent`

Only the four routes above are currently exposed by adapter HTTP endpoints in
this repo. Other AO actions remain direct AO contracts until additional adapter
routes are implemented.

## Adapter actions planned (not implemented as routes yet)
- Extra read route coverage for registry/catalog/access actions.
- Extra write route coverage for payment webhook/status updates, session/OTP
  lifecycle commands, and gateway-flag commands.

## Ingest surface (from `blackcat-darkmesh-write` only)
Ingest dispatch is keyed by `ev.action`/`ev.type` in `ao/ingest/apply.lua`.
Current handlers include (examples): `RouteUpserted`, `PublishPageVersion`,
`ProductUpserted`, `OrderCreated`, `OrderStatusUpdated`,
`PaymentIntentCreated`, `PaymentStatusChanged`, `DomainLinked`,
`EntitlementGranted`, `SessionStarted`, `SessionRevoked`, `GatewayFlagged`.

Required tags: `Action`, `Site-Id`, `Publish-Id`, `Version`, `Schema-Version`,
`Timestamp`, `Request-Id`, `Signature-Ref`, hash/tx refs for immutable payloads.
Gateways/clients **must not** call these; they flow only from the write process.
