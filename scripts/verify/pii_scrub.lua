package.path =
  table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")
local export = require "ao.shared.export"
local function assert_ok(cond, msg)
  if not cond then
    io.stderr:write(msg .. "\n")
    os.exit(1)
  end
end
local sample = {
  address = "secret",
  email = "user@example.com",
  token = "t",
  nested = { phone = "123", keep = "ok" },
  keep = "yes",
}
local scrubbed = export._scrub(sample)
assert_ok(scrubbed.address == nil, "address not scrubbed")
assert_ok(scrubbed.email == nil, "email not scrubbed")
assert_ok(scrubbed.token == nil, "token not scrubbed")
assert_ok(scrubbed.nested and scrubbed.nested.phone == nil, "nested phone not scrubbed")
assert_ok(scrubbed.keep == "yes", "keep lost")
assert_ok(scrubbed.nested.keep == "ok", "nested keep lost")
print "pii_scrub: ok"
