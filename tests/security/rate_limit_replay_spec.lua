package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local auth = require "ao.shared.auth"

local function force(name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(auth.check_rate_limit, i)
    if not n then
      break
    end
    if n == name then
      debug.setupvalue(auth.check_rate_limit, i, value)
      break
    end
    i = i + 1
  end
end

-- If env already sets strict limits, keep them; otherwise tighten for tests.
local rl_env = tonumber(os.getenv "AUTH_RATE_LIMIT_MAX_REQUESTS" or "")
if not rl_env or rl_env > 5 then
  force("RL_MAX", 1)
  force("RL_WINDOW", 30)
end

local msg = { ["Site-Id"] = "s-test", ["Request-Id"] = "req-1" }
local ok = auth.check_rate_limit(msg)
assert(ok, "first request should pass rate limit")
local ok2, err2 = auth.check_rate_limit(msg)
assert(ok2 == false and err2 == "rate_limited", "second request should be rate limited")

-- Nonce replay guard
local n1_ok = auth.require_nonce { Nonce = "nonce-1", ["Request-Id"] = "rid-1" }
assert(n1_ok, "first nonce should pass")
local n1_ok2, n1_err2 = auth.require_nonce { Nonce = "nonce-1", ["Request-Id"] = "rid-2" }
assert(n1_ok2 == false and n1_err2 == "replay_nonce", "replay nonce must be blocked")
local n_same_ok = auth.require_nonce { Nonce = "nonce-same", ["Request-Id"] = "rid-3" }
assert(n_same_ok, "initial nonce should be accepted")
local n_same_ok2, n_same_err2 =
  auth.require_nonce { Nonce = "nonce-same", ["Request-Id"] = "rid-3" }
assert(n_same_ok2, n_same_err2 or "same nonce + Request-Id should be idempotent")

print "rate_limit_replay_spec: ok"
