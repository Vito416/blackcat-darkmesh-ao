# Process Topology

Target split (aligned to architecture v2):

- **router/registry** – domains → site mapping, active version pointers, public keys,
  trusted resolvers list.
- **public_state** – published pages, layouts, navigation, SEO metadata, public
  configuration per site/version.
- **catalog** – public product/category payloads + hashes/asset references (no
  customer/PII).
- **permissions** – publish key registry, role → capability mapping for write
  acceptance, allowlist of who can link domains or rotate keys.
- **audit/events** – receipts and references emitted by `-write`; stores hashes and
  links to non-public payloads, never the payloads themselves.

Each process owns its schema and tests; shared libs live under `ao/shared`.
