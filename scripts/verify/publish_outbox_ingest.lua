package.path =
  table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local apply = require "ao.ingest.apply"

-- Simulate a publish + shipment + payment flow landing on AO ingest.
local events = {
  {
    type = "PublishPageVersion",
    siteId = "s1",
    pageId = "home",
    versionId = "v1",
    manifestTx = "tx-test",
    requestId = "ao-1",
  },
  {
    type = "OrderCreated",
    orderId = "ao-order-1",
    siteId = "s1",
    totalAmount = 1234,
    currency = "USD",
    requestId = "ao-2",
  },
  {
    type = "ShipmentUpdated",
    shipmentId = "ship-ao-1",
    orderId = "ao-order-1",
    status = "shipped",
    carrier = "test-carrier",
    requestId = "ao-3",
  },
  {
    type = "PaymentStatusChanged",
    paymentId = "pay-ao-1",
    orderId = "ao-order-1",
    providerStatus = "paid",
    status = "captured",
    requestId = "ao-4",
  },
}

for _, ev in ipairs(events) do
  local ok, err = apply.apply(ev)
  assert(ok, err or ("handler missing for " .. tostring(ev.type)))
end

print "publish_outbox_ingest: ok"
