package.path =
  table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local function assert_truthy(value, label)
  if not value then
    error(label .. " expected truthy")
  end
end

local function assert_eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function assert_not_hmac_blocked(resp, label)
  assert_truthy(type(resp) == "table", label .. " response")
  if resp.code == "FORBIDDEN" then
    local msg = tostring(resp.message or "")
    if msg:find("outbox_hmac", 1, true) then
      error(label .. " should not be blocked by OUTBOX_HMAC_SECRET")
    end
  end
end

local function assert_hmac_enforced(resp, label)
  assert_truthy(type(resp) == "table", label .. " response")
  assert_eq(resp.status, "ERROR", label .. " status")
  assert_eq(resp.code, "FORBIDDEN", label .. " code")
  local msg = tostring(resp.message or "")
  if msg ~= "missing_outbox_hmac" and msg ~= "outbox_hmac_mismatch" then
    error(label .. " expected outbox hmac rejection, got message=" .. msg)
  end
end

local outbox_secret = os.getenv "OUTBOX_HMAC_SECRET"
if not outbox_secret or outbox_secret == "" then
  error "OUTBOX_HMAC_SECRET must be set for outbox_hmac_separation.lua"
end

local function rid(prefix)
  return string.format("%s-%d-%04d", prefix, os.time(), math.random(0, 9999))
end

local site = require "ao.site.process"
local registry = require "ao.registry.process"
local catalog = require "ao.catalog.process"
local access = require "ao.access.process"

local site_read = site.route {
  Action = "ResolveRoute",
  ["Request-Id"] = rid "site-read",
  ["Site-Id"] = "verify-site",
  Path = "/",
}
assert_not_hmac_blocked(site_read, "site read")

local registry_read = registry.route {
  Action = "GetSiteByHost",
  ["Request-Id"] = rid "registry-read",
  Host = "verify.example.test",
}
assert_not_hmac_blocked(registry_read, "registry read")

local catalog_read = catalog.route {
  Action = "GetProduct",
  ["Request-Id"] = rid "catalog-read",
  ["Site-Id"] = "verify-site",
  Sku = "missing-sku",
}
assert_not_hmac_blocked(catalog_read, "catalog read")

local access_read = access.route {
  Action = "HasEntitlement",
  ["Request-Id"] = rid "access-read",
  Subject = "verify-subject",
  Asset = "verify-asset",
}
assert_not_hmac_blocked(access_read, "access read")

local site_write = site.route {
  Action = "PutDraft",
  ["Request-Id"] = rid "site-write",
  ["Site-Id"] = "verify-site",
  ["Page-Id"] = "home",
  Content = { title = "Verify", blocks = { { type = "paragraph", text = "verify" } } },
  ["Actor-Role"] = "editor",
}
assert_hmac_enforced(site_write, "site write")

local registry_write = registry.route {
  Action = "RegisterSite",
  ["Request-Id"] = rid "registry-write",
  ["Site-Id"] = "verify-site",
  Config = { version = "v1" },
  ["Actor-Role"] = "admin",
}
assert_hmac_enforced(registry_write, "registry write")

local catalog_write = catalog.route {
  Action = "UpsertProduct",
  ["Request-Id"] = rid "catalog-write",
  ["Site-Id"] = "verify-site",
  Sku = "verify-sku",
  Payload = { name = "Verify" },
  ["Actor-Role"] = "catalog-admin",
}
assert_hmac_enforced(catalog_write, "catalog write")

local access_write = access.route {
  Action = "GrantEntitlement",
  ["Request-Id"] = rid "access-write",
  Subject = "verify-subject",
  Asset = "verify-asset",
  Policy = "view",
  ["Actor-Role"] = "admin",
}
assert_hmac_enforced(access_write, "access write")

print "outbox_hmac_separation: ok"
