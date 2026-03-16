-- Bundle PII-scrubbed export NDJSON into a single JSON array for WeaveDB/Arweave upload.
-- Usage:
--   LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" \
--   AO_WEAVEDB_EXPORT_PATH=/var/lib/ao/public-export.ndjson \
--   lua5.4 scripts/export/bundle_export.lua > bundle.json
--
-- Notes:
-- - Input must already be scrubbed (see ao.shared.export).
-- - Output is a compact JSON array of event objects; WeaveDB is immutable so
--   do not include PII here.

local path = os.getenv "AO_WEAVEDB_EXPORT_PATH" or "public-export.ndjson"
local json_ok, cjson = pcall(require, "cjson.safe")
if not json_ok then
  io.stderr:write "cjson.safe not available\n"
  os.exit(1)
end

local f = io.open(path, "r")
if not f then
  io.stderr:write("cannot open export file: " .. tostring(path) .. "\n")
  os.exit(1)
end

local rows = {}
for line in f:lines() do
  if line and line:match "%S" then
    local obj = cjson.decode(line)
    if obj then
      table.insert(rows, obj)
    end
  end
end
f:close()

local out = cjson.encode(rows)
io.write(out)
