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
  "GetPolicySnapshot",
  "GetSiteServingPolicy",
  "GetHBNodeProfile",
  "GetDecisionForHostNode",
  "GetDnsProofState",
  "ResolveHostPolicyBundle",
  "GetTemplateActionContract",
  "GetSiteRuntimeBundle",
  "GetSiteAuthMetadata",
  "GetDomainLifecycleState",
  "CreateSessionLifecycle",
  "ReadSessionLifecycle",
  "GetSessionLifecycle",
  "RotateSessionLifecycle",
  "RevokeSessionLifecycle",
  "ListSessionsBySubject",
  "CheckPaymentWebhookIdempotency",
  "GetPaymentWebhookIdempotencyState",
  "ResetPaymentWebhookIdempotencyState",
  "RegisterHBNode",
  "UpdateHBNodeStatus",
  "SetSiteServingPolicy",
  "SetSiteFundingState",
  "SetDnsProofState",
  "SetSiteAuthMetadata",
  "SetDomainLifecycleState",
  "SetPolicyMode",
  "PublishPolicySnapshot",
  "RevokePolicySnapshot",
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
  RegisterHBNode = { "admin", "registry-admin" },
  UpdateHBNodeStatus = { "admin", "registry-admin" },
  SetSiteServingPolicy = { "admin", "registry-admin" },
  SetSiteFundingState = { "admin", "registry-admin" },
  SetDnsProofState = { "admin", "registry-admin" },
  SetSiteAuthMetadata = { "admin", "registry-admin" },
  SetDomainLifecycleState = { "admin", "registry-admin" },
  CreateSessionLifecycle = { "admin", "registry-admin" },
  ReadSessionLifecycle = { "admin", "registry-admin" },
  GetSessionLifecycle = { "admin", "registry-admin" },
  RotateSessionLifecycle = { "admin", "registry-admin" },
  RevokeSessionLifecycle = { "admin", "registry-admin" },
  ListSessionsBySubject = { "admin", "registry-admin" },
  CheckPaymentWebhookIdempotency = { "admin", "registry-admin" },
  GetPaymentWebhookIdempotencyState = { "admin", "registry-admin" },
  ResetPaymentWebhookIdempotencyState = { "admin", "registry-admin" },
  SetPolicyMode = { "admin", "registry-admin" },
  PublishPolicySnapshot = { "admin", "registry-admin" },
  RevokePolicySnapshot = { "admin", "registry-admin" },
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
  GetPolicySnapshot = true,
  GetSiteServingPolicy = true,
  GetHBNodeProfile = true,
  GetDecisionForHostNode = true,
  GetDnsProofState = true,
  ResolveHostPolicyBundle = true,
  GetTemplateActionContract = true,
  GetSiteRuntimeBundle = true,
  GetSiteAuthMetadata = true,
  GetDomainLifecycleState = true,
}

local public_read_actions = {
  GetSiteByHost = true,
  GetSiteConfig = true,
  ResolveGatewayForHost = true,
  ListGateways = true,
  GetSiteRuntime = true,
  GetPolicySnapshot = true,
  GetSiteServingPolicy = true,
  GetHBNodeProfile = true,
  GetDecisionForHostNode = true,
  GetDnsProofState = true,
  ResolveHostPolicyBundle = true,
  GetTemplateActionContract = true,
  GetSiteRuntimeBundle = true,
  GetSiteAuthMetadata = true,
  GetDomainLifecycleState = true,
}
local site_id_guard_actions = {
  RegisterSite = true,
  SetSiteRuntime = true,
  UpsertSiteRuntime = true,
  BindDomain = true,
  SetActiveVersion = true,
  GrantRole = true,
  SetSiteServingPolicy = true,
  SetSiteFundingState = true,
  SetSiteAuthMetadata = true,
  CreateSessionLifecycle = true,
  ReadSessionLifecycle = true,
  GetSessionLifecycle = true,
  RotateSessionLifecycle = true,
  RevokeSessionLifecycle = true,
  ListSessionsBySubject = true,
  CheckPaymentWebhookIdempotency = true,
  GetPaymentWebhookIdempotencyState = true,
  ResetPaymentWebhookIdempotencyState = true,
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
  policy = {
    mode = "off", -- off | observe | soft | enforce
    modeUpdatedAt = nil,
    modeUpdatedBy = nil,
    hb_nodes = {}, -- nodeId => { nodeId, url?, region?, country?, status, labels?, metadata?, registeredAt, updatedAt }
    site_serving = {}, -- siteId => serving policy document
    site_funding = {}, -- siteId => funding state document
    dns_proofs = {}, -- host => dns proof state document
    site_auth = {}, -- siteId => auth/session metadata document
    sessions = {}, -- siteId => sessionId => session lifecycle document
    payment_webhooks = {}, -- siteId => provider => { ttlSec, maxKeys, keyMaxBytes, entries = { eventId => entry } }
    domain_lifecycle = {}, -- host => { host, siteId, state = pending|active|suspended, ... }
    snapshots = {}, -- snapshotId => snapshot document
    activeSnapshotId = nil,
  },
})

local MAX_CONFIG_BYTES = tonumber(os.getenv "REGISTRY_MAX_CONFIG_BYTES" or "") or (16 * 1024)
local FLAGS_PATH = os.getenv "AO_FLAGS_PATH"
local WAL_PATH = os.getenv "AO_WAL_PATH"

local function now_iso()
  -- coarse timestamp for audit/debug; determinism is sufficient here.
  return os.date "!%Y-%m-%dT%H:%M:%SZ"
end

local function now_unix()
  return tonumber(os.time()) or 0
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

local POLICY_MODE_ALLOW = {
  off = true,
  observe = true,
  soft = true,
  enforce = true,
}

local function ensure_policy_state()
  state.policy = state.policy or {}
  local policy = state.policy

  if type(policy.mode) ~= "string" or not POLICY_MODE_ALLOW[policy.mode] then
    policy.mode = "off"
  end
  if type(policy.modeUpdatedAt) ~= "string" or policy.modeUpdatedAt == "" then
    policy.modeUpdatedAt = "1970-01-01T00:00:00Z"
  end
  if type(policy.modeUpdatedBy) ~= "string" then
    policy.modeUpdatedBy = ""
  end

  if type(policy.hb_nodes) ~= "table" then
    policy.hb_nodes = {}
  end
  if type(policy.site_serving) ~= "table" then
    policy.site_serving = {}
  end
  if type(policy.site_funding) ~= "table" then
    policy.site_funding = {}
  end
  if type(policy.dns_proofs) ~= "table" then
    policy.dns_proofs = {}
  end
  if type(policy.site_auth) ~= "table" then
    policy.site_auth = {}
  end
  if type(policy.sessions) ~= "table" then
    policy.sessions = {}
  end
  if type(policy.payment_webhooks) ~= "table" then
    policy.payment_webhooks = {}
  end
  if type(policy.domain_lifecycle) ~= "table" then
    policy.domain_lifecycle = {}
  end
  if type(policy.snapshots) ~= "table" then
    policy.snapshots = {}
  end
  if policy.activeSnapshotId ~= nil and type(policy.activeSnapshotId) ~= "string" then
    policy.activeSnapshotId = nil
  end
end

ensure_policy_state()

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
  templateTxId = true,
  TemplateTxId = true,
  ["Template-Tx-Id"] = true,
  template_tx_id = true,
  manifestTxId = true,
  ManifestTxId = true,
  ["Manifest-Tx-Id"] = true,
  manifest_tx_id = true,
  templateSha256 = true,
  TemplateSha256 = true,
  ["Template-Sha256"] = true,
  template_sha256 = true,
  templateVariant = true,
  TemplateVariant = true,
  ["Template-Variant"] = true,
  template_variant = true,
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
  templateTxId = true,
  TemplateTxId = true,
  ["Template-Tx-Id"] = true,
  template_tx_id = true,
  manifestTxId = true,
  ManifestTxId = true,
  ["Manifest-Tx-Id"] = true,
  manifest_tx_id = true,
  templateSha256 = true,
  TemplateSha256 = true,
  ["Template-Sha256"] = true,
  template_sha256 = true,
  templateVariant = true,
  TemplateVariant = true,
  ["Template-Variant"] = true,
  template_variant = true,
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

local function normalize_sha256_hex(value)
  local normalized = tostring(value):lower()
  if normalized:sub(1, 7) == "sha256-" then
    normalized = normalized:sub(8)
  end
  if normalized:sub(1, 2) == "0x" then
    normalized = normalized:sub(3)
  end
  return normalized
end

local function validate_runtime_pointer_sha256(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 80, field)
  if not ok_len then
    return false, err_len
  end
  local normalized = normalize_sha256_hex(value)
  if #normalized ~= 64 or not normalized:match "^[a-f0-9]+$" then
    return false, ("invalid_format:%s"):format(field)
  end
  return normalized
end

local function validate_runtime_pointer_variant(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 64, field)
  if not ok_len then
    return false, err_len
  end
  if value == "" or not tostring(value):match "^[A-Za-z0-9][A-Za-z0-9%._/%-]*$" then
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
  local template_tx_id =
    first_present(raw, { "templateTxId", "TemplateTxId", "Template-Tx-Id", "template_tx_id" })
  local manifest_tx_id =
    first_present(raw, { "manifestTxId", "ManifestTxId", "Manifest-Tx-Id", "manifest_tx_id" })
  local template_sha256 =
    first_present(raw, { "templateSha256", "TemplateSha256", "Template-Sha256", "template_sha256" })
  local template_variant =
    first_present(raw, { "templateVariant", "TemplateVariant", "Template-Variant", "template_variant" })
  local updated_at = first_present(raw, { "updatedAt", "UpdatedAt", "Updated-At", "updated_at" })

  local has_any_process = process_id ~= nil
    or site_process_id ~= nil
    or catalog_process_id ~= nil
    or access_process_id ~= nil
    or write_process_id ~= nil
    or ingest_process_id ~= nil
    or registry_process_id ~= nil
  local has_any_template = template_tx_id ~= nil
    or manifest_tx_id ~= nil
    or template_sha256 ~= nil
    or template_variant ~= nil

  if not has_any_process and not has_any_template and require_process then
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
  if template_tx_id ~= nil then
    local ok_template_tx, err_template_tx =
      validate_runtime_pointer_token(template_tx_id, field_name .. ".templateTxId")
    if not ok_template_tx then
      return nil, err_template_tx, field_name .. ".templateTxId"
    end
    runtime.templateTxId = tostring(template_tx_id)
  end
  if manifest_tx_id ~= nil then
    local ok_manifest_tx, err_manifest_tx =
      validate_runtime_pointer_token(manifest_tx_id, field_name .. ".manifestTxId")
    if not ok_manifest_tx then
      return nil, err_manifest_tx, field_name .. ".manifestTxId"
    end
    runtime.manifestTxId = tostring(manifest_tx_id)
  end
  if template_sha256 ~= nil then
    local normalized_sha, err_sha = validate_runtime_pointer_sha256(
      template_sha256,
      field_name .. ".templateSha256"
    )
    if not normalized_sha then
      return nil, err_sha, field_name .. ".templateSha256"
    end
    runtime.templateSha256 = normalized_sha
  end
  if template_variant ~= nil then
    local ok_variant, err_variant =
      validate_runtime_pointer_variant(template_variant, field_name .. ".templateVariant")
    if not ok_variant then
      return nil, err_variant, field_name .. ".templateVariant"
    end
    runtime.templateVariant = tostring(template_variant)
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
  local has_pointer = false
  for _, key in ipairs {
    "processId",
    "siteProcessId",
    "catalogProcessId",
    "accessProcessId",
    "writeProcessId",
    "ingestProcessId",
    "registryProcessId",
    "workerId",
    "workerUrl",
    "moduleId",
    "scheduler",
    "templateTxId",
    "manifestTxId",
    "templateSha256",
    "templateVariant",
  } do
    if type(runtime[key]) == "string" and runtime[key] ~= "" then
      has_pointer = true
      break
    end
  end
  if not has_pointer then
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
  if type(runtime.templateTxId) == "string" and runtime.templateTxId ~= "" then
    out.templateTxId = runtime.templateTxId
  end
  if type(runtime.manifestTxId) == "string" and runtime.manifestTxId ~= "" then
    out.manifestTxId = runtime.manifestTxId
  end
  if type(runtime.templateSha256) == "string" and runtime.templateSha256 ~= "" then
    out.templateSha256 = runtime.templateSha256
  end
  if type(runtime.templateVariant) == "string" and runtime.templateVariant ~= "" then
    out.templateVariant = runtime.templateVariant
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
  local existing = nil
  if type(state.site_runtimes) == "table" then
    existing = state.site_runtimes[site_id]
  end
  if type(existing) == "table" then
    local merged = {}
    for key, value in pairs(existing) do
      merged[key] = value
    end
    for key, value in pairs(normalized) do
      merged[key] = value
    end
    normalized = merged
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

