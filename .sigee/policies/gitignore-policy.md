# GitIgnore Policy For .sigee

This policy separates repository knowledge from runtime output.
It follows a deny-by-default model for `.sigee` to keep git history clean.

## Tracked (must commit)

- `.sigee/README.md`
- `.sigee/policies/**`
- `.sigee/product-truth/**`
- `.sigee/scenarios/**`
- `.sigee/dag/`
- `.sigee/dag/schema/**`
- `.sigee/dag/pipelines/**`
- `.sigee/dag/scenarios/**`
- `.sigee/migrations/`
- `.sigee/migrations/**`

## Ignored (must not commit by default)

- `.sigee/templates/**`
- `.sigee/.runtime/**`
  - includes queue runtime data and done archives (`.sigee/.runtime/orchestration/archive/**`)
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

- Ignore `.sigee/*` by default, then allow-list only governed assets.
- Add explicit allow-list exceptions (`!`) only for governance paths (README, policies, product-truth, scenarios, DAG, migrations).
- Keep runtime directories blocked even when nested files are generated.
- Promote only curated snapshots, not raw logs.

## Required .gitignore Signals

The root `.gitignore` must contain both:

1. Ignore paths:
- `.sigee/*`
- `.sigee/templates/`
- `.sigee/.runtime/`
- `.sigee/tmp/`
- `.sigee/locks/`
- `.sigee/evidence/`
- `.sigee/reports/`

2. Allow-list paths:
- `!.sigee/README.md`
- `!.sigee/policies/`
- `!.sigee/product-truth/`
- `!.sigee/scenarios/`
- `!.sigee/dag/`
- `!.sigee/dag/schema/`
- `!.sigee/dag/pipelines/`
- `!.sigee/dag/scenarios/`
- `!.sigee/migrations/`
