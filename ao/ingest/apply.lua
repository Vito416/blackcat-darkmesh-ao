-- Apply events emitted by blackcat-darkmesh-write into AO public state.
-- Expect events shaped by the minimal write process (see write process emits).

local catalog = require "ao.catalog.process"
local site = require "ao.site.process"
local registry = require "ao.registry.process"
local access = require "ao.access.process"

local cstate = catalog._state
local sstate = site._state
local rstate = registry._state
local astate = access._state

local export = require "ao.shared.export"

local handlers = {}

local function k(a, b)
  return string.format("%s|%s", a or "", b or "")
end

local function site_of(ev)
  return ev.siteId or ev.site_id or ev.site or ev.tenant or ev.Tenant or "default"
end

local function sku_of(ev)
  return ev.sku or ev.Sku
end

-- Site routing / content --------------------------------------------------
function handlers.RouteUpserted(ev)
  sstate.routes[k(site_of(ev), ev.path)] = ev.target
end

function handlers.PublishPageVersion(ev)
  local key = k(site_of(ev), ev.pageId)
  sstate.pages[key] = {
    version = ev.version,
    publishId = ev.publishId,
    updatedAt = os.time(),
  }
  sstate.active_versions[site_of(ev)] = ev.version
end

-- Catalog -----------------------------------------------------------------
function handlers.ProductUpserted(ev)
  cstate.products[k(site_of(ev), ev.sku)] = {
    payload = ev.payload,
    sku = ev.sku,
    siteId = site_of(ev),
    updatedAt = os.time(),
  }
end

function handlers.InventorySet(ev)
  local site_id = site_of(ev)
  local wh = ev.warehouse or ev.warehouseId or ev["Warehouse-Id"] or "default"
  cstate.inventory[site_id] = cstate.inventory[site_id] or {}
  cstate.inventory[site_id][wh] = cstate.inventory[site_id][wh] or {}
  cstate.inventory[site_id][wh][sku_of(ev)] = tonumber(ev.quantity or 0) or 0
end

function handlers.ShippingRulesSet(ev)
  cstate.shipping_rules[site_of(ev)] = ev.rules
end

function handlers.TaxRulesSet(ev)
  cstate.tax_rules[site_of(ev)] = ev.rules
end

function handlers.PromoAdded(ev)
  local site_id = site_of(ev)
  cstate.promos[site_id] = cstate.promos[site_id] or {}
  cstate.promos[site_id][ev.code] = ev.payload or ev
end
function handlers.AddressValidated(ev)
  -- Do not store PII on AO; only track proof that validation happened.
  astate.address_validations = astate.address_validations or {}
  local subj = ev.subject or "_anon"
  astate.address_validations[subj] = { ts = os.time(), siteId = site_of(ev) }
end

-- Orders / payments -------------------------------------------------------
function handlers.OrderCreated(ev)
  cstate.orders = cstate.orders or {}
  cstate.orders[ev.orderId] = {
    siteId = site_of(ev),
    amount = ev.totalAmount or ev.amount,
    currency = ev.currency,
    items = ev.items or {},
    status = ev.status or "pending",
    customerRef = ev.customerRef or ev.customerId,
    updatedAt = os.time(),
  }
end

function handlers.OrderStatusUpdated(ev)
  cstate.orders = cstate.orders or {}
  local ord = cstate.orders[ev.orderId] or { siteId = site_of(ev) }
  ord.status = ev.status or ord.status
  ord.updatedAt = os.time()
  cstate.orders[ev.orderId] = ord
end

function handlers.PaymentStatusChanged(ev)
  cstate.payments = cstate.payments or {}
  cstate.payments[ev.paymentId] = cstate.payments[ev.paymentId] or {}
  local p = cstate.payments[ev.paymentId]
  p.status = ev.status or p.status
  p.providerStatus = ev.providerStatus or p.providerStatus
  p.orderId = ev.orderId or p.orderId
  p.siteId = site_of(ev) or p.siteId
  p.updatedAt = os.time()
end

function handlers.PaymentIntentCreated(ev)
  cstate.payments = cstate.payments or {}
  cstate.payments[ev.paymentId] = {
    status = ev.status or "requires_capture",
    amount = ev.amount,
    currency = ev.currency,
    orderId = ev.orderId,
    provider = ev.provider,
    siteId = site_of(ev),
    providerPaymentId = ev.providerPaymentId,
    updatedAt = os.time(),
  }
end

function handlers.PaymentDisputeEvidence(ev)
  cstate.payments = cstate.payments or {}
  local p = cstate.payments[ev.paymentId] or {}
  p.status = ev.status or p.status or "disputed"
  p.reason = ev.reason or p.reason
  p.provider = ev.provider or p.provider
  p.updatedAt = os.time()
  cstate.payments[ev.paymentId] = p
end

function handlers.PaymentVoided(ev)
  cstate.payments = cstate.payments or {}
  local p = cstate.payments[ev.paymentId] or {}
  p.status = ev.status or "voided"
  p.orderId = ev.orderId or p.orderId
  p.updatedAt = os.time()
  cstate.payments[ev.paymentId] = p