local hb_node_status_allow = {
  online = true,
  offline = true,
  degraded = true,
  draining = true,
  maintenance = true,
}

local serving_state_allow = {
  allow = true,
  deny = true,
  observe = true,
  shadow = true,
}

local funding_state_allow = {
  active = true,
  grace = true,
  paused = true,
  blocked = true,
  unknown = true,
}

local dns_proof_status_allow = {
  unknown = true,
  pending = true,
  valid = true,
  invalid = true,
  expired = true,
  error = true,
}

local domain_lifecycle_state_allow = {
  pending = true,
  active = true,
  suspended = true,
}

local domain_lifecycle_transition_allow = {
  pending = { pending = true, active = true, suspended = true },
  active = { active = true, suspended = true },
  suspended = { suspended = true, active = true },
}

local session_lifecycle_status_allow = {
  active = true,
  revoked = true,
  rotated = true,
}

local webhook_idempotency_policy_allow = {
  dedupe = true,
  reject = true,
}

local DEFAULT_WEBHOOK_IDEMP_TTL_SEC = 600
local DEFAULT_WEBHOOK_IDEMP_MAX_KEYS = 10000
local DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES = 512

local function shallow_copy_table(input)
  if type(input) ~= "table" then
    return nil
  end
  local out = {}
  for key, value in pairs(input) do
    out[key] = value
  end
  return out
end

local function validate_policy_token(value, field, max_len, pattern)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, max_len or 128, field)
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

local function validate_policy_url(value, field)
  local ok_type, err_type = validation.assert_type(value, "string", field)
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 512, field)
  if not ok_len then
    return false, err_len
  end
  if value:find "%s" then
    return false, ("invalid_format:%s"):format(field)
  end
  if not value:match "^https?://[%w]" then
    return false, ("invalid_format:%s"):format(field)
  end
  return true
end

local function normalize_bool(value, field)
  if type(value) == "boolean" then
    return true, value
  end
  if type(value) == "number" then
    if value == 1 then
      return true, true
    end
    if value == 0 then
      return true, false
    end
  end
  if type(value) == "string" then
    local normalized = value:lower()
    if normalized == "1" or normalized == "true" or normalized == "yes" then
      return true, true
    end
    if normalized == "0" or normalized == "false" or normalized == "no" then
      return true, false
    end
  end
  return false, ("invalid_boolean:%s"):format(field)
end

local function normalize_positive_int(value, field, min_value, max_value)
  local num = tonumber(value)
  if not num or num ~= math.floor(num) then
    return nil, ("invalid_number:%s"):format(field)
  end
  if min_value ~= nil and num < min_value then
    return nil, ("invalid_number:%s"):format(field)
  end
  if max_value ~= nil and num > max_value then
    return nil, ("invalid_number:%s"):format(field)
  end
  return num
end

local function validate_policy_iso8601_utc(value, field)
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

