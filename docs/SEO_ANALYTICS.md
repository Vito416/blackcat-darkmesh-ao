# SEO / Analytics / Risk stubs

- SEO: structured-data helper exists via `ao.shared.analytics` (page/product/risk events with metrics + log).
- Locale fallback: handled at resolver layer by passing locale list; add tenants' fallback chain in config (see resolver docs).
- Analytics: page/product view emitters available in `ao.shared.analytics` (counts + NDJSON log via METRICS_LOG).
- Risk/Fraud: `ao.shared.analytics.risk_event(kind, attrs)` for hashed signals; metrics `ao_risk_event_total`.
- Subscriptions: TODO recurring billing hooks and churn analytics (still open).
