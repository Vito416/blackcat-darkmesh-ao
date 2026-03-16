# AO (read) Roadmap – 99% web/eshop coverage

## Feeds / SEO
- NDJSON exports: catalog (products/variants/prices), sitemap, merchant feeds (Google/Bing), robots.txt generator.
- Sitemap builder from AO state; incremental export on catalog changes.
- Search index export (title, description, tags, availability); hook for external indexer.

## State & snapshots
- Versioned schema manifest validation in CI (read-side state, snapshots, WAL).
- Export verifier: hash/size check of NDJSON bundle before publish.

## Observability
- Metrics: ingest_apply_errors, outbox_lag_seconds (from Write), cache_hit/miss (gateway), sitemap_export_duration, feed_export_errors.
- Alerts: ingest error rate >0 over 5m; outbox lag > threshold; feed export failures.

## Security/Privacy
- Data access/forget flow: ensure pseudonymized public state; expose minimal ForgetSubject result for audit (no PII).
- Rate-limit on public endpoints; throttling by IP/UA.

## Performance
- Optional edge render hint: inject public state snapshot for landing pages.
- Prefetch hints for hot catalog pages.

## Testing
- CI: validate NDJSON feed shape; schema manifest check; ingest smoke already in place.
