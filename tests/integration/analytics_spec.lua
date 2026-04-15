local analytics = require "ao.shared.analytics"
local metrics = require "ao.shared.metrics"

local function run_plain_assertions()
  metrics._reset()
  analytics.page_view("site1", "/home", "en")
  assert(metrics.get("ao_page_view") >= 1, "ao_page_view should increment")

  metrics._reset()
  analytics.product_view("site1", "sku1", "en")
  assert(metrics.get("ao_product_view") >= 1, "ao_product_view should increment")

  metrics._reset()
  analytics.risk_event("fraud_signal", { ip_hash = "abc" })
  assert(metrics.get("ao_risk_event") >= 1, "ao_risk_event should increment")

  metrics._reset()
  analytics.subscription_start("site1", "pro")
  analytics.subscription_cancel("site1", "pro", "churn")
  assert(metrics.get("ao_subscription_start") >= 1, "ao_subscription_start should increment")
  assert(metrics.get("ao_subscription_cancel") >= 1, "ao_subscription_cancel should increment")
  assert(metrics.get("ao_subscription_churn") >= 1, "ao_subscription_churn should increment")
end

-- Allow running under plain lua (CI calls lua5.4 <file>) without busted.
if type(describe) ~= "function" then
  run_plain_assertions()
  io.stdout:write("analytics_spec: ok\n")
  return
end

describe("analytics helpers", function()
  before_each(function()
    metrics._reset()
  end)

  it("counts page views and logs", function()
    analytics.page_view("site1", "/home", "en")
    assert.is_true(metrics.get("ao_page_view") >= 1)
  end)

  it("counts product views", function()
    analytics.product_view("site1", "sku1", "en")
    assert.is_true(metrics.get("ao_product_view") >= 1)
  end)

  it("counts risk events", function()
    analytics.risk_event("fraud_signal", { ip_hash = "abc" })
    assert.is_true(metrics.get("ao_risk_event") >= 1)
  end)

  it("tracks subscriptions", function()
    analytics.subscription_start("site1", "pro")
    analytics.subscription_cancel("site1", "pro", "churn")
    assert.is_true(metrics.get("ao_subscription_start") >= 1)
    assert.is_true(metrics.get("ao_subscription_cancel") >= 1)
    assert.is_true(metrics.get("ao_subscription_churn") >= 1)
  end)
end)
