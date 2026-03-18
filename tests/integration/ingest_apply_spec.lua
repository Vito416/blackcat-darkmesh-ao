package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local metrics = require "ao.shared.metrics"
metrics._reset()

local apply = require "ao.ingest.apply"

local ok, err = apply.apply {
  type = "RouteUpserted",
  siteId = "site-test",
  path = "/home",
  target = "page:home",
  Timestamp = os.time() - 5,
}
assert(ok, err or "expected RouteUpserted to succeed")

local ok2, err2 = apply.apply {}
assert(ok2 == false, "missing event must fail")
assert(err2, "missing event should return error reason")

assert(metrics.get("ao_ingest_apply_ok") >= 1, "apply success counter not incremented")
assert(metrics.get("ao_ingest_apply_failed") >= 1, "apply failure counter not incremented")
local lag = metrics.get_gauge("ao_outbox_lag_seconds")
assert(lag == nil or lag >= 0, "outbox lag gauge should be non-negative when set")

print "ingest_apply_spec: ok"
