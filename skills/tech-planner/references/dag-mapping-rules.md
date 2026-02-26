# Scenario -> DAG Mapping Rules

## Core Mapping
- scenario id `X` maps to nodes:
  - `X_red` (TDD red)
  - `X_impl` (impl)
  - `X_green` (green)
- smoke/e2e gates are shared terminal nodes.

## Dependency Rules
- `X_impl` depends on `X_red`
- `X_green` depends on `X_impl`
- smoke depends on all `*_green`
- e2e depends on smoke
- explicit scenario `depends on` injects upstream dependencies between scenario chains

## Validation Rules
- all nodes require run+verify
- scenario fields `id`, `changed_paths`, `red_run`, `impl_run`, `green_run`, `verify` are mandatory
- `red_run`, `impl_run`, `green_run` must be executable commands; no-op values (`true`, `:`) are invalid
- `verify` must be an executable command; no-op values (`true`, `:`) are invalid
- changed_paths must exist for changed-only execution
- use stable ids for rerun targeting
