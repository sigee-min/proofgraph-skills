# GitIgnore Policy For .sigee

This policy separates repository knowledge from runtime output.

## Tracked (must commit)

- `.sigee/README.md`
- `.sigee/policies/**`
- `.sigee/templates/**`
- `.sigee/scenarios/**`
- `.sigee/dag/schema/**`
- `.sigee/dag/pipelines/**`
- `.sigee/migrations/**`

## Ignored (must not commit by default)

- `.sigee/runtime/**`
- `.sigee/tmp/**`
- `.sigee/locks/**`
- `.sigee/evidence/**`
- `.sigee/reports/**`

## Decision Resolution (Applied)

- `.sigee/reports/**`: ignored by default.
  - Release snapshots are tracked only when curated under `.sigee/migrations/release-report-snapshots/`.
- `.sigee/evidence/**`: always ignored.
  - If incident evidence must be retained, attach summarized outputs to tracked migration/release docs instead of committing raw logs.

## Rule Design Notes

- Add explicit allow-list exceptions (`!`) for policy/template/scenario/DAG paths.
- Keep runtime directories blocked even when nested files are generated.
- Promote only curated snapshots, not raw logs.

## Required .gitignore Signals

The root `.gitignore` must contain both:

1. Ignore paths:
- `.sigee/runtime/`
- `.sigee/tmp/`
- `.sigee/locks/`
- `.sigee/evidence/`
- `.sigee/reports/`

2. Allow-list paths:
- `!.sigee/README.md`
- `!.sigee/policies/`
- `!.sigee/templates/`
- `!.sigee/scenarios/`
- `!.sigee/dag/schema/`
- `!.sigee/dag/pipelines/`
