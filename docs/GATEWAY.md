# Gateway ↔ AO quick guide (public runtime, secretless)

AO je public state. Gateway je replaceable cache/translator bez tajemství. Níže
je minimální smlouva pro aktuální scope (web + e‑shop + passwordless login).

## Read (gateway → AO)
- Catalog/pages: `GetProduct`, `ListCategoryProducts`, `GetCategory`,
  `ListCategories`, `SearchCatalog`, `FacetSearch`, `RelatedProducts`,
  `RecentlyViewed`, `GetRecommendations`.
- Site: `ResolveRoute`, `GetPage`, `GetLayout`, `GetNavigation`.
- Registry: `GetSiteByHost`, `GetSiteConfig`, `GetTrustedResolvers`,
  `GetResolverFlags`.
- Orders (public metadata only): `GetOrder`, `ListOrders`.
- Sessions: validate by checking session hash in AO `sessions` (ingest keeps
  hashes only, žádné secret klíče).

## Write (gateway → write)
- Scoped commands:
  - `CreateOrder` (pseudonymní `Customer-Ref` hash, amount/currency/items).
  - `UpdatePaymentStatus` (gateway/web worker po PSP callbacku).
  - `IssueLoginToken` / `ConfirmLoginToken` / `DestroySession`.
  - `FlagGateway` (když gateway zjistí podezřelé chování jiné gatewaye nebo sama
    sebe označí pro quarantine).
- Gateway nesmí posílat plaintext PII ani PSP tajemství; pouze hashované
  identifikátory (např. `Customer-Ref`, `Token-Hash`, `Session-Hash`).

## Passwordless flow (secretless AO)
1) Gateway/worker vygeneruje token HMAC lokálním tajemstvím (mimo AO), pošle
   e‑mail/SMS. Do write pošle `IssueLoginToken` s `Token-Hash`, `Subject`,
   `Expires-At`.
2) Klient vrátí token → gateway ověří HMAC lokálně → pošle do write
   `ConfirmLoginToken` s `Token-Hash`, `Session-Hash`, `Expires-At`.
3) Write emituje `SessionStarted`; ingest uloží hash do AO. Gateway při každém
   requestu jen porovná hash (žádný tajný klíč v AO).
4) Logout → `DestroySession` → ingest smaže hash.

## Bad-behaviour detection (gateway list)
- Gateway může hlásit incidenty přes `FlagGateway` (action → event
  `GatewayFlagged`).
- AO ingest zapisuje `resolver_flags[gatewayId] = {flag,reason,ts}`. Klienti
  mohou číst přes `GetResolverFlags` a vynechat/karantenovat označené gatewaye.

## PSP / platby
- PSP tajemství a webhooky zůstávají ve workeru/gateway; do write/AO jde pouze:
  - `CreateOrder` s částkou/menou a hash customerRef.
  - `UpdatePaymentStatus` s novým stavem (pending/paid/failed/refunded…).
- AO drží jen public order metadata (bez PII), takže je cache‑safe a auditable.

## Cache/TTL policy (gateway)
- Šifrované obálky (OTP/PII) drž jen v RAM/disk cache s pevným TTL (např. 15–60 min) a wipe-on-expire. Nikdy neukládej na Arweave.
- Exportuj metriky: `gateway_cache_requests_total`, `gateway_cache_hits_total`, `gateway_cache_evictions_total`, `gateway_cache_ttl_seconds` (max configured), `gateway_cache_live_items`.
- Při změně order/status/catalog invaliduj cache daného klíče (hash siteId/route/orderId); mimo to nech krátké TTL + stale-while-revalidate pro čtení obsahu.
- Při cache-missu nepropouštěj PII; AO vrací jen pseudonymní stav, takže cache je bezpečná.

## Bezpečnostní pravidla
- Povinné tagy: `Action`, `Request-Id`, `Actor-Role` (pro write commands),
  `Nonce`/`Signature-Ref` dle vaší politiky; AO/ingest je secretless.
- Gateway podpisy/nonce/ratelimits si řiďte na gateway vrstvě; AO nesmí spoléhat
  na tajné klíče.

## Co zůstává offline
- Mapování e‑mail/telefon → subjectId.
- PSP/SMTP/API klíče, salts pro hashování identit.
- Citlivé payloady (faktury, účtenky, PII) v admin inboxu / offline DB.
