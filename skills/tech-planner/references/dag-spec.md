# DAG Spec

## Required Pipeline Fields
- pipeline id
- node id
- node type
- deps
- run
- verify
- changed-only selection signal (`changed_paths`)

## Node Field Semantics
- `id`: stable unique key
- `type`: execution lane classification
- `deps`: predecessors that must pass first
- `run`: command run in repo root
- `verify`: post-run check
- `changed_paths`: impacts matching for changed-only mode
- `stability_layer`: governance layer classification (`core|system|experimental`)

## Validation Expectations
- unknown deps are invalid
- cycles are invalid
- run/verify must be non-empty
- source/runtime split is required:
  - source: `.sigee/dag/scenarios/`
  - runtime compiled: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}/dag/scenarios/`
- layer guard expectations:
  - `core` changes must pass protected-layer guard
  - `system` and `experimental` changes follow normal impact gate rules
- test contract is mandatory per scenario:
  - `unit_normal_tests` exactly 2
  - `unit_boundary_tests` exactly 2
  - `unit_failure_tests` exactly 2
  - `boundary_smoke_tests` exactly 5
