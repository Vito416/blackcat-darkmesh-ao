# Sample Prometheus alerts (Worker)

- alert: WorkerInboxRateLimit
  expr: increase(worker_rate_limit_blocked_total[1m]) > 5
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Worker inbox rate-limit firing"
    description: "Too many inbox requests blocked; check abusive clients or raise thresholds if expected."

- alert: WorkerNotifyRateLimit
  expr: increase(worker_notify_rate_blocked_total[5m]) > 3
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Notify rate-limit firing"
    description: "Notification relay throttled; review NOTIFY_RATE_MAX/NOTIFY_RATE_WINDOW."

- alert: WorkerInboxReplay
  expr: increase(worker_inbox_replay_total[5m]) > 3
  for: 2m
  labels:
    severity: info
  annotations:
    summary: "Inbox replay attempts detected"
    description: "Repeated duplicate subject+nonce submissions; investigate clients or gateway."

- alert: WorkerInboxExpired
  expr: increase(worker_inbox_expired_total[10m]) > 100
  for: 5m
  labels:
    severity: info
  annotations:
    summary: "Many envelopes expiring in worker"
    description: "High expirations; check TTL settings vs processing latency."

- alert: WorkerForgetDeletes
  expr: increase(worker_forget_deleted_total[5m]) > 50
  for: 5m
  labels:
    severity: info
  annotations:
    summary: "Frequent forget requests"
    description: "Elevated forget deletions; verify AO/ForgetSubject or abuse."

- alert: WorkerNotifyFailures
  expr: increase(worker_notify_failed_total[5m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Notify delivery failures"
    description: "Notification retries exhausted (webhook/SendGrid). Check NOTIFY target health and secrets."

- alert: WorkerNotifyBreakerOpen
  expr: increase(worker_notify_breaker_open_total[5m]) > 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Notify breaker tripped"
    description: "Circuit breaker opened for notify target. Investigate webhook/SendGrid outages."

## Scrape example
```
scrape_configs:
  - job_name: worker
    static_configs:
      - targets: ["worker.local:8787"]
    metrics_path: /metrics
    basic_auth:
      username: ${WORKER_METRICS_USER}
      password: ${WORKER_METRICS_PASS}
```
