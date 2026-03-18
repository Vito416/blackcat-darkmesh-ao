package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local schema = require "ao.shared.schema"

local ok, err = schema.validate("page", { id = "p1", title = "Home", blocks = { { type = "text" } } })
assert(ok, err and err[1] or "expected page schema to pass")

local bad_ok, bad_errs = schema.validate("page", { title = "Missing ID" })
assert(bad_ok == false, "expected invalid page without id to fail validation")
assert(type(bad_errs) == "table" and #bad_errs > 0, "expected validation errors array")

print "schema_validation_spec: ok"
