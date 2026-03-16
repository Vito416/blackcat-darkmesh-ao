-- Minimal smoke for AO: load key processes to ensure they parse under Lua 5.4.
package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local ok, catalog = pcall(require, "ao.catalog.process")
if not ok then
  io.stderr:write("catalog process load failed: " .. tostring(catalog) .. "\n")
  os.exit(1)
end
local ok2, site = pcall(require, "ao.site.process")
if not ok2 then
  io.stderr:write("site process load failed: " .. tostring(site) .. "\n")
  os.exit(1)
end
local ok3, apply = pcall(require, "ao.ingest.apply")
if not ok3 then
  io.stderr:write("ingest apply load failed: " .. tostring(apply) .. "\n")
  os.exit(1)
end
-- minimal replay-like sanity: apply a shipment update twice
local ev = { type = "ShipmentUpdated", shipmentId = "smoke-ship", status = "shipped", orderId = "order-smoke" }
if apply and apply.handle and apply.handle.ShipmentUpdated then
  apply.handle.ShipmentUpdated(ev)
  apply.handle.ShipmentUpdated(ev) -- second pass should not error
end
print("ingest_smoke: OK")
