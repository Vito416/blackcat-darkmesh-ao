local require_luv = os.getenv "DEPS_REQUIRE_LUV" == "1"

local deps = {
  {
    name = "luv",
    mods = { "luv" },
    optional = not require_luv,
    note = "optional for preflight (required only for timer/event-loop integrations)",
  },
  {
    name = "lsqlite3",
    mods = { "lsqlite3" },
    optional = true,
    note = "optional for preflight (auth falls back to in-memory/file state when sqlite is unavailable)",
  },
  { name = "cjson", mods = { "cjson.safe", "cjson" } },
  {
    name = "luaossl",
    mods = { "openssl" },
    optional = true,
    note = "optional for preflight (openssl/sodium fallback paths are available)",
  },
  { name = "sodium", mods = { "sodium", "luasodium" } },
}

local function require_any(label, modules)
  for _, m in ipairs(modules) do
    local ok = pcall(require, m)
    if ok then
      io.stdout:write(string.format("%-10s: available (%s)\n", label, m))
      return true
    end
  end
  io.stdout:write(string.format("%-10s: missing\n", label))
  return false
end

-- core deps
for _, d in ipairs(deps) do
  local ok = require_any(d.name, d.mods)
  if not ok and d.optional then
    if d.note then
      io.stdout:write(string.format("%-10s: %s\n", d.name, d.note))
    end
  elseif not ok then
    os.exit(1)
  end
end

-- Ed25519 signer: allow either ed25519 rock or sodium providing crypto_sign_* API
local ed25519_ok = require_any("ed25519", { "ed25519", "sodium", "luasodium" })
if not ed25519_ok then
  os.exit(1)
end

-- Fail-closed if signatures required and no sodium available (used for ed25519)
if os.getenv "AUTH_REQUIRE_SIGNATURE" == "1" then
  local ok_sodium = pcall(require, "sodium")
  if not ok_sodium then
    io.stderr:write "sodium module missing but AUTH_REQUIRE_SIGNATURE=1\n"
    os.exit(1)
  end
end
