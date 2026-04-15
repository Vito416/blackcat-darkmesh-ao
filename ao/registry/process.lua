-- Registry process handlers: domains, sites, versions, roles.
-- Lightweight in-memory scaffolding to keep contracts testable.

local codec = require "ao.shared.codec"
local validation = require "ao.shared.validation"
local auth = require "ao.shared.auth"
local idem = require "ao.shared.idempotency"
local audit = require "ao.shared.audit"
local metrics = require "ao.shared.metrics"
local schema = require "ao.shared.schema"
local json_ok, json = pcall(require, "cjson.safe")
local persist = require "ao.shared.persist"

local handlers = {}
local validate_gateway_domain_label
local normalize_site_id
local allowed_actions = {
  "GetSiteByHost",
  "GetSiteConfig",
  "RegisterGateway",
  "UpdateGatewayStatus",
  "ResolveGatewayForHost",
  "ListGateways",
  "RegisterSite",
  "SetSiteRuntime",
  "UpsertSiteRuntime",
  "GetSiteRuntime",
  "BindDomain",
  "SetActiveVersion",
  "GrantRole",
  "UpdateTrustResolvers",
  "GetTrustedResolvers",
  "PublishTrustedRelease",
  "RevokeTrustedRelease",
  "GetTrustedReleaseByVersion",
  "GetTrustedReleaseByRoot",
  "GetTrustedRoot",
  "SetIntegrityPolicyPause",
  "GetIntegrityPolicy",
  "SetIntegrityAuthority",
  "GetIntegrityAuthority",
  "AppendIntegrityAuditCommitment",
  "GetIntegrityAuditState",
  "GetIntegritySnapshot",
  "FlagResolver",
  "UnflagResolver",
  "GetResolverFlags",
}

local role_policy = {
  RegisterGateway = { "admin", "registry-admin" },
  UpdateGatewayStatus = { "admin", "registry-admin" },
  RegisterSite = { "admin", "registry-admin" },
  SetSiteRuntime = { "admin", "registry-admin" },
  UpsertSiteRuntime = { "admin", "registry-admin" },
  BindDomain = { "admin", "registry-admin" },
  SetActiveVersion = { "admin", "registry-admin" },
  GrantRole = { "admin", "registry-admin" },
  UpdateTrustResolvers = { "admin", "registry-admin" },
  GetTrustedResolvers = { "admin", "registry-admin" },
  PublishTrustedRelease = { "admin", "registry-admin" },
  RevokeTrustedRelease = { "admin", "registry-admin" },
  SetIntegrityPolicyPause = { "admin", "registry-admin" },
  SetIntegrityAuthority = { "admin", "registry-admin" },
  AppendIntegrityAuditCommitment = { "admin", "registry-admin" },
  FlagResolver = { "admin", "registry-admin" },
  UnflagResolver = { "admin", "registry-admin" },
  GetResolverFlags = { "admin", "registry-admin" },
}

local hmac_skip_actions = {
  GetSiteByHost = true,
  GetSiteConfig = true,
  ResolveGatewayForHost = true,
  ListGateways = true,
  GetSiteRuntime = true,
  GetTrustedResolvers = true,
  GetTrustedReleaseByVersion = true,
  GetTrustedReleaseByRoot = true,
  GetTrustedRoot = true,
  GetIntegrityPolicy = true,
  GetIntegrityAuthority = true,
  GetIntegrityAuditState = true,
  GetIntegritySnapshot = true,
  GetResolverFlags = true,
}

local public_read_actions = {
  GetSiteByHost = true,
  GetSiteConfig = true,
  ResolveGatewayForHost = true,
  ListGateways = true,
  GetSiteRuntime = true,
}
local site_id_guard_actions = {
  RegisterSite = true,
  SetSiteRuntime = true,
  UpsertSiteRuntime = true,
  BindDomain = true,
  SetActiveVersion = true,
  GrantRole = true,
}
local site_id_guard_fields = { "Site-Id", "siteId", "SiteId", "site_id" }
local PUBLIC_READ_REQUIRE_AUTH = (os.getenv "REGISTRY_PUBLIC_READ_REQUIRE_AUTH" or "0") == "1"

-- pseudo-state kept in-memory for now; AO runtime would persist this.
local state = persist.load("registry_state", {
  sites = {}, -- siteId => {config = {}, createdAt = ts}
  site_runtimes = {}, -- siteId => { processId, moduleId?, scheduler?, updatedAt }
  domains = {}, -- host => siteId
  gateways = {}, -- gatewayId => { id, url, region, country, capacityWeight, score, status, lastSeen, domains = {} }
  active_versions = {}, -- siteId => versionId
  roles = {}, -- siteId => map[user] = role
  trust = { resolvers = {}, manifestTx = nil, updatedAt = nil },
  integrity = {
    releases = {}, -- "<component>@<version>" => release object
    roots = {}, -- root => "<component>@<version>"
    active = {}, -- component => version
    policy = {
      activeRoot = nil,
      activePolicyHash = "policy-unset",
      paused = false,
      maxCheckInAgeSec = 3600,
      updatedAt = nil,
      pausedAt = nil,
      pausedBy = nil,
      pauseReason = nil,
    },
    authority = {
      root = "authority-root-unset",
      upgrade = "authority-upgrade-unset",
      emergency = "authority-emergency-unset",
      reporter = "authority-reporter-unset",
      signatureRefs = { "authority-root-unset" },
      updatedAt = nil,
    },
    audit = {
      seqFrom = 0,
      seqTo = 0,
      merkleRoot = "audit-root-unset",
      metaHash = "audit-meta-unset",
      reporterRef = "authority-reporter-unset",
      acceptedAt = "1970-01-01T00:00:00Z",
    },
  },
  resolver_flags = {}, -- resolverId => { flag = "suspicious"|"blocked"|"ok", reason, raisedAt, raisedBy }
})

local MAX_CONFIG_BYTES = tonumber(os.getenv "REGISTRY_MAX_CONFIG_BYTES" or "") or (16 * 1024)
local FLAGS_PATH = os.getenv "AO_FLAGS_PATH"
local WAL_PATH = os.getenv "AO_WAL_PATH"

local function now_iso()
  -- coarse timestamp for audit/debug; determinism is sufficient here.
  return os.date "!%Y-%m-%dT%H:%M:%SZ"
end

local function ensure_integrity_state()
  state.integrity = state.integrity or {}
  state.integrity.releases = state.integrity.releases or {}
  state.integrity.roots = state.integrity.roots or {}
  state.integrity.active = state.integrity.active or {}

  state.integrity.policy = state.integrity.policy or {}
  local policy = state.integrity.policy
  if policy.activePolicyHash == nil or policy.activePolicyHash == "" then
    policy.activePolicyHash = "policy-unset"
  end
  if policy.maxCheckInAgeSec == nil then
    policy.maxCheckInAgeSec = 3600
  end
  if policy.paused == nil then
    policy.paused = false
  end

  state.integrity.authority = state.integrity.authority or {}
  local authority = state.integrity.authority
  authority.root = authority.root or "authority-root-unset"
  authority.upgrade = authority.upgrade or "authority-upgrade-unset"
  authority.emergency = authority.emergency or "authority-emergency-unset"
  authority.reporter = authority.reporter or "authority-reporter-unset"
  if type(authority.signatureRefs) ~= "table" or #authority.signatureRefs == 0 then
    authority.signatureRefs = { authority.root }
  end

  state.integrity.audit = state.integrity.audit or {}
  local audit_state = state.integrity.audit
  if type(audit_state.seqFrom) ~= "number" then
    audit_state.seqFrom = 0
  end
  if type(audit_state.seqTo) ~= "number" then
    audit_state.seqTo = 0
  end
  audit_state.merkleRoot = audit_state.merkleRoot or "audit-root-unset"
  audit_state.metaHash = audit_state.metaHash or "audit-meta-unset"
  audit_state.reporterRef = audit_state.reporterRef or authority.reporter
  audit_state.acceptedAt = audit_state.acceptedAt or "1970-01-01T00:00:00Z"
end

ensure_integrity_state()

local function ensure_gateway_state()
  state.gateways = state.gateways or {}
  for gateway_id, gateway in pairs(state.gateways) do
    if type(gateway) ~= "table" then
      state.gateways[gateway_id] = nil
    else
      gateway.id = gateway.id or gateway_id
      gateway.url = gateway.url or ""
      gateway.region = gateway.region or ""
      gateway.country = gateway.country or ""
      gateway.capacityWeight = tonumber(gateway.capacityWeight) or 0
      gateway.score = tonumber(gateway.score) or 0
      gateway.status = gateway.status or "offline"
      gateway.lastSeen = gateway.lastSeen or "1970-01-01T00:00:00Z"
      if type(gateway.domains) ~= "table" then
        gateway.domains = {}
      end
    end
  end
end

ensure_gateway_state()

local RUNTIME_POINTER_INPUT_KEYS = {
  processId = true,
  siteProcessId = true,
  catalogProcessId = true,
  accessProcessId = true,
  writeProcessId = true,
  ingestProcessId = true,
  registryProcessId = true,
  workerId = true,
  workerUrl = true,
  ProcessId = true,
  ["Process-Id"] = true,
  process_id = true,
  sitePid = true,
  catalogPid = true,
  accessPid = true,
  writePid = true,
  ingestPid = true,
  registryPid = true,
  workerPid = true,
  site_process_id = true,
  catalog_process_id = true,
  access_process_id = true,
  write_process_id = true,
  ingest_process_id = true,
  registry_process_id = true,
  worker_id = true,
  worker_url = true,
  moduleId = true,
  ModuleId = true,
  ["Module-Id"] = true,
  module_id = true,
  scheduler = true,
  Scheduler = true,
  ["Scheduler-Id"] = true,
  schedulerId = true,
  scheduler_id = true,
}

