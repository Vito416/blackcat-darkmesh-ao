package.path = table.concat({ "?.lua", "?/init.lua", "ao/?.lua", "ao/?/init.lua", package.path }, ";")

local auth = require "ao.shared.auth"

local original_auth = {
  enforce = auth.enforce,
  verify_outbox_hmac_for_action = auth.verify_outbox_hmac_for_action,
  require_role_for_action = auth.require_role_for_action,
  check_rate_limit = auth.check_rate_limit,
}

auth.enforce = function()
  return true
end

auth.verify_outbox_hmac_for_action = function()
  return true
end

auth.require_role_for_action = function()
  return true
end

auth.check_rate_limit = function()
  return true
end

local registry = require "ao.registry.process"
local route = registry.route
local state = registry._state
local request_seq = 0

local function with_request_id(msg)
  request_seq = request_seq + 1
  if msg["Request-Id"] == nil then
    msg["Request-Id"] = ("registry-policy-contract-%d"):format(request_seq)
  end
  return msg
end

state.sites = {}
state.site_runtimes = {}
state.domains = {}
state.gateways = {}
state.active_versions = {}
state.roles = {}
state.resolver_flags = {}
state.policy = {
  mode = "off",
  modeUpdatedAt = "1970-01-01T00:00:00Z",
  modeUpdatedBy = "",
  hb_nodes = {},
  site_serving = {},
  site_funding = {},
  dns_proofs = {},
  site_auth = {},
  sessions = {},
  payment_webhooks = {},
  domain_lifecycle = {},
  snapshots = {},
  activeSnapshotId = nil,
}

local function expect_ok(msg)
  local resp = route(with_request_id(msg))
  assert(resp and resp.status == "OK", (resp and (resp.code or resp.message)) or "expected OK")
  return resp.payload or {}
end

local function expect_error(msg, code)
  local resp = route(with_request_id(msg))
  assert(resp and resp.status == "ERROR", "expected ERROR response")
  assert(resp.code == code, ("expected %s, got %s"):format(code, tostring(resp.code)))
  return resp
end

expect_ok {
  Action = "RegisterSite",
  ["Site-Id"] = "site-registry-policy",
}

expect_ok {
  Action = "BindDomain",
  ["Site-Id"] = "site-registry-policy",
  Host = "policy-test.darkmesh.fun",
}

local off_decision = expect_ok {
  Action = "GetDecisionForHostNode",
  Host = "policy-test.darkmesh.fun",
  ["Node-Id"] = "hb-node-eu-1",
}
assert(off_decision.allow == true, "off-mode decision must remain allow-friendly")
assert(off_decision.reason == "policy_mode_off", "off-mode reason should be explicit")
assert(off_decision.siteId == "site-registry-policy", "domain should resolve to registered site")

local node_profile = expect_ok {
  Action = "RegisterHBNode",
  ["Node-Id"] = "hb-node-eu-1",
  Url = "https://hb-node-eu-1.example",
  Status = "online",
  Labels = { "eu", "primary" },
  Metadata = { operator = "darkmesh" },
}
assert(node_profile.profile and node_profile.profile.registered == true, "node should be registered")
assert(node_profile.profile.status == "online", "node status should be online")

expect_ok {
  Action = "SetSiteServingPolicy",
  ["Site-Id"] = "site-registry-policy",
  ["Serving-State"] = "allow",
  ["Cache-Ttl-Sec"] = 120,
  ["DNS-Proof-Required"] = "true",
  ["HB-Allow-List"] = { "hb-node-eu-1" },
  ["Policy-Ref"] = "snapshot-v1",
}

expect_ok {
  Action = "SetSiteFundingState",
  ["Site-Id"] = "site-registry-policy",
  ["Funding-State"] = "active",
  Plan = "starter",
  Tier = "free",
}

