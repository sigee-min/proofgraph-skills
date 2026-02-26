# .sigee Workspace Contract

`.sigee` is the governance root for shared planning, template, and migration assets.

## Directory Policy

| Path | Policy | Notes |
| --- | --- | --- |
| `.sigee/README.md` | Tracked | Entry point for new contributors |
| `.sigee/policies/` | Tracked | Normative operating policy and prompt contracts |
| `.sigee/templates/` | Tracked | Reusable ticket/ops/handoff/board templates |
| `.sigee/scenarios/` | Tracked | Scenario catalog used by planner |
| `.sigee/dag/schema/` | Tracked | DAG schema and node contracts |
| `.sigee/dag/pipelines/` | Tracked | Baseline pipeline definitions |
| `.sigee/migrations/` | Tracked | Migration maps and cutover playbooks |
| `.sigee/runtime/` | Ignored | Local runtime state |
| `.sigee/tmp/` | Ignored | Temporary artifacts |
| `.sigee/locks/` | Ignored | Lease/lock runtime files |
| `.sigee/evidence/` | Ignored | Local execution logs and transient evidence |
| `.sigee/reports/` | Ignored by default | Report snapshots are promoted manually |

## Tracked vs Ignored Rules

- Tracked content is team knowledge and must be committed.
- Ignored content is machine- or run-specific and must not be committed by default.
- If report/evidence needs to be preserved, promote a summarized snapshot into `migrations/` or a release note rather than committing raw runtime output.
- Report snapshots for releases are tracked only under `.sigee/migrations/release-report-snapshots/`.

## Runtime Path Compatibility

- `.sigee` is the source of truth for governance and long-lived policy assets.
- Operational runtime paths can remain on a legacy execution root during migration.
- Compatibility phases and cutover policy are documented in `.sigee/migrations/runtime-path-compatibility-plan.md`.
