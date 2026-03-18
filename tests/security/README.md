# Security regression scaffolding

Run with `LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" lua5.4 tests/security/*.lua`.
Covers rate-limit/replay protections and PII scrubbing regression.