expect_ok {
  Action = "SetSiteAuthMetadata",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Required"] = "true",
  Provider = "wallet-signature",
  ["Token-Ttl-Sec"] = 3600,
  ["Cookie-Name"] = "dm_session",
  ["Session-Mode"] = "stateless",
}

local auth_metadata_payload = expect_ok {
  Action = "GetSiteAuthMetadata",
  ["Site-Id"] = "site-registry-policy",
}
assert(auth_metadata_payload.authMetadata.sessionRequired == true, "site auth should be session-required")
assert(auth_metadata_payload.authMetadata.provider == "wallet-signature", "site auth provider should persist")
assert(auth_metadata_payload.authMetadata.tokenTtlSec == 3600, "site auth ttl should persist")

local created_session = expect_ok {
  Action = "CreateSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  Subject = "subject:user:alpha",
  ["Session-Id"] = "sess:test:alpha-001",
  ["Token-Ttl-Sec"] = 900,
  Claims = { tier = "starter" },
  Context = { ip = "203.0.113.10" },
}
assert(created_session.session.sessionId == "sess:test:alpha-001", "session id should be persisted")
assert(created_session.session.status == "active", "session should start active")
assert(created_session.session.ttlSec == 900, "session ttl should be persisted")

local read_session = expect_ok {
  Action = "ReadSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Id"] = "sess:test:alpha-001",
}
assert(read_session.session.status == "active", "read should return active session")
assert(read_session.session.expired == false, "fresh session should not be expired")

local listed_active_sessions = expect_ok {
  Action = "ListSessionsBySubject",
  ["Site-Id"] = "site-registry-policy",
  Subject = "subject:user:alpha",
}
assert(listed_active_sessions.count == 1, "list should include one active session")

local rotated_session = expect_ok {
  Action = "RotateSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Id"] = "sess:test:alpha-001",
  ["New-Session-Id"] = "sess:test:alpha-002",
}
assert(rotated_session.previousSessionId == "sess:test:alpha-001", "rotate should reference previous session")
assert(rotated_session.session.sessionId == "sess:test:alpha-002", "rotate should create successor session")
assert(rotated_session.session.rotatedFrom == "sess:test:alpha-001", "successor should track source session")

expect_error({
  Action = "ReadSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Id"] = "sess:test:alpha-001",
}, "FORBIDDEN")

local revoked_session = expect_ok {
  Action = "RevokeSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Id"] = "sess:test:alpha-002",
  Reason = "manual-logout",
}
assert(revoked_session.session.status == "revoked", "revoke should mark session revoked")
assert(revoked_session.previousStatus == "active", "revoke should expose previous status")

expect_error({
  Action = "ReadSessionLifecycle",
  ["Site-Id"] = "site-registry-policy",
  ["Session-Id"] = "sess:test:alpha-002",
}, "FORBIDDEN")

local listed_inactive_sessions = expect_ok {
  Action = "ListSessionsBySubject",
  ["Site-Id"] = "site-registry-policy",
  Subject = "subject:user:alpha",
  ["Include-Inactive"] = "true",
}
assert(listed_inactive_sessions.count == 2, "inactive-inclusive list should include rotated+revoked sessions")

local webhook_accept = expect_ok {
  Action = "CheckPaymentWebhookIdempotency",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
  ["Event-Id"] = "evt-001",
  Fingerprint = "sha256:aaa",
  Policy = "dedupe",
  ["Ttl-Sec"] = 600,
  ["Max-Keys"] = 10,
  ["Key-Max-Bytes"] = 128,
}
assert(webhook_accept.decision.status == "accepted", "first webhook id should be accepted")
assert(webhook_accept.decision.httpStatus == 200, "accepted webhook should map to http 200")

local webhook_duplicate = expect_ok {
  Action = "CheckPaymentWebhookIdempotency",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
  ["Event-Id"] = "evt-001",
  Fingerprint = "sha256:aaa",
  Policy = "dedupe",
}
assert(webhook_duplicate.decision.status == "duplicate", "same event id should be duplicate")
assert(webhook_duplicate.decision.httpStatus == 200, "dedupe duplicate should be replay/200")

