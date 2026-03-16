# Security Model

- **Public by design:** assume full disclosure; keep metadata minimal and
  non-sensitive.
- **Ingress control:** accept publish/apply events only from
  `blackcat-darkmesh-write`, signed and tagged with `Request-Id/Publish-Id`.
  Enforce schema + size validation and append-only history.
- **No secrets:** never store private keys, OTP/PSP credentials, mailbox
  ciphertext, or raw form payloads. Only store hashes/references.
- **Anti-abuse:** optional nonce/replay window for resolver calls,
  tenant-scoped rate limits, and trusted-resolver allowlist.
- **Key registry:** public keys and roles are verifiable but contain no private
  material; rotation handled via write commands.
