# .sigee Workspace Contract

`.sigee` is the governance root for shared planning, policy, and migration assets.

## Directory Policy

| Path | Policy | Notes |
| --- | --- | --- |
| `.sigee/README.md` | Tracked | Entry point for new contributors |
| `.sigee/policies/` | Tracked | Normative operating policy and prompt contracts |
| `.sigee/product-truth/` | Tracked | Single source of truth for outcomes, capabilities, and traceability |
| `.sigee/templates/` | Ignored | Auto-generated local templates created by queue runtime bootstrap |
| `.sigee/scenarios/` | Tracked | Human-readable scenario notes (reference only) |
| `.sigee/dag/schema/` | Tracked | DAG schema and node contracts |
| `.sigee/dag/pipelines/` | Tracked | Baseline pipeline definitions |
| `.sigee/dag/scenarios/` | Tracked | UX planning DAG scenario source of truth (compile source) |
| `.sigee/migrations/` | Tracked | Migration maps and cutover playbooks |
| `.sigee/.runtime/` | Ignored | Local runtime state (plans, evidence, queues) |
| `.sigee/tmp/` | Ignored | Temporary artifacts |
| `.sigee/locks/` | Ignored | Lease/lock runtime files |
| `.sigee/evidence/` | Ignored | Local execution logs and transient evidence |
| `.sigee/reports/` | Ignored by default | Report snapshots are promoted manually |

## Tracked vs Ignored Rules

- Tracked content is team knowledge and must be committed.
- Ignored content is machine- or run-specific and must not be committed by default.
- `.sigee` is deny-by-default in gitignore; only allow-listed governance paths are tracked.
- Legacy policy snapshots are archived under `.sigee/migrations/legacy-policy/` and are non-normative.
- `.sigee/product-truth/` is the authoritative planning source; planner must reconcile updates here first.
- UX DAG scenarios are tracked in `.sigee/dag/scenarios/`.
- Runtime DAG scenarios at `<runtime-root>/dag/scenarios/` are compiled artifacts only.
- `.sigee/templates/` is generated locally and intentionally excluded from git history.
- If report/evidence needs to be preserved, promote a summarized snapshot into `migrations/` or a release note rather than committing raw runtime output.
- Report snapshots for releases are tracked only under `.sigee/migrations/release-report-snapshots/`.

## Runtime Contract

- `.sigee` is the source of truth for governance and long-lived policy assets.
- Operational runtime root is `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`.
- Queue orchestration policy is documented in `.sigee/policies/orchestration-loop.md`.
- DAG mandatory test contract is documented in `.sigee/policies/product-truth-ssot.md`.
