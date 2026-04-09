-- Lightweight contract smoke tests for AO handlers.
-- Uses in-memory handler state; ensures deterministic behavior matches contracts.
-- Set SKIP_CONTRACTS=1 to skip the entire suite (useful for CI quick passes).

if os.getenv "SKIP_CONTRACTS" then
  return
end

local function assert_eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function assert_truthy(val, label)
  if not val then
    error(label .. " expected truthy")
  end
end

local function assert_falsy(val, label)
  if val then
    error(label .. " expected falsy")
  end
end

local function assert_code(resp, code, label)
  assert_eq(resp.code, code, label .. " code")
end

local function assert_status(resp, status, label)
  if resp.status ~= status then
    error(
      string.format(
        "%s expected %s, got %s (code=%s, msg=%s)",
        label,
        tostring(status),
        tostring(resp.status),
        tostring(resp.code),
        tostring(resp.message)
      )
    )
  end
end

local SIG_SECRET = os.getenv "AUTH_SIGNATURE_SECRET"
local REQUIRE_SIGNATURE = os.getenv "AUTH_REQUIRE_SIGNATURE" == "1"
local openssl_ok, openssl = pcall(require, "openssl")
local sodium_ok, sodium = pcall(require, "sodium")
if not sodium_ok then
  sodium_ok, sodium = pcall(require, "luasodium")
end

