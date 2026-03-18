package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local export = require "ao.shared.export"
local scrub = export._scrub

local cleaned =
  scrub { email = "hidden@example.com", Subject = "secret", nested = { phone = "123", keep = "ok" }, ok = true }

assert(cleaned.email == nil, "email should be scrubbed")
assert(cleaned.Subject == nil, "Subject should be scrubbed")
assert(cleaned.nested.phone == nil, "nested phone should be scrubbed")
assert(cleaned.nested.keep == "ok", "non-PII fields should remain")
assert(cleaned.ok == true, "non-PII boolean should remain")

print "pii_regression_spec: ok"
