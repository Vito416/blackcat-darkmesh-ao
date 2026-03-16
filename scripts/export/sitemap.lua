-- Generate sitemap.xml from catalog state (products only).
-- Usage:
--   LUA_PATH="?.lua;?/init.lua;ao/?.lua;ao/?/init.lua" \
--   BASE_URL="https://example.com" \
--   SITEMAP_PATH=./sitemap.xml \
--   lua5.4 scripts/export/sitemap.lua
--
-- Requirements:
-- - BASE_URL must be set (no trailing slash).
-- - Reads in-process catalog state (including persisted AO_STATE_DIR if set).

local base_url = os.getenv("BASE_URL")
if not base_url or base_url == "" then
  io.stderr:write("BASE_URL is required (e.g., https://example.com)\n")
  os.exit(1)
end
base_url = base_url:gsub("/+$", "")

local path = os.getenv("SITEMAP_PATH") or "sitemap.xml"

local catalog = require "ao.catalog.process"
local state = catalog._state or {}

local function xml_escape(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  s = s:gsub("\"", "&quot;"):gsub("'", "&apos;")
  return s
end

local lines = {}
table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')
table.insert(lines, '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')

for key, prod in pairs(state.products or {}) do
  local site, sku = key:match("^product:([^:]+):(.+)$")
  local slug = prod.payload and (prod.payload.slug or prod.payload.url or sku) or sku
  if slug then
    local loc = base_url .. "/" .. xml_escape(slug)
    table.insert(lines, "  <url>")
    table.insert(lines, "    <loc>" .. loc .. "</loc>")
    table.insert(lines, "  </url>")
  end
end

table.insert(lines, "</urlset>")

local f = assert(io.open(path, "w"))
f:write(table.concat(lines, "\n"))
f:write("\n")
f:close()

print("sitemap written to " .. path)
