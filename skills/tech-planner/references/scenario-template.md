# Scenario Template

Use this exact YAML contract for `<runtime-root>/dag/scenarios/<scenario-id>.scenario.yml`.

```yaml
id: auth_login_flow
title: Login API and session propagation
owner: platform-team

# Optional. CSV list of upstream scenario ids.
depends_on: ""

# Required. CSV list of impact paths used by --changed-only selection.
changed_paths: "src/auth/**,src/session/**,tests/auth/**"

# Required hard-TDD chain commands.
red_run: "pnpm test tests/auth/login.spec.ts -t \"rejects invalid credentials\""
impl_run: "pnpm exec tsx scripts/dev/apply-login-change.ts"
green_run: "pnpm test tests/auth/login.spec.ts"

# Required. Must be a real command (no-op like true/: prohibited).
verify: "pnpm test tests/auth/login.spec.ts && pnpm test tests/session/session.spec.ts"
```
