# Integration tests

Run with `LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" lua5.4 tests/integration/*.lua`.
Current scaffolding covers ingest apply (happy + error path) and schema validation regression.