local function normalize_string_list(raw, field, validator)
  if raw == nil then
    return {}
  end
  if type(raw) == "string" then
    raw = { raw }
  end
  if type(raw) ~= "table" then
    return nil, ("invalid_type:%s"):format(field), field
  end
  local seen = {}
  local out = {}
  for idx, value in ipairs(raw) do
    local entry_field = ("%s[%d]"):format(field, idx)
    local ok_entry, err_entry = validator(value, entry_field)
    if not ok_entry then
      return nil, err_entry, entry_field
    end
    local normalized = tostring(value)
    if not seen[normalized] then
      seen[normalized] = true
      out[#out + 1] = normalized
    end
  end
  table.sort(out)
  return out
end

local function policy_mode_or_default()
  ensure_policy_state()
  return state.policy.mode or "off"
end

local function snapshot_site_serving_policy(site_id)
  ensure_policy_state()
  local existing = state.policy.site_serving[site_id]
  if type(existing) ~= "table" then
    return {
      siteId = site_id,
      servingState = "allow",
      dnsProofRequired = false,
      cacheTtlSec = 300,
      hbAllowList = {},
      hbDenyList = {},
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
      policyRef = nil,
    }
  end
  local out = {
    siteId = site_id,
    servingState = existing.servingState or "allow",
    dnsProofRequired = existing.dnsProofRequired == true,
    cacheTtlSec = tonumber(existing.cacheTtlSec) or 300,
    hbAllowList = {},
    hbDenyList = {},
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
    policyRef = existing.policyRef,
    note = existing.note,
  }
  if type(existing.hbAllowList) == "table" then
    for idx, node_id in ipairs(existing.hbAllowList) do
      out.hbAllowList[idx] = node_id
    end
  end
  if type(existing.hbDenyList) == "table" then
    for idx, node_id in ipairs(existing.hbDenyList) do
      out.hbDenyList[idx] = node_id
    end
  end
  return out
end

local function snapshot_site_funding_state(site_id)
  ensure_policy_state()
  local existing = state.policy.site_funding[site_id]
  if type(existing) ~= "table" then
    return {
      siteId = site_id,
      fundingState = "active",
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
      plan = nil,
      tier = nil,
      payerRef = nil,
      reason = nil,
    }
  end
  return {
    siteId = site_id,
    fundingState = existing.fundingState or "active",
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
    plan = existing.plan,
    tier = existing.tier,
    payerRef = existing.payerRef,
    reason = existing.reason,
  }
end

local function snapshot_dns_proof_state(host, site_id)
  ensure_policy_state()
  local existing = state.policy.dns_proofs[host]
  if type(existing) ~= "table" then
    return {
      host = host,
      siteId = site_id,
      status = "unknown",
      verified = false,
      checkedAt = "1970-01-01T00:00:00Z",
      expiresAt = nil,
      source = "stub",
      challenge = nil,
      txtValue = nil,
      proofRef = nil,
      reason = nil,
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
    }
  end
  return {
    host = host,
    siteId = existing.siteId or site_id,
    status = existing.status or "unknown",
    verified = existing.verified == true,
    checkedAt = existing.checkedAt or "1970-01-01T00:00:00Z",
    expiresAt = existing.expiresAt,
    source = existing.source or "stub",
    challenge = existing.challenge,
    txtValue = existing.txtValue,
    proofRef = existing.proofRef,
    reason = existing.reason,
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
  }
end

local function snapshot_site_auth_metadata(site_id)
  ensure_policy_state()
  local existing = state.policy.site_auth[site_id]
  if type(existing) ~= "table" then
    return {
      siteId = site_id,
      sessionRequired = false,
      provider = "none",
      tokenTtlSec = 0,
      cookieName = nil,
      sessionMode = "stateless",
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
      note = nil,
    }
  end
  return {
    siteId = site_id,
    sessionRequired = existing.sessionRequired == true,
    provider = existing.provider or "none",
    tokenTtlSec = tonumber(existing.tokenTtlSec) or 0,
    cookieName = existing.cookieName,
    sessionMode = existing.sessionMode or "stateless",
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
    note = existing.note,
  }
end

local function ensure_site_sessions(site_id)
  ensure_policy_state()
  if type(state.policy.sessions[site_id]) ~= "table" then
    state.policy.sessions[site_id] = {}
  end
  return state.policy.sessions[site_id]
end

local function session_is_expired(session_doc, now_sec)
  local expires = tonumber(session_doc and session_doc.expiresAtUnix) or 0
  return expires > 0 and expires <= now_sec
end

local function normalize_session_id(value, field)
  return validate_policy_token(value, field, 160, "^[%w%-%._:@/+=]+$")
end

local function normalize_session_subject(value, field)
  return validate_policy_token(value, field, 320, "^[%w%-%._:@/+=]+$")
end

local function default_session_ttl_sec(site_id)
  local auth_doc = snapshot_site_auth_metadata(site_id)
  local configured = tonumber(auth_doc.tokenTtlSec) or 0
  if configured > 0 then
    return configured
  end
  return 14 * 24 * 60 * 60
end

local function make_session_id(msg, site_id, subject)
  local req = tostring(msg["Request-Id"] or ""):gsub("[^%w%-%._:@/+=]", "")
  if req ~= "" then
    return "sess:" .. site_id .. ":" .. req
  end
  local normalized_subject = tostring(subject or ""):gsub("[^%w%-%._:@/+=]", ""):sub(1, 24)
  if normalized_subject == "" then
    normalized_subject = "anonymous"
  end
  return ("sess:%s:%d:%s"):format(site_id, now_unix(), normalized_subject)
end

local function snapshot_session_lifecycle(site_id, session_id)
  local site_sessions = ensure_site_sessions(site_id)
  local existing = site_sessions[session_id]
  if type(existing) ~= "table" then
    return nil
  end

  local claims = shallow_copy_table(existing.claims) or {}
  local context = shallow_copy_table(existing.context) or {}
  local now_sec = now_unix()
  local status = existing.status or "active"
  if not session_lifecycle_status_allow[status] then
    status = "active"
  end

  local out = {
    siteId = existing.siteId or site_id,
    sessionId = existing.sessionId or session_id,
    subject = existing.subject or "",
    status = status,
    ttlSec = tonumber(existing.ttlSec) or 0,
    createdAt = existing.createdAt or "1970-01-01T00:00:00Z",
    createdAtUnix = tonumber(existing.createdAtUnix) or 0,
    expiresAt = existing.expiresAt or "1970-01-01T00:00:00Z",
    expiresAtUnix = tonumber(existing.expiresAtUnix) or 0,
    rotatedFrom = existing.rotatedFrom,
    rotatedTo = existing.rotatedTo,
    rotatedAt = existing.rotatedAt,
    revokedAt = existing.revokedAt,
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
    claims = claims,
    context = context,
    expired = session_is_expired(existing, now_sec),
  }
  return out
end

local function normalize_webhook_provider(value)
  if value == nil then
    return true, "default"
  end
  local ok_provider, err_provider = validate_policy_token(value, "Provider", 128, "^[%w%-%._:@/+=]+$")
  if not ok_provider then
    return false, err_provider
  end
  return true, tostring(value)
end

local function normalize_webhook_idempotency_policy(value)
  local raw = value
  if raw == nil then
    return true, "dedupe"
  end
  local ok_type, err_type = validation.assert_type(raw, "string", "Policy")
  if not ok_type then
    return false, err_type
  end
  local normalized = tostring(raw):lower()
  if not webhook_idempotency_policy_allow[normalized] then
    return false, "invalid_value:Policy"
  end
  return true, normalized
end

local function normalize_webhook_event_id(value, key_max_bytes)
  if value == nil then
    return true, ""
  end
  local ok_type, err_type = validation.assert_type(value, "string", "Event-Id")
  if not ok_type then
    return false, err_type
  end
  local event_id = tostring(value)
  if event_id == "" then
    return true, ""
  end
  if #event_id > key_max_bytes then
    return true, ""
  end
  return true, event_id
end

local function normalize_webhook_fingerprint(value)
  local ok_type, err_type = validation.assert_type(value, "string", "Fingerprint")
  if not ok_type then
    return false, err_type
  end
  local ok_len, err_len = validation.check_length(value, 512, "Fingerprint")
  if not ok_len then
    return false, err_len
  end
  local fingerprint = tostring(value)
  if fingerprint == "" then
    return false, "invalid_format:Fingerprint"
  end
  return true, fingerprint
end

local function ensure_site_payment_webhooks(site_id)
  ensure_policy_state()
  if type(state.policy.payment_webhooks[site_id]) ~= "table" then
    state.policy.payment_webhooks[site_id] = {}
  end
  return state.policy.payment_webhooks[site_id]
end

local function ensure_provider_payment_ledger(site_id, provider)
  local site_map = ensure_site_payment_webhooks(site_id)
  local existing = site_map[provider]
  if type(existing) ~= "table" then
    existing = {
      ttlSec = DEFAULT_WEBHOOK_IDEMP_TTL_SEC,
      maxKeys = DEFAULT_WEBHOOK_IDEMP_MAX_KEYS,
      keyMaxBytes = DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES,
      entries = {},
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
    }
    site_map[provider] = existing
  end
  if type(existing.entries) ~= "table" then
    existing.entries = {}
  end
  existing.ttlSec = tonumber(existing.ttlSec) or DEFAULT_WEBHOOK_IDEMP_TTL_SEC
  existing.maxKeys = tonumber(existing.maxKeys) or DEFAULT_WEBHOOK_IDEMP_MAX_KEYS
  existing.keyMaxBytes = tonumber(existing.keyMaxBytes) or DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES
  existing.updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z"
  existing.updatedBy = existing.updatedBy or ""
  return existing
end

local function prune_expired_webhook_entries(ledger, now_unix, ttl_sec)
  if type(ledger.entries) ~= "table" then
    ledger.entries = {}
    return 0
  end
  local removed = 0
  for event_id, entry in pairs(ledger.entries) do
    local seen_at_unix = tonumber(entry and entry.seenAtUnix) or 0
    if seen_at_unix <= 0 or (now_unix - seen_at_unix) > ttl_sec then
      ledger.entries[event_id] = nil
      removed = removed + 1
    end
  end
  return removed
end

local function count_webhook_entries(ledger)
  local count = 0
  for _ in pairs(ledger.entries or {}) do
    count = count + 1
  end
  return count
end

local function prune_oldest_webhook_entry(ledger)
  local oldest_key = nil
  local oldest_unix = nil
  for event_id, entry in pairs(ledger.entries or {}) do
    local seen_at_unix = tonumber(entry and entry.seenAtUnix) or 0
    if oldest_unix == nil or seen_at_unix < oldest_unix then
      oldest_key = event_id
      oldest_unix = seen_at_unix
    end
  end
  if oldest_key ~= nil then
    ledger.entries[oldest_key] = nil
    return 1
  end
  return 0
end

local function snapshot_payment_webhook_entry(event_id, entry, ttl_sec, now_unix)
  local seen_at_unix = tonumber(entry and entry.seenAtUnix) or 0
  local seen_at = entry and entry.seenAt or "1970-01-01T00:00:00Z"
  local expires_at_unix = seen_at_unix + ttl_sec
  local expires_at = os.date("!%Y-%m-%dT%H:%M:%SZ", expires_at_unix)
  return {
    eventId = event_id,
    fingerprint = entry and entry.fingerprint or "",
    seenAt = seen_at,
    seenAtUnix = seen_at_unix,
    expiresAt = expires_at,
    expiresAtUnix = expires_at_unix,
    expired = seen_at_unix <= 0 or expires_at_unix <= now_unix,
  }
end

local function snapshot_payment_webhook_ledger(site_id, provider, ledger, limit)
  local ttl_sec = tonumber(ledger.ttlSec) or DEFAULT_WEBHOOK_IDEMP_TTL_SEC
  local now_unix_value = now_unix()
  local entries = {}
  for event_id, entry in pairs(ledger.entries or {}) do
    entries[#entries + 1] = snapshot_payment_webhook_entry(event_id, entry, ttl_sec, now_unix_value)
  end
  table.sort(entries, function(a, b)
    return (tonumber(a.seenAtUnix) or 0) > (tonumber(b.seenAtUnix) or 0)
  end)
  while #entries > limit do
    table.remove(entries)
  end
  return {
    siteId = site_id,
    provider = provider,
    ttlSec = ttl_sec,
    maxKeys = tonumber(ledger.maxKeys) or DEFAULT_WEBHOOK_IDEMP_MAX_KEYS,
    keyMaxBytes = tonumber(ledger.keyMaxBytes) or DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES,
    count = count_webhook_entries(ledger),
    updatedAt = ledger.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = ledger.updatedBy or "",
    entries = entries,
  }
end

local function snapshot_domain_lifecycle_state(host, site_id)
  ensure_policy_state()
  local existing = state.policy.domain_lifecycle[host]
  if type(existing) ~= "table" then
    return {
      host = host,
      siteId = site_id,
      state = "active",
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
      reason = nil,
      source = "default",
    }
  end
  return {
    host = host,
    siteId = existing.siteId or site_id,
    state = existing.state or "active",
    updatedAt = existing.updatedAt or "1970-01-01T00:00:00Z",
    updatedBy = existing.updatedBy or "",
    reason = existing.reason,
    source = existing.source or "manual",
  }
end

local function snapshot_hb_node_profile(node_id)
  ensure_policy_state()
  local existing = state.policy.hb_nodes[node_id]
  if type(existing) ~= "table" then
    return {
      nodeId = node_id,
      registered = false,
      status = "unknown",
      labels = {},
      metadata = {},
      registeredAt = nil,
      updatedAt = nil,
    }
  end
  local labels = {}
  if type(existing.labels) == "table" then
    for idx, label in ipairs(existing.labels) do
      labels[idx] = label
    end
  end
  local metadata = shallow_copy_table(existing.metadata) or {}
  return {
    nodeId = node_id,
    registered = true,
    status = existing.status or "unknown",
    url = existing.url,
    region = existing.region,
    country = existing.country,
    capabilityTier = existing.capabilityTier,
    scoreWeight = existing.scoreWeight,
    labels = labels,
    metadata = metadata,
    registeredAt = existing.registeredAt,
    updatedAt = existing.updatedAt,
  }
end

function handlers.GetPolicySnapshot(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Snapshot-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  ensure_policy_state()
  local policy_mode = policy_mode_or_default()
  local requested_snapshot = msg["Snapshot-Id"]
  local snapshot_id = requested_snapshot or state.policy.activeSnapshotId
  local snapshot = nil

  if snapshot_id ~= nil then
    local ok_snapshot_id, err_snapshot_id = validate_policy_token(
      snapshot_id,
      "Snapshot-Id",
      128,
      "^[%w%-%._:@/]+$"
    )
    if not ok_snapshot_id then
      return codec.error("INVALID_INPUT", err_snapshot_id, { field = "Snapshot-Id" })
    end
    snapshot = state.policy.snapshots[snapshot_id]
    if snapshot == nil and requested_snapshot ~= nil then
      return codec.error("NOT_FOUND", "Policy snapshot not found", { snapshotId = snapshot_id })
    end
  end

  if snapshot == nil then
    return codec.ok {
      snapshot = nil,
      activeSnapshotId = state.policy.activeSnapshotId,
      policyMode = policy_mode,
      note = "snapshot_unpublished",
    }
  end

  return codec.ok {
    snapshot = shallow_copy_table(snapshot),
    activeSnapshotId = state.policy.activeSnapshotId,
    policyMode = policy_mode,
  }
end

function handlers.GetSiteServingPolicy(msg)
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

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    servingPolicy = snapshot_site_serving_policy(site_id),
    fundingState = snapshot_site_funding_state(site_id),
  }
end

function handlers.GetHBNodeProfile(msg)
  local ok, missing = validation.require_fields(msg, { "Node-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Node-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Node-Id",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_node_id, err_node_id = validate_policy_token(
    msg["Node-Id"],
    "Node-Id",
    128,
    "^[%w%-%._:@]+$"
  )
  if not ok_node_id then
    return codec.error("INVALID_INPUT", err_node_id, { field = "Node-Id" })
  end
  local node_id = tostring(msg["Node-Id"])

  return codec.ok {
    nodeId = node_id,
    policyMode = policy_mode_or_default(),
    profile = snapshot_hb_node_profile(node_id),
  }
end

function handlers.GetDnsProofState(msg)
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
  local host = normalized_host_or_err
  local site_id = state.domains[host]
  local dns_state = snapshot_dns_proof_state(host, site_id)

  return codec.ok {
    host = host,
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    dnsProofState = dns_state,
  }
end

local function resolve_host_policy_bundle(host, node_id)
  local site_id = state.domains[host]
  local serving_policy = site_id and snapshot_site_serving_policy(site_id) or nil
  local funding_state = site_id and snapshot_site_funding_state(site_id) or nil
  local auth_metadata = site_id and snapshot_site_auth_metadata(site_id) or nil
  local dns_proof_state = snapshot_dns_proof_state(host, site_id)
  local domain_lifecycle = snapshot_domain_lifecycle_state(host, site_id)
  local node_profile = node_id and snapshot_hb_node_profile(node_id) or nil
  local policy_mode = policy_mode_or_default()
  local allow = true
  local reason = "policy_stub_allow"
  if policy_mode == "off" then
    reason = "policy_mode_off"
  end

  local cache_ttl = 300
  if serving_policy and tonumber(serving_policy.cacheTtlSec) then
    cache_ttl = tonumber(serving_policy.cacheTtlSec)
  end

  return {
    host = host,
    nodeId = node_id,
    siteId = site_id,
    allow = allow,
    decision = allow and "allow" or "deny",
    reason = reason,
    policyMode = policy_mode,
    cacheTtlSec = cache_ttl,
    servingPolicy = serving_policy,
    fundingState = funding_state,
    authMetadata = auth_metadata,
    dnsProofState = dns_proof_state,
    domainLifecycle = domain_lifecycle,
    nodeProfile = node_profile,
  }
end

local TEMPLATE_ACTION_CONTRACT = {
  contractVersion = "1.0.0",
  updatedAt = "2026-04-22T00:00:00Z",
  checksum = "sha256:c93530e2f7d31d1f270af4ab8e11f9654c6cb6c397d17c0adf652f64806419f3",
  authority = "registry",
  defaultMode = "off",
  defaultDecision = "allow",
  actions = {
    read = {
      ["resolve-route"] = {
        registryAction = "ResolveHostPolicyBundle",
        required = { "Host" },
        optional = { "Node-Id", "Request-Id", "Nonce", "Timestamp" },
      },
      ["site-by-host"] = {
        registryAction = "GetSiteByHost",
        required = { "Host" },
        optional = { "Request-Id", "Nonce", "Timestamp" },
      },
      ["get-page"] = {
        registryAction = "GetSiteRuntimeBundle",
        required = { "Site-Id" },
        optional = { "Host", "Request-Id", "Nonce", "Timestamp" },
      },
    },
    write = {
      checkout = {
        metadata = {
          requiresAuth = true,
          idempotent = true,
          requestIdField = "Request-Id",
          actorRoleField = "Actor-Role",
          tags = { "Action", "Site-Id", "Request-Id", "Schema-Version" },
          note = "Checkout write handlers stay outside registry scope; this contract is authority metadata.",
        },
      },
    },
  },
}

local function parse_action_filters(msg)
  local selected = {}
  local out = {}

  local csv = msg["Action-Names"]
  if csv ~= nil then
    local ok_csv, err_csv = validation.assert_type(csv, "string", "Action-Names")
    if not ok_csv then
      return nil, err_csv, "Action-Names"
    end
    for raw in tostring(csv):gmatch "([^,]+)" do
      local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" and not selected[name] then
        selected[name] = true
        out[#out + 1] = name
      end
    end
  end

  local arr = msg.ActionNames
  if arr ~= nil then
    if type(arr) ~= "table" then
      return nil, "invalid_type:ActionNames", "ActionNames"
    end
    for idx, value in ipairs(arr) do
      local field = ("ActionNames[%d]"):format(idx)
      local ok_name, err_name = validate_policy_token(value, field, 128, "^[%w%-%._:@/]+$")
      if not ok_name then
        return nil, err_name, field
      end
      local name = tostring(value)
      if not selected[name] then
        selected[name] = true
        out[#out + 1] = name
      end
    end
  end

  if #out == 0 then
    return {}
  end
  table.sort(out)
  return out
end

local function copy_template_contract_actions()
  local actions = { read = {}, write = {} }
  for name, def in pairs(TEMPLATE_ACTION_CONTRACT.actions.read or {}) do
    actions.read[name] = def
  end
  for name, def in pairs(TEMPLATE_ACTION_CONTRACT.actions.write or {}) do
    actions.write[name] = def
  end
  return actions
end

local function filter_template_contract_actions(filters)
  local known = {}
  local filtered = { read = {}, write = {} }

  for name, def in pairs(TEMPLATE_ACTION_CONTRACT.actions.read or {}) do
    known[name] = true
    if filters[name] then
      filtered.read[name] = def
    end
  end
  for name, def in pairs(TEMPLATE_ACTION_CONTRACT.actions.write or {}) do
    known[name] = true
    if filters[name] then
      filtered.write[name] = def
    end
  end

  local unknown = {}
  for name in pairs(filters) do
    if not known[name] then
      unknown[#unknown + 1] = name
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    return nil, unknown
  end
  return filtered
end

function handlers.GetTemplateActionContract(msg)
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Action-Names",
    "ActionNames",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local payload = shallow_copy_table(TEMPLATE_ACTION_CONTRACT) or {}
  local parsed_filters, filter_err, filter_field = parse_action_filters(msg)
  if parsed_filters == nil then
    return codec.error("INVALID_INPUT", filter_err, { field = filter_field or "ActionNames" })
  end

  if #parsed_filters == 0 then
    payload.actions = copy_template_contract_actions()
  else
    local selected = {}
    for _, name in ipairs(parsed_filters) do
      selected[name] = true
    end
    local filtered_actions, unknown = filter_template_contract_actions(selected)
    if filtered_actions == nil then
      return codec.error("INVALID_INPUT", "unknown_action_filters", {
        unknown = unknown,
        known = {
          "checkout",
          "get-page",
          "resolve-route",
          "site-by-host",
        },
      })
    end
    payload.actions = filtered_actions
    payload.appliedFilter = parsed_filters
  end

  payload.policyMode = policy_mode_or_default()
  payload.generatedAt = now_iso()
  return codec.ok(payload)
end

local function list_hosts_for_site(site_id)
  local hosts = {}
  for host, mapped_site in pairs(state.domains or {}) do
    if mapped_site == site_id then
      hosts[#hosts + 1] = host
    end
  end
  table.sort(hosts)
  return hosts
end

function handlers.GetSiteRuntimeBundle(msg)
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

  local site_id = nil
  local host = nil
  if msg["Site-Id"] ~= nil then
    local normalized_site_id, site_id_err = normalize_site_id(msg["Site-Id"], "Site-Id")
    if not normalized_site_id then
      return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
    end
    site_id = normalized_site_id
  end
  if msg.Host ~= nil then
    local ok_host, normalized_host_or_err = validate_gateway_domain_label(msg.Host, "Host", false)
    if not ok_host then
      return codec.error("INVALID_INPUT", normalized_host_or_err, { field = "Host" })
    end
    host = normalized_host_or_err
  end

  if site_id == nil and host == nil then
    return codec.error("INVALID_INPUT", "Site-Id or Host is required", {
      missing = { "Site-Id|Host" },
    })
  end

  if site_id == nil and host ~= nil then
    site_id = state.domains[host]
  end
  if site_id ~= nil and host ~= nil then
    local mapped_site_id = state.domains[host]
    if mapped_site_id ~= nil and mapped_site_id ~= site_id then
      return codec.error("INVALID_INPUT", "conflicting_site_host", {
        siteId = site_id,
        host = host,
        mappedSiteId = mapped_site_id,
      })
    end
  end

  if site_id == nil or not state.sites[site_id] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = site_id, host = host })
  end

  local hosts = list_hosts_for_site(site_id)
  local selected_host = host or hosts[1]
  local runtime = runtime_for_site(site_id)
  local serving_policy = snapshot_site_serving_policy(site_id)
  local funding_state = snapshot_site_funding_state(site_id)
  local dns_state = selected_host and snapshot_dns_proof_state(selected_host, site_id) or {
    host = nil,
    siteId = site_id,
    status = "unknown",
    verified = false,
    checkedAt = "1970-01-01T00:00:00Z",
    expiresAt = nil,
    source = "stub",
    challenge = nil,
    txtValue = nil,
    proofRef = nil,
    reason = nil,
    updatedAt = "1970-01-01T00:00:00Z",
    updatedBy = "",
  }

  return codec.ok {
    siteId = site_id,
    host = selected_host,
    hosts = hosts,
    policyMode = policy_mode_or_default(),
    runtime = runtime,
    servingPolicy = serving_policy,
    fundingState = funding_state,
    authMetadata = snapshot_site_auth_metadata(site_id),
    dnsProofSummary = {
      host = dns_state.host,
      status = dns_state.status,
      verified = dns_state.verified == true,
      checkedAt = dns_state.checkedAt,
      expiresAt = dns_state.expiresAt,
      source = dns_state.source,
      proofRef = dns_state.proofRef,
      reason = dns_state.reason,
    },
    domainLifecycle = selected_host and snapshot_domain_lifecycle_state(selected_host, site_id) or nil,
  }
end

function handlers.GetSiteAuthMetadata(msg)
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

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    authMetadata = snapshot_site_auth_metadata(site_id),
  }
end

function handlers.GetDomainLifecycleState(msg)
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
  local host = normalized_host_or_err
  local site_id = state.domains[host]

  return codec.ok {
    host = host,
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    lifecycle = snapshot_domain_lifecycle_state(host, site_id),
  }
end

function handlers.CreateSessionLifecycle(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Subject" })
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
    "Session-Id",
    "Token-Ttl-Sec",
    "Claims",
    "Context",
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

  local ok_subject, err_subject = normalize_session_subject(msg.Subject, "Subject")
  if not ok_subject then
    return codec.error("INVALID_INPUT", err_subject, { field = "Subject" })
  end
  local subject = tostring(msg.Subject)

  local session_id = msg["Session-Id"]
  if session_id ~= nil then
    local ok_session_id, err_session_id = normalize_session_id(session_id, "Session-Id")
    if not ok_session_id then
      return codec.error("INVALID_INPUT", err_session_id, { field = "Session-Id" })
    end
    session_id = tostring(session_id)
  else
    session_id = make_session_id(msg, site_id, subject)
  end

  local ttl_default = default_session_ttl_sec(site_id)
  local ttl_input = msg["Token-Ttl-Sec"] ~= nil and msg["Token-Ttl-Sec"] or ttl_default
  local ttl_sec, ttl_err = normalize_positive_int(ttl_input, "Token-Ttl-Sec", 1, 31536000)
  if ttl_sec == nil then
    return codec.error("INVALID_INPUT", ttl_err, { field = "Token-Ttl-Sec" })
  end

  if msg.Claims ~= nil and type(msg.Claims) ~= "table" then
    return codec.error("INVALID_INPUT", "invalid_type:Claims", { field = "Claims" })
  end
  if msg.Context ~= nil and type(msg.Context) ~= "table" then
    return codec.error("INVALID_INPUT", "invalid_type:Context", { field = "Context" })
  end

  local site_sessions = ensure_site_sessions(site_id)
  local existing = site_sessions[session_id]
  if type(existing) == "table" then
    if tostring(existing.subject or "") ~= subject then
      return codec.error("CONFLICT", "session_id_already_used", {
        siteId = site_id,
        sessionId = session_id,
      })
    end
    return codec.ok {
      siteId = site_id,
      session = snapshot_session_lifecycle(site_id, session_id),
      policyMode = policy_mode_or_default(),
      idempotent = true,
    }
  end

  local created_unix = now_unix()
  local expires_unix = created_unix + ttl_sec
  local created_at = now_iso()
  local expires_at = os.date("!%Y-%m-%dT%H:%M:%SZ", expires_unix)
  local actor = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  local claims = shallow_copy_table(msg.Claims) or {}
  local context = shallow_copy_table(msg.Context) or {}

  site_sessions[session_id] = {
    siteId = site_id,
    sessionId = session_id,
    subject = subject,
    status = "active",
    ttlSec = ttl_sec,
    createdAt = created_at,
    createdAtUnix = created_unix,
    expiresAt = expires_at,
    expiresAtUnix = expires_unix,
    claims = claims,
    context = context,
    updatedAt = created_at,
    updatedBy = actor,
  }

  audit.record("registry", "CreateSessionLifecycle", msg, nil, {
    siteId = site_id,
    sessionId = session_id,
    subject = subject,
    ttlSec = ttl_sec,
  })

  return codec.ok {
    siteId = site_id,
    session = snapshot_session_lifecycle(site_id, session_id),
    policyMode = policy_mode_or_default(),
  }
end

function handlers.GetSessionLifecycle(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Session-Id" })
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
    "Session-Id",
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

  local ok_session_id, err_session_id = normalize_session_id(msg["Session-Id"], "Session-Id")
  if not ok_session_id then
    return codec.error("INVALID_INPUT", err_session_id, { field = "Session-Id" })
  end
  local session_id = tostring(msg["Session-Id"])

  local snapshot = snapshot_session_lifecycle(site_id, session_id)
  if not snapshot then
    return codec.error("NOT_FOUND", "session_not_found", { siteId = site_id, sessionId = session_id })
  end

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    session = snapshot,
  }
end

function handlers.ReadSessionLifecycle(msg)
  local raw = handlers.GetSessionLifecycle(msg)
  if raw.status ~= "OK" then
    return raw
  end
  local session = raw.payload and raw.payload.session or nil
  if type(session) ~= "table" then
    return codec.error("NOT_FOUND", "session_not_found")
  end

  local status = tostring(session.status or "active")
  if status == "revoked" then
    return codec.error("FORBIDDEN", "session_revoked", {
      siteId = session.siteId,
      sessionId = session.sessionId,
    })
  end
  if status == "rotated" then
    return codec.error("FORBIDDEN", "session_rotated", {
      siteId = session.siteId,
      sessionId = session.sessionId,
      rotatedTo = session.rotatedTo,
    })
  end
  if session.expired == true then
    return codec.error("EXPIRED", "session_expired", {
      siteId = session.siteId,
      sessionId = session.sessionId,
      expiresAt = session.expiresAt,
    })
  end

  return raw
end

function handlers.RotateSessionLifecycle(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Session-Id" })
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
    "Session-Id",
    "New-Session-Id",
    "Token-Ttl-Sec",
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

  local ok_session_id, err_session_id = normalize_session_id(msg["Session-Id"], "Session-Id")
  if not ok_session_id then
    return codec.error("INVALID_INPUT", err_session_id, { field = "Session-Id" })
  end
  local session_id = tostring(msg["Session-Id"])
  local existing = snapshot_session_lifecycle(site_id, session_id)
  if not existing then
    return codec.error("NOT_FOUND", "session_not_found", { siteId = site_id, sessionId = session_id })
  end
  if existing.status == "revoked" then
    return codec.error("FORBIDDEN", "session_revoked", { siteId = site_id, sessionId = session_id })
  end
  if existing.status == "rotated" then
    return codec.error("FORBIDDEN", "session_rotated", {
      siteId = site_id,
      sessionId = session_id,
      rotatedTo = existing.rotatedTo,
    })
  end
  if existing.expired == true then
    return codec.error("EXPIRED", "session_expired", { siteId = site_id, sessionId = session_id })
  end

  local next_session_id = msg["New-Session-Id"]
  if next_session_id ~= nil then
    local ok_next, err_next = normalize_session_id(next_session_id, "New-Session-Id")
    if not ok_next then
      return codec.error("INVALID_INPUT", err_next, { field = "New-Session-Id" })
    end
    next_session_id = tostring(next_session_id)
  else
    next_session_id = make_session_id(msg, site_id, existing.subject)
  end
  if next_session_id == session_id then
    return codec.error("INVALID_INPUT", "invalid_value:New-Session-Id", {
      field = "New-Session-Id",
      reason = "must_not_match_current",
    })
  end

  local ttl_input = msg["Token-Ttl-Sec"] ~= nil and msg["Token-Ttl-Sec"] or existing.ttlSec
  local ttl_sec, ttl_err = normalize_positive_int(ttl_input, "Token-Ttl-Sec", 1, 31536000)
  if ttl_sec == nil then
    return codec.error("INVALID_INPUT", ttl_err, { field = "Token-Ttl-Sec" })
  end

  local site_sessions = ensure_site_sessions(site_id)
  local existing_next = site_sessions[next_session_id]
  if type(existing_next) == "table" then
    local next_snapshot = snapshot_session_lifecycle(site_id, next_session_id)
    if next_snapshot and next_snapshot.rotatedFrom == session_id then
      return codec.ok {
        siteId = site_id,
        policyMode = policy_mode_or_default(),
        session = next_snapshot,
        previousSessionId = session_id,
        idempotent = true,
      }
    end
    return codec.error("CONFLICT", "session_id_already_used", {
      siteId = site_id,
      sessionId = next_session_id,
    })
  end

  local now_iso_value = now_iso()
  local now_unix_value = now_unix()
  local actor = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  local expires_unix = now_unix_value + ttl_sec

  local current_doc = site_sessions[session_id]
  current_doc.status = "rotated"
  current_doc.rotatedAt = now_iso_value
  current_doc.rotatedTo = next_session_id
  current_doc.updatedAt = now_iso_value
  current_doc.updatedBy = actor

  site_sessions[next_session_id] = {
    siteId = site_id,
    sessionId = next_session_id,
    subject = existing.subject,
    status = "active",
    ttlSec = ttl_sec,
    createdAt = now_iso_value,
    createdAtUnix = now_unix_value,
    expiresAt = os.date("!%Y-%m-%dT%H:%M:%SZ", expires_unix),
    expiresAtUnix = expires_unix,
    rotatedFrom = session_id,
    claims = shallow_copy_table(existing.claims) or {},
    context = shallow_copy_table(existing.context) or {},
    updatedAt = now_iso_value,
    updatedBy = actor,
  }

  audit.record("registry", "RotateSessionLifecycle", msg, nil, {
    siteId = site_id,
    sessionId = session_id,
    nextSessionId = next_session_id,
    ttlSec = ttl_sec,
  })

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    previousSessionId = session_id,
    session = snapshot_session_lifecycle(site_id, next_session_id),
  }
end

function handlers.RevokeSessionLifecycle(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Session-Id" })
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
    "Session-Id",
    "Reason",
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
  local ok_session_id, err_session_id = normalize_session_id(msg["Session-Id"], "Session-Id")
  if not ok_session_id then
    return codec.error("INVALID_INPUT", err_session_id, { field = "Session-Id" })
  end
  local session_id = tostring(msg["Session-Id"])
  local existing = snapshot_session_lifecycle(site_id, session_id)
  if not existing then
    return codec.error("NOT_FOUND", "session_not_found", { siteId = site_id, sessionId = session_id })
  end
  if existing.status == "revoked" then
    return codec.error("FORBIDDEN", "session_revoked", { siteId = site_id, sessionId = session_id })
  end
  if existing.status == "rotated" then
    return codec.error("FORBIDDEN", "session_rotated", { siteId = site_id, sessionId = session_id })
  end
  if existing.expired == true then
    return codec.error("EXPIRED", "session_expired", { siteId = site_id, sessionId = session_id })
  end

  local site_sessions = ensure_site_sessions(site_id)
  local now_iso_value = now_iso()
  local actor = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  local previous_status = site_sessions[session_id].status or "active"
  site_sessions[session_id].status = "revoked"
  site_sessions[session_id].revokedAt = now_iso_value
  site_sessions[session_id].reason = msg.Reason or site_sessions[session_id].reason
  site_sessions[session_id].updatedAt = now_iso_value
  site_sessions[session_id].updatedBy = actor

  audit.record("registry", "RevokeSessionLifecycle", msg, nil, {
    siteId = site_id,
    sessionId = session_id,
    previousStatus = previous_status,
    reason = msg.Reason,
  })

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    previousStatus = previous_status,
    session = snapshot_session_lifecycle(site_id, session_id),
  }
end

function handlers.ListSessionsBySubject(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Subject" })
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
    "Include-Inactive",
    "Limit",
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

  local ok_subject, err_subject = normalize_session_subject(msg.Subject, "Subject")
  if not ok_subject then
    return codec.error("INVALID_INPUT", err_subject, { field = "Subject" })
  end
  local subject = tostring(msg.Subject)

  local include_inactive = false
  if msg["Include-Inactive"] ~= nil then
    local ok_bool, bool_or_err = normalize_bool(msg["Include-Inactive"], "Include-Inactive")
    if not ok_bool then
      return codec.error("INVALID_INPUT", bool_or_err, { field = "Include-Inactive" })
    end
    include_inactive = bool_or_err
  end

  local limit = 100
  if msg.Limit ~= nil then
    local parsed_limit, limit_err = normalize_positive_int(msg.Limit, "Limit", 1, 500)
    if parsed_limit == nil then
      return codec.error("INVALID_INPUT", limit_err, { field = "Limit" })
    end
    limit = parsed_limit
  end

  local out = {}
  local site_sessions = ensure_site_sessions(site_id)
  for session_id, doc in pairs(site_sessions) do
    if tostring(doc.subject or "") == subject then
      local snapshot = snapshot_session_lifecycle(site_id, session_id)
      if snapshot then
        local include = include_inactive
        if not include then
          include = snapshot.status == "active" and snapshot.expired ~= true
        end
        if include then
          out[#out + 1] = snapshot
        end
      end
    end
  end

  table.sort(out, function(a, b)
    return (tonumber(a.createdAtUnix) or 0) > (tonumber(b.createdAtUnix) or 0)
  end)
  while #out > limit do
    table.remove(out)
  end

  return codec.ok {
    siteId = site_id,
    subject = subject,
    includeInactive = include_inactive,
    count = #out,
    policyMode = policy_mode_or_default(),
    sessions = out,
  }
end

function handlers.CheckPaymentWebhookIdempotency(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Fingerprint" })
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
    "Provider",
    "Event-Id",
    "Fingerprint",
    "Policy",
    "Ttl-Sec",
    "Max-Keys",
    "Key-Max-Bytes",
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

  local ok_provider, provider_or_err = normalize_webhook_provider(msg.Provider)
  if not ok_provider then
    return codec.error("INVALID_INPUT", provider_or_err, { field = "Provider" })
  end
  local provider = provider_or_err

  local ok_fingerprint, fingerprint_or_err = normalize_webhook_fingerprint(msg.Fingerprint)
  if not ok_fingerprint then
    return codec.error("INVALID_INPUT", fingerprint_or_err, { field = "Fingerprint" })
  end
  local fingerprint = fingerprint_or_err

  local ok_policy, policy_or_err = normalize_webhook_idempotency_policy(msg.Policy)
  if not ok_policy then
    return codec.error("INVALID_INPUT", policy_or_err, { field = "Policy" })
  end
  local policy = policy_or_err

  local ledger = ensure_provider_payment_ledger(site_id, provider)
  local ttl_sec_default = tonumber(ledger.ttlSec) or DEFAULT_WEBHOOK_IDEMP_TTL_SEC
  local max_keys_default = tonumber(ledger.maxKeys) or DEFAULT_WEBHOOK_IDEMP_MAX_KEYS
  local key_max_bytes_default = tonumber(ledger.keyMaxBytes) or DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES

  local ttl_input = msg["Ttl-Sec"] ~= nil and msg["Ttl-Sec"] or ttl_sec_default
  local ttl_sec, ttl_err = normalize_positive_int(ttl_input, "Ttl-Sec", 1, 31536000)
  if ttl_sec == nil then
    return codec.error("INVALID_INPUT", ttl_err, { field = "Ttl-Sec" })
  end

  local max_keys_input = msg["Max-Keys"] ~= nil and msg["Max-Keys"] or max_keys_default
  local max_keys, max_keys_err = normalize_positive_int(max_keys_input, "Max-Keys", 1, 500000)
  if max_keys == nil then
    return codec.error("INVALID_INPUT", max_keys_err, { field = "Max-Keys" })
  end

  local key_max_bytes_input = msg["Key-Max-Bytes"] ~= nil and msg["Key-Max-Bytes"] or key_max_bytes_default
  local key_max_bytes, key_max_bytes_err =
    normalize_positive_int(key_max_bytes_input, "Key-Max-Bytes", 16, 4096)
  if key_max_bytes == nil then
    return codec.error("INVALID_INPUT", key_max_bytes_err, { field = "Key-Max-Bytes" })
  end

  ledger.ttlSec = ttl_sec
  ledger.maxKeys = max_keys
  ledger.keyMaxBytes = key_max_bytes

  local now_unix_value = now_unix()
  local now_iso_value = now_iso()
  local actor = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  local pruned = prune_expired_webhook_entries(ledger, now_unix_value, ttl_sec)

  local ok_event_id, event_id_or_err = normalize_webhook_event_id(msg["Event-Id"], key_max_bytes)
  if not ok_event_id then
    return codec.error("INVALID_INPUT", event_id_or_err, { field = "Event-Id" })
  end
  local event_id = event_id_or_err
  if event_id == "" then
    return codec.ok {
      siteId = site_id,
      provider = provider,
      policy = policy,
      decision = {
        status = "missing-id",
        httpStatus = 400,
        body = "missing event id",
        accepted = false,
        replay = true,
        rejected = true,
        conflict = false,
      },
      ledger = {
        count = count_webhook_entries(ledger),
        ttlSec = ttl_sec,
        maxKeys = max_keys,
        keyMaxBytes = key_max_bytes,
        pruned = pruned,
      },
      policyMode = policy_mode_or_default(),
    }
  end

  local existing = ledger.entries[event_id]
  if type(existing) == "table" then
    if tostring(existing.fingerprint or "") == fingerprint then
      local status = "duplicate"
      local http_status = policy == "reject" and 409 or 200
      local body = policy == "reject" and "duplicate event id" or "replay"
      return codec.ok {
        siteId = site_id,
        provider = provider,
        policy = policy,
        eventId = event_id,
        decision = {
          status = status,
          httpStatus = http_status,
          body = body,
          accepted = false,
          replay = true,
          rejected = policy == "reject",
          conflict = false,
        },
        existing = snapshot_payment_webhook_entry(event_id, existing, ttl_sec, now_unix_value),
        ledger = {
          count = count_webhook_entries(ledger),
          ttlSec = ttl_sec,
          maxKeys = max_keys,
          keyMaxBytes = key_max_bytes,
          pruned = pruned,
        },
        policyMode = policy_mode_or_default(),
      }
    end
    return codec.ok {
      siteId = site_id,
      provider = provider,
      policy = policy,
      eventId = event_id,
      decision = {
        status = "conflict",
        httpStatus = 409,
        body = "conflicting event payload for event id",
        accepted = false,
        replay = true,
        rejected = true,
        conflict = true,
      },
      existing = snapshot_payment_webhook_entry(event_id, existing, ttl_sec, now_unix_value),
      ledger = {
        count = count_webhook_entries(ledger),
        ttlSec = ttl_sec,
        maxKeys = max_keys,
        keyMaxBytes = key_max_bytes,
        pruned = pruned,
      },
      policyMode = policy_mode_or_default(),
    }
  end

  while count_webhook_entries(ledger) >= max_keys do
    pruned = pruned + prune_oldest_webhook_entry(ledger)
  end

  ledger.entries[event_id] = {
    fingerprint = fingerprint,
    seenAt = now_iso_value,
    seenAtUnix = now_unix_value,
  }
  ledger.updatedAt = now_iso_value
  ledger.updatedBy = actor

  audit.record("registry", "CheckPaymentWebhookIdempotency", msg, nil, {
    siteId = site_id,
    provider = provider,
    eventId = event_id,
    accepted = true,
  })

  return codec.ok {
    siteId = site_id,
    provider = provider,
    policy = policy,
    eventId = event_id,
    decision = {
      status = "accepted",
      httpStatus = 200,
      body = "ok",
      accepted = true,
      replay = false,
      rejected = false,
      conflict = false,
    },
    entry = snapshot_payment_webhook_entry(event_id, ledger.entries[event_id], ttl_sec, now_unix_value),
    ledger = {
      count = count_webhook_entries(ledger),
      ttlSec = ttl_sec,
      maxKeys = max_keys,
      keyMaxBytes = key_max_bytes,
      pruned = pruned,
    },
    policyMode = policy_mode_or_default(),
  }
end

function handlers.GetPaymentWebhookIdempotencyState(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id" })
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
    "Provider",
    "Include-Entries",
    "Limit",
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

  local include_entries = false
  if msg["Include-Entries"] ~= nil then
    local ok_include, include_or_err = normalize_bool(msg["Include-Entries"], "Include-Entries")
    if not ok_include then
      return codec.error("INVALID_INPUT", include_or_err, { field = "Include-Entries" })
    end
    include_entries = include_or_err
  end

  local limit = 50
  if msg.Limit ~= nil then
    local parsed_limit, limit_err = normalize_positive_int(msg.Limit, "Limit", 1, 1000)
    if parsed_limit == nil then
      return codec.error("INVALID_INPUT", limit_err, { field = "Limit" })
    end
    limit = parsed_limit
  end

  local site_map = ensure_site_payment_webhooks(site_id)
  local provider_raw = msg.Provider
  if provider_raw ~= nil then
    local ok_provider, provider_or_err = normalize_webhook_provider(provider_raw)
    if not ok_provider then
      return codec.error("INVALID_INPUT", provider_or_err, { field = "Provider" })
    end
    local provider = provider_or_err
    local existing = site_map[provider]
    local ledger = type(existing) == "table" and existing or {
      ttlSec = DEFAULT_WEBHOOK_IDEMP_TTL_SEC,
      maxKeys = DEFAULT_WEBHOOK_IDEMP_MAX_KEYS,
      keyMaxBytes = DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES,
      entries = {},
      updatedAt = "1970-01-01T00:00:00Z",
      updatedBy = "",
    }
    local snapshot = snapshot_payment_webhook_ledger(site_id, provider, ledger, include_entries and limit or 0)
    if not include_entries then
      snapshot.entries = {}
    end
    return codec.ok {
      siteId = site_id,
      provider = provider,
      ledger = snapshot,
      policyMode = policy_mode_or_default(),
    }
  end

  local providers = {}
  for provider, ledger in pairs(site_map) do
    if type(ledger) == "table" then
      local snapshot = snapshot_payment_webhook_ledger(site_id, provider, ledger, include_entries and limit or 0)
      if not include_entries then
        snapshot.entries = {}
      end
      providers[#providers + 1] = snapshot
    end
  end
  table.sort(providers, function(a, b)
    return tostring(a.provider or "") < tostring(b.provider or "")
  end)

  return codec.ok {
    siteId = site_id,
    count = #providers,
    providers = providers,
    includeEntries = include_entries,
    policyMode = policy_mode_or_default(),
  }
end

function handlers.ResetPaymentWebhookIdempotencyState(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id" })
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
    "Provider",
    "Event-Id",
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

  local site_map = ensure_site_payment_webhooks(site_id)
  local actor = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  local now_iso_value = now_iso()
  local removed = 0
  local scope = "site"
  local provider = nil
  local event_id = nil

  if msg.Provider ~= nil then
    local ok_provider, provider_or_err = normalize_webhook_provider(msg.Provider)
    if not ok_provider then
      return codec.error("INVALID_INPUT", provider_or_err, { field = "Provider" })
    end
    provider = provider_or_err
  end

  if msg["Event-Id"] ~= nil then
    local key_max_bytes = DEFAULT_WEBHOOK_IDEMP_KEY_MAX_BYTES
    if provider and type(site_map[provider]) == "table" then
      key_max_bytes = tonumber(site_map[provider].keyMaxBytes) or key_max_bytes
    end
    local ok_event_id, event_id_or_err = normalize_webhook_event_id(msg["Event-Id"], key_max_bytes)
    if not ok_event_id or event_id_or_err == "" then
      return codec.error("INVALID_INPUT", "invalid_value:Event-Id", { field = "Event-Id" })
    end
    event_id = event_id_or_err
    scope = "event"
    if not provider then
      provider = "default"
    end
  elseif provider then
    scope = "provider"
  end

  if scope == "event" then
    local ledger = site_map[provider]
    if type(ledger) == "table" and type(ledger.entries) == "table" then
      if ledger.entries[event_id] ~= nil then
        ledger.entries[event_id] = nil
        ledger.updatedAt = now_iso_value
        ledger.updatedBy = actor
        removed = 1
      end
    end
  elseif scope == "provider" then
    local ledger = site_map[provider]
    if type(ledger) == "table" then
      removed = count_webhook_entries(ledger)
      ledger.entries = {}
      ledger.updatedAt = now_iso_value
      ledger.updatedBy = actor
    end
  else
    for provider_key, ledger in pairs(site_map) do
      if type(ledger) == "table" then
        removed = removed + count_webhook_entries(ledger)
        site_map[provider_key] = nil
      end
    end
  end

  audit.record("registry", "ResetPaymentWebhookIdempotencyState", msg, nil, {
    siteId = site_id,
    scope = scope,
    provider = provider,
    eventId = event_id,
    removed = removed,
  })

  return codec.ok {
    siteId = site_id,
    scope = scope,
    provider = provider,
    eventId = event_id,
    removed = removed,
    policyMode = policy_mode_or_default(),
  }
end

function handlers.ResolveHostPolicyBundle(msg)
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
    "Node-Id",
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

  local node_id = msg["Node-Id"]
  if node_id ~= nil then
    local ok_node_id, err_node_id =
      validate_policy_token(node_id, "Node-Id", 128, "^[%w%-%._:@]+$")
    if not ok_node_id then
      return codec.error("INVALID_INPUT", err_node_id, { field = "Node-Id" })
    end
    node_id = tostring(node_id)
  end

  local bundle = resolve_host_policy_bundle(normalized_host_or_err, node_id)
  return codec.ok(bundle)
end

function handlers.GetDecisionForHostNode(msg)
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
    "Node-Id",
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

  local node_id = msg["Node-Id"]
  if node_id ~= nil then
    local ok_node_id, err_node_id =
      validate_policy_token(node_id, "Node-Id", 128, "^[%w%-%._:@]+$")
    if not ok_node_id then
      return codec.error("INVALID_INPUT", err_node_id, { field = "Node-Id" })
    end
    node_id = tostring(node_id)
  end

  local bundle = resolve_host_policy_bundle(normalized_host_or_err, node_id)
  return codec.ok(bundle)
end

function handlers.RegisterHBNode(msg)
  local ok, missing = validation.require_fields(msg, { "Node-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Node-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Node-Id",
    "Url",
    "Region",
    "Country",
    "Status",
    "Capability-Tier",
    "Score-Weight",
    "Labels",
    "Metadata",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end

  local ok_node_id, err_node_id = validate_policy_token(
    msg["Node-Id"],
    "Node-Id",
    128,
    "^[%w%-%._:@]+$"
  )
  if not ok_node_id then
    return codec.error("INVALID_INPUT", err_node_id, { field = "Node-Id" })
  end
  local node_id = tostring(msg["Node-Id"])

  if msg.Url ~= nil then
    local ok_url, err_url = validate_policy_url(msg.Url, "Url")
    if not ok_url then
      return codec.error("INVALID_INPUT", err_url, { field = "Url" })
    end
  end
  if msg.Region ~= nil then
    local ok_region, err_region = validate_policy_token(msg.Region, "Region", 64, "^[%w%-%._]+$")
    if not ok_region then
      return codec.error("INVALID_INPUT", err_region, { field = "Region" })
    end
  end
  if msg.Country ~= nil then
    local ok_country, err_country =
      validate_policy_token(msg.Country, "Country", 8, "^[A-Za-z][A-Za-z0-9%-_]*$")
    if not ok_country then
      return codec.error("INVALID_INPUT", err_country, { field = "Country" })
    end
  end

  local status = msg.Status and tostring(msg.Status):lower() or "online"
  if not hb_node_status_allow[status] then
    return codec.error("INVALID_INPUT", "invalid_value:Status", { field = "Status" })
  end

  local labels, labels_err, labels_field = normalize_string_list(
    msg.Labels,
    "Labels",
    function(value, field)
      return validate_policy_token(value, field, 64, "^[%w%-%._:@/]+$")
    end
  )
  if not labels then
    return codec.error("INVALID_INPUT", labels_err, { field = labels_field or "Labels" })
  end

  local score_weight = nil
  if msg["Score-Weight"] ~= nil then
    score_weight = tonumber(msg["Score-Weight"])
    if not score_weight or score_weight < 0 then
      return codec.error("INVALID_INPUT", "invalid_number:Score-Weight", { field = "Score-Weight" })
    end
  end

  if msg.Metadata ~= nil and type(msg.Metadata) ~= "table" then
    return codec.error("INVALID_INPUT", "invalid_type:Metadata", { field = "Metadata" })
  end
  local metadata = shallow_copy_table(msg.Metadata) or {}

  ensure_policy_state()
  local existing = state.policy.hb_nodes[node_id]
  local now = now_iso()
  local entry = type(existing) == "table" and shallow_copy_table(existing) or { nodeId = node_id }
  if not entry.registeredAt then
    entry.registeredAt = now
  end
  entry.updatedAt = now
  entry.status = status
  entry.url = msg.Url or entry.url
  entry.region = msg.Region or entry.region
  entry.country = msg.Country or entry.country
  entry.capabilityTier = msg["Capability-Tier"] or entry.capabilityTier
  entry.scoreWeight = score_weight or entry.scoreWeight
  entry.labels = labels
  entry.metadata = metadata
  state.policy.hb_nodes[node_id] = entry

  audit.record("registry", "RegisterHBNode", msg, nil, {
    nodeId = node_id,
    status = status,
  })

  return codec.ok {
    nodeId = node_id,
    registered = true,
    status = status,
    profile = snapshot_hb_node_profile(node_id),
  }
end

function handlers.UpdateHBNodeStatus(msg)
  local ok, missing = validation.require_fields(msg, { "Node-Id", "Status" })
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Node-Id",
    "Status",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_node_id, err_node_id = validate_policy_token(
    msg["Node-Id"],
    "Node-Id",
    128,
    "^[%w%-%._:@]+$"
  )
  if not ok_node_id then
    return codec.error("INVALID_INPUT", err_node_id, { field = "Node-Id" })
  end
  local node_id = tostring(msg["Node-Id"])

  local status = tostring(msg.Status):lower()
  if not hb_node_status_allow[status] then
    return codec.error("INVALID_INPUT", "invalid_value:Status", { field = "Status" })
  end

  ensure_policy_state()
  local existing = state.policy.hb_nodes[node_id]
  if type(existing) ~= "table" then
    return codec.error("NOT_FOUND", "HB node not registered", { nodeId = node_id })
  end
  existing.status = status
  existing.updatedAt = now_iso()
  state.policy.hb_nodes[node_id] = existing

  audit.record("registry", "UpdateHBNodeStatus", msg, nil, {
    nodeId = node_id,
    status = status,
  })

  return codec.ok {
    nodeId = node_id,
    status = status,
    updatedAt = existing.updatedAt,
    profile = snapshot_hb_node_profile(node_id),
  }
end

function handlers.SetSiteServingPolicy(msg)
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
    "Serving-State",
    "Policy-Ref",
    "Cache-Ttl-Sec",
    "DNS-Proof-Required",
    "HB-Allow-List",
    "HB-Deny-List",
    "Note",
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

  local serving_state = msg["Serving-State"] and tostring(msg["Serving-State"]):lower()
    or "allow"
  if not serving_state_allow[serving_state] then
    return codec.error("INVALID_INPUT", "invalid_value:Serving-State", { field = "Serving-State" })
  end

  if msg["Policy-Ref"] ~= nil then
    local ok_ref, err_ref = validate_policy_token(
      msg["Policy-Ref"],
      "Policy-Ref",
      128,
      "^[%w%-%._:@/]+$"
    )
    if not ok_ref then
      return codec.error("INVALID_INPUT", err_ref, { field = "Policy-Ref" })
    end
  end

  local cache_ttl_sec = 300
  if msg["Cache-Ttl-Sec"] ~= nil then
    local parsed_ttl, ttl_err =
      normalize_positive_int(msg["Cache-Ttl-Sec"], "Cache-Ttl-Sec", 1, 86400)
    if parsed_ttl == nil then
      return codec.error("INVALID_INPUT", ttl_err, { field = "Cache-Ttl-Sec" })
    end
    cache_ttl_sec = parsed_ttl
  end

  local dns_proof_required = false
  if msg["DNS-Proof-Required"] ~= nil then
    local ok_bool, parsed_bool = normalize_bool(msg["DNS-Proof-Required"], "DNS-Proof-Required")
    if not ok_bool then
      return codec.error("INVALID_INPUT", parsed_bool, { field = "DNS-Proof-Required" })
    end
    dns_proof_required = parsed_bool
  end

  local hb_allow_list, allow_err, allow_field = normalize_string_list(
    msg["HB-Allow-List"],
    "HB-Allow-List",
    function(value, field)
      return validate_policy_token(value, field, 128, "^[%w%-%._:@]+$")
    end
  )
  if not hb_allow_list then
    return codec.error("INVALID_INPUT", allow_err, { field = allow_field or "HB-Allow-List" })
  end

  local hb_deny_list, deny_err, deny_field = normalize_string_list(
    msg["HB-Deny-List"],
    "HB-Deny-List",
    function(value, field)
      return validate_policy_token(value, field, 128, "^[%w%-%._:@]+$")
    end
  )
  if not hb_deny_list then
    return codec.error("INVALID_INPUT", deny_err, { field = deny_field or "HB-Deny-List" })
  end

  ensure_policy_state()
  local policy_doc = state.policy.site_serving[site_id] or {}
  policy_doc.siteId = site_id
  policy_doc.servingState = serving_state
  policy_doc.policyRef = msg["Policy-Ref"] or policy_doc.policyRef
  policy_doc.cacheTtlSec = cache_ttl_sec
  policy_doc.dnsProofRequired = dns_proof_required
  policy_doc.hbAllowList = hb_allow_list
  policy_doc.hbDenyList = hb_deny_list
  policy_doc.note = msg.Note or policy_doc.note
  policy_doc.updatedAt = now_iso()
  policy_doc.updatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  state.policy.site_serving[site_id] = policy_doc

  audit.record("registry", "SetSiteServingPolicy", msg, nil, {
    siteId = site_id,
    servingState = serving_state,
  })

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    servingPolicy = snapshot_site_serving_policy(site_id),
  }
end

function handlers.SetSiteFundingState(msg)
  local ok, missing = validation.require_fields(msg, { "Site-Id", "Funding-State" })
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
    "Funding-State",
    "Plan",
    "Tier",
    "Payer-Ref",
    "Reason",
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

  local funding_state = tostring(msg["Funding-State"]):lower()
  if not funding_state_allow[funding_state] then
    return codec.error("INVALID_INPUT", "invalid_value:Funding-State", { field = "Funding-State" })
  end

  if msg.Plan ~= nil then
    local ok_plan, err_plan = validate_policy_token(msg.Plan, "Plan", 64, "^[%w%-%._:@/]+$")
    if not ok_plan then
      return codec.error("INVALID_INPUT", err_plan, { field = "Plan" })
    end
  end
  if msg.Tier ~= nil then
    local ok_tier, err_tier = validate_policy_token(msg.Tier, "Tier", 64, "^[%w%-%._:@/]+$")
    if not ok_tier then
      return codec.error("INVALID_INPUT", err_tier, { field = "Tier" })
    end
  end
  if msg["Payer-Ref"] ~= nil then
    local ok_payer, err_payer =
      validate_policy_token(msg["Payer-Ref"], "Payer-Ref", 128, "^[%w%-%._:@/]+$")
    if not ok_payer then
      return codec.error("INVALID_INPUT", err_payer, { field = "Payer-Ref" })
    end
  end

  ensure_policy_state()
  local funding_doc = state.policy.site_funding[site_id] or {}
  funding_doc.siteId = site_id
  funding_doc.fundingState = funding_state
  funding_doc.plan = msg.Plan or funding_doc.plan
  funding_doc.tier = msg.Tier or funding_doc.tier
  funding_doc.payerRef = msg["Payer-Ref"] or funding_doc.payerRef
  funding_doc.reason = msg.Reason or funding_doc.reason
  funding_doc.updatedAt = now_iso()
  funding_doc.updatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  state.policy.site_funding[site_id] = funding_doc

  audit.record("registry", "SetSiteFundingState", msg, nil, {
    siteId = site_id,
    fundingState = funding_state,
  })

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    fundingState = snapshot_site_funding_state(site_id),
  }
end

function handlers.SetDnsProofState(msg)
  local ok, missing = validation.require_fields(msg, { "Host", "Status" })
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Host",
    "Site-Id",
    "Status",
    "Verified",
    "Checked-At",
    "Expires-At",
    "Challenge",
    "TXT-Value",
    "Proof-Ref",
    "Source",
    "Reason",
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
  local host = normalized_host_or_err
  local mapped_site_id = state.domains[host]

  local site_id = msg["Site-Id"]
  if site_id ~= nil then
    local normalized_site_id, site_id_err = normalize_site_id(site_id, "Site-Id")
    if not normalized_site_id then
      return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
    end
    if not state.sites[normalized_site_id] then
      return codec.error("NOT_FOUND", "Site not registered", { siteId = normalized_site_id })
    end
    site_id = normalized_site_id
  else
    site_id = mapped_site_id
  end

  local status = tostring(msg.Status):lower()
  if not dns_proof_status_allow[status] then
    return codec.error("INVALID_INPUT", "invalid_value:Status", { field = "Status" })
  end

  local verified = status == "valid"
  if msg.Verified ~= nil then
    local ok_verified, parsed_verified = normalize_bool(msg.Verified, "Verified")
    if not ok_verified then
      return codec.error("INVALID_INPUT", parsed_verified, { field = "Verified" })
    end
    verified = parsed_verified
  end

  if msg["Checked-At"] ~= nil then
    local ok_checked, err_checked =
      validate_policy_iso8601_utc(msg["Checked-At"], "Checked-At")
    if not ok_checked then
      return codec.error("INVALID_INPUT", err_checked, { field = "Checked-At" })
    end
  end
  if msg["Expires-At"] ~= nil then
    local ok_expires, err_expires =
      validate_policy_iso8601_utc(msg["Expires-At"], "Expires-At")
    if not ok_expires then
      return codec.error("INVALID_INPUT", err_expires, { field = "Expires-At" })
    end
  end
  if msg.Challenge ~= nil then
    local ok_challenge, err_challenge =
      validate_policy_token(msg.Challenge, "Challenge", 256, "^[%w%-%._:@/+=]+$")
    if not ok_challenge then
      return codec.error("INVALID_INPUT", err_challenge, { field = "Challenge" })
    end
  end
  if msg["TXT-Value"] ~= nil then
    local ok_txt, err_txt = validation.assert_type(msg["TXT-Value"], "string", "TXT-Value")
    if not ok_txt then
      return codec.error("INVALID_INPUT", err_txt, { field = "TXT-Value" })
    end
    local ok_txt_len, err_txt_len = validation.check_length(msg["TXT-Value"], 2048, "TXT-Value")
    if not ok_txt_len then
      return codec.error("INVALID_INPUT", err_txt_len, { field = "TXT-Value" })
    end
  end
  if msg["Proof-Ref"] ~= nil then
    local ok_ref, err_ref =
      validate_policy_token(msg["Proof-Ref"], "Proof-Ref", 128, "^[%w%-%._:@/]+$")
    if not ok_ref then
      return codec.error("INVALID_INPUT", err_ref, { field = "Proof-Ref" })
    end
  end
  if msg.Source ~= nil then
    local ok_source, err_source = validate_policy_token(msg.Source, "Source", 64, "^[%w%-%._:@/]+$")
    if not ok_source then
      return codec.error("INVALID_INPUT", err_source, { field = "Source" })
    end
  end

  ensure_policy_state()
  local now = now_iso()
  local proof_doc = state.policy.dns_proofs[host] or {}
  proof_doc.host = host
  proof_doc.siteId = site_id
  proof_doc.status = status
  proof_doc.verified = verified
  proof_doc.checkedAt = msg["Checked-At"] or now
  proof_doc.expiresAt = msg["Expires-At"] or proof_doc.expiresAt
  proof_doc.challenge = msg.Challenge or proof_doc.challenge
  proof_doc.txtValue = msg["TXT-Value"] or proof_doc.txtValue
  proof_doc.proofRef = msg["Proof-Ref"] or proof_doc.proofRef
  proof_doc.source = msg.Source or proof_doc.source or "manual"
  proof_doc.reason = msg.Reason or proof_doc.reason
  proof_doc.updatedAt = now
  proof_doc.updatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  state.policy.dns_proofs[host] = proof_doc

  audit.record("registry", "SetDnsProofState", msg, nil, {
    host = host,
    siteId = site_id,
    status = status,
    verified = verified,
  })

  return codec.ok {
    host = host,
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    dnsProofState = snapshot_dns_proof_state(host, site_id),
  }
end

function handlers.SetSiteAuthMetadata(msg)
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
    "Session-Required",
    "Provider",
    "Token-Ttl-Sec",
    "Cookie-Name",
    "Session-Mode",
    "Note",
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

  local session_required = false
  if msg["Session-Required"] ~= nil then
    local ok_bool, parsed_bool = normalize_bool(msg["Session-Required"], "Session-Required")
    if not ok_bool then
      return codec.error("INVALID_INPUT", parsed_bool, { field = "Session-Required" })
    end
    session_required = parsed_bool
  end

  local provider = "none"
  if msg.Provider ~= nil then
    local ok_provider, err_provider =
      validate_policy_token(msg.Provider, "Provider", 64, "^[%w%-%._:@/]+$")
    if not ok_provider then
      return codec.error("INVALID_INPUT", err_provider, { field = "Provider" })
    end
    provider = tostring(msg.Provider)
  end

  local token_ttl_sec = 0
  if msg["Token-Ttl-Sec"] ~= nil then
    local parsed_ttl, ttl_err = normalize_positive_int(msg["Token-Ttl-Sec"], "Token-Ttl-Sec", 0, 604800)
    if parsed_ttl == nil then
      return codec.error("INVALID_INPUT", ttl_err, { field = "Token-Ttl-Sec" })
    end
    token_ttl_sec = parsed_ttl
  end

  local cookie_name = nil
  if msg["Cookie-Name"] ~= nil then
    local ok_cookie, err_cookie =
      validate_policy_token(msg["Cookie-Name"], "Cookie-Name", 128, "^[%w%-%._:@]+$")
    if not ok_cookie then
      return codec.error("INVALID_INPUT", err_cookie, { field = "Cookie-Name" })
    end
    cookie_name = tostring(msg["Cookie-Name"])
  end

  local session_mode = "stateless"
  if msg["Session-Mode"] ~= nil then
    local ok_mode, err_mode =
      validate_policy_token(msg["Session-Mode"], "Session-Mode", 64, "^[%w%-%._:@/]+$")
    if not ok_mode then
      return codec.error("INVALID_INPUT", err_mode, { field = "Session-Mode" })
    end
    session_mode = tostring(msg["Session-Mode"])
  end

  ensure_policy_state()
  local auth_doc = state.policy.site_auth[site_id] or {}
  auth_doc.siteId = site_id
  auth_doc.sessionRequired = session_required
  auth_doc.provider = provider
  auth_doc.tokenTtlSec = token_ttl_sec
  auth_doc.cookieName = cookie_name
  auth_doc.sessionMode = session_mode
  auth_doc.note = msg.Note or auth_doc.note
  auth_doc.updatedAt = now_iso()
  auth_doc.updatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  state.policy.site_auth[site_id] = auth_doc

  audit.record("registry", "SetSiteAuthMetadata", msg, nil, {
    siteId = site_id,
    provider = provider,
    sessionRequired = session_required,
  })

  return codec.ok {
    siteId = site_id,
    policyMode = policy_mode_or_default(),
    authMetadata = snapshot_site_auth_metadata(site_id),
  }
end

function handlers.SetDomainLifecycleState(msg)
  local ok, missing = validation.require_fields(msg, { "Host", "State" })
  if not ok then
    return codec.error("INVALID_INPUT", "Missing required field", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Host",
    "Site-Id",
    "State",
    "Reason",
    "Source",
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
  local host = normalized_host_or_err

  local lifecycle_state = tostring(msg.State):lower()
  if not domain_lifecycle_state_allow[lifecycle_state] then
    return codec.error("INVALID_INPUT", "invalid_value:State", { field = "State" })
  end

  local mapped_site_id = state.domains[host]
  local site_id = msg["Site-Id"]
  if site_id ~= nil then
    local normalized_site_id, site_id_err = normalize_site_id(site_id, "Site-Id")
    if not normalized_site_id then
      return codec.error("INVALID_INPUT", site_id_err, { field = "Site-Id" })
    end
    if not state.sites[normalized_site_id] then
      return codec.error("NOT_FOUND", "Site not registered", { siteId = normalized_site_id })
    end
    if mapped_site_id ~= nil and mapped_site_id ~= normalized_site_id then
      return codec.error("INVALID_INPUT", "conflicting_site_host", {
        host = host,
        siteId = normalized_site_id,
        mappedSiteId = mapped_site_id,
      })
    end
    site_id = normalized_site_id
  else
    site_id = mapped_site_id
  end

  ensure_policy_state()
  local existing = state.policy.domain_lifecycle[host] or {}
  local prev_state = existing.state or "active"
  local allow_map = domain_lifecycle_transition_allow[prev_state] or {}
  if prev_state ~= lifecycle_state and not allow_map[lifecycle_state] then
    return codec.error("INVALID_INPUT", "invalid_domain_lifecycle_transition", {
      host = host,
      from = prev_state,
      to = lifecycle_state,
    })
  end

  local lifecycle = existing
  lifecycle.host = host
  lifecycle.siteId = site_id
  lifecycle.state = lifecycle_state
  lifecycle.reason = msg.Reason or lifecycle.reason
  lifecycle.source = msg.Source or lifecycle.source or "manual"
  lifecycle.updatedAt = now_iso()
  lifecycle.updatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  state.policy.domain_lifecycle[host] = lifecycle

  audit.record("registry", "SetDomainLifecycleState", msg, nil, {
    host = host,
    siteId = site_id,
    from = prev_state,
    to = lifecycle_state,
  })

  return codec.ok {
    host = host,
    siteId = site_id,
    lifecycle = snapshot_domain_lifecycle_state(host, site_id),
    policyMode = policy_mode_or_default(),
  }
end

function handlers.SetPolicyMode(msg)
  local ok, missing = validation.require_fields(msg, { "Mode" })
  if not ok then
    return codec.error("INVALID_INPUT", "Mode is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Mode",
    "Reason",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local mode = tostring(msg.Mode):lower()
  if not POLICY_MODE_ALLOW[mode] then
    return codec.error("INVALID_INPUT", "invalid_value:Mode", { field = "Mode" })
  end
  ensure_policy_state()
  state.policy.mode = mode
  state.policy.modeUpdatedAt = now_iso()
  state.policy.modeUpdatedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  audit.record("registry", "SetPolicyMode", msg, nil, { mode = mode, reason = msg.Reason })
  return codec.ok {
    mode = state.policy.mode,
    updatedAt = state.policy.modeUpdatedAt,
    updatedBy = state.policy.modeUpdatedBy,
    reason = msg.Reason,
  }
end

function handlers.PublishPolicySnapshot(msg)
  local ok, missing = validation.require_fields(msg, { "Snapshot-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Snapshot-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Snapshot-Id",
    "Snapshot",
    "Note",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_snapshot_id, err_snapshot_id = validate_policy_token(
    msg["Snapshot-Id"],
    "Snapshot-Id",
    128,
    "^[%w%-%._:@/]+$"
  )
  if not ok_snapshot_id then
    return codec.error("INVALID_INPUT", err_snapshot_id, { field = "Snapshot-Id" })
  end
  if msg.Snapshot ~= nil and type(msg.Snapshot) ~= "table" then
    return codec.error("INVALID_INPUT", "invalid_type:Snapshot", { field = "Snapshot" })
  end

  ensure_policy_state()
  local snapshot_id = tostring(msg["Snapshot-Id"])
  local now = now_iso()
  local payload = shallow_copy_table(msg.Snapshot) or {
    mode = state.policy.mode,
    nodeCount = (function()
      local count = 0
      for _ in pairs(state.policy.hb_nodes) do
        count = count + 1
      end
      return count
    end)(),
  }
  local snapshot_doc = {
    snapshotId = snapshot_id,
    status = "active",
    note = msg.Note,
    mode = state.policy.mode,
    payload = payload,
    publishedAt = now,
    publishedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or "",
    revokedAt = nil,
    revokedBy = nil,
    revokeReason = nil,
  }
  state.policy.snapshots[snapshot_id] = snapshot_doc
  state.policy.activeSnapshotId = snapshot_id

  audit.record("registry", "PublishPolicySnapshot", msg, nil, {
    snapshotId = snapshot_id,
    mode = state.policy.mode,
  })

  return codec.ok {
    snapshotId = snapshot_id,
    activeSnapshotId = state.policy.activeSnapshotId,
    policyMode = state.policy.mode,
    snapshot = shallow_copy_table(snapshot_doc),
  }
end

function handlers.RevokePolicySnapshot(msg)
  local ok, missing = validation.require_fields(msg, { "Snapshot-Id" })
  if not ok then
    return codec.error("INVALID_INPUT", "Snapshot-Id is required", { missing = missing })
  end
  local ok_extra, extras = validation.require_no_extras(msg, {
    "Action",
    "Request-Id",
    "Nonce",
    "ts",
    "Timestamp",
    "Snapshot-Id",
    "Reason",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_snapshot_id, err_snapshot_id = validate_policy_token(
    msg["Snapshot-Id"],
    "Snapshot-Id",
    128,
    "^[%w%-%._:@/]+$"
  )
  if not ok_snapshot_id then
    return codec.error("INVALID_INPUT", err_snapshot_id, { field = "Snapshot-Id" })
  end

  ensure_policy_state()
  local snapshot_id = tostring(msg["Snapshot-Id"])
  local snapshot_doc = state.policy.snapshots[snapshot_id]
  if type(snapshot_doc) ~= "table" then
    return codec.error("NOT_FOUND", "Policy snapshot not found", { snapshotId = snapshot_id })
  end
  snapshot_doc.status = "revoked"
  snapshot_doc.revokedAt = now_iso()
  snapshot_doc.revokedBy = msg.From or msg["Actor-Id"] or msg["Actor-Role"] or ""
  snapshot_doc.revokeReason = msg.Reason
  state.policy.snapshots[snapshot_id] = snapshot_doc
  if state.policy.activeSnapshotId == snapshot_id then
    state.policy.activeSnapshotId = nil
  end

  audit.record("registry", "RevokePolicySnapshot", msg, nil, {
    snapshotId = snapshot_id,
    reason = msg.Reason,
  })

  return codec.ok {
    snapshotId = snapshot_id,
    status = snapshot_doc.status,
    activeSnapshotId = state.policy.activeSnapshotId,
    revokedAt = snapshot_doc.revokedAt,
    revokedBy = snapshot_doc.revokedBy,
    reason = snapshot_doc.revokeReason,
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
  ensure_policy_state()
  local lifecycle = state.policy.domain_lifecycle[normalized_host] or {}
  lifecycle.host = normalized_host
  lifecycle.siteId = site_id
  lifecycle.state = lifecycle.state or "active"
  lifecycle.updatedAt = lifecycle.updatedAt or now_iso()
  lifecycle.updatedBy = lifecycle.updatedBy or (msg.From or msg["Actor-Id"] or msg["Actor-Role"] or "")
  lifecycle.reason = lifecycle.reason
  lifecycle.source = lifecycle.source or "bind"
  state.policy.domain_lifecycle[normalized_host] = lifecycle
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

local function get_active_release(component_id)
  if component_id then
    local active_version = state.integrity.active[component_id]
    if active_version then
      local key = release_key(component_id, active_version)
      local release = state.integrity.releases[key]
      if release then
        return release
      end
    end
  end

  local root = state.integrity.policy.activeRoot
  if not root then
    return nil
  end
  local key = state.integrity.roots[root]
  if not key then
    return nil
  end
  local release = state.integrity.releases[key]
  if not release then
    return nil
  end
  if component_id and release.componentId ~= component_id then
    return nil
  end
  return release
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
  local component_id = read_component_id(msg)
  local ok_component, err_component =
    validate_token_field(component_id, "Component-Id", 96, "^[%w%-%._]+$")
  if not ok_component then
    return codec.error("INVALID_INPUT", err_component, { field = "Component-Id" })
  end
  local active_release = get_active_release(component_id)
  if not active_release then
    return codec.error("NOT_FOUND", "Active trusted root is not set", {
      componentId = component_id,
    })
  end
  if active_release.revokedAt then
    return codec.error("NOT_FOUND", "Active trusted root is revoked", {
      componentId = component_id,
      root = active_release.root,
      revokedAt = active_release.revokedAt,
    })
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
  else
    -- Public-read mode still needs throttling, otherwise host/runtime lookups
    -- can be spammed when auth is intentionally bypassed.
    local ok_rl, rl_err = auth.check_rate_limit(msg)
    if not ok_rl then
      return codec.error("FORBIDDEN", rl_err)
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

  local function scope_value(...)
    for idx = 1, select("#", ...) do
      local candidate = select(idx, ...)
      if type(candidate) == "string" and candidate ~= "" then
        return candidate
      end
    end
    return ""
  end

  local request_id = tostring(msg["Request-Id"] or "")
  local idem_scope_key = nil
  if request_id ~= "" then
    local scope_site_id = scope_value(msg["Site-Id"], msg.siteId, msg.SiteId, msg.site_id)
    local scope_host = string.lower(scope_value(msg.Host, msg["Site-Host"], msg.Domain))
    idem_scope_key = table.concat({
      request_id,
      tostring(msg.Action or ""),
      tostring(msg.From or msg["Actor-Id"] or ""),
      scope_site_id,
      scope_host,
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
