# Third-party dependencies (optional)

These libraries are MIT/BSD licensed and safe for commercial use. They are optional; code falls back gracefully if absent.

- **luv** (MIT): event loop/timers. Install via `luarocks install luv`.
- **ed25519** (MIT): pure-Lua Ed25519 verify. Install via `luarocks install ed25519`.
- **lsqlite3** (MIT): persistent rate-limit store. Install via `luarocks install lsqlite3`.
- **luaossl** (OpenSSL/SSLeay): alternate crypto backend. Install via `luarocks install luaossl`.
- **lua-cjson** (MIT): JSON decode for Arweave response validation. Install via `luarocks install lua-cjson`.
- **weavedb-http** (optional client): if you later push PII-scrubbed exports to
  WeaveDB, keep in mind the database is immutable; only store public/pseudonymous
  payloads. Use the `AO_WEAVEDB_EXPORT_PATH`/`WRITE_OUTBOX_EXPORT_PATH` append-only
  logs and bundle from there instead of writing from AO directly.

If not installed, features degrade safely (signature enforcement fails closed when required, timers stay tick-based, response JSON validation is pattern-only).
