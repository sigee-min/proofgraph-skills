# Runtime Path Compatibility Plan

## Goals

- Preserve existing script execution while migrating governance assets.
- Avoid breaking current plan execution paths.

## Phase Model

### Phase 1: dual-read
- Runtime scripts continue reading legacy operational inputs.
- Governance loaders can read `.sigee` policy files when present.

### Phase 2: dual-write
- Planning outputs remain in the legacy runtime path for backward compatibility.
- Selected policy metadata is written to `.sigee` concurrently.

### Phase 3: cutover
- Primary policy references switch to `.sigee`.
- Legacy runtime path keeps compatibility shims for operational scripts.

## Rollback Strategy

- If cutover destabilizes workflows, rollback to legacy-runtime-primary mode.
- Keep `.sigee` policy files intact and re-enable by feature flag.

## Path Scope

- Legacy runtime plans/evidence/reports path
- `.sigee/policies`, `.sigee/scenarios`, `.sigee/dag` (tracked)
- `.sigee/templates` (local auto-generated, ignored)