local RUNTIME_POINTER_STORED_KEYS = {
  processId = true,
  siteProcessId = true,
  catalogProcessId = true,
  accessProcessId = true,
  writeProcessId = true,
  ingestProcessId = true,
  registryProcessId = true,
  workerId = true,
  workerUrl = true,
  ProcessId = true,
  ["Process-Id"] = true,
  process_id = true,
  sitePid = true,
  catalogPid = true,
  accessPid = true,
  writePid = true,
  ingestPid = true,
  registryPid = true,
  workerPid = true,
  site_process_id = true,
  catalog_process_id = true,
  access_process_id = true,
  write_process_id = true,
  ingest_process_id = true,
  registry_process_id = true,
  worker_id = true,
  worker_url = true,
  moduleId = true,
  ModuleId = true,
  ["Module-Id"] = true,
  module_id = true,
  scheduler = true,
  Scheduler = true,
  ["Scheduler-Id"] = true,
  schedulerId = true,
  scheduler_id = true,
  updatedAt = true,
  UpdatedAt = true,
  ["Updated-At"] = true,
  updated_at = true,
}

local function first_present(tbl, keys)
  for _, key in ipairs(keys) do
    if tbl[key] ~= nil then
      return tbl[key]
    end
  end
  return nil
end

local function validate_runtime_pointer_token(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 128, field)
  if not ok_len then
    return false, err_len
  end
  if value == "" or not tostring(value):match "^[A-Za-z0-9_-]+$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function validate_runtime_pointer_url(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 512, field)
  if not ok_len then
    return false, err_len
  end
  if value == "" or not tostring(value):match "^https?://[%w%._~:/%?#%[%]@!$&'()*+,;=-]+$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function validate_runtime_pointer_timestamp(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 64, field)
  if not ok_len then
    return false, err_len
  end
  if not value:match "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function normalize_runtime_pointer(raw, opts)
  opts = opts or {}
  local field_name = opts.field_name or "Runtime"
  local require_process = opts.require_process ~= false
  local allow_stored_shape = opts.allow_stored_shape == true

  if type(raw) ~= "table" then
    return nil, ("invalid_type:%s"):format(field_name), field_name
  end

  local allowed = allow_stored_shape and RUNTIME_POINTER_STORED_KEYS or RUNTIME_POINTER_INPUT_KEYS
  for key in pairs(raw) do
    if not allowed[key] then
      return nil, ("unsupported_field:%s.%s"):format(field_name, tostring(key)), field_name
    end
  end

  local process_id = first_present(raw, { "processId", "ProcessId", "Process-Id", "process_id" })
  local site_process_id = first_present(raw, { "siteProcessId", "sitePid", "site_process_id" })
  local catalog_process_id =
    first_present(raw, { "catalogProcessId", "catalogPid", "catalog_process_id" })
  local access_process_id =
    first_present(raw, { "accessProcessId", "accessPid", "access_process_id" })
  local write_process_id = first_present(raw, { "writeProcessId", "writePid", "write_process_id" })
  local ingest_process_id =
    first_present(raw, { "ingestProcessId", "ingestPid", "ingest_process_id" })
  local registry_process_id =
    first_present(raw, { "registryProcessId", "registryPid", "registry_process_id" })
  local worker_id = first_present(raw, { "workerId", "workerPid", "worker_id" })
  local worker_url = first_present(raw, { "workerUrl", "worker_url" })
  local module_id = first_present(raw, { "moduleId", "ModuleId", "Module-Id", "module_id" })
  local scheduler =
    first_present(raw, { "scheduler", "Scheduler", "Scheduler-Id", "schedulerId", "scheduler_id" })
  local updated_at = first_present(raw, { "updatedAt", "UpdatedAt", "Updated-At", "updated_at" })

  local has_any_process = process_id ~= nil
    or site_process_id ~= nil
    or catalog_process_id ~= nil
    or access_process_id ~= nil
    or write_process_id ~= nil
    or ingest_process_id ~= nil
    or registry_process_id ~= nil

  if not has_any_process and require_process then
    return nil, ("missing_field:%s.processId"):format(field_name), field_name .. ".processId"
  end

  local runtime = {}
  if process_id ~= nil then
    local ok_process, err_process =
      validate_runtime_pointer_token(process_id, field_name .. ".processId")
    if not ok_process then
      return nil, err_process, field_name .. ".processId"
    end
    runtime.processId = tostring(process_id)
  end
  if site_process_id ~= nil then
    local ok_site, err_site =
      validate_runtime_pointer_token(site_process_id, field_name .. ".siteProcessId")
    if not ok_site then
      return nil, err_site, field_name .. ".siteProcessId"
    end
    runtime.siteProcessId = tostring(site_process_id)
  end
  if catalog_process_id ~= nil then
    local ok_catalog, err_catalog =
      validate_runtime_pointer_token(catalog_process_id, field_name .. ".catalogProcessId")
    if not ok_catalog then
      return nil, err_catalog, field_name .. ".catalogProcessId"
    end
    runtime.catalogProcessId = tostring(catalog_process_id)
  end
  if access_process_id ~= nil then
    local ok_access, err_access =
      validate_runtime_pointer_token(access_process_id, field_name .. ".accessProcessId")
    if not ok_access then
      return nil, err_access, field_name .. ".accessProcessId"
    end
    runtime.accessProcessId = tostring(access_process_id)
  end
  if write_process_id ~= nil then
    local ok_write, err_write =
      validate_runtime_pointer_token(write_process_id, field_name .. ".writeProcessId")
    if not ok_write then
      return nil, err_write, field_name .. ".writeProcessId"
    end
    runtime.writeProcessId = tostring(write_process_id)
  end
  if ingest_process_id ~= nil then
    local ok_ingest, err_ingest =
      validate_runtime_pointer_token(ingest_process_id, field_name .. ".ingestProcessId")
    if not ok_ingest then
      return nil, err_ingest, field_name .. ".ingestProcessId"
    end
    runtime.ingestProcessId = tostring(ingest_process_id)
  end
  if registry_process_id ~= nil then
    local ok_registry, err_registry =
      validate_runtime_pointer_token(registry_process_id, field_name .. ".registryProcessId")
    if not ok_registry then
      return nil, err_registry, field_name .. ".registryProcessId"
    end
    runtime.registryProcessId = tostring(registry_process_id)
  end
  if worker_id ~= nil then
    local ok_worker, err_worker =
      validate_runtime_pointer_token(worker_id, field_name .. ".workerId")
    if not ok_worker then
      return nil, err_worker, field_name .. ".workerId"
    end
    runtime.workerId = tostring(worker_id)
  end
  if worker_url ~= nil then
    local ok_url, err_url = validate_runtime_pointer_url(worker_url, field_name .. ".workerUrl")
    if not ok_url then
      return nil, err_url, field_name .. ".workerUrl"
    end
    runtime.workerUrl = tostring(worker_url)
  end
  if module_id ~= nil then
    local ok_module, err_module =
      validate_runtime_pointer_token(module_id, field_name .. ".moduleId")
    if not ok_module then
      return nil, err_module, field_name .. ".moduleId"
    end
    runtime.moduleId = tostring(module_id)
  end
  if scheduler ~= nil then
    local ok_scheduler, err_scheduler =
      validate_runtime_pointer_token(scheduler, field_name .. ".scheduler")
    if not ok_scheduler then
      return nil, err_scheduler, field_name .. ".scheduler"
    end
    runtime.scheduler = tostring(scheduler)
  end
  if allow_stored_shape and updated_at ~= nil then
    local ok_updated, err_updated =
      validate_runtime_pointer_timestamp(updated_at, field_name .. ".updatedAt")
    if not ok_updated then
      return nil, err_updated, field_name .. ".updatedAt"
    end
    runtime.updatedAt = tostring(updated_at)
  end
  return runtime
end

local function snapshot_runtime_pointer(runtime)
  if type(runtime) ~= "table" then
    return nil
  end
  local has_process = false
  for _, key in ipairs {
    "processId",
    "siteProcessId",
    "catalogProcessId",
    "accessProcessId",
    "writeProcessId",
    "ingestProcessId",
    "registryProcessId",
  } do
    if type(runtime[key]) == "string" and runtime[key] ~= "" then
      has_process = true
      break
    end
  end
  if not has_process then
    return nil
  end
  local out = {}
  if type(runtime.processId) == "string" and runtime.processId ~= "" then
    out.processId = runtime.processId
  end
  if type(runtime.siteProcessId) == "string" and runtime.siteProcessId ~= "" then
    out.siteProcessId = runtime.siteProcessId
  end
  if type(runtime.catalogProcessId) == "string" and runtime.catalogProcessId ~= "" then
    out.catalogProcessId = runtime.catalogProcessId
  end
  if type(runtime.accessProcessId) == "string" and runtime.accessProcessId ~= "" then
    out.accessProcessId = runtime.accessProcessId
  end
  if type(runtime.writeProcessId) == "string" and runtime.writeProcessId ~= "" then
    out.writeProcessId = runtime.writeProcessId
  end
  if type(runtime.ingestProcessId) == "string" and runtime.ingestProcessId ~= "" then
    out.ingestProcessId = runtime.ingestProcessId
  end
  if type(runtime.registryProcessId) == "string" and runtime.registryProcessId ~= "" then
    out.registryProcessId = runtime.registryProcessId
  end
  if type(runtime.workerId) == "string" and runtime.workerId ~= "" then
    out.workerId = runtime.workerId
  end
  if type(runtime.workerUrl) == "string" and runtime.workerUrl ~= "" then
    out.workerUrl = runtime.workerUrl
  end
  if type(runtime.moduleId) == "string" and runtime.moduleId ~= "" then
    out.moduleId = runtime.moduleId
  end
  if type(runtime.scheduler) == "string" and runtime.scheduler ~= "" then
    out.scheduler = runtime.scheduler
  end
  if type(runtime.updatedAt) == "string" and runtime.updatedAt ~= "" then
    out.updatedAt = runtime.updatedAt
  end
  return out
