local analytics = require "ao.shared.analytics"
local metrics = require "ao.shared.metrics"

-- Allow running under plain lua (CI calls lua5.4 <file>) without busted.
if type(describe) ~= "function" then
  io.stdout:write("analytics_spec: skipped (busted not available)\n")
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
