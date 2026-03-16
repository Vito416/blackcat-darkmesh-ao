# Data Model

- **Primary stores:** document/NoSQL keyed maps for `sites`, `domains`,
  `routes`, `pages`, `layouts`, `navigation`, `products`, `categories`,
  `versions`, `asset_refs`, `permissions`.
- **Public-only:** every record must be safe to publish. Sensitive payloads are
  represented by hashes and tx references only (no plaintext mailbox/forms/IP
  logs/PII).
- **Immutable payloads:** large pages/media/catalog exports live on Arweave (or
  another perma store). AO keeps `txId`, `contentHash`, `mime`, `size`.
- **Audit receipts:** append-only, referencing external ciphertext locations or
  gateway/web worker mailboxes; the ciphertext itself never lives here.
- **Versioning:** append-only publish history; `activeVersion` per site points to
  the current public manifest.