end

local function runtime_for_site(site_id)
  if type(state.site_runtimes) ~= "table" then
    return nil
  end
  return snapshot_runtime_pointer(state.site_runtimes[site_id])
end

local function upsert_site_runtime(site_id, runtime_pointer)
  local normalized, norm_err, norm_field = normalize_runtime_pointer(runtime_pointer, {
    field_name = "Runtime",
  })
  if not normalized then
    return nil, norm_err, norm_field
  end
  normalized.updatedAt = now_iso()
  state.site_runtimes = state.site_runtimes or {}
  state.site_runtimes[site_id] = normalized
  return snapshot_runtime_pointer(normalized)
end

local function ensure_site_runtime_state()
  if type(state.sites) ~= "table" then
    state.sites = {}
  end
  if type(state.site_runtimes) ~= "table" then
    state.site_runtimes = {}
  end

  for site_id, site in pairs(state.sites) do
    if type(site_id) ~= "string" or type(site) ~= "table" then
      state.sites[site_id] = nil
    else
      if type(site.config) ~= "table" then
        site.config = {}
      end
      if type(site.createdAt) ~= "string" or site.createdAt == "" then
        site.createdAt = "1970-01-01T00:00:00Z"
      end
      if state.site_runtimes[site_id] == nil and type(site.runtime) == "table" then
        local normalized = normalize_runtime_pointer(site.runtime, {
          field_name = "Runtime",
          allow_stored_shape = true,
        })
        if normalized then
          normalized.updatedAt = normalized.updatedAt or now_iso()
          state.site_runtimes[site_id] = normalized
        end
      end
    end
  end

  for site_id, runtime_pointer in pairs(state.site_runtimes) do
    if type(site_id) ~= "string" or state.sites[site_id] == nil then
      state.site_runtimes[site_id] = nil
    else
      local normalized = normalize_runtime_pointer(runtime_pointer, {
        field_name = "Runtime",
        allow_stored_shape = true,
      })
      if not normalized then
        state.site_runtimes[site_id] = nil
      else
        normalized.updatedAt = normalized.updatedAt or now_iso()
        state.site_runtimes[site_id] = normalized
      end
    end
  end
end

ensure_site_runtime_state()

local function append_log(path, obj)
  if not path or path == "" or not json_ok then
    return
  end
  local line = json.encode(obj)
  if not line then
    return
  end
  local f = io.open(path, "a")
  if f then
    f:write(line)
    f:write "\n"
    f:close()
  end
end

local function persist_flag_event(ev)
  append_log(WAL_PATH, ev)
  append_log(FLAGS_PATH, ev)
end

function handlers.GetSiteByHost(msg)
  local ok, missing = validation.require_fields(msg, { "Host" })
  if not ok then
    return codec.error("INVALID_INPUT", "Host is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Host",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_host, normalized_host_or_err = validate_gateway_domain_label(msg.Host, "Host", false)
  if not ok_host then
    return codec.error("INVALID_INPUT", normalized_host_or_err, { field = "Host" })
  end
  local normalized_host = normalized_host_or_err
  local site_id = state.domains[normalized_host]
  if not site_id then
    return codec.error("NOT_FOUND", "Domain not bound", { host = normalized_host })
  end
  local payload = {
    siteId = site_id,
    activeVersion = state.active_versions[site_id],
  }
  local runtime = runtime_for_site(site_id)
  if runtime then
    payload.runtime = runtime
  end
  return codec.ok(payload)
end

function handlers.GetSiteConfig(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Site-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  local site = state.sites[site_id]
  if not site then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  local payload = {
    siteId = site_id,
    config = site.config,
    activeVersion = state.active_versions[site_id],
  }
  local runtime = runtime_for_site(site_id)
  if runtime then
    payload.runtime = runtime
  end
  return codec.ok(payload)
end

function handlers.GetSiteRuntime(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Site-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  if not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  local runtime = runtime_for_site(site_id)
  if not runtime then
    return codec.error("NOT_FOUND", "Site runtime not set", { siteId = site_id })
  end
  return codec.ok {
    siteId = site_id,
    runtime = runtime,
  }
end

local gateway_status_allow = {
  online = true,
  offline = true,
  degraded = true,
  draining = true,
  maintenance = true,
}

local function normalize_host_label(value)
  if type(value) ~= "string" then
    return nil
  end
  local normalized = string.lower(value):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.+$", "")
  if normalized == "" then
    return nil
  end
  return normalized
end

local function validate_gateway_id(value)
  local ok_type, err_type = validation.assert_type(value, "string", "Gateway-Id")
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 128, "Gateway-Id")
  if not ok_len then
    return false, err_len
  end
  if not tostring(value):match "^[%w%-%._]+$" then
    return false, "invalid_format:Gateway-Id"
  end
  return true
end

local function validate_gateway_url(value)
  local ok_type, err_type = validation.assert_type(value, "string", "Url")
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 512, "Url")
  if not ok_len then
    return false, err_len
  end
  if value:find "%s" then
    return false, "invalid_format:Url"
  end
  if not value:match "^https?://[%w]" then
    return false, "invalid_format:Url"
  end
  return true
end

local function validate_gateway_short_token(value, field, max_len)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, max_len, field)
  if not ok_len then
    return false, err_len
  end
  if not value:match "^[%w%-%._]+$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function parse_gateway_numeric(value, field)
  local num = tonumber(value)
  if not num then
    return nil, ("invalid_number:%s"):format(field)
  end
  if num < 0 then
    return nil, ("invalid_number:%s"):format(field)
  end
  return num
end

local function validate_gateway_status(value)
  local ok_type, err_type = validation.assert_type(value, "string", "Status")
  if not ok_type then
    return false, err_type
  end
  local normalized = string.lower(value)
  if not gateway_status_allow[normalized] then
    return false, "invalid_value:Status"
  end
  return true, normalized
end

local function validate_gateway_last_seen(value)
  local ok_type, err_type = validation.assert_type(value, "string", "Last-Seen")
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 64, "Last-Seen")
  if not ok_len then
    return false, err_len
  end
  if not value:match "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$" then
    return false, "invalid_format:Last-Seen"
  end
  return true
end

validate_gateway_domain_label = function(value, field, allow_wildcard)
  local normalized = normalize_host_label(value)
  if not normalized then
    return false, ("invalid_type:%s"):format(field)
  end
  local ok_len, err_len = validation.check_length(normalized, 255, field)
  if not ok_len then
    return false, err_len
  end
  if normalized:find "%s" or normalized:find "%.%.+" then
    return false, ("invalid_format:%s"):format(field)
  end
  if normalized:sub(1, 1) == "." or normalized:sub(-1) == "." then
    return false, ("invalid_format:%s"):format(field)
  end
  if normalized:find "%*" then
    if not allow_wildcard or not normalized:match "^%*%.[%w%-%.]+$" then
      return false, ("invalid_format:%s"):format(field)
    end
  elseif not normalized:match "^[%w%-%.]+$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true, normalized
end

normalize_site_id = function(value, field)
  local label = field or "Site-Id"
  local ok_type, err_type = validation.assert_type(value, "string", label)
  if not ok_type then
    return nil, err_type
  end
  local site_id = tostring(value)
  if site_id == "" then
    return nil, ("invalid_format:%s"):format(label)
  end
  local ok_len, err_len = validation.check_length(site_id, 128, label)
  if not ok_len then
    return nil, err_len
  end
  return site_id
end

local function enforce_site_id_fail_closed(msg)
  local action = msg.Action
  if not site_id_guard_actions[action] then
    return true
  end

  local canonical = nil
  for _, key in ipairs(site_id_guard_fields) do
    local value = msg[key]
    if value ~= nil then
      local ok_type, err_type = validation.assert_type(value, "string", "Site-Id")
      if not ok_type then
        return false, err_type
      end
      if canonical ~= nil and canonical ~= value then
        return false, "conflicting_site_id_fields"
      end
      canonical = value
    end
  end

  if canonical ~= nil and msg["Site-Id"] == nil then
    msg["Site-Id"] = canonical
  end
  return true
end