local function hex_encode(bytes)
  if not bytes then
    return nil
  end
  if openssl_ok and openssl.hex then
    return openssl.hex(bytes)
  end
  if sodium_ok then
    if sodium.to_hex then
      return sodium.to_hex(bytes)
    end
    if sodium.bin2hex then
      return sodium.bin2hex(bytes)
    end
  end
  return (bytes:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

local function canonical_key(secret)
  if not secret then
    return nil
  end
  if #secret == 32 then
    return secret
  end
  if #secret > 32 then
    return secret:sub(1, 32)
  end
  return secret .. string.rep("\0", 32 - #secret)
end

local SIGNATURE_EXCLUDE_KEYS = {
  Signature = true,
  signature = true,
  ["Signature-Ref"] = true,
}

local function sorted_pairs(tbl)
  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  local i = 0
  return function()
    i = i + 1
    local key = keys[i]
    if key then
      return key, tbl[key]
    end
  end
end

local function canonical_value(val)
  local t = type(val)
  if t == "table" then
    local parts = {}
    for k, v in sorted_pairs(val) do
      parts[#parts + 1] = tostring(k) .. "=" .. canonical_value(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    return tostring(val)
  elseif t == "string" then
    return val
  else
    return ""
  end
end

local function canonical_payload(msg)
  local cleaned = {}
  for k, v in pairs(msg) do
    if not SIGNATURE_EXCLUDE_KEYS[k] then
      cleaned[k] = v
    end
  end
  return canonical_value(cleaned)
end

local function hmac_sign(msg)
  if not (SIG_SECRET and SIG_SECRET ~= "") then
    return nil
  end
  local target = canonical_payload(msg)

  if openssl_ok and openssl.hmac and openssl.hex then
    local raw = openssl.hmac.digest("sha256", target, SIG_SECRET, true)
    if raw then
      return openssl.hex(raw)
    end
  end

  if sodium_ok and sodium.crypto_auth then
    local key = canonical_key(SIG_SECRET)
    local tag = sodium.crypto_auth(target, key)
    if tag then
      return hex_encode(tag)
    end
  end

  -- Fallback: best-effort deterministic placeholder so tests can run even without crypto libs.
  return string.format("sig-%s", target)
end

local function with_req(fields)
  fields["Request-Id"] = fields["Request-Id"] or tostring(math.random())
  fields.Nonce = fields.Nonce or tostring(math.random(1, 1e9))
  fields.ts = fields.ts or os.time()
  if SIG_SECRET then
    local sig = hmac_sign(fields)
    if sig then
      fields.Signature = sig
    elseif REQUIRE_SIGNATURE then
      error "AUTH_REQUIRE_SIGNATURE=1 but could not generate signature (missing openssl/luasodium?)"
    end
  end
  return fields
end

-- Registry tests
do
  local registry = require "ao.registry.process"
  registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-1",
    Config = { version = "v1" },
    ["Actor-Role"] = "admin",
  })
  local bind = registry.route(with_req {
    Action = "BindDomain",
    ["Site-Id"] = "site-1",
    Host = "example.com",
    ["Actor-Role"] = "registry-admin",
  })
  assert_eq(bind.status, "OK", "bind status")
  local lookup = registry.route(with_req { Action = "GetSiteByHost", Host = "example.com" })
  assert_eq(lookup.status, "OK", "get site by host status")
  assert_eq(lookup.payload.siteId, "site-1", "domain->siteId")

  -- conflict: binding another site to same host should overwrite in stub (and keep deterministic)
  registry.route(
    with_req { Action = "RegisterSite", ["Site-Id"] = "site-2", ["Actor-Role"] = "admin" }
  )
  local rebind = registry.route(with_req {
    Action = "BindDomain",
    ["Site-Id"] = "site-2",
    Host = "example.com",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(rebind, "OK", "rebind status")
  local lookup2 = registry.route(with_req { Action = "GetSiteByHost", Host = "example.com" })
  assert_eq(lookup2.payload.siteId, "site-2", "rebinding took effect")

  -- forbidden bind
  local denied = registry.route(with_req {
    Action = "BindDomain",
    ["Site-Id"] = "site-2",
    Host = "forbidden.com",
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied, "ERROR", "bind forbidden status")
  assert_code(denied, "FORBIDDEN", "bind forbidden code")

  -- ExpectedVersion conflict
  registry.route(with_req {
    Action = "SetActiveVersion",
    ["Site-Id"] = "site-2",
    Version = "v10",
    ["Actor-Role"] = "registry-admin",
  })
  local conflict = registry.route(with_req {
    Action = "SetActiveVersion",
    ["Site-Id"] = "site-2",
    Version = "v11",
    ExpectedVersion = "v0",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(conflict, "ERROR", "set version conflict status")
  assert_code(conflict, "VERSION_CONFLICT", "set version conflict code")

  -- Idempotent bind (same Request-Id)
  local idem_req = with_req {
    Action = "BindDomain",
    ["Site-Id"] = "site-2",
    Host = "example.com",
    ["Actor-Role"] = "registry-admin",
    ["Request-Id"] = "rid-bind",
  }
  local b1 = registry.route(idem_req)
  local b2 = registry.route(idem_req)
  assert_eq(b1.payload.host, b2.payload.host, "idempotent bind host")

  -- Conflict on GrantRole with different payload same Request-Id returns original
  local g1 = registry.route(with_req {
    Action = "GrantRole",
    ["Site-Id"] = "site-2",
    Subject = "userA",
    Role = "editor",
    ["Actor-Role"] = "registry-admin",
    ["Request-Id"] = "rid-grant",
  })
  local g2 = registry.route(with_req {
    Action = "GrantRole",
    ["Site-Id"] = "site-2",
    Subject = "userA",
    Role = "admin",
    ["Actor-Role"] = "registry-admin",
    ["Request-Id"] = "rid-grant",
  })
  assert_eq(g2.payload.role, g1.payload.role, "grant role idempotent keeps first role")

  -- Unexpected field in register
  local extra = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-extra",
    Config = {},
    Foo = "bar",
    ["Actor-Role"] = "admin",
  })
  assert_status(extra, "ERROR", "register extra status")
  assert_code(extra, "UNSUPPORTED_FIELD", "register extra code")

  -- Invalid flags/policies schema
  local bad_cfg = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badcfg",
    Config = { policies = { auditLevel = "ultra" } },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_cfg, "ERROR", "register bad cfg status")
  assert_code(bad_cfg, "INVALID_INPUT", "register bad cfg code")

  -- Invalid policies arrays / flags patterns
  local bad_origins = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badorigins",
    Config = { policies = { allowedOrigins = {} } },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_origins, "ERROR", "register bad origins status")
  local bad_methods = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badmethods",
    Config = { policies = { allowedMethods = {} } },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_methods, "ERROR", "register bad methods status")
  local bad_cors = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badcors",
    Config = { flags = { corsAllowlist = { "ftp://invalid" } } },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_cors, "ERROR", "register bad cors status")

  -- Unknown tableProfile
  local bad_profile = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badprofile",
    Config = { tableProfile = "nonexistent" },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_profile, "ERROR", "register bad profile status")
  assert_code(bad_profile, "INVALID_INPUT", "register bad profile code")

  -- Invalid schema hash/tx patterns
  local bad_schema = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badschema",
    Config = { schemaHash = "xyz", schemaManifestTx = "??bad" },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_schema, "ERROR", "register bad schema status")
  assert_code(bad_schema, "INVALID_INPUT", "register bad schema code")

  -- Invalid codeHash pattern
  local bad_hash = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-badhash",
    Config = { codeHash = "xyz" },
    ["Actor-Role"] = "admin",
  })
  assert_status(bad_hash, "ERROR", "register bad hash status")
  assert_code(bad_hash, "INVALID_INPUT", "register bad hash code")

  -- Oversize config guard
  local big_cfg = { blob = string.rep("x", 20 * 1024) }
  local oversize_cfg = registry.route(with_req {
    Action = "RegisterSite",
    ["Site-Id"] = "site-big",
    Config = big_cfg,
    ["Actor-Role"] = "admin",
  })
  assert_status(oversize_cfg, "ERROR", "register oversize status")
  assert_code(oversize_cfg, "INVALID_INPUT", "register oversize code")

  -- Resolver flagging
  local flag = registry.route(with_req {
    Action = "FlagResolver",
    ["Resolver-Id"] = "resolver-1",
    Flag = "suspicious",
    Reason = "high error rate",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(flag, "OK", "flag resolver status")
  local listed = registry.route(with_req {
    Action = "GetResolverFlags",
    ["Resolver-Id"] = "resolver-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_eq(listed.payload.flag, "suspicious", "resolver flag stored")
  local all_flags =
    registry.route(with_req { Action = "GetResolverFlags", ["Actor-Role"] = "registry-admin" })
  assert_truthy(all_flags.payload.count >= 1, "resolver flags count")
  local cleared = registry.route(with_req {
    Action = "UnflagResolver",
    ["Resolver-Id"] = "resolver-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(cleared, "OK", "unflag status")
  local cleared_get = registry.route(with_req {
    Action = "GetResolverFlags",
    ["Resolver-Id"] = "resolver-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_eq(cleared_get.payload.flag, "none", "resolver flag cleared")

  local bad_flag = registry.route(with_req {
    Action = "FlagResolver",
    ["Resolver-Id"] = "resolver-2",
    Flag = "maybe",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(bad_flag, "ERROR", "bad flag status")
  assert_code(bad_flag, "INVALID_INPUT", "bad flag code")

  -- Integrity release lifecycle (P0.1)
  local publish_rel = registry.route(with_req {
    Action = "PublishTrustedRelease",
    ["Component-Id"] = "gateway",
    Version = "1.2.0",
    Root = "root-abc",
    ["Uri-Hash"] = "uri-123",
    ["Meta-Hash"] = "meta-456",
    ["Policy-Hash"] = "policy-789",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(publish_rel, "OK", "publish trusted release status")
  assert_eq(publish_rel.payload.release.root, "root-abc", "publish trusted release root")
  assert_eq(publish_rel.payload.activeRoot, "root-abc", "publish trusted release active root")

  local get_root = registry.route(with_req {
    Action = "GetTrustedRoot",
    ["Component-Id"] = "gateway",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(get_root, "OK", "get trusted root status")
  assert_eq(get_root.payload.root, "root-abc", "get trusted root value")

  local by_version = registry.route(with_req {
    Action = "GetTrustedReleaseByVersion",
    ["Component-Id"] = "gateway",
    Version = "1.2.0",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(by_version, "OK", "get trusted release by version status")
  assert_eq(by_version.payload.release.metaHash, "meta-456", "trusted release by version payload")

  local by_root = registry.route(with_req {
    Action = "GetTrustedReleaseByRoot",
    Root = "root-abc",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(by_root, "OK", "get trusted release by root status")
  assert_eq(by_root.payload.release.version, "1.2.0", "trusted release by root payload")

  local set_authority = registry.route(with_req {
    Action = "SetIntegrityAuthority",
    Root = "auth-root-1",
    Upgrade = "auth-upgrade-1",
    Emergency = "auth-emergency-1",
    Reporter = "auth-reporter-1",
    ["Signature-Refs"] = { "sig-root-1", "sig-upgrade-1" },
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(set_authority, "OK", "set integrity authority status")
  assert_eq(set_authority.payload.reporter, "auth-reporter-1", "set integrity authority reporter")

  local get_authority = registry.route(with_req {
    Action = "GetIntegrityAuthority",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(get_authority, "OK", "get integrity authority status")
  assert_eq(get_authority.payload.root, "auth-root-1", "get integrity authority root")
  assert_eq(
    get_authority.payload.signatureRefs[2],
    "sig-upgrade-1",
    "get integrity authority signatures"
  )

  local append_audit = registry.route(with_req {
    Action = "AppendIntegrityAuditCommitment",
    ["Seq-From"] = 1,
    ["Seq-To"] = 7,
    ["Merkle-Root"] = "merkle-1",
    ["Meta-Hash"] = "audit-meta-1",
    ["Reporter-Ref"] = "auth-reporter-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(append_audit, "OK", "append integrity audit commitment status")
  assert_eq(append_audit.payload.seqTo, 7, "append integrity audit commitment seqTo")

  local get_audit = registry.route(with_req {
    Action = "GetIntegrityAuditState",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(get_audit, "OK", "get integrity audit status")
  assert_eq(get_audit.payload.merkleRoot, "merkle-1", "get integrity audit merkle root")

  local pause_on = registry.route(with_req {
    Action = "SetIntegrityPolicyPause",
    Paused = true,
    Reason = "maintenance",
    ["Max-CheckIn-Age-Sec"] = 120,
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(pause_on, "OK", "set integrity pause status")
  assert_eq(pause_on.payload.paused, true, "set integrity pause value")
  assert_eq(pause_on.payload.maxCheckInAgeSec, 120, "set integrity pause max age")

  local get_policy = registry.route(with_req {
    Action = "GetIntegrityPolicy",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(get_policy, "OK", "get integrity policy status")
  assert_eq(get_policy.payload.paused, true, "get integrity policy paused")

  local snap_ok = registry.route(with_req {
    Action = "GetIntegritySnapshot",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(snap_ok, "OK", "integrity snapshot status")
  assert_eq(snap_ok.payload.release.root, "root-abc", "integrity snapshot root")
  assert_eq(snap_ok.payload.policy.activePolicyHash, "policy-789", "integrity snapshot policy hash")
  assert_eq(snap_ok.payload.authority.root, "auth-root-1", "integrity snapshot authority root")
  assert_eq(snap_ok.payload.audit.seqTo, 7, "integrity snapshot audit seqTo")

  local revoke = registry.route(with_req {
    Action = "RevokeTrustedRelease",
    Root = "root-abc",
    Reason = "compromised",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(revoke, "OK", "revoke trusted release status")
  assert_truthy(revoke.payload.release.revokedAt, "revoke trusted release timestamp")
  assert_eq(revoke.payload.paused, true, "revoke trusted release pauses policy")

  local snap_revoked = registry.route(with_req {
    Action = "GetIntegritySnapshot",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(snap_revoked, "ERROR", "integrity snapshot revoked status")
  assert_code(snap_revoked, "NOT_FOUND", "integrity snapshot revoked code")

  local publish_next = registry.route(with_req {
    Action = "PublishTrustedRelease",
    ["Component-Id"] = "gateway",
    Version = "1.2.1",
    Root = "root-def",
    ["Uri-Hash"] = "uri-124",
    ["Meta-Hash"] = "meta-457",
    ["Policy-Hash"] = "policy-790",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(publish_next, "OK", "publish next trusted release status")

  local snap_next = registry.route(with_req {
    Action = "GetIntegritySnapshot",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(snap_next, "OK", "integrity snapshot after republish status")
  assert_eq(snap_next.payload.release.root, "root-def", "integrity snapshot after republish root")

  local release_conflict = registry.route(with_req {
    Action = "PublishTrustedRelease",
    ["Component-Id"] = "gateway",
    Version = "1.2.1",
    Root = "root-mismatch",
    ["Uri-Hash"] = "uri-999",
    ["Meta-Hash"] = "meta-999",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(release_conflict, "ERROR", "publish trusted release conflict status")
  assert_code(release_conflict, "VERSION_CONFLICT", "publish trusted release conflict code")

  local bad_publish_format = registry.route(with_req {
    Action = "PublishTrustedRelease",
    ["Component-Id"] = "gateway",
    Version = "bad version!",
    Root = "root bad",
    ["Uri-Hash"] = "uri bad",
    ["Meta-Hash"] = "meta bad",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(bad_publish_format, "ERROR", "publish trusted release invalid format status")
  assert_code(bad_publish_format, "INVALID_INPUT", "publish trusted release invalid format code")

  local bad_pause = registry.route(with_req {
    Action = "SetIntegrityPolicyPause",
    Paused = "not-bool",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(bad_pause, "ERROR", "set integrity pause invalid status")
  assert_code(bad_pause, "INVALID_INPUT", "set integrity pause invalid code")

  local bad_authority = registry.route(with_req {
    Action = "SetIntegrityAuthority",
    Root = "auth-root-bad",
    Upgrade = "auth-upgrade-bad",
    Emergency = "auth-emergency-bad",
    Reporter = "auth-reporter-bad",
    ["Signature-Refs"] = {},
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(bad_authority, "ERROR", "set integrity authority invalid status")
  assert_code(bad_authority, "INVALID_INPUT", "set integrity authority invalid code")

  local bad_authority_format = registry.route(with_req {
    Action = "SetIntegrityAuthority",
    Root = "auth-root-1",
    Upgrade = "auth-upgrade-1",
    Emergency = "auth/emergency",
    Reporter = "auth-reporter-1",
    ["Signature-Refs"] = { "sig-root-1" },
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(bad_authority_format, "ERROR", "set integrity authority invalid format status")
  assert_code(bad_authority_format, "INVALID_INPUT", "set integrity authority invalid format code")

  local deny_authority = registry.route(with_req {
    Action = "SetIntegrityAuthority",
    Root = "auth-root-deny",
    Upgrade = "auth-upgrade-deny",
    Emergency = "auth-emergency-deny",
    Reporter = "auth-reporter-deny",
    ["Actor-Role"] = "viewer",
  })
  assert_status(deny_authority, "ERROR", "set integrity authority forbidden status")
  assert_code(deny_authority, "FORBIDDEN", "set integrity authority forbidden code")

  local audit_conflict = registry.route(with_req {
    Action = "AppendIntegrityAuditCommitment",
    ["Seq-From"] = 7,
    ["Seq-To"] = 8,
    ["Merkle-Root"] = "merkle-overlap",
    ["Meta-Hash"] = "audit-meta-overlap",
    ["Reporter-Ref"] = "auth-reporter-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(audit_conflict, "ERROR", "append integrity audit conflict status")
  assert_code(audit_conflict, "VERSION_CONFLICT", "append integrity audit conflict code")

  local audit_format = registry.route(with_req {
    Action = "AppendIntegrityAuditCommitment",
    ["Seq-From"] = 8.5,
    ["Seq-To"] = 9,
    ["Merkle-Root"] = "merkle-2",
    ["Meta-Hash"] = "audit-meta-2",
    ["Reporter-Ref"] = "auth-reporter-1",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(audit_format, "ERROR", "append integrity audit invalid format status")
  assert_code(audit_format, "INVALID_INPUT", "append integrity audit invalid format code")

  local audit_time_format = registry.route(with_req {
    Action = "AppendIntegrityAuditCommitment",
    ["Seq-From"] = 9,
    ["Seq-To"] = 10,
    ["Merkle-Root"] = "merkle-3",
    ["Meta-Hash"] = "audit-meta-3",
    ["Reporter-Ref"] = "auth-reporter-1",
    ["Accepted-At"] = "not-a-time",
    ["Actor-Role"] = "registry-admin",
  })
  assert_status(audit_time_format, "ERROR", "append integrity audit invalid timestamp status")
  assert_code(audit_time_format, "INVALID_INPUT", "append integrity audit invalid timestamp code")

  local deny_publish = registry.route(with_req {
    Action = "PublishTrustedRelease",
    ["Component-Id"] = "gateway",
    Version = "1.2.2",
    Root = "root-deny",
    ["Uri-Hash"] = "uri-deny",
    ["Meta-Hash"] = "meta-deny",
    ["Actor-Role"] = "viewer",
  })
  assert_status(deny_publish, "ERROR", "publish trusted release forbidden status")
  assert_code(deny_publish, "FORBIDDEN", "publish trusted release forbidden code")

  local idem_first = registry.route(with_req {
    Action = "SetIntegrityPolicyPause",
    Paused = false,
    ["Actor-Role"] = "registry-admin",
    ["Request-Id"] = "rid-integrity-pause",
  })
  local idem_second = registry.route(with_req {
    Action = "SetIntegrityPolicyPause",
    Paused = true,
    ["Actor-Role"] = "registry-admin",
    ["Request-Id"] = "rid-integrity-pause",
  })
  assert_eq(
    idem_second.payload.paused,
    idem_first.payload.paused,
    "set integrity pause idempotent keeps first response"
  )
end

-- Site tests
do
  local site = require "ao.site.process"
  site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-1",
    ["Page-Id"] = "home",
    Content = { title = "Hello", blocks = { { type = "paragraph", text = "Hello" } } },
    ["Actor-Role"] = "editor",
  })
  site.route(with_req {
    Action = "UpsertRoute",
    ["Site-Id"] = "site-1",
    Path = "/",
    ["Page-Id"] = "home",
    ["Layout-Id"] = "layout-1",
    ["Actor-Role"] = "editor",
  })
  local publish = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-1",
    Version = "v2",
    ["Actor-Role"] = "publisher",
  })
  assert_status(publish, "OK", "publish status")
  assert_truthy(publish.payload.manifestTx, "publish manifestTx")
  assert_truthy(publish.payload.manifestHash, "publish manifestHash")
  local ar = require "ao.shared.arweave"
  local ok_hash = ar.verify_snapshot(publish.payload.manifestTx, publish.payload.manifestHash)
  assert_truthy(ok_hash, "verify manifest hash")
  local route = site.route(with_req { Action = "ResolveRoute", ["Site-Id"] = "site-1", Path = "/" })
  assert_eq(route.status, "OK", "resolve route status")
  local page =
    site.route(with_req { Action = "GetPage", ["Site-Id"] = "site-1", ["Page-Id"] = "home" })
  assert_eq(page.status, "OK", "get page status")
  assert_eq(page.payload.version, "v2", "page version active")

  -- Order write/read/list contract
  local rec = site.route(with_req {
    Action = "RecordOrder",
    ["Site-Id"] = "site-1",
    ["Order-Id"] = "order-1",
    Status = "paid",
    TotalAmount = 19.99,
    Currency = "EUR",
    VatRate = 0.21,
    ["Actor-Role"] = "support",
  })
  assert_eq(rec.status, "OK", "record order status")
  local get = site.route(with_req {
    Action = "GetOrder",
    ["Site-Id"] = "site-1",
    ["Order-Id"] = "order-1",
    ["Actor-Role"] = "support",
  })
  assert_eq(get.status, "OK", "get order status")
  assert_eq(get.payload.currency, "EUR", "order currency")
  assert_eq(get.payload.vatRate, 0.21, "order vat")
  local list = site.route(with_req {
    Action = "ListOrders",
    ["Site-Id"] = "site-1",
    Status = "paid",
    Page = 1,
    PageSize = 10,
    ["Actor-Role"] = "support",
  })
  assert_eq(list.status, "OK", "list orders status")
  assert_truthy(list.payload.items and list.payload.items[1], "list orders items present")

  -- role enforcement for order actions
  local denied_rec = site.route(with_req {
    Action = "RecordOrder",
    ["Site-Id"] = "site-1",
    ["Order-Id"] = "order-2",
    Status = "paid",
    TotalAmount = 12.34,
    Currency = "USD",
    VatRate = 0.1,
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied_rec, "ERROR", "record order forbidden status")
  assert_code(denied_rec, "FORBIDDEN", "record order forbidden code")
  local denied_get = site.route(with_req {
    Action = "GetOrder",
    ["Site-Id"] = "site-1",
    ["Order-Id"] = "order-1",
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied_get, "ERROR", "get order forbidden status")
  assert_code(denied_get, "FORBIDDEN", "get order forbidden code")
  local denied_list = site.route(with_req {
    Action = "ListOrders",
    ["Site-Id"] = "site-1",
    Status = "paid",
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied_list, "ERROR", "list orders forbidden status")
  assert_code(denied_list, "FORBIDDEN", "list orders forbidden code")
end

-- Site edge cases
do
  local site = require "ao.site.process"
  local missing = site.route(with_req { Action = "ResolveRoute", ["Site-Id"] = "site-1" }) -- missing Path
  assert_eq(missing.status, "ERROR", "missing field status")
  assert_code(missing, "INVALID_INPUT", "missing field code")

  local notfound =
    site.route(with_req { Action = "ResolveRoute", ["Site-Id"] = "site-1", Path = "/nope" })
  assert_eq(notfound.status, "ERROR", "resolve unknown status")
  assert_code(notfound, "NOT_FOUND", "resolve unknown code")

  local publish_empty = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-2",
    Version = "v1",
    ["Actor-Role"] = "publisher",
  })
  assert_eq(publish_empty.status, "OK", "publish empty status")
  assert_falsy(publish_empty.payload.manifestTx, "publish empty manifest")

  -- Oversize content guard
  local big_content =
    { title = "Big", blocks = { { type = "paragraph", text = string.rep("x", 70 * 1024) } } }
  local oversize = site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-oversize",
    ["Page-Id"] = "home",
    Content = big_content,
    ["Actor-Role"] = "editor",
  })
  assert_status(oversize, "ERROR", "putdraft oversize status")
  assert_code(oversize, "INVALID_INPUT", "putdraft oversize code")

  -- Archive then fetch
  site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-2",
    ["Page-Id"] = "old",
    Content = { title = "Old", blocks = { { type = "paragraph", text = "Old" } } },
    ["Actor-Role"] = "editor",
  })
  site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-2",
    Version = "v1",
    ["Actor-Role"] = "publisher",
  })
  site.route(with_req {
    Action = "ArchivePage",
    ["Site-Id"] = "site-2",
    ["Page-Id"] = "old",
    ["Actor-Role"] = "publisher",
  })
  local archived =
    site.route(with_req { Action = "GetPage", ["Site-Id"] = "site-2", ["Page-Id"] = "old" })
  assert_status(archived, "ERROR", "archived page status")
  assert_code(archived, "NOT_FOUND", "archived page code")

  -- Unexpected field
  local extra = site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-1",
    ["Page-Id"] = "x",
    Content = { title = "X", blocks = { { type = "paragraph", text = "X" } } },
    Foo = "bar",
    ["Actor-Role"] = "editor",
  })
  assert_status(extra, "ERROR", "putdraft extra status")
  assert_code(extra, "UNSUPPORTED_FIELD", "putdraft extra code")

  -- Forbidden publish
  local denied = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-3",
    Version = "v1",
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied, "ERROR", "publish forbidden status")
  assert_code(denied, "FORBIDDEN", "publish forbidden code")

  -- Idempotent publish with same Request-Id returns same manifest
  local req = with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-4",
    Version = "v1",
    ["Actor-Role"] = "publisher",
    ["Request-Id"] = "rid-same",
  }
  local first = site.route(req)
  local second = site.route(req)
  assert_eq(first.payload.manifestTx, second.payload.manifestTx, "idempotent publish manifest")

  -- Conflicting publish payload (different drafts) same Request-Id keeps original
  site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-4",
    ["Page-Id"] = "extra",
    Content = { title = "Extra", blocks = { { type = "paragraph", text = "Extra" } } },
    ["Actor-Role"] = "editor",
    ["Request-Id"] = "rid-extra1",
  })
  local third = site.route(req)
  assert_eq(
    third.payload.manifestTx,
    first.payload.manifestTx,
    "idempotent publish ignores new drafts"
  )

  -- ExpectedVersion conflict on publish
  local conflict = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-1",
    Version = "v3",
    ExpectedVersion = "old",
    ["Actor-Role"] = "publisher",
  })
  assert_status(conflict, "ERROR", "publish expected version conflict")
  assert_code(conflict, "VERSION_CONFLICT", "publish conflict code")

  -- concurrent-like publish attempts (simulate sequence)
  site.route(with_req {
    Action = "PutDraft",
    ["Site-Id"] = "site-conc",
    ["Page-Id"] = "p1",
    Content = { title = "A", blocks = { { type = "paragraph", text = "A" } } },
    ["Actor-Role"] = "editor",
  })
  local p1 = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-conc",
    Version = "v1",
    ["Actor-Role"] = "publisher",
  })
  assert_status(p1, "OK", "publish v1 status")
  local p2 = site.route(with_req {
    Action = "PublishVersion",
    ["Site-Id"] = "site-conc",
    Version = "v2",
    ExpectedVersion = "v0",
    ["Actor-Role"] = "publisher",
  })
  assert_status(p2, "ERROR", "publish v2 conflict status")
  assert_code(p2, "VERSION_CONFLICT", "publish v2 conflict code")

  -- Path length guard
  local long_path = "/" .. string.rep("p", 2050)
  local long_path_resp =
    site.route(with_req { Action = "ResolveRoute", ["Site-Id"] = "site-1", Path = long_path })
  assert_status(long_path_resp, "ERROR", "resolve long path status")
  assert_code(long_path_resp, "INVALID_INPUT", "resolve long path code")

  -- ArchivePage unexpected field and version length guard
  local archive_extra = site.route(with_req {
    Action = "ArchivePage",
    ["Site-Id"] = "site-2",
    ["Page-Id"] = "old",
    Extra = true,
    ["Actor-Role"] = "publisher",
  })
  assert_status(archive_extra, "ERROR", "archive extra status")
  assert_code(archive_extra, "UNSUPPORTED_FIELD", "archive extra code")
  local long_version = string.rep("v", 130)
  local archive_long_version = site.route(with_req {
    Action = "ArchivePage",
    ["Site-Id"] = "site-2",
    ["Page-Id"] = "old",
    Version = long_version,
    ["Actor-Role"] = "publisher",
  })
  assert_status(archive_long_version, "ERROR", "archive long version status")
  assert_code(archive_long_version, "INVALID_INPUT", "archive long version code")
end

-- Catalog tests (can be skipped by setting SKIP_CATALOG=1 for faster CI)
if not os.getenv "SKIP_CATALOG" then
  local catalog = require "ao.catalog.process"
  for i = 1, 60 do
    catalog.route(with_req {
      Action = "UpsertProduct",
      ["Site-Id"] = "site-1",
      Sku = "sku-" .. i,
      Payload = { name = "Prod" .. i },
      ["Actor-Role"] = "catalog-admin",
    })
  end
  catalog.route(with_req {
    Action = "UpsertCategory",
    ["Site-Id"] = "site-1",
    ["Category-Id"] = "cat-1",
    Products = { "sku-1", "sku-2", "sku-3", "sku-55" },
    ["Actor-Role"] = "catalog-admin",
  })
  local product =
    catalog.route(with_req { Action = "GetProduct", ["Site-Id"] = "site-1", Sku = "sku-1" })
  assert_eq(product.status, "OK", "get product status")
  local listing = catalog.route(
    with_req { Action = "ListCategoryProducts", ["Site-Id"] = "site-1", ["Category-Id"] = "cat-1" }
  )
  assert_eq(listing.status, "OK", "list category products")
  assert_eq(listing.payload.total, 4, "category total")
  local search =
    catalog.route(with_req { Action = "SearchCatalog", ["Site-Id"] = "site-1", Query = "Prod" })
  assert_eq(search.status, "OK", "search status")
  assert_eq(search.payload.total, 60, "search total")
  local paged = catalog.route(with_req {
    Action = "ListCategoryProducts",
    ["Site-Id"] = "site-1",
    ["Category-Id"] = "cat-1",
    Page = 2,
    PageSize = 2,
  })
  assert_eq(paged.payload.page, 2, "second page number")
  assert_eq(#paged.payload.items, 2, "second page size")

  local paged_out = catalog.route(with_req {
    Action = "ListCategoryProducts",
    ["Site-Id"] = "site-1",
    ["Category-Id"] = "cat-1",
    Page = 10,
    PageSize = 10,
  })
  assert_eq(#paged_out.payload.items, 0, "empty page")

  -- page bounds
  local capped = catalog.route(with_req {
    Action = "ListCategoryProducts",
    ["Site-Id"] = "site-1",
    ["Category-Id"] = "cat-1",
    Page = -1,
    PageSize = 500,
  })
  assert_eq(capped.payload.page, 1, "page capped to 1")
  assert_eq(capped.payload.pageSize, 200, "pageSize capped to 200")

  local missing =
    catalog.route(with_req { Action = "GetProduct", ["Site-Id"] = "site-1", Sku = "nope" })
  assert_eq(missing.status, "ERROR", "missing product status")
  assert_code(missing, "NOT_FOUND", "missing product code")

  -- oversize payload guard
  local huge_payload = { name = string.rep("X", 70 * 1024) }
  local oversize_payload = catalog.route(with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = "sku-big",
    Payload = huge_payload,
    ["Actor-Role"] = "catalog-admin",
  })
  assert_status(oversize_payload, "ERROR", "upsert payload oversize status")
  assert_code(oversize_payload, "INVALID_INPUT", "upsert payload oversize code")

  -- pagination property-ish test (monotone total, no duplication across pages)
  local seen = {}
  for page = 1, 5 do
    local resp = catalog.route(with_req {
      Action = "ListCategoryProducts",
      ["Site-Id"] = "site-1",
      ["Category-Id"] = "cat-1",
      Page = page,
      PageSize = 2,
    })
    assert_status(resp, "OK", "pagination status page " .. page)
    for _, item in ipairs(resp.payload.items) do
      assert_falsy(seen[item.sku], "pagination duplicate sku")
      seen[item.sku] = true
    end
  end

  -- search miss
  local search_miss =
    catalog.route(with_req { Action = "SearchCatalog", ["Site-Id"] = "site-1", Query = "zzz" })
  assert_eq(search_miss.payload.total, 0, "search miss total")

  -- Forbidden upsert
  local denied = catalog.route(with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = "bad",
    Payload = {},
    ["Actor-Role"] = "viewer",
  })
  assert_status(denied, "ERROR", "catalog forbidden status")
  assert_code(denied, "FORBIDDEN", "catalog forbidden code")

  -- Idempotent upsert
  local idem_req = with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = "sku-idem",
    Payload = { name = "Idem" },
    ["Actor-Role"] = "catalog-admin",
    ["Request-Id"] = "rid-upsert",
  }
  local first = catalog.route(idem_req)
  local second = catalog.route(idem_req)
  assert_eq(first.payload.sku, second.payload.sku, "idempotent upsert sku")

  -- Conflicting payload same Request-Id keeps original
  local conflict = catalog.route(with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = "sku-idem",
    Payload = { name = "changed" },
    ["Actor-Role"] = "catalog-admin",
    ["Request-Id"] = "rid-upsert",
  })
  assert_status(conflict, "OK", "idempotent conflict status")
  assert_eq(conflict.payload.sku, first.payload.sku, "idempotent conflict ignores change")

  -- ExpectedVersion conflict on PublishCatalogVersion
  catalog.route(with_req {
    Action = "PublishCatalogVersion",
    ["Site-Id"] = "site-1",
    Version = "cat-v1",
    ["Actor-Role"] = "catalog-admin",
  })
  local publish_conflict = catalog.route(with_req {
    Action = "PublishCatalogVersion",
    ["Site-Id"] = "site-1",
    Version = "cat-v2",
    ExpectedVersion = "different",
    ["Actor-Role"] = "catalog-admin",
  })
  assert_status(publish_conflict, "ERROR", "catalog publish conflict status")
  assert_code(publish_conflict, "VERSION_CONFLICT", "catalog publish conflict code")

  -- Unexpected field in upsert
  local extra = catalog.route(with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = "sku-extra",
    Payload = {},
    Extra = true,
    ["Actor-Role"] = "catalog-admin",
  })
  assert_status(extra, "ERROR", "upsert extra status")
  assert_code(extra, "UNSUPPORTED_FIELD", "upsert extra code")

  -- Length guard on SKU
  local long_sku = string.rep("s", 129)
  local too_long = catalog.route(with_req {
    Action = "UpsertProduct",
    ["Site-Id"] = "site-1",
    Sku = long_sku,
    Payload = {},
    ["Actor-Role"] = "catalog-admin",
  })
  assert_status(too_long, "ERROR", "upsert sku too long status")
  assert_code(too_long, "INVALID_INPUT", "upsert sku too long code")
end

-- Access tests (set SKIP_ACCESS=1 to skip)
if not os.getenv "SKIP_ACCESS" then
  local access = require "ao.access.process"
  access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "user-1",
    Asset = "asset-1",
    Policy = "view",
    ["Actor-Role"] = "admin",
  })
  access.route(with_req {
    Action = "PutProtectedAssetRef",
    Asset = "asset-1",
    Ref = "ar://tx123",
    Visibility = "protected",
    ["Actor-Role"] = "access-admin",
  })
  local check =
    access.route(with_req { Action = "HasEntitlement", Subject = "user-1", Asset = "asset-1" })
  assert_eq(check.status, "OK", "has entitlement status")
  assert_truthy(check.payload.hasEntitlement, "entitlement flag")
  local asset = access.route(with_req { Action = "GetProtectedAssetRef", Asset = "asset-1" })
  assert_eq(asset.status, "OK", "get asset ref")
  assert_eq(asset.payload.ref, "ar://tx123", "asset ref matches")

  access.route(with_req {
    Action = "RevokeEntitlement",
    Subject = "user-1",
    Asset = "asset-1",
    ["Actor-Role"] = "admin",
  })
  local check2 =
    access.route(with_req { Action = "HasEntitlement", Subject = "user-1", Asset = "asset-1" })
  assert_eq(check2.status, "OK", "has entitlement revoked status")
  assert_falsy(check2.payload.hasEntitlement, "entitlement revoked flag")

  local missing_asset =
    access.route(with_req { Action = "GetProtectedAssetRef", Asset = "asset-missing" })
  assert_eq(missing_asset.status, "ERROR", "missing asset ref status")
  assert_code(missing_asset, "NOT_FOUND", "missing asset ref code")

  -- revoke idempotency
  local rev2 = access.route(with_req {
    Action = "RevokeEntitlement",
    Subject = "user-1",
    Asset = "asset-1",
    ["Actor-Role"] = "admin",
  })
  assert_status(rev2, "OK", "second revoke status")

  -- Forbidden grant
  local deny = access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "u2",
    Asset = "asset-2",
    Policy = "view",
    ["Actor-Role"] = "viewer",
  })
  assert_status(deny, "ERROR", "grant forbidden status")
  assert_code(deny, "FORBIDDEN", "grant forbidden code")

  -- Idempotent grant (same Request-Id returns same ref)
  local idem_req = with_req {
    Action = "GrantEntitlement",
    Subject = "u3",
    Asset = "asset-3",
    Policy = "view",
    ["Actor-Role"] = "admin",
    ["Request-Id"] = "idem-grant",
  }
  local first = access.route(idem_req)
  local second = access.route(idem_req)
  assert_eq(first.payload.subject, second.payload.subject, "idempotent grant subject")

  -- Conflicting payload with same Request-Id returns original
  local conflict = access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "u3",
    Asset = "asset-3",
    Policy = "edit",
    ["Actor-Role"] = "admin",
    ["Request-Id"] = "idem-grant",
  })
  assert_eq(conflict.payload.policy, first.payload.policy, "idempotent ignores new payload")

  -- Unexpected field in grant
  local extra = access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "u4",
    Asset = "asset-4",
    Policy = "view",
    Foo = "bar",
    ["Actor-Role"] = "admin",
  })
  assert_status(extra, "ERROR", "grant extra status")
  assert_code(extra, "UNSUPPORTED_FIELD", "grant extra code")

  -- Length guard on asset id
  local long_asset = string.rep("a", 300)
  local long_asset_resp = access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "user-long",
    Asset = long_asset,
    Policy = "view",
    ["Actor-Role"] = "admin",
  })
  assert_status(long_asset_resp, "ERROR", "grant long asset status")
  assert_code(long_asset_resp, "INVALID_INPUT", "grant long asset code")

  -- Size guard on policy
  local huge_policy = { blob = string.rep("x", 40 * 1024) }
  local oversize_policy = access.route(with_req {
    Action = "GrantEntitlement",
    Subject = "u5",
    Asset = "asset-oversize",
    Policy = huge_policy,
    ["Actor-Role"] = "admin",
  })
  assert_status(oversize_policy, "ERROR", "grant oversize policy status")
  assert_code(oversize_policy, "INVALID_INPUT", "grant oversize policy code")
end

-- Unknown action test
do
  local registry = require "ao.registry.process"
  local resp = registry.route(with_req { Action = "NopeAction" })
  assert_eq(resp.status, "ERROR", "unknown action status")
  assert_code(resp, "UNKNOWN_ACTION", "unknown action code")
end

print "contract tests passed"
