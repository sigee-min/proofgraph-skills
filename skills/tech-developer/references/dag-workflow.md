# DAG Workflow

## Commands
- Build pipeline:
  - `skills/tech-developer/scripts/dag_build.sh --from <runtime-root>/dag/scenarios --out <runtime-root>/dag/pipelines/default.pipeline.yml`
- Dry run:
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --dry-run`
- Changed-only run:
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --changed-only`

## Rerun
- Single node (with dependency closure):
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --only <node-id>`

## Hard TDD Requirements
- At least one scenario file must exist under `<runtime-root>/dag/scenarios/`.
- Each scenario must define `id`, `changed_paths`, `red_run`, `impl_run`, `green_run`, `verify`.
- `red_run`, `impl_run`, `green_run`, `verify` cannot be no-op values (`true`, `:`).
