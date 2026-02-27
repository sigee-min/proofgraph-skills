# DAG Workflow

## Commands
- Scenario catalog interaction (recommended for large DAG context):
  - `skills/tech-planner/scripts/dag_scenario_crud.sh list --from .sigee/dag/scenarios`
  - `skills/tech-planner/scripts/dag_scenario_crud.sh summary --from .sigee/dag/scenarios --id <scenario-id>`
  - `skills/tech-planner/scripts/dag_scenario_crud.sh validate --from .sigee/dag/scenarios`
- Compile source scenarios to runtime:
  - `skills/tech-developer/scripts/dag_compile.sh --source .sigee/dag/scenarios --out <runtime-root>/dag/scenarios`
- Build pipeline:
  - `skills/tech-developer/scripts/dag_build.sh --from <runtime-root>/dag/scenarios --out <runtime-root>/dag/pipelines/default.pipeline.yml`
  - Optional protected-layer guard:
    - `skills/tech-developer/scripts/dag_build.sh --from <runtime-root>/dag/scenarios --out <runtime-root>/dag/pipelines/default.pipeline.yml --enforce-layer-guard`
- Dry run:
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --dry-run`
- Changed-only run:
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --changed-only`
  - For controlled regression scope, pass explicit change set:
    - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --changed-only --changed-file <path>`
  - Include shared smoke/e2e gates only when needed:
    - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --changed-only --include-global-gates`
- Stress validation (synthetic scale classes):
  - `skills/tech-developer/scripts/dag_stress.sh --pipeline-dir <runtime-root>/dag/pipelines --class all --run`
- Dual-layer regression:
  - `skills/tech-developer/scripts/dag_dual_layer_regression.sh`
- Framework self-check (separate from product default gates):
  - `skills/tech-developer/scripts/self_check.sh --scope all`
- Governance + impact gates:
  - `skills/tech-planner/scripts/goal_governance_validate.sh --project-root . --strict --require-scenarios`
  - `skills/tech-planner/scripts/change_impact_gate.sh --project-root . --base-ref HEAD~1 --head-ref HEAD --format markdown --emit-required-verification`

## Rerun
- Single node (with dependency closure):
  - `skills/tech-developer/scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --only <node-id>`

## Observability Artifacts
- `dag_run.sh` writes machine-readable artifacts per run under `<runtime-root>/evidence/dag/<pipeline-id>-<run-id>/`:
  - `run-summary.json`
  - `trace.jsonl`
  - `dag.mmd`
- State pointer remains at `<runtime-root>/dag/state/last-run.json`.

## Hard TDD Requirements
- At least one source scenario file must exist under `.sigee/dag/scenarios/`.
- Runtime scenario files under `<runtime-root>/dag/scenarios/` must come from compiler output and pass drift checks.
- Each scenario must define `id`, `outcome_id`, `capability_id`, `changed_paths`, `linked_nodes`, `red_run`, `impl_run`, `green_run`, `verify`.
- Each scenario must define `stability_layer` (`core|system|experimental`).
- Each scenario must define test bundles:
  - `unit_normal_tests` (exactly 2)
  - `unit_boundary_tests` (exactly 2)
  - `unit_failure_tests` (exactly 2)
  - `boundary_smoke_tests` (exactly 5)
- scenario `red_run`, `impl_run`, `green_run`, `verify` cannot be no-op values (`true`, `:`).
- generated helper nodes (`unit_*`, `smoke_boundary`, shared gates) may use wrapper-level `verify: true`.

## Profile Scenario Guidance
- Keep at least one scenario for profile-specialized cleanup (`refactoring-specialist`) in the catalog.
- Profile scenario should assert:
  - residue detection coverage,
  - behavior-lock tests before cleanup,
  - cleanup regression proof,
  - planner-review handoff readiness.