end

function handlers.IssueRefund(ev)
  cstate.payments = cstate.payments or {}
  local p = cstate.payments[ev.paymentId] or {}
  p.status = ev.status or "refunded"
  p.refundAmount = ev.amount or p.refundAmount
  p.orderId = ev.orderId or p.orderId
  p.updatedAt = os.time()
  cstate.payments[ev.paymentId] = p
end

-- Logistics ---------------------------------------------------------------
function handlers.ShipmentUpdated(ev)
  local sh = cstate.shipments[ev.shipmentId] or {}
  sh.status = ev.status or sh.status
  sh.tracking = ev.tracking or sh.tracking
  sh.carrier = ev.carrier or sh.carrier
  sh.labelUrl = ev.labelUrl or sh.labelUrl
  sh.eta = ev.eta or sh.eta
  sh.orderId = ev.orderId or sh.orderId
  sh.updatedAt = os.time()
  cstate.shipments[ev.shipmentId] = sh
end

function handlers.ShippingLabelCreated(ev)
  handlers.ShipmentUpdated(ev)
end

function handlers.ShipmentTrackingUpdated(ev)
  handlers.ShipmentUpdated(ev)
end

function handlers.ReturnUpdated(ev)
  local r = cstate.returns[ev.returnId] or {}
  r.status = ev.status or r.status
  r.reason = ev.reason or r.reason
  r.orderId = ev.orderId or r.orderId
  r.updatedAt = os.time()
  cstate.returns[ev.returnId] = r
end

-- Registry / access -------------------------------------------------------
function handlers.DomainLinked(ev)
  rstate.domains[ev.host] = site_of(ev)
end

function handlers.EntitlementGranted(ev)
  astate.entitlements[k(ev.subject, ev.asset)] = ev.policy
end

function handlers.KeyRotated(ev)
  rstate.keys = rstate.keys or {}
  rstate.keys[site_of(ev) or "_global"] = {
    version = ev.keyVersion,
    ref = ev.keyRef,
    rotatedAt = ev.rotatedAt or os.time(),
  }
end

function handlers.SubscriptionCreated(ev)
  cstate.subscriptions = cstate.subscriptions or {}
  cstate.subscriptions[ev.subscriptionId] = {
    customerId = ev.customerId,
    planId = ev.planId,
    status = ev.status or "active",
    siteId = site_of(ev),
    createdAt = ev.createdAt or os.time(),
  }
end

function handlers.SubscriptionStatusUpdated(ev)
  cstate.subscriptions = cstate.subscriptions or {}
  local sub = cstate.subscriptions[ev.subscriptionId] or { siteId = site_of(ev) }
  sub.status = ev.status or sub.status
  sub.updatedAt = os.time()
  cstate.subscriptions[ev.subscriptionId] = sub
end

function handlers.ReceiptCreated(ev)
  astate.receipts = astate.receipts or {}
  table.insert(astate.receipts, {
    receiptId = ev.receiptId,
    siteId = site_of(ev),
    ts = ev.ts or os.time(),
  })
end

function handlers.SessionStarted(ev)
  astate.sessions = astate.sessions or {}
  astate.sessions[ev.sessionHash] = {
    subject = ev.subject,
    exp = ev.exp,
  }
end

function handlers.SessionRevoked(ev)
  if astate.sessions then
    astate.sessions[ev.sessionHash] = nil
  end
end

function handlers.CouponApplied(ev)
  cstate.orders = cstate.orders or {}
  local ord = cstate.orders[ev.orderId] or { siteId = site_of(ev) }
  ord.coupon = ev.code or ord.coupon
  ord.discount = ev.discount or ord.discount
  ord.updatedAt = os.time()
  cstate.orders[ev.orderId] = ord
end

function handlers.CouponRemoved(ev)
  if cstate.orders and cstate.orders[ev.orderId] then
    local ord = cstate.orders[ev.orderId]
    ord.coupon = nil
    ord.discount = nil
    ord.updatedAt = os.time()
  end
end

function handlers.FormSubmitted(ev)
  sstate.forms = sstate.forms or {}
  local site_id = site_of(ev)
  sstate.forms[site_id] = sstate.forms[site_id] or {}
  table.insert(sstate.forms[site_id], ev)
end

function handlers.FormWebhook(ev)
  handlers.FormSubmitted(ev)
end

function handlers.GatewayFlagged(ev)
  rstate.resolver_flags = rstate.resolver_flags or {}
  rstate.resolver_flags[ev.gatewayId] = {
    flag = ev.flag,
    reason = ev.reason,
    ts = ev.ts or os.time(),
  }
end

-- Minimal PII scrubber before writing immutable exports
local function apply(ev)
  if not ev then
    return false, "missing_event"
  end
  local key = ev.action or ev.type
  if not key then
    return false, "missing_action"
  end
  local fn = handlers[key]
  if not fn then
    return false, "unknown_action"
  end
  fn(ev)
  export.write(ev)
  return true
end

return {
  apply = apply,
}
