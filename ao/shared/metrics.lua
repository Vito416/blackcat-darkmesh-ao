-- Minimal metrics stub: counts and durations written to NDJSON file (mock-friendly).

local Metrics = {}

local LOG_PATH = os.getenv "METRICS_LOG" or "metrics/metrics.log"
local ENABLED = os.getenv "METRICS_ENABLED" ~= "0"
local PROM_PATH = os.getenv "METRICS_PROM_PATH"
local FLUSH_EVERY = tonumber(os.getenv "METRICS_FLUSH_EVERY" or "0")
local FLUSH_INTERVAL = tonumber(os.getenv "METRICS_FLUSH_INTERVAL_SEC" or "0")
local counters = {}
local gauges = {}
local since_flush = 0
local last_flush = os.time()
local timer = require "ao.shared.timer"
local started = false

local function ensure_dir(path)
  local dir = path:match "(.+)/[^/]+$"
  if dir then
    os.execute(string.format('mkdir -p "%s"', dir))
  end
end

local function log(event)
  if not ENABLED or not LOG_PATH then
    return
  end
  ensure_dir(LOG_PATH)
  local f = io.open(LOG_PATH, "a")
  if not f then
    return
  end
  f:write(
    string.format(
      '{"ts":"%s","event":"%s","value":%s}\n',
      os.date "!%Y-%m-%dT%H:%M:%SZ",
      event.name or "metric",
      event.value or 0
    )
  )
  f:close()
end

function Metrics.inc(name, value)
  if os.getenv "METRICS_DISABLED" == "1" then
    return
  end
  value = value or 1
  counters[name] = (counters[name] or 0) + value
  log { name = name, value = counters[name] }
  since_flush = since_flush + 1
  if FLUSH_EVERY > 0 and since_flush >= FLUSH_EVERY then
    Metrics.flush_prom()
    since_flush = 0
  elseif FLUSH_EVERY == 0 then
    Metrics.flush_prom()
  end
end

function Metrics.tick()
  if os.getenv "METRICS_DISABLED" == "1" then
    return
  end
  local now = os.time()
  if FLUSH_INTERVAL > 0 and (now - last_flush) >= FLUSH_INTERVAL then
    Metrics.flush_prom()
    last_flush = now
    since_flush = 0
  end
  if FLUSH_INTERVAL > 0 then
    timer.start(FLUSH_INTERVAL, Metrics.flush_prom)
  end
end

function Metrics.flush_prom()
  if not PROM_PATH then
    return
  end
  -- optional gauges sourced from queue files so gateway can scrape them
  local function file_lines(path)
    if not path or path == "" then
      return nil
    end
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local n = 0
    for _ in f:lines() do
      n = n + 1
    end
    f:close()
    return n
  end
  local queue_path = os.getenv "AO_QUEUE_PATH"
  local retry_path = os.getenv "AO_WEBHOOK_RETRY_PATH" or os.getenv "AO_RETRY_QUEUE_PATH"
  local breaker_flag = os.getenv "AO_PSP_BREAKER_FLAG"
  local outbox_size = file_lines(queue_path)
  local retry_size = file_lines(retry_path)
  if outbox_size then
    gauges.ao_outbox_queue_size = outbox_size
  end
  if retry_size then
    gauges.ao_webhook_retry_queue_size = retry_size
  end
  if breaker_flag then
    local bf = io.open(breaker_flag, "r")
    if bf then
      local val = bf:read "*l"
      bf:close()
      gauges.ao_psp_breaker_open = tonumber(val) or 0
    end
  end
  ensure_dir(PROM_PATH)
  local f = io.open(PROM_PATH, "w")
  if not f then
    return
  end
  for k, v in pairs(counters) do
    f:write(string.format("%s_total %d\n", k:gsub("[^%w_]", "_"), v))
  end
  for k, v in pairs(gauges) do
    f:write(string.format("%s %s\n", k:gsub("[^%w_]", "_"), tostring(v)))
  end
  f:close()
end

function Metrics.last_flush_ts()
  return last_flush
end

function Metrics.get(name)
  return counters[name] or 0
end

function Metrics.counter(name, value)
  Metrics.inc(name, value)
end

function Metrics.gauge(name, value)
  if os.getenv "METRICS_DISABLED" == "1" then
    return
  end
  gauges[name] = value
  log { name = name, value = value }
end

function Metrics._reset()
  counters = {}
end

function Metrics.start_background()
  if started then
    return
  end
  started = true
  if FLUSH_INTERVAL > 0 then
    timer.start(FLUSH_INTERVAL, Metrics.flush_prom)
  end
end

-- auto-start if interval specified
Metrics.start_background()

return Metrics