local function normalize_gateway_domains(raw_domains)
  if raw_domains == nil then
    return {}
  end
  if type(raw_domains) == "string" then
    raw_domains = { raw_domains }
  end
  if type(raw_domains) ~= "table" then
    return nil, "Domains must be string or array", "Domains"
  end
  local seen = {}
  local out = {}
  for idx, domain in ipairs(raw_domains) do
    local ok_domain, norm_or_err =
      validate_gateway_domain_label(domain, ("Domains[%d]"):format(idx), true)
    if not ok_domain then
      return nil, norm_or_err, ("Domains[%d]"):format(idx)
    end
    local normalized = norm_or_err
    if not seen[normalized] then
      seen[normalized] = true
      out[#out + 1] = normalized
    end
  end
  table.sort(out)
  return out
end

local function snapshot_gateway(gateway)
  local domains = {}
  for i, domain in ipairs(gateway.domains or {}) do
    domains[i] = domain
  end
  return {
    id = gateway.id,
    url = gateway.url,
    region = gateway.region,
    country = gateway.country,
    capacityWeight = gateway.capacityWeight,
    score = gateway.score,
    status = gateway.status,
    lastSeen = gateway.lastSeen,
    domains = domains,
  }
end

local function host_matches_gateway_domain(host, domain)
  if host == domain then
    return true
  end
  if domain:sub(1, 2) ~= "*." then
    return false
  end
  local suffix = domain:sub(3)
  local tail = "." .. suffix
  return host:sub(-#tail) == tail
end

function handlers.RegisterGateway(msg)
  local required = {
    "Gateway-Id",
    "Url",
    "Region",
    "Country",
    "Capacity-Weight",
    "Score",
    "Status",
  }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Gateway-Id",
    "Url",
    "Region",
    "Country",
    "Capacity-Weight",
    "Score",
    "Status",
    "Last-Seen",
    "Domains",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local ok_id, err_id = validate_gateway_id(msg["Gateway-Id"])
  if not ok_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Gateway-Id" })
  end
  local ok_url, err_url = validate_gateway_url(msg.Url)
  if not ok_url then
    return codec.error("INVALID_INPUT", err_url, { field = "Url" })
  end
  local ok_region, err_region = validate_gateway_short_token(msg.Region, "Region", 64)
  if not ok_region then
    return codec.error("INVALID_INPUT", err_region, { field = "Region" })
  end
  local ok_country, err_country = validate_gateway_short_token(msg.Country, "Country", 16)
  if not ok_country then
    return codec.error("INVALID_INPUT", err_country, { field = "Country" })
  end
  local capacity_weight, err_weight =
    parse_gateway_numeric(msg["Capacity-Weight"], "Capacity-Weight")
  if err_weight then
    return codec.error("INVALID_INPUT", err_weight, { field = "Capacity-Weight" })
  end
  local score, err_score = parse_gateway_numeric(msg.Score, "Score")
  if err_score then
    return codec.error("INVALID_INPUT", err_score, { field = "Score" })
  end
  local ok_status, status_or_err = validate_gateway_status(msg.Status)
  if not ok_status then
    return codec.error("INVALID_INPUT", status_or_err, { field = "Status" })
  end
  local status = status_or_err

  local last_seen = msg["Last-Seen"] or now_iso()
  local ok_seen, err_seen = validate_gateway_last_seen(last_seen)
  if not ok_seen then
    return codec.error("INVALID_INPUT", err_seen, { field = "Last-Seen" })
  end
  local domains, domains_err, domains_field = normalize_gateway_domains(msg.Domains)
  if not domains then
    return codec.error("INVALID_INPUT", domains_err, { field = domains_field or "Domains" })
  end

  local gateway_id = msg["Gateway-Id"]
  local existing = state.gateways[gateway_id]
  if existing then
    return codec.ok {
      gateway = snapshot_gateway(existing),
      note = "already_registered",
    }
  end

  local gateway = {
    id = gateway_id,
    url = msg.Url,
    region = msg.Region,
    country = msg.Country,
    capacityWeight = capacity_weight,
    score = score,
    status = status,
    lastSeen = last_seen,
    domains = domains,
  }
  state.gateways[gateway_id] = gateway
  audit.record("registry", "RegisterGateway", msg, nil, {
    gatewayId = gateway_id,
    status = status,
    domains = #domains,
  })
  return codec.ok { gateway = snapshot_gateway(gateway) }
end

function handlers.UpdateGatewayStatus(msg)
  local required = { "Gateway-Id" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Gateway-Id",
    "Status",
    "Score",
    "Capacity-Weight",
    "Last-Seen",
    "Domains",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_id, err_id = validate_gateway_id(msg["Gateway-Id"])
  if not ok_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Gateway-Id" })
  end
  local gateway = state.gateways[msg["Gateway-Id"]]
  if not gateway then
    return codec.error("NOT_FOUND", "Gateway not registered", { gatewayId = msg["Gateway-Id"] })
  end

  local has_update = msg.Status ~= nil
    or msg.Score ~= nil
    or msg["Capacity-Weight"] ~= nil
    or msg["Last-Seen"] ~= nil
    or msg.Domains ~= nil
  if not has_update then
    return codec.error("INVALID_INPUT", "No mutable fields supplied")
  end

  if msg.Status ~= nil then
    local ok_status, status_or_err = validate_gateway_status(msg.Status)
    if not ok_status then
      return codec.error("INVALID_INPUT", status_or_err, { field = "Status" })
    end
    gateway.status = status_or_err
  end
  if msg.Score ~= nil then
    local score, err_score = parse_gateway_numeric(msg.Score, "Score")
    if err_score then
      return codec.error("INVALID_INPUT", err_score, { field = "Score" })
    end
    gateway.score = score
  end
  if msg["Capacity-Weight"] ~= nil then
    local weight, err_weight = parse_gateway_numeric(msg["Capacity-Weight"], "Capacity-Weight")
    if err_weight then
      return codec.error("INVALID_INPUT", err_weight, { field = "Capacity-Weight" })
    end
    gateway.capacityWeight = weight
  end
  if msg["Last-Seen"] ~= nil then
    local ok_seen, err_seen = validate_gateway_last_seen(msg["Last-Seen"])
    if not ok_seen then
      return codec.error("INVALID_INPUT", err_seen, { field = "Last-Seen" })
    end
    gateway.lastSeen = msg["Last-Seen"]
  end
  if msg.Domains ~= nil then
    local domains, domains_err, domains_field = normalize_gateway_domains(msg.Domains)
    if not domains then
      return codec.error("INVALID_INPUT", domains_err, { field = domains_field or "Domains" })
    end
    gateway.domains = domains
  end

  audit.record("registry", "UpdateGatewayStatus", msg, nil, {
    gatewayId = gateway.id,
    status = gateway.status,
  })
  return codec.ok { gateway = snapshot_gateway(gateway) }
end

function handlers.ResolveGatewayForHost(msg)
  local required = { "Host" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Host is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Host",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_host, host_or_err = validate_gateway_domain_label(msg.Host, "Host", false)
  if not ok_host then
    return codec.error("INVALID_INPUT", host_or_err, { field = "Host" })
  end
  local host = host_or_err

  local candidates = {}
  for _, gateway in pairs(state.gateways) do
    if gateway.status == "online" then
      for _, domain in ipairs(gateway.domains or {}) do
        if host_matches_gateway_domain(host, domain) then
          candidates[#candidates + 1] = {
            gateway = gateway,
            matchedDomain = domain,
            score = tonumber(gateway.score) or 0,
            capacityWeight = tonumber(gateway.capacityWeight) or 0,
          }
          break
        end
      end
    end
  end

  if #candidates == 0 then
    return codec.error("NOT_FOUND", "No online gateway candidate for host", { host = host })
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.capacityWeight ~= b.capacityWeight then
      return a.capacityWeight > b.capacityWeight
    end
    return tostring(a.gateway.id) < tostring(b.gateway.id)
  end)

  local chosen = candidates[1]
  return codec.ok {
    host = host,
    matchedDomain = chosen.matchedDomain,
    gateway = snapshot_gateway(chosen.gateway),
  }
end

function handlers.ListGateways(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Status",
    "Host",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local status_filter = nil
  if msg.Status ~= nil then
    local ok_status, status_or_err = validate_gateway_status(msg.Status)
    if not ok_status then
      return codec.error("INVALID_INPUT", status_or_err, { field = "Status" })
    end
    status_filter = status_or_err
  end

  local host_filter = nil
  if msg.Host ~= nil then
    local ok_host, host_or_err = validate_gateway_domain_label(msg.Host, "Host", false)
    if not ok_host then
      return codec.error("INVALID_INPUT", host_or_err, { field = "Host" })
    end
    host_filter = host_or_err
  end

  local list = {}
  for _, gateway in pairs(state.gateways) do
    local include = true
    if status_filter and gateway.status ~= status_filter then
      include = false
    end
    if include and host_filter then
      include = false
      for _, domain in ipairs(gateway.domains or {}) do
        if host_matches_gateway_domain(host_filter, domain) then
          include = true
          break
        end
      end
    end
    if include then
      list[#list + 1] = snapshot_gateway(gateway)
    end
  end
  table.sort(list, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)

  return codec.ok {
    count = #list,
    gateways = list,
  }
end

function handlers.RegisterSite(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Site-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Config",
    "Runtime",
    "Version",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  local config = msg.Config or {}
  if msg.Config ~= nil then
    local ok_type_cfg, err_type_cfg = validation.assert_type(msg.Config, "table", "Config")
    if not ok_type_cfg then
      return codec.error("INVALID_INPUT", err_type_cfg, { field = "Config" })
    end
    local ok_schema, schema_err = schema.validate("registryConfig", msg.Config)
    if not ok_schema then
      return codec.error("INVALID_INPUT", "Config failed schema", { errors = schema_err })
    end
  end
  local config_len = validation.estimate_json_length(config)
  local ok_size, err_size = validation.check_size(config_len, MAX_CONFIG_BYTES, "Config")
  if not ok_size then
    return codec.error("INVALID_INPUT", err_size, { field = "Config" })
  end
  local runtime = nil
  if msg.Runtime ~= nil then
    local runtime_err, runtime_field
    runtime, runtime_err, runtime_field = normalize_runtime_pointer(msg.Runtime, {
      field_name = "Runtime",
    })
    if not runtime then
      return codec.error("INVALID_INPUT", runtime_err, { field = runtime_field or "Runtime" })
    end
  end
  local existing = state.sites[site_id]
  if existing then
    local payload = {
      siteId = site_id,
      createdAt = existing.createdAt,
      config = existing.config,
      activeVersion = state.active_versions[site_id],
      note = "already_registered",
    }
    local existing_runtime = runtime_for_site(site_id)
    if existing_runtime then
      payload.runtime = existing_runtime
    end
    return codec.ok(payload)
  end
  state.sites[site_id] = {
    config = config,
    createdAt = now_iso(),
  }
  state.active_versions[site_id] = config.version or msg.Version or nil
  if runtime then
    local upserted, upsert_err, upsert_field = upsert_site_runtime(site_id, runtime)
    if not upserted then
      return codec.error("INVALID_INPUT", upsert_err, { field = upsert_field or "Runtime" })
    end
  end
  audit.record("registry", "RegisterSite", msg, nil)
  local payload = {
    siteId = site_id,
    createdAt = state.sites[site_id].createdAt,
    activeVersion = state.active_versions[site_id],
  }
  local current_runtime = runtime_for_site(site_id)
  if current_runtime then
    payload.runtime = current_runtime
  end
  return codec.ok(payload)
end

function handlers.SetSiteRuntime(msg)
  local required = { "Site-Id", "Runtime" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Runtime",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  if not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  local runtime, runtime_err, runtime_field = normalize_runtime_pointer(msg.Runtime, {
    field_name = "Runtime",
  })
  if not runtime then
    return codec.error("INVALID_INPUT", runtime_err, { field = runtime_field or "Runtime" })
  end
  local upserted, upsert_err, upsert_field = upsert_site_runtime(site_id, runtime)
  if not upserted then
    return codec.error("INVALID_INPUT", upsert_err, { field = upsert_field or "Runtime" })
  end
  audit.record("registry", msg.Action or "SetSiteRuntime", msg, nil, {
    siteId = site_id,
    processId = upserted.processId,
  })
  return codec.ok {
    siteId = site_id,
    runtime = upserted,
  }
end

handlers.UpsertSiteRuntime = handlers.SetSiteRuntime

function handlers.BindDomain(msg)
  local required = { "Site-Id", "Host" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Host",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  local ok_host, normalized_host_or_err = validate_gateway_domain_label(msg.Host, "Host", false)
  if not ok_host then
    return codec.error("INVALID_INPUT", normalized_host_or_err, { field = "Host" })
  end
  local normalized_host = normalized_host_or_err
  if not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  state.domains[normalized_host] = site_id
  audit.record("registry", "BindDomain", msg, nil, { host = normalized_host })
  return codec.ok {
    host = normalized_host,
    siteId = site_id,
  }
end

function handlers.SetActiveVersion(msg)
  local required = { "Site-Id", "Version" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Version",
    "ExpectedVersion",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  local ok_len_ver, err_ver = validation.check_length(msg.Version, 128, "Version")
  if not ok_len_ver then
    return codec.error("INVALID_INPUT", err_ver, { field = "Version" })
  end
  if msg.ExpectedVersion then
    local ok_len_exp, err_exp = validation.check_length(msg.ExpectedVersion, 128, "ExpectedVersion")
    if not ok_len_exp then
      return codec.error("INVALID_INPUT", err_exp, { field = "ExpectedVersion" })
    end
  end
  if not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  local current = state.active_versions[site_id]
  if msg.ExpectedVersion and current and current ~= msg.ExpectedVersion then
    return codec.error(
      "VERSION_CONFLICT",
      "ExpectedVersion mismatch",
      { expected = msg.ExpectedVersion, current = current }
    )
  end
  state.active_versions[site_id] = msg.Version
  local resp = codec.ok {
    siteId = site_id,
    activeVersion = msg.Version,
  }
  audit.record("registry", "SetActiveVersion", msg, resp, { version = msg.Version })
  return resp
end

function handlers.GrantRole(msg)
  local required = { "Site-Id", "Subject", "Role" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Site-Id",
    "Subject",
    "Role",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
  if not site_id then
    return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
  end
  local ok_len_subj, err_subj = validation.check_length(msg.Subject, 128, "Subject")
  if not ok_len_subj then
    return codec.error("INVALID_INPUT", err_subj, { field = "Subject" })
  end
  local ok_len_role, err_role = validation.check_length(msg.Role, 64, "Role")
  if not ok_len_role then
    return codec.error("INVALID_INPUT", err_role, { field = "Role" })
  end
  if not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id })
  end
  state.roles[site_id] = state.roles[site_id] or {}
  state.roles[site_id][msg.Subject] = msg.Role
  audit.record("registry", "GrantRole", msg, nil, { subject = msg.Subject, role = msg.Role })
  return codec.ok {
    siteId = site_id,
    subject = msg.Subject,
    role = msg.Role,
  }
end

function handlers.UpdateTrustResolvers(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Manifest-Tx",
    "Resolvers",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  if msg.Resolvers and type(msg.Resolvers) ~= "table" then
    return codec.error("INVALID_INPUT", "Resolvers must be array")
  end
  local list = msg.Resolvers or {}
  state.trust.resolvers = list
  state.trust.manifestTx = msg["Manifest-Tx"]
  state.trust.updatedAt = now_iso()
  audit.record("registry", "UpdateTrustResolvers", msg, nil, { count = #list })
  return codec.ok {
    updatedAt = state.trust.updatedAt,
    count = #list,
    manifestTx = state.trust.manifestTx,
  }
end

function handlers.GetTrustedResolvers(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  return codec.ok {
    manifestTx = state.trust.manifestTx,
    updatedAt = state.trust.updatedAt,
    resolvers = state.trust.resolvers,
  }
end

local function release_key(component_id, version)
  return tostring(component_id) .. "@" .. tostring(version)
end

local function read_component_id(msg)
  return msg["Component-Id"] or "gateway"
end

local function validate_token_field(value, field, max_len, pattern)
  local ok_len, err_len = validation.check_length(value, max_len, field)
  if not ok_len then
    return false, err_len
  end
  local text = tostring(value)
  if text == "" then
    return false, ("invalid_format:%s"):format(field)
  end
  if pattern and not text:match(pattern) then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function validate_iso8601_utc(value, field)
  local ok_len, err_len = validation.check_length(value, 64, field)
  if not ok_len then
    return false, err_len
  end
  if type(value) ~= "string" or not value:match "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function validate_positive_integer(value, field)
  local num = tonumber(value)
  if not num or num <= 0 or num ~= math.floor(num) then
    return false, ("invalid_number:%s"):format(field)
  end
  return true, num
end

local function validate_integrity_release_fields(component_id, version, root, uri_hash, meta_hash)
  local ok_component, err_component =
    validate_token_field(component_id, "Component-Id", 96, "^[%w%-%._]+$")
  if not ok_component then
    return false, err_component, "Component-Id"
  end
  local ok_version, err_version = validate_token_field(version, "Version", 128, "^[%w%-%._]+$")
  if not ok_version then
    return false, err_version, "Version"
  end
  local ok_root, err_root = validate_token_field(root, "Root", 256, "^[%w%-%._]+$")
  if not ok_root then
    return false, err_root, "Root"
  end
  local ok_uri, err_uri = validate_token_field(uri_hash, "Uri-Hash", 256, "^[%w%-%._]+$")
  if not ok_uri then
    return false, err_uri, "Uri-Hash"
  end
  local ok_meta, err_meta = validate_token_field(meta_hash, "Meta-Hash", 256, "^[%w%-%._]+$")
  if not ok_meta then
    return false, err_meta, "Meta-Hash"
  end
  return true
end

local function parse_optional_number(value, field)
  if value == nil then
    return nil
  end
  local num = tonumber(value)
  if not num then
    return nil, ("invalid_number:%s"):format(field)
  end
  return num
end

local function parse_bool(value, field)
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "number" then
    if value == 1 then
      return true
    end
    if value == 0 then
      return false
    end
  end
  if type(value) == "string" then
    local lower = string.lower(value)
    if lower == "1" or lower == "true" or lower == "yes" then
      return true
    end
    if lower == "0" or lower == "false" or lower == "no" then
      return false
    end
  end
  return nil, ("invalid_boolean:%s"):format(field)
end

local function get_active_release()
  local root = state.integrity.policy.activeRoot
  if not root then
    return nil
  end
  local key = state.integrity.roots[root]
  if not key then
    return nil
  end
  return state.integrity.releases[key]
end

function handlers.PublishTrustedRelease(msg)
  local required = { "Version", "Root", "Uri-Hash", "Meta-Hash" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Component-Id",
    "Version",
    "Root",
    "Uri-Hash",
    "Meta-Hash",
    "Published-At",
    "Activate",
    "Policy-Hash",
    "Max-CheckIn-Age-Sec",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local component_id = read_component_id(msg)
  local version = msg.Version
  local root = msg.Root
  local uri_hash = msg["Uri-Hash"]
  local meta_hash = msg["Meta-Hash"]
  local ok_fields, err_fields, err_field =
    validate_integrity_release_fields(component_id, version, root, uri_hash, meta_hash)
  if not ok_fields then
    return codec.error("INVALID_INPUT", err_fields, { field = err_field })
  end
  local published_at = msg["Published-At"] or now_iso()
  local ok_pub_len, err_pub_len = validate_iso8601_utc(published_at, "Published-At")
  if not ok_pub_len then
    return codec.error("INVALID_INPUT", err_pub_len, { field = "Published-At" })
  end
  local policy_hash = msg["Policy-Hash"]
  if policy_hash ~= nil then
    local ok_policy_len, err_policy_len =
      validate_token_field(policy_hash, "Policy-Hash", 256, "^[%w%-%._]+$")
    if not ok_policy_len then
      return codec.error("INVALID_INPUT", err_policy_len, { field = "Policy-Hash" })
    end
  end
  local max_age, err_max_age =
    parse_optional_number(msg["Max-CheckIn-Age-Sec"], "Max-CheckIn-Age-Sec")
  if err_max_age then
    return codec.error("INVALID_INPUT", err_max_age, { field = "Max-CheckIn-Age-Sec" })
  end
  if max_age and (max_age <= 0 or max_age ~= math.floor(max_age)) then
    return codec.error(
      "INVALID_INPUT",
      "invalid_number:Max-CheckIn-Age-Sec",
      { field = "Max-CheckIn-Age-Sec" }
    )
  end
  local activate, err_activate =
    parse_bool(msg.Activate == nil and true or msg.Activate, "Activate")
  if err_activate then
    return codec.error("INVALID_INPUT", err_activate, { field = "Activate" })
  end

  local key = release_key(component_id, version)
  local existing = state.integrity.releases[key]
  if existing then
    if existing.root ~= root or existing.uriHash ~= uri_hash or existing.metaHash ~= meta_hash then
      return codec.error(
        "VERSION_CONFLICT",
        "Version already published with different release data",
        {
          componentId = component_id,
          version = version,
        }
      )
    end
    return codec.ok {
      release = existing,
      activeRoot = state.integrity.policy.activeRoot,
      note = "already_published",
    }
  end

  local root_key = state.integrity.roots[root]
  if root_key and root_key ~= key then
    return codec.error("ROOT_CONFLICT", "Root already registered for a different release", {
      root = root,
      current = root_key,
      incoming = key,
    })
  end

  local release = {
    componentId = component_id,
    version = version,
    root = root,
    uriHash = uri_hash,
    metaHash = meta_hash,
    publishedAt = published_at,
  }
  state.integrity.releases[key] = release
  state.integrity.roots[root] = key

  if activate then
    state.integrity.active[component_id] = version
    state.integrity.policy.activeRoot = root
    if policy_hash and policy_hash ~= "" then
      state.integrity.policy.activePolicyHash = policy_hash
    end
    if max_age then
      state.integrity.policy.maxCheckInAgeSec = max_age
    end
    state.integrity.policy.updatedAt = now_iso()
  end

  audit.record("registry", "PublishTrustedRelease", msg, nil, {
    componentId = component_id,
    version = version,
    root = root,
    activate = activate,
  })
  return codec.ok {
    release = release,
    activated = activate,
    activeRoot = state.integrity.policy.activeRoot,
    activePolicyHash = state.integrity.policy.activePolicyHash,
  }
end

function handlers.RevokeTrustedRelease(msg)
  local has_root = msg.Root ~= nil
  local has_version = msg.Version ~= nil
  if not has_root and not has_version then
    return codec.error("INVALID_INPUT", "Root or Version is required")
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Component-Id",
    "Version",
    "Root",
    "Reason",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local component_id = read_component_id(msg)
  local key_from_version
  if has_version then
    local ok_ver, err_ver = validation.check_length(msg.Version, 128, "Version")
    if not ok_ver then
      return codec.error("INVALID_INPUT", err_ver, { field = "Version" })
    end
    key_from_version = release_key(component_id, msg.Version)
  end
  local key_from_root
  if has_root then
    local ok_root, err_root = validation.check_length(msg.Root, 256, "Root")
    if not ok_root then
      return codec.error("INVALID_INPUT", err_root, { field = "Root" })
    end
    key_from_root = state.integrity.roots[msg.Root]
  end
  if key_from_version and key_from_root and key_from_version ~= key_from_root then
    return codec.error("INVALID_INPUT", "Root and Version point to different releases")
  end

  local key = key_from_root or key_from_version
  local release = key and state.integrity.releases[key] or nil
  if not release then
    return codec.error("NOT_FOUND", "Trusted release not found", {
      componentId = component_id,
      version = msg.Version,
      root = msg.Root,
    })
  end

  local reason = msg.Reason or ""
  local ok_reason, err_reason = validation.check_length(reason, 512, "Reason")
  if not ok_reason then
    return codec.error("INVALID_INPUT", err_reason, { field = "Reason" })
  end

  if release.revokedAt then
    return codec.ok { release = release, note = "already_revoked" }
  end

  release.revokedAt = now_iso()
  release.revokedReason = reason
  if state.integrity.policy.activeRoot == release.root then
    state.integrity.policy.paused = true
    state.integrity.policy.pauseReason = "active_root_revoked"
    state.integrity.policy.pausedBy = msg["Actor-Role"]
    state.integrity.policy.pausedAt = now_iso()
    state.integrity.policy.updatedAt = now_iso()
  end

  audit.record("registry", "RevokeTrustedRelease", msg, nil, {
    componentId = release.componentId,
    version = release.version,
    root = release.root,
  })
  return codec.ok {
    release = release,
    paused = state.integrity.policy.paused,
    activeRoot = state.integrity.policy.activeRoot,
  }
end

function handlers.GetTrustedReleaseByVersion(msg)
  local required = { "Version" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Component-Id",
    "Version",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local component_id = read_component_id(msg)
  local key = release_key(component_id, msg.Version)
  local ok_component, err_component =
    validate_token_field(component_id, "Component-Id", 96, "^[%w%-%._]+$")
  if not ok_component then
    return codec.error("INVALID_INPUT", err_component, { field = "Component-Id" })
  end
  local ok_version, err_version = validate_token_field(msg.Version, "Version", 128, "^[%w%-%._]+$")
  if not ok_version then
    return codec.error("INVALID_INPUT", err_version, { field = "Version" })
  end
  local release = state.integrity.releases[key]
  if not release then
    return codec.error("NOT_FOUND", "Trusted release not found", {
      componentId = component_id,
      version = msg.Version,
    })
  end
  return codec.ok { release = release }
end

function handlers.GetTrustedReleaseByRoot(msg)
  local required = { "Root" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Root",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local key = state.integrity.roots[msg.Root]
  local ok_root, err_root = validate_token_field(msg.Root, "Root", 256, "^[%w%-%._]+$")
  if not ok_root then
    return codec.error("INVALID_INPUT", err_root, { field = "Root" })
  end
  local release = key and state.integrity.releases[key] or nil
  if not release then
    return codec.error("NOT_FOUND", "Trusted release not found", { root = msg.Root })
  end
  return codec.ok { release = release }
end

function handlers.GetTrustedRoot(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Component-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local active_release = get_active_release()
  if not active_release then
    return codec.error("NOT_FOUND", "Active trusted root is not set")
  end
  return codec.ok {
    componentId = active_release.componentId,
    version = active_release.version,
    root = active_release.root,
    paused = state.integrity.policy.paused,
    activePolicyHash = state.integrity.policy.activePolicyHash,
  }
end

function handlers.SetIntegrityPolicyPause(msg)
  local required = { "Paused" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Paused",
    "Reason",
    "Policy-Hash",
    "Max-CheckIn-Age-Sec",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local paused, err_paused = parse_bool(msg.Paused, "Paused")
  if err_paused then
    return codec.error("INVALID_INPUT", err_paused, { field = "Paused" })
  end
  local reason = msg.Reason or ""
  local ok_reason, err_reason = validation.check_length(reason, 512, "Reason")
  if not ok_reason then
    return codec.error("INVALID_INPUT", err_reason, { field = "Reason" })
  end
  if msg["Policy-Hash"] ~= nil then
    local ok_policy_hash, err_policy_hash =
      validate_token_field(msg["Policy-Hash"], "Policy-Hash", 256, "^[%w%-%._]+$")
    if not ok_policy_hash then
      return codec.error("INVALID_INPUT", err_policy_hash, { field = "Policy-Hash" })
    end
    if msg["Policy-Hash"] ~= "" then
      state.integrity.policy.activePolicyHash = msg["Policy-Hash"]
    end
  end
  if msg["Max-CheckIn-Age-Sec"] ~= nil then
    local max_age, err_age =
      parse_optional_number(msg["Max-CheckIn-Age-Sec"], "Max-CheckIn-Age-Sec")
    if err_age then
      return codec.error("INVALID_INPUT", err_age, { field = "Max-CheckIn-Age-Sec" })
    end
    if max_age <= 0 or max_age ~= math.floor(max_age) then
      return codec.error(
        "INVALID_INPUT",
        "invalid_number:Max-CheckIn-Age-Sec",
        { field = "Max-CheckIn-Age-Sec" }
      )
    end
    state.integrity.policy.maxCheckInAgeSec = max_age
  end

  state.integrity.policy.paused = paused
  state.integrity.policy.updatedAt = now_iso()
  state.integrity.policy.pausedBy = msg["Actor-Role"]
  if paused then
    state.integrity.policy.pausedAt = now_iso()
    state.integrity.policy.pauseReason = reason
  else
    state.integrity.policy.pausedAt = nil
    state.integrity.policy.pauseReason = nil
  end

  audit.record("registry", "SetIntegrityPolicyPause", msg, nil, {
    paused = paused,
    reason = reason,
  })
  return codec.ok {
    paused = state.integrity.policy.paused,
    pauseReason = state.integrity.policy.pauseReason,
    pausedAt = state.integrity.policy.pausedAt,
    pausedBy = state.integrity.policy.pausedBy,
    activeRoot = state.integrity.policy.activeRoot,
    activePolicyHash = state.integrity.policy.activePolicyHash,
    maxCheckInAgeSec = state.integrity.policy.maxCheckInAgeSec,
    updatedAt = state.integrity.policy.updatedAt,
  }
end

function handlers.GetIntegrityPolicy(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  return codec.ok {
    activeRoot = state.integrity.policy.activeRoot,
    activePolicyHash = state.integrity.policy.activePolicyHash,
    paused = state.integrity.policy.paused,
    pausedAt = state.integrity.policy.pausedAt,
    pausedBy = state.integrity.policy.pausedBy,
    pauseReason = state.integrity.policy.pauseReason,
    maxCheckInAgeSec = state.integrity.policy.maxCheckInAgeSec,
    updatedAt = state.integrity.policy.updatedAt,
  }
end

function handlers.SetIntegrityAuthority(msg)
  local required = { "Root", "Upgrade", "Emergency", "Reporter" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Root",
    "Upgrade",
    "Emergency",
    "Reporter",
    "Signature-Refs",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local checks = {
    { field = "Root", value = msg.Root },
    { field = "Upgrade", value = msg.Upgrade },
    { field = "Emergency", value = msg.Emergency },
    { field = "Reporter", value = msg.Reporter },
  }
  for _, c in ipairs(checks) do
    local ok_len, err_len = validate_token_field(c.value, c.field, 256, "^[%w%-%._]+$")
    if not ok_len then
      return codec.error("INVALID_INPUT", err_len, { field = c.field })
    end
  end

  local signature_refs = msg["Signature-Refs"]
  if signature_refs == nil then
    signature_refs = { msg.Root }
  elseif type(signature_refs) == "string" then
    signature_refs = { signature_refs }
  elseif type(signature_refs) ~= "table" then
    return codec.error("INVALID_INPUT", "Signature-Refs must be string or array", {
      field = "Signature-Refs",
    })
  end
  if #signature_refs == 0 then
    return codec.error("INVALID_INPUT", "Signature-Refs cannot be empty", {
      field = "Signature-Refs",
    })
  end
  for idx, ref in ipairs(signature_refs) do
    local ok_ref, err_ref = validate_token_field(ref, "Signature-Refs", 256, "^[%w%-%._]+$")
    if not ok_ref then
      return codec.error("INVALID_INPUT", err_ref, { field = ("Signature-Refs[%d]"):format(idx) })
    end
  end

  state.integrity.authority.root = msg.Root
  state.integrity.authority.upgrade = msg.Upgrade
  state.integrity.authority.emergency = msg.Emergency
  state.integrity.authority.reporter = msg.Reporter
  state.integrity.authority.signatureRefs = signature_refs
  state.integrity.authority.updatedAt = now_iso()

  audit.record("registry", "SetIntegrityAuthority", msg, nil, {
    root = msg.Root,
    reporter = msg.Reporter,
    signatures = #signature_refs,
  })
  return codec.ok {
    root = state.integrity.authority.root,
    upgrade = state.integrity.authority.upgrade,
    emergency = state.integrity.authority.emergency,
    reporter = state.integrity.authority.reporter,
    signatureRefs = state.integrity.authority.signatureRefs,
    updatedAt = state.integrity.authority.updatedAt,
  }
end

function handlers.GetIntegrityAuthority(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  return codec.ok {
    root = state.integrity.authority.root,
    upgrade = state.integrity.authority.upgrade,
    emergency = state.integrity.authority.emergency,
    reporter = state.integrity.authority.reporter,
    signatureRefs = state.integrity.authority.signatureRefs,
    updatedAt = state.integrity.authority.updatedAt,
  }
end

function handlers.AppendIntegrityAuditCommitment(msg)
  local required = { "Seq-From", "Seq-To", "Merkle-Root", "Meta-Hash", "Reporter-Ref" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Seq-From",
    "Seq-To",
    "Merkle-Root",
    "Meta-Hash",
    "Reporter-Ref",
    "Accepted-At",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local ok_seq_from, seq_from = validate_positive_integer(msg["Seq-From"], "Seq-From")
  if not ok_seq_from then
    return codec.error("INVALID_INPUT", seq_from, { field = "Seq-From" })
  end
  local ok_seq_to, seq_to = validate_positive_integer(msg["Seq-To"], "Seq-To")
  if not ok_seq_to then
    return codec.error("INVALID_INPUT", seq_to, { field = "Seq-To" })
  end
  if seq_to < seq_from then
    return codec.error("INVALID_INPUT", "Invalid audit sequence range", {
      seqFrom = seq_from,
      seqTo = seq_to,
    })
  end
  if state.integrity.audit.seqTo > 0 and seq_from <= state.integrity.audit.seqTo then
    return codec.error("VERSION_CONFLICT", "Audit sequence overlaps existing range", {
      currentSeqTo = state.integrity.audit.seqTo,
      seqFrom = seq_from,
      seqTo = seq_to,
    })
  end

  local fields = {
    { field = "Merkle-Root", value = msg["Merkle-Root"] },
    { field = "Meta-Hash", value = msg["Meta-Hash"] },
    { field = "Reporter-Ref", value = msg["Reporter-Ref"] },
  }
  for _, f in ipairs(fields) do
    local ok_len, err_len = validate_token_field(f.value, f.field, 256, "^[%w%-%._]+$")
    if not ok_len then
      return codec.error("INVALID_INPUT", err_len, { field = f.field })
    end
  end

  local accepted_at = msg["Accepted-At"] or now_iso()
  local ok_time, err_time = validate_iso8601_utc(accepted_at, "Accepted-At")
  if not ok_time then
    return codec.error("INVALID_INPUT", err_time, { field = "Accepted-At" })
  end

  state.integrity.audit.seqFrom = seq_from
  state.integrity.audit.seqTo = seq_to
  state.integrity.audit.merkleRoot = msg["Merkle-Root"]
  state.integrity.audit.metaHash = msg["Meta-Hash"]
  state.integrity.audit.reporterRef = msg["Reporter-Ref"]
  state.integrity.audit.acceptedAt = accepted_at

  audit.record("registry", "AppendIntegrityAuditCommitment", msg, nil, {
    seqFrom = seq_from,
    seqTo = seq_to,
  })
  return codec.ok {
    seqFrom = state.integrity.audit.seqFrom,
    seqTo = state.integrity.audit.seqTo,
    merkleRoot = state.integrity.audit.merkleRoot,
    metaHash = state.integrity.audit.metaHash,
    reporterRef = state.integrity.audit.reporterRef,
    acceptedAt = state.integrity.audit.acceptedAt,
  }
end

function handlers.GetIntegrityAuditState(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  return codec.ok {
    seqFrom = state.integrity.audit.seqFrom,
    seqTo = state.integrity.audit.seqTo,
    merkleRoot = state.integrity.audit.merkleRoot,
    metaHash = state.integrity.audit.metaHash,
    reporterRef = state.integrity.audit.reporterRef,
    acceptedAt = state.integrity.audit.acceptedAt,
  }
end

function handlers.GetIntegritySnapshot(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local active_release = get_active_release()
  if not active_release then
    return codec.error("NOT_FOUND", "Active trusted release is not set")
  end
  if active_release.revokedAt then
    return codec.error("NOT_FOUND", "Active trusted release is revoked", {
      root = active_release.root,
      revokedAt = active_release.revokedAt,
    })
  end

  return codec.ok {
    release = {
      componentId = active_release.componentId,
      version = active_release.version,
      root = active_release.root,
      uriHash = active_release.uriHash,
      metaHash = active_release.metaHash,
      publishedAt = active_release.publishedAt,
      revokedAt = active_release.revokedAt,
    },
    policy = {
      activeRoot = state.integrity.policy.activeRoot,
      activePolicyHash = state.integrity.policy.activePolicyHash,
      paused = state.integrity.policy.paused,
      maxCheckInAgeSec = state.integrity.policy.maxCheckInAgeSec,
    },
    authority = {
      root = state.integrity.authority.root,
      upgrade = state.integrity.authority.upgrade,
      emergency = state.integrity.authority.emergency,
      reporter = state.integrity.authority.reporter,
      signatureRefs = state.integrity.authority.signatureRefs,
    },
    audit = {
      seqFrom = state.integrity.audit.seqFrom,
      seqTo = state.integrity.audit.seqTo,
      merkleRoot = state.integrity.audit.merkleRoot,
      metaHash = state.integrity.audit.metaHash,
      reporterRef = state.integrity.audit.reporterRef,
      acceptedAt = state.integrity.audit.acceptedAt,
    },
  }
end

local function validate_resolver_id(id)
  local ok_len, err = validation.check_length(id, 256, "Resolver-Id")
  if not ok_len then
    return false, err
  end
  return true
end

function handlers.FlagResolver(msg)
  local required = { "Resolver-Id", "Flag" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Resolver-Id",
    "Flag",
    "Reason",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_id, err_id = validate_resolver_id(msg["Resolver-Id"])
  if not ok_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Resolver-Id" })
  end
  local flag = msg.Flag
  if flag ~= "suspicious" and flag ~= "blocked" and flag ~= "ok" then
    return codec.error("INVALID_INPUT", "Flag must be suspicious|blocked|ok", { flag = flag })
  end
  local reason = msg.Reason or ""
  local ok_len_reason, err_reason = validation.check_length(reason, 512, "Reason")
  if not ok_len_reason then
    return codec.error("INVALID_INPUT", err_reason, { field = "Reason" })
  end
  state.resolver_flags[msg["Resolver-Id"]] = {
    flag = flag,
    reason = reason,
    raisedAt = now_iso(),
    raisedBy = msg["Actor-Role"],
  }
  persist_flag_event {
    ts = now_iso(),
    action = "FlagResolver",
    resolverId = msg["Resolver-Id"],
    flag = flag,
    reason = reason,
  }
  audit.record("registry", "FlagResolver", msg, nil, { resolver = msg["Resolver-Id"], flag = flag })
  return codec.ok { resolverId = msg["Resolver-Id"], flag = flag, reason = reason }
end

function handlers.UnflagResolver(msg)
  local required = { "Resolver-Id" }
  local ok, missing = validation.require_fields(msg, required)
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Resolver-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_id, err_id = validate_resolver_id(msg["Resolver-Id"])
  if not ok_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Resolver-Id" })
  end
  state.resolver_flags[msg["Resolver-Id"]] = nil
  persist_flag_event {
    ts = now_iso(),
    action = "UnflagResolver",
    resolverId = msg["Resolver-Id"],
    flag = "cleared",
  }
  audit.record("registry", "UnflagResolver", msg, nil, { resolver = msg["Resolver-Id"] })
  return codec.ok { resolverId = msg["Resolver-Id"], flag = "cleared" }
end

function handlers.GetResolverFlags(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Resolver-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  if msg["Resolver-Id"] then
    local ok_id, err_id = validate_resolver_id(msg["Resolver-Id"])
    if not ok_id then
      return codec.error("INVALID_INPUT", err_id, { field = "Resolver-Id" })
    end
    local entry = state.resolver_flags[msg["Resolver-Id"]]
    if not entry then
      return codec.ok { resolverId = msg["Resolver-Id"], flag = "none" }
    end
    return codec.ok {
      resolverId = msg["Resolver-Id"],
      flag = entry.flag,
      reason = entry.reason,
      raisedAt = entry.raisedAt,
      raisedBy = entry.raisedBy,
    }
  end
  local cnt = 0
  for _ in pairs(state.resolver_flags) do
    cnt = cnt + 1
  end
  return codec.ok { flags = state.resolver_flags, count = cnt }
end

local function route(msg)
  local ok, missing = validation.require_tags(msg, { "Action" })
  if not ok then
    return codec.missing_tags(missing)
  end

  local ok_action, err = validation.require_action(msg, allowed_actions)
  if not ok_action then
    if err == "unknown_action" then
      return codec.unknown_action(msg.Action)
    end
    return codec.error("MISSING_ACTION", "Action is required")
  end

  local ok_site_guard, site_guard_err = enforce_site_id_fail_closed(msg)
  if not ok_site_guard then
    return codec.error("INVALID_INPUT", site_guard_err, { field = "Site-Id" })
  end

  local requires_auth = PUBLIC_READ_REQUIRE_AUTH or not public_read_actions[msg.Action]
  if requires_auth then
    local ok_sec, sec_err = auth.enforce(msg)
    if not ok_sec then
      return codec.error("FORBIDDEN", sec_err)
    end
  end

  local ok_hmac, hmac_err =
    auth.verify_outbox_hmac_for_action(msg, { skip_for = hmac_skip_actions })
  if not ok_hmac then
    return codec.error("FORBIDDEN", hmac_err)
  end

  local ok_role, role_err = auth.require_role_for_action(msg, role_policy)
  if not ok_role then
    return codec.error("FORBIDDEN", role_err)
  end

  local request_id = tostring(msg["Request-Id"] or "")
  local idem_scope_key = nil
  if request_id ~= "" then
    idem_scope_key = table.concat({
      request_id,
      tostring(msg.Action or ""),
      tostring(msg.From or msg["Actor-Id"] or ""),
    }, "|")
    local seen = idem.check(idem_scope_key)
    if seen then
      return seen
    end
  end

  local handler = handlers[msg.Action]
  if not handler then
    return codec.unknown_action(msg.Action)
  end

  local resp = handler(msg)
  metrics.inc("registry." .. msg.Action .. ".count")
  metrics.tick()
  if idem_scope_key then
    idem.record(idem_scope_key, resp)
  end
  persist.save("registry_state", state)
  return resp
end

local function is_array(value)
  if type(value) ~= "table" then
    return false, 0
  end
  local max = 0
  local count = 0
  for k in pairs(value) do
    if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then
      return false, 0
    end
    if k > max then
      max = k
    end
    count = count + 1
  end
  if max == 0 then
    return true, 0
  end
  if max ~= count then
    return false, 0
  end
  return true, max
end

local function json_quote(value)
  local s = tostring(value)
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local function encode_json_fallback(value, seen)
  local t = type(value)
  if t == "nil" then
    return "null"
  end
  if t == "boolean" then
    return value and "true" or "false"
  end
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  end
  if t == "string" then
    return json_quote(value)
  end
  if t ~= "table" then
    return json_quote(tostring(value))
  end
  seen = seen or {}
  if seen[value] then
    return json_quote "__cycle__"
  end
  seen[value] = true
  local out = {}
  local array_like, length = is_array(value)
  if array_like then
    for i = 1, length do
      out[#out + 1] = encode_json_fallback(value[i], seen)
    end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    out[#out + 1] = json_quote(tostring(key)) .. ":" .. encode_json_fallback(value[key], seen)
  end
  seen[value] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

local function encode_json(value)
  if json_ok and json then
    local ok, encoded = pcall(json.encode, value)
    if ok and type(encoded) == "string" then
      return encoded
    end
  end
  return encode_json_fallback(value, {})
end

local function tag_value(tags, key)
  if type(tags) ~= "table" then
    return nil
  end
  if tags[key] ~= nil then
    return tags[key]
  end
  if tags[key:lower()] ~= nil then
    return tags[key:lower()]
  end
  for _, entry in ipairs(tags) do
    if type(entry) == "table" and (entry.name == key or entry.Name == key) then
      return entry.value or entry.Value
    end
  end
  return nil
end

local function parse_json_object(raw)
  if type(raw) == "table" then
    return raw
  end
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local ok, decoded = pcall(function()
    if json_ok and json then
      return json.decode(raw)
    end
    return nil
  end)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil
end

local function merge_string_keys(dst, src)
  if type(src) ~= "table" then
    return
  end
  for key, value in pairs(src) do
    if type(key) == "string" and dst[key] == nil then
      dst[key] = value
    end
  end
end

local function merge_tag_keys(dst, tags)
  if type(tags) ~= "table" then
    return
  end
  merge_string_keys(dst, tags)
  for _, entry in ipairs(tags) do
    if type(entry) == "table" then
      local name = entry.name or entry.Name
      local value = entry.value or entry.Value
      if type(name) == "string" and dst[name] == nil and value ~= nil then
        dst[name] = value
      end
    end
  end
end

local function enrich_message(msg)
  local envelope = (type(msg) == "table" and (msg.Body or msg.body)) or {}
  local tags = msg.Tags or msg.tags or envelope.Tags or envelope.tags or {}
  local data_obj = parse_json_object(msg.Data or msg.data)
    or parse_json_object(envelope.Data or envelope.data)
    or {}

  local out = {}
  merge_string_keys(out, data_obj)
  merge_string_keys(out, envelope)
  merge_string_keys(out, msg)
  merge_tag_keys(out, tags)

  out.Action = out.Action or out.action or tag_value(tags, "Action")
  out["Request-Id"] = out["Request-Id"] or out.requestId or tag_value(tags, "Request-Id")
  out["Actor-Role"] = out["Actor-Role"] or out.actorRole or tag_value(tags, "Actor-Role")
  out["Schema-Version"] = out["Schema-Version"]
    or out.schemaVersion
    or tag_value(tags, "Schema-Version")
  out.Signature = out.Signature or out.signature or tag_value(tags, "Signature")
  out.Nonce = out.Nonce or out.nonce or tag_value(tags, "Nonce")
  out.ts = out.ts or out.timestamp or tag_value(tags, "ts")
  out.From = msg.From or msg.from
  out.Tags = tags
  return out, tags
end

local function emit_response_json(json_text)
  pcall(function()
    if type(print) == "function" then
      print(json_text)
    end
  end)
  return json_text
end

local function handle_registry_action(msg)
  local normalized = enrich_message(msg or {})
  local ok_route, route_result = pcall(route, normalized)
  local resp = ok_route and route_result
    or codec.error("HANDLER_CRASH", tostring(route_result or "registry_handler_crash"))
  local resp_json = encode_json(resp)
  return emit_response_json(resp_json)
end

local function is_registry_action(msg)
  if type(msg) ~= "table" then
    return false
  end
  local normalized = enrich_message(msg)
  local action = normalized.Action
  return type(action) == "string" and handlers[action] ~= nil
end

local registry_handler_registered = false
local registry_evaluate_wrapped = false
local original_handlers_evaluate = nil
local function resolve_handlers_api()
  if type(_G) == "table" and type(_G.Handlers) == "table" then
    return _G.Handlers
  end
  local env = _ENV
  if type(env) == "table" and type(env.Handlers) == "table" then
    return env.Handlers
  end
  return nil
end

local function ensure_registry_evaluate_wrapped(handlers_api)
  local api = handlers_api
  if type(api) ~= "table" then
    api = resolve_handlers_api()
  end
  if type(api) ~= "table" or type(api.evaluate) ~= "function" then
    return false
  end
  if not registry_evaluate_wrapped then
    original_handlers_evaluate = api.evaluate
    api.evaluate = function(msg, env)
      if is_registry_action(msg) then
        return handle_registry_action(msg)
      end
      return original_handlers_evaluate(msg, env)
    end
    registry_evaluate_wrapped = true
  end
  return true
end

local function ensure_registry_handler_registered()
  local handlers_api = resolve_handlers_api()
  if type(handlers_api) ~= "table" or type(handlers_api.add) ~= "function" then
    local ok_handlers, resolved_handlers = pcall(require, ".handlers")
    if
      ok_handlers
      and type(resolved_handlers) == "table"
      and type(resolved_handlers.add) == "function"
    then
      handlers_api = resolved_handlers
    else
      return false
    end
  end

  if not registry_handler_registered then
    handlers_api.add("Registry-Action", is_registry_action, handle_registry_action)
    registry_handler_registered = true
  end
  ensure_registry_evaluate_wrapped(handlers_api)
  return true
end

ensure_registry_handler_registered()

local function fallback_handle(msg)
  ensure_registry_handler_registered()
  if is_registry_action(msg) then
    return handle_registry_action(msg)
  end
  return nil
end

local previous_Handle = _G.Handle
local previous_handle = _G.handle

local function emit_handler_error(code, message, meta)
  return emit_response_json(encode_json(codec.error(code, message, meta)))
end

local function merged_global_handle(original, msg)
  local routed = fallback_handle(msg)
  if routed ~= nil then
    return routed
  end
  if type(original) == "function" then
    local ok_original, original_result = pcall(original, msg)
    if ok_original then
      return original_result
    else
      return emit_handler_error(
        "HANDLER_CRASH",
        tostring(original_result or "registry_original_handle_crash")
      )
    end
  end
  return nil
end

_G.Handle = function(msg)
  return merged_global_handle(previous_Handle, msg)
end

_G.handle = function(msg)
  local original = previous_handle
  if type(original) ~= "function" then
    original = previous_Handle
  end
  return merged_global_handle(original, msg)
end

return {
  route = route,
  _state = state, -- exposed for tests
}
