# Sample Prometheus alerts

```
# Checksum daemon failures
- alert: AOChecksumDaemonDown
  expr: probe_success{job="ao-checksum"} == 0
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "AO checksum daemon not running"

# Rate limit error spikes (example metric name if exported)
- alert: AORateLimitErrors
  expr: increase(ao_rate_limited_total[5m]) > 10
  labels:
    severity: warning
  annotations:
    summary: "AO rate-limit errors high"

# Outbox/WAL checksum drift
- alert: AOChecksumMismatch
  expr: increase(ao_checksum_mismatch_total[5m]) > 0
  labels:
    severity: critical
  annotations:
    summary: "AO checksum mismatch detected"

# Queue lag (if exported)
- alert: AOQueueLagHigh
  expr: ao_outbox_queue_size > 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "AO outbox queue backlog high"

# Ingest apply failures (AO applying write outbox)
- alert: AOIngestApplyFailures
  expr: increase(ao_ingest_apply_failed_total[5m]) > 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "AO ingest apply failures"
    description: "Failed to apply write outbox events. Check AO logs and schema drift."

# Gateway cache health (hit ratio)
- alert: AOGatewayCacheLowHit
  expr: (1 - (sum(rate(gateway_cache_hits_total[5m])) / sum(rate(gateway_cache_requests_total[5m])))) > 0.4
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Gateway cache hit ratio low"
    description: "Cache hit ratio <60%. Check TTLs/invalidations or upstream latency."

# Ingest queue lag (if exported)
- alert: AOIngestQueueLag
  expr: ao_ingest_queue_lag_seconds > 30
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "AO ingest queue lag high"
    description: "Apply loop delayed. Investigate worker saturation or schema errors."
```

Adjust metric names to your scrape config; checksum daemon can expose a blackbox probe or use systemd service monitor.

## Prometheus scrape example
```
scrape_configs:
  - job_name: ao
    static_configs:
      - targets: ["ao.yourdomain:9100"]   # expose METRICS_PROM_PATH via node/sidecar
    metrics_path: /metrics
  - job_name: gateway
    static_configs:
      - targets: ["gateway.yourdomain:9200"]  # exports cache hit/miss + TTL metrics
    metrics_path: /metrics
```
