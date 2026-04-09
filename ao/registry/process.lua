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
local allowed_actions = {
  "GetSiteByHost",
  "GetSiteConfig",
  "RegisterSite",
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
  RegisterSite = { "admin", "registry-admin" },
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

-- pseudo-state kept in-memory for now; AO runtime would persist this.
local state = persist.load("registry_state", {
  sites = {}, -- siteId => {config = {}, createdAt = ts}
  domains = {}, -- host => siteId
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
  local ok_len, err = validation.check_length(msg.Host, 255, "Host")
  if not ok_len then
    return codec.error("INVALID_INPUT", err, { field = "Host" })
  end
  local site_id = state.domains[msg.Host]
  if not site_id then
    return codec.error("NOT_FOUND", "Domain not bound", { host = msg.Host })
  end
  return codec.ok {
    siteId = site_id,
    activeVersion = state.active_versions[site_id],
  }
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
  local ok_len, err = validation.check_length(msg["Site-Id"], 128, "Site-Id")
  if not ok_len then
    return codec.error("INVALID_INPUT", err, { field = "Site-Id" })
  end
  local site = state.sites[msg["Site-Id"]]
  if not site then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = msg["Site-Id"] })
  end
  return codec.ok {
    siteId = msg["Site-Id"],
    config = site.config,
    activeVersion = state.active_versions[msg["Site-Id"]],
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
    "Version",
    "Actor-Role",
    "Schema-Version",
    "Signature",
  })
  if not ok_extra then
    return codec.error("UNSUPPORTED_FIELD", "Unexpected fields", { unexpected = extras })
  end
  local ok_len, err = validation.check_length(msg["Site-Id"], 128, "Site-Id")
  if not ok_len then
    return codec.error("INVALID_INPUT", err, { field = "Site-Id" })
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
  local existing = state.sites[msg["Site-Id"]]
  if existing then
    return codec.ok {
      siteId = msg["Site-Id"],
      createdAt = existing.createdAt,
      config = existing.config,
      activeVersion = state.active_versions[msg["Site-Id"]],
      note = "already_registered",
    }
  end
  state.sites[msg["Site-Id"]] = {
    config = config,
    createdAt = now_iso(),
  }
  state.active_versions[msg["Site-Id"]] = config.version or msg.Version or nil
  audit.record("registry", "RegisterSite", msg, nil)
  return codec.ok {
    siteId = msg["Site-Id"],
    createdAt = state.sites[msg["Site-Id"]].createdAt,
    activeVersion = state.active_versions[msg["Site-Id"]],
  }
end

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
  local ok_len_id, err_id = validation.check_length(msg["Site-Id"], 128, "Site-Id")
  if not ok_len_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Site-Id" })
  end
  local ok_len_host, err_host = validation.check_length(msg.Host, 255, "Host")
  if not ok_len_host then
    return codec.error("INVALID_INPUT", err_host, { field = "Host" })
  end
  if not state.sites[msg["Site-Id"]] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = msg["Site-Id"] })
  end
  state.domains[msg.Host] = msg["Site-Id"]
  audit.record("registry", "BindDomain", msg, nil, { host = msg.Host })
  return codec.ok {
    host = msg.Host,
    siteId = msg["Site-Id"],
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
  local ok_len_id, err_id = validation.check_length(msg["Site-Id"], 128, "Site-Id")
  if not ok_len_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Site-Id" })
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
  if not state.sites[msg["Site-Id"]] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = msg["Site-Id"] })
  end
  local current = state.active_versions[msg["Site-Id"]]
  if msg.ExpectedVersion and current and current ~= msg.ExpectedVersion then
    return codec.error(
      "VERSION_CONFLICT",
      "ExpectedVersion mismatch",
      { expected = msg.ExpectedVersion, current = current }
    )
  end
  state.active_versions[msg["Site-Id"]] = msg.Version
  local resp = codec.ok {
    siteId = msg["Site-Id"],
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
  local ok_len_id, err_id = validation.check_length(msg["Site-Id"], 128, "Site-Id")
  if not ok_len_id then
    return codec.error("INVALID_INPUT", err_id, { field = "Site-Id" })
  end
  local ok_len_subj, err_subj = validation.check_length(msg.Subject, 128, "Subject")
  if not ok_len_subj then
    return codec.error("INVALID_INPUT", err_subj, { field = "Subject" })
  end
  local ok_len_role, err_role = validation.check_length(msg.Role, 64, "Role")
  if not ok_len_role then
    return codec.error("INVALID_INPUT", err_role, { field = "Role" })
  end
  if not state.sites[msg["Site-Id"]] then
    return codec.error("NOT_FOUND", "Site not registered", { siteId = msg["Site-Id"] })
  end
  state.roles[msg["Site-Id"]] = state.roles[msg["Site-Id"]] or {}
  state.roles[msg["Site-Id"]][msg.Subject] = msg.Role
  audit.record("registry", "GrantRole", msg, nil, { subject = msg.Subject, role = msg.Role })
  return codec.ok {
    siteId = msg["Site-Id"],
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

  local ok_sec, sec_err = auth.enforce(msg)
  if not ok_sec then
    return codec.error("FORBIDDEN", sec_err)
  end

  local seen = idem.check(msg["Request-Id"])
  if seen then
    return seen
  end

  local ok_action, err = validation.require_action(msg, allowed_actions)
  if not ok_action then
    if err == "unknown_action" then
      return codec.unknown_action(msg.Action)
    end
    return codec.error("MISSING_ACTION", "Action is required")
  end

  local ok_hmac, hmac_err = auth.verify_outbox_hmac(msg)
  if not ok_hmac then
    return codec.error("FORBIDDEN", hmac_err)
  end

  local ok_role, role_err = auth.require_role_for_action(msg, role_policy)
  if not ok_role then
    return codec.error("FORBIDDEN", role_err)
  end

  local handler = handlers[msg.Action]
  if not handler then
    return codec.unknown_action(msg.Action)
  end

  local resp = handler(msg)
  metrics.inc("registry." .. msg.Action .. ".count")
  metrics.tick()
  idem.record(msg["Request-Id"], resp)
  persist.save("registry_state", state)
  return resp
end

return {
  route = route,
  _state = state, -- exposed for tests
}
