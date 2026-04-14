# Gateway <-> AO adapter guide (implemented vs planned)

AO remains the public, secretless read state. The gateway layer is replaceable.
This document describes the route/action surface that is currently implemented in
this repository, and what is still planned.

## Implemented now (adapter surface)

Current HTTP routes exposed by adapters in this repo:

- `POST /api/public/resolve-route` -> AO action `ResolveRoute`
- `POST /api/public/page` -> AO action `GetPage`
- `POST /api/checkout/order` -> write command `CreateOrder` (worker adapter only)
- `POST /api/checkout/payment-intent` -> write command `CreatePaymentIntent` (worker adapter only)

Health/check endpoints:

- `GET /healthz` in `scripts/http/public_api_server.mjs`
- `GET /health` and `GET /api/health` in `worker/src/index.ts`

Adapter implementations:

- `scripts/http/public_api_server.mjs`: read-only adapter (`resolve-route`, `page`)
- `worker/src/index.ts`: read adapter + checkout write adapter

## Currently supported request semantics

- `GetPage` supports `Page-Id` or `Slug`/`Path` fallback (slug/path maps to route then page).
- Checkout write routes are fixed per path:
  - `/api/checkout/order` accepts only `CreateOrder` (or alias `checkout.create-order`).
  - `/api/checkout/payment-intent` accepts only `CreatePaymentIntent` (or alias `checkout.create-payment-intent`).
- Site scope is strict: top-level `siteId`, `payload.siteId`, and `x-bridge-site-id` must match when provided.

## Planned (not implemented by current adapter routes)

The following are not currently exposed as gateway adapter HTTP routes in this
repo, even if AO processes may support some of them directly:

- Additional read routes for registry/catalog/access actions (for example:
  `GetSiteByHost`, `GetSiteConfig`, `ResolveGatewayForHost`, `ListGateways`,
  `GetLayout`, `GetNavigation`, `GetProduct`,
  `ListCategoryProducts`, `GetCategory`, `ListCategories`, `SearchCatalog`,
  `FacetSearch`, `RelatedProducts`, `RecentlyViewed`, `GetRecommendations`,
  `GetResolverFlags`, `GetTrustedResolvers`, `HasEntitlement`).
- Additional write routes for payment status/webhook updates, passwordless
  session lifecycle, or gateway-flag submissions.

## Security and data handling rules (still valid)

- Do not send plaintext PII or PSP secrets through AO/read state.
- Keep OTP/PII envelopes in TTL storage only (`/inbox` + janitor); wipe on expiry.
- Keep identity mapping secrets, PSP/SMTP/API keys, and private key material
  outside AO.
