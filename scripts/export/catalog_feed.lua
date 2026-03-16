-- Export catalog products into NDJSON feed (PII-free) for search/merchant center.
-- Usage:
--   LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" \
--   CATALOG_FEED_PATH=./catalog.ndjson \
--   lua5.4 scripts/export/catalog_feed.lua
--
-- Reads in-process catalog state (including persisted AO_STATE_DIR if set).
-- Each line: {sku, siteId, payload}

local ok_json, cjson = pcall(require, "cjson.safe")
if not ok_json then
  ok_json, cjson = pcall(require, "cjson")
end

local function encode_fallback(obj)
  local t = type(obj)
  if t == "nil" then
    return "null"
  end
  if t == "boolean" then
    return obj and "true" or "false"
  end
  if t == "number" then
    return tostring(obj)
  end
  if t == "string" then
    return string.format("%q", obj)
  end
  if t == "table" then
    local is_array = true
    local idx = 0
    for k, _ in pairs(obj) do
      idx = idx + 1
      if obj[idx] == nil then
        is_array = false
        break
      end
    end
    if is_array then
      local parts = {}
      for _, v in ipairs(obj) do
        table.insert(parts, encode_fallback(v))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, string.format("%q:%s", tostring(k), encode_fallback(v)))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return '""'
end

local function encode(obj)
  if ok_json and cjson then
    return cjson.encode(obj)
  end
  return encode_fallback(obj)
end

local catalog = require "ao.catalog.process"
local state = catalog._state or {}
local path = os.getenv "CATALOG_FEED_PATH" or "catalog.ndjson"

local function write_line(f, obj)
  local line = encode(obj)
  f:write(line)
  f:write "\n"
end

local f = io.open(path, "w")
if not f then
  io.stderr:write("cannot open feed path: " .. tostring(path) .. "\n")
  os.exit(1)
end

for key, prod in pairs(state.products or {}) do
  -- key format product:<site>:<sku>
  local site, sku = key:match "^product:([^:]+):(.+)$"
  write_line(f, {
    sku = sku or prod.sku,
    siteId = site or prod.siteId,
    payload = prod.payload,
  })
end

f:close()
print("catalog_feed written to " .. path)
