# Scenario -> DAG Mapping Rules

## Core Mapping
- scenario id `X` maps to nodes:
  - `X_red` (TDD red)
  - `X_impl` (impl)
  - `X_unit_normal_1..2`
  - `X_unit_boundary_1..2`
  - `X_unit_failure_1..2`
  - `X_green` (green)
  - `X_smoke_boundary_1..5`
- smoke/e2e gates are shared terminal nodes.
- changed-only mode may exclude shared global smoke/e2e gates by default to avoid whole-graph fan-in collapse; include them explicitly when needed.

## Dependency Rules
- `X_impl` depends on `X_red`
- `X_unit_normal_*`, `X_unit_boundary_*`, `X_unit_failure_*` depend on `X_impl`
- `X_green` depends on `X_impl` and all `X_unit_*` nodes
- `X_smoke_boundary_*` depend on `X_green` and linked scenario `*_green` nodes
- smoke depends on all `*_smoke_boundary_*`
- e2e depends on smoke
- explicit scenario `depends on` injects upstream dependencies between scenario chains

## Validation Rules
- all nodes require `run`; scenario-chain nodes require executable `verify`
- scenario fields `id`, `outcome_id`, `capability_id`, `changed_paths`, `red_run`, `impl_run`, `green_run`, `verify`, `linked_nodes` are mandatory
- test fields `unit_normal_tests`, `unit_boundary_tests`, `unit_failure_tests`, `boundary_smoke_tests` are mandatory
- exact test counts are mandatory:
  - `unit_normal_tests = 2`
  - `unit_boundary_tests = 2`
  - `unit_failure_tests = 2`
  - `boundary_smoke_tests = 5`
- `red_run`, `impl_run`, `green_run` must be executable commands; no-op values (`true`, `:`) are invalid
- scenario `verify` must be an executable command; no-op values (`true`, `:`) are invalid
- generated helper nodes (`unit_*`, `smoke_boundary`, shared gates) may use `verify: true` wrapper semantics
- changed_paths must exist for changed-only execution
- use stable ids for rerun targeting
