# Scenario Template

Use this exact YAML contract for `.sigee/dag/scenarios/<scenario-id>.scenario.yml` (tracked source).

```yaml
id: auth_login_flow
title: Login API and session propagation
owner: platform-team
outcome_id: "OUT-001"
capability_id: "CAP-001"
stability_layer: "system" # one of: core|system|experimental

# Optional. CSV list of upstream scenario ids.
depends_on: ""

# Required. CSV list of bug-prone linked scenario ids for boundary smoke linkage.
linked_nodes: "session_refresh_flow,authz_guard_flow"

# Required. CSV list of impact paths used by --changed-only selection.
changed_paths: "src/auth/**,src/session/**,tests/auth/**"

# Required hard-TDD chain commands.
red_run: "pnpm test tests/auth/login.spec.ts -t \"rejects invalid credentials\""
impl_run: "pnpm exec tsx scripts/dev/apply-login-change.ts"
green_run: "pnpm test tests/auth/login.spec.ts"

# Required. Must be a real command (no-op like true/: prohibited).
verify: "pnpm test tests/auth/login.spec.ts && pnpm test tests/session/session.spec.ts"

# Mandatory test contract (exact counts).
# Delimiter for multi-command fields: |||
unit_normal_tests: "pnpm test tests/auth/login.spec.ts -t \"normal: valid login\"|||pnpm test tests/auth/login.spec.ts -t \"normal: persisted session\""
unit_boundary_tests: "pnpm test tests/auth/login.spec.ts -t \"boundary: max username length\"|||pnpm test tests/auth/login.spec.ts -t \"boundary: token ttl edge\""
unit_failure_tests: "pnpm test tests/auth/login.spec.ts -t \"failure: locked account\"|||pnpm test tests/auth/login.spec.ts -t \"failure: malformed token\""
boundary_smoke_tests: "pnpm test tests/smoke/auth-linked.spec.ts -t \"boundary-1\"|||pnpm test tests/smoke/auth-linked.spec.ts -t \"boundary-2\"|||pnpm test tests/smoke/auth-linked.spec.ts -t \"boundary-3\"|||pnpm test tests/smoke/auth-linked.spec.ts -t \"boundary-4\"|||pnpm test tests/smoke/auth-linked.spec.ts -t \"boundary-5\""
```
