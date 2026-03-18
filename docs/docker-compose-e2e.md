# Docker Compose E2E (optional)

Minimal compose to smoke write→gateway→worker→ao flow locally (no persistence):

```yaml
version: '3.9'
services:
  write:
    image: lua:5.4
    working_dir: /app
    volumes:
      - ../blackcat-darkmesh-write:/app:ro
    environment:
      OUTBOX_HMAC_SECRET: ${OUTBOX_HMAC_SECRET:?set}
      WRITE_REQUIRE_SIGNATURE: '0'
      WRITE_REQUIRE_NONCE: '0'
      METRICS_PROM_PATH: /tmp/metrics.prom
    command: ["lua", "scripts/verify/publish_outbox_mock_ao.lua"]

  gateway:
    build: ../blackcat-darkmesh-gateway
    environment:
      METRICS_BASIC_USER: prom
      METRICS_BASIC_PASS: prompass
      PAYPAL_WEBHOOK_SECRET: test
      GW_CERT_PIN_SHA256: ''
    command: ["npm", "test", "--", "--run", "tests/metrics-auth.test.ts"]

  worker:
    build: ../blackcat-darkmesh-ao/worker
    environment:
      TEST_IN_MEMORY_KV: '1'
      INBOX_HMAC_SECRET: change-me
      NOTIFY_HMAC_SECRET: change-me
      METRICS_BASIC_USER: prom
      METRICS_BASIC_PASS: prompass
    command: ["npm", "test", "--", "--run", "tests/metrics-auth.test.ts"]
```

Use as a template; wire real routes instead of tests for a full flow. Keep secrets in a `.env` passed via `--env-file` (no literals in the YAML).