local webhook_conflict = expect_ok {
  Action = "CheckPaymentWebhookIdempotency",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
  ["Event-Id"] = "evt-001",
  Fingerprint = "sha256:bbb",
}
assert(webhook_conflict.decision.status == "conflict", "fingerprint mismatch should conflict")
assert(webhook_conflict.decision.httpStatus == 409, "conflict should map to 409")

local webhook_missing_id = expect_ok {
  Action = "CheckPaymentWebhookIdempotency",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
  Fingerprint = "sha256:ccc",
}
assert(webhook_missing_id.decision.status == "missing-id", "missing event id should be explicit")
assert(webhook_missing_id.decision.httpStatus == 400, "missing id should map to 400")

local webhook_state = expect_ok {
  Action = "GetPaymentWebhookIdempotencyState",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
  ["Include-Entries"] = "true",
  Limit = 5,
}
assert(webhook_state.ledger.provider == "gopay", "provider state should be available")
assert(webhook_state.ledger.count == 1, "only one accepted event should be stored")
assert(#webhook_state.ledger.entries == 1, "entry list should include accepted event")
assert(webhook_state.ledger.entries[1].eventId == "evt-001", "accepted event id should be persisted")

local webhook_reset = expect_ok {
  Action = "ResetPaymentWebhookIdempotencyState",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
}
assert(webhook_reset.scope == "provider", "provider reset scope should be explicit")
assert(webhook_reset.removed == 1, "provider reset should remove stored event id")

local webhook_state_after_reset = expect_ok {
  Action = "GetPaymentWebhookIdempotencyState",
  ["Site-Id"] = "site-registry-policy",
  Provider = "gopay",
}
assert(webhook_state_after_reset.ledger.count == 0, "provider ledger should be empty after reset")

expect_ok {
  Action = "SetDomainLifecycleState",
  Host = "policy-test.darkmesh.fun",
  ["Site-Id"] = "site-registry-policy",
  State = "suspended",
  Reason = "abuse-review",
}

local suspended_lifecycle = expect_ok {
  Action = "GetDomainLifecycleState",
  Host = "policy-test.darkmesh.fun",
}
assert(suspended_lifecycle.lifecycle.state == "suspended", "domain lifecycle should be suspended")

expect_ok {
  Action = "SetDomainLifecycleState",
  Host = "policy-test.darkmesh.fun",
  State = "active",
  Reason = "manual-restore",
}

local active_lifecycle = expect_ok {
  Action = "GetDomainLifecycleState",
  Host = "policy-test.darkmesh.fun",
}
assert(active_lifecycle.lifecycle.state == "active", "domain lifecycle should return to active")

expect_ok {
  Action = "SetDnsProofState",
  Host = "policy-test.darkmesh.fun",
  ["Site-Id"] = "site-registry-policy",
  Status = "valid",
  Verified = "true",
  ["Checked-At"] = "2026-04-22T00:00:00Z",
  ["Expires-At"] = "2026-04-23T00:00:00Z",
  Challenge = "dns-proof-challenge-01",
  ["TXT-Value"] = "v=dm1;site=site-registry-policy;challenge=dns-proof-challenge-01",
  ["Proof-Ref"] = "dns-proof-ref-1",
  Source = "resolver-cache",
}

local serving_payload = expect_ok {
  Action = "GetSiteServingPolicy",
  ["Site-Id"] = "site-registry-policy",
}
assert(serving_payload.servingPolicy.cacheTtlSec == 120, "serving policy ttl should be stored")
assert(serving_payload.servingPolicy.dnsProofRequired == true, "dns proof flag should be stored")
assert(serving_payload.fundingState.fundingState == "active", "funding state should be active")

local dns_proof_payload = expect_ok {
  Action = "GetDnsProofState",
  Host = "policy-test.darkmesh.fun",
}
assert(dns_proof_payload.dnsProofState.status == "valid", "dns proof status should be valid")
assert(dns_proof_payload.dnsProofState.verified == true, "dns proof should be marked verified")
assert(
  dns_proof_payload.dnsProofState.challenge == "dns-proof-challenge-01",
  "dns proof challenge should be stored"
)

local template_contract = expect_ok {
  Action = "GetTemplateActionContract",
}
assert(template_contract.actions and template_contract.actions.read, "template contract should include read actions")
assert(template_contract.contractVersion == "1.0.0", "template contract version should be stable")
assert(
  template_contract.updatedAt == "2026-04-22T00:00:00Z",
  "template contract updatedAt metadata should be present"
)
assert(
  template_contract.checksum == "sha256:c93530e2f7d31d1f270af4ab8e11f9654c6cb6c397d17c0adf652f64806419f3",
  "template contract checksum metadata should be present"
)
assert(
  template_contract.actions.read["resolve-route"].registryAction == "ResolveHostPolicyBundle",
  "resolve-route must point to ResolveHostPolicyBundle"
)
assert(
  template_contract.actions.read["get-page"].registryAction == "GetSiteRuntimeBundle",
  "get-page must point to GetSiteRuntimeBundle"
)
assert(template_contract.actions.write.checkout ~= nil, "no-filter contract should keep write actions")

local template_contract_csv_filter = expect_ok {
  Action = "GetTemplateActionContract",
  ["Action-Names"] = "resolve-route, checkout",
}
assert(template_contract_csv_filter.actions.read["resolve-route"] ~= nil, "csv filter should include resolve-route")
assert(template_contract_csv_filter.actions.write.checkout ~= nil, "csv filter should include checkout")
assert(
  template_contract_csv_filter.actions.read["site-by-host"] == nil,
  "csv filter should omit unselected read action"
)

local template_contract_array_filter = expect_ok {
  Action = "GetTemplateActionContract",
  ActionNames = { "site-by-host", "get-page" },
}
assert(
  template_contract_array_filter.actions.read["site-by-host"] ~= nil,
  "array filter should include site-by-host"
)
assert(template_contract_array_filter.actions.read["get-page"] ~= nil, "array filter should include get-page")
assert(template_contract_array_filter.actions.write.checkout == nil, "array filter should omit checkout")

local runtime_bundle_by_site = expect_ok {
  Action = "GetSiteRuntimeBundle",
  ["Site-Id"] = "site-registry-policy",
}
assert(runtime_bundle_by_site.siteId == "site-registry-policy", "runtime bundle should resolve site")
assert(runtime_bundle_by_site.policyMode == "off", "runtime bundle should expose policy mode")
assert(runtime_bundle_by_site.dnsProofSummary.status == "valid", "runtime bundle should expose dns summary")
assert(runtime_bundle_by_site.authMetadata.provider == "wallet-signature", "runtime bundle should include auth metadata")
assert(runtime_bundle_by_site.domainLifecycle.state == "active", "runtime bundle should include lifecycle state")

local runtime_bundle_by_host = expect_ok {
  Action = "GetSiteRuntimeBundle",
  Host = "policy-test.darkmesh.fun",
}
assert(runtime_bundle_by_host.siteId == "site-registry-policy", "host runtime bundle should resolve site")
assert(runtime_bundle_by_host.host == "policy-test.darkmesh.fun", "runtime bundle host should be preserved")

local bundled_payload = expect_ok {
  Action = "ResolveHostPolicyBundle",
  Host = "policy-test.darkmesh.fun",
  ["Node-Id"] = "hb-node-eu-1",
}
assert(bundled_payload.siteId == "site-registry-policy", "bundle should resolve bound host")
assert(bundled_payload.dnsProofState.status == "valid", "bundle should include dns proof state")
assert(bundled_payload.allow == true, "bundle should remain allow-friendly in off mode")
assert(bundled_payload.authMetadata.provider == "wallet-signature", "bundle should include auth metadata")
assert(bundled_payload.domainLifecycle.state == "active", "bundle should include canonical lifecycle state")

expect_ok {
  Action = "SetPolicyMode",
  Mode = "observe",
}

local observe_decision = expect_ok {
  Action = "GetDecisionForHostNode",
  Host = "policy-test.darkmesh.fun",
  ["Node-Id"] = "hb-node-eu-1",
}
assert(observe_decision.allow == true, "stub decision should stay allow-friendly in observe mode")
assert(observe_decision.policyMode == "observe", "decision should expose current policy mode")
assert(observe_decision.dnsProofState.status == "valid", "decision should include dns proof snapshot")

expect_ok {
  Action = "PublishPolicySnapshot",
  ["Snapshot-Id"] = "snap-001",
  Snapshot = { revision = 1 },
}

local active_snapshot = expect_ok {
  Action = "GetPolicySnapshot",
}
assert(active_snapshot.activeSnapshotId == "snap-001", "active snapshot id should be set")
assert(active_snapshot.snapshot and active_snapshot.snapshot.snapshotId == "snap-001", "snapshot should be returned")

expect_ok {
  Action = "RevokePolicySnapshot",
  ["Snapshot-Id"] = "snap-001",
  Reason = "rotation",
}

local revoked_snapshot = expect_ok {
  Action = "GetPolicySnapshot",
  ["Snapshot-Id"] = "snap-001",
}
assert(revoked_snapshot.snapshot and revoked_snapshot.snapshot.status == "revoked", "snapshot should be revoked")

expect_ok {
  Action = "SetPolicyMode",
  Mode = "off",
}

local unknown_host_off = expect_ok {
  Action = "GetDecisionForHostNode",
  Host = "unknown-policy.darkmesh.fun",
}
assert(unknown_host_off.allow == true, "off-mode should still allow unknown hosts")
assert(unknown_host_off.siteId == nil, "unknown host should not resolve a site")
assert(unknown_host_off.reason == "policy_mode_off", "off-mode reason should stay stable")

local unknown_bundle_off = expect_ok {
  Action = "ResolveHostPolicyBundle",
  Host = "unknown-policy.darkmesh.fun",
}
assert(unknown_bundle_off.allow == true, "off-mode bundle should fail-open for unknown host")
assert(unknown_bundle_off.siteId == nil, "unknown bundle host should not resolve a site")
assert(
  unknown_bundle_off.dnsProofState.status == "unknown",
  "unknown host should expose unknown dns proof state"
)

expect_error({ Action = "GetHBNodeProfile", ["Node-Id"] = "bad node id" }, "INVALID_INPUT")
expect_error({ Action = "GetDnsProofState", Host = "bad host with space" }, "INVALID_INPUT")
expect_error({ Action = "GetSiteAuthMetadata", ["Site-Id"] = "missing-site" }, "NOT_FOUND")
expect_error(
  { Action = "SetDnsProofState", Host = "policy-test.darkmesh.fun", Status = "bogus" },
  "INVALID_INPUT"
)
expect_error(
  { Action = "SetDomainLifecycleState", Host = "policy-test.darkmesh.fun", State = "pending" },
  "INVALID_INPUT"
)
expect_error({ Action = "GetTemplateActionContract", ["Action-Names"] = "resolve-route,unknown-x" }, "INVALID_INPUT")

auth.enforce = original_auth.enforce
auth.verify_outbox_hmac_for_action = original_auth.verify_outbox_hmac_for_action
auth.require_role_for_action = original_auth.require_role_for_action
auth.check_rate_limit = original_auth.check_rate_limit

print "registry_policy_contract_spec: ok"
