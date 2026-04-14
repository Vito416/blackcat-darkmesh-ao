-- Focused integrity registry lifecycle spec.
-- This runs without external crypto/runtime dependencies by stubbing the
-- cross-cutting AO auth/audit/metrics/persist helpers.

package.path =
  table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

package.preload["ao.shared.auth"] = function()
  local Auth = {}
  function Auth.enforce(_msg)
    return true
  end
  function Auth.verify_outbox_hmac(_msg)
    return true
  end
  function Auth.verify_outbox_hmac_for_action(_msg, _opts)
    return true
  end
  function Auth.require_role_for_action(_msg, _policy)
    return true
  end
  return Auth
end

package.preload["ao.shared.audit"] = function()
  local Audit = {}
  function Audit.record()
    return true
  end
  return Audit
end

package.preload["ao.shared.metrics"] = function()
  local Metrics = {}
  function Metrics.inc()
    return true
  end
  function Metrics.tick()
    return true
  end
  function Metrics.gauge()
    return true
  end
  return Metrics
end

package.preload["ao.shared.persist"] = function()
  local Persist = {}
  function Persist.load(_ns, default_value)
    return default_value
  end
  function Persist.save()
    return true
  end
  return Persist
end

local function fail(label, expected, actual)
  error(string.format("%s expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function assert_eq(actual, expected, label)
  if actual ~= expected then
    fail(label, expected, actual)
  end
end

local function assert_truthy(value, label)
  if not value then
    error(label .. " expected truthy")
  end
end

local function assert_status(resp, status, label)
  if not resp or resp.status ~= status then
    error(
      string.format(
        "%s expected %s, got %s",
        label,
        tostring(status),
        tostring(resp and resp.status)
      )
    )
  end
end

local function assert_code(resp, code, label)
  if not resp or resp.code ~= code then
    error(
      string.format(
        "%s expected code %s, got %s",
        label,
        tostring(code),
        tostring(resp and resp.code)
      )
    )
  end
end

local function msg(fields)
  fields = fields or {}
  fields.Action = fields.Action or fields.action
  fields["Request-Id"] = fields["Request-Id"]
    or fields.requestId
    or ("req-" .. tostring(math.random(1, 1e9)))
  fields.Nonce = fields.Nonce or fields.nonce or ("nonce-" .. tostring(math.random(1, 1e9)))
  fields.ts = fields.ts or math.floor(os.time())
  fields["Actor-Role"] = fields["Actor-Role"] or fields.actorRole or "registry-admin"
  fields["Schema-Version"] = fields["Schema-Version"] or "1.0"
  return fields
end

math.randomseed(42)

local registry = require "ao.registry.process"

local publish = registry.route(msg {
  Action = "PublishTrustedRelease",
  ["Component-Id"] = "gateway",
  Version = "1.4.0",
  Root = "root-1",
  ["Uri-Hash"] = "uri-1",
  ["Meta-Hash"] = "meta-1",
  ["Policy-Hash"] = "policy-1",
  Activate = true,
})
assert_status(publish, "OK", "publish trusted release")
assert_eq(publish.payload.activeRoot, "root-1", "publish active root")

local authority = registry.route(msg {
  Action = "SetIntegrityAuthority",
  Root = "auth-root-1",
  Upgrade = "auth-upgrade-1",
  Emergency = "auth-emergency-1",
  Reporter = "auth-reporter-1",
  ["Signature-Refs"] = { "sig-root-1", "sig-upgrade-1" },
})
assert_status(authority, "OK", "set authority")
assert_eq(authority.payload.reporter, "auth-reporter-1", "authority reporter")

local audit = registry.route(msg {
  Action = "AppendIntegrityAuditCommitment",
  ["Seq-From"] = 1,
  ["Seq-To"] = 4,
  ["Merkle-Root"] = "merkle-1",
  ["Meta-Hash"] = "audit-meta-1",
  ["Reporter-Ref"] = "auth-reporter-1",
})
assert_status(audit, "OK", "append audit commitment")
assert_eq(audit.payload.seqTo, 4, "audit seqTo")

local root = registry.route(msg { Action = "GetTrustedRoot" })
assert_status(root, "OK", "get trusted root")
assert_eq(root.payload.root, "root-1", "trusted root")

local policy = registry.route(msg { Action = "GetIntegrityPolicy" })
assert_status(policy, "OK", "get policy")
assert_eq(policy.payload.paused, false, "policy paused false")

local audit_state = registry.route(msg { Action = "GetIntegrityAuditState" })
assert_status(audit_state, "OK", "get audit state")
assert_eq(audit_state.payload.merkleRoot, "merkle-1", "audit merkle root")

local snapshot = registry.route(msg { Action = "GetIntegritySnapshot" })
assert_status(snapshot, "OK", "get snapshot")
assert_eq(snapshot.payload.release.version, "1.4.0", "snapshot release version")
assert_eq(snapshot.payload.authority.root, "auth-root-1", "snapshot authority root")
assert_eq(snapshot.payload.audit.seqTo, 4, "snapshot audit seqTo")

local pause = registry.route(msg {
  Action = "SetIntegrityPolicyPause",
  Paused = true,
  Reason = "maintenance",
})
assert_status(pause, "OK", "pause policy")
assert_eq(pause.payload.paused, true, "pause true")

local revoke = registry.route(msg {
  Action = "RevokeTrustedRelease",
  Root = "root-1",
  Reason = "revoked-for-test",
})
assert_status(revoke, "OK", "revoke trusted release")
assert_eq(revoke.payload.paused, true, "revocation pauses policy")
assert_truthy(revoke.payload.release.revokedAt, "revokedAt")

local blocked_snapshot = registry.route(msg { Action = "GetIntegritySnapshot" })
assert_status(blocked_snapshot, "ERROR", "revoked snapshot")
assert_code(blocked_snapshot, "NOT_FOUND", "revoked snapshot code")

local republish = registry.route(msg {
  Action = "PublishTrustedRelease",
  ["Component-Id"] = "gateway",
  Version = "1.4.1",
  Root = "root-2",
  ["Uri-Hash"] = "uri-2",
  ["Meta-Hash"] = "meta-2",
  ["Policy-Hash"] = "policy-2",
  Activate = true,
})
assert_status(republish, "OK", "republish trusted release")

local by_version = registry.route(msg {
  Action = "GetTrustedReleaseByVersion",
  ["Component-Id"] = "gateway",
  Version = "1.4.1",
})
assert_status(by_version, "OK", "get release by version")
assert_eq(by_version.payload.release.root, "root-2", "release by version root")

local by_root = registry.route(msg { Action = "GetTrustedReleaseByRoot", Root = "root-2" })
assert_status(by_root, "OK", "get release by root")
assert_eq(by_root.payload.release.version, "1.4.1", "release by root version")

local bad_authority = registry.route(msg {
  Action = "SetIntegrityAuthority",
  Root = "auth-root-3",
  Upgrade = "auth-upgrade-3",
  Emergency = "auth-emergency-3",
  Reporter = "auth-reporter-3",
  ["Signature-Refs"] = {},
})
assert_status(bad_authority, "ERROR", "bad authority")
assert_code(bad_authority, "INVALID_INPUT", "bad authority code")

local audit_conflict = registry.route(msg {
  Action = "AppendIntegrityAuditCommitment",
  ["Seq-From"] = 4,
  ["Seq-To"] = 6,
  ["Merkle-Root"] = "merkle-2",
  ["Meta-Hash"] = "audit-meta-2",
  ["Reporter-Ref"] = "auth-reporter-1",
})
assert_status(audit_conflict, "ERROR", "audit conflict")
assert_code(audit_conflict, "VERSION_CONFLICT", "audit conflict code")

print "integrity_registry_spec: OK"
