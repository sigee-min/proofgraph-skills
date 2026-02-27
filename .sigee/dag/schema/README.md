# DAG Schema

Define node fields:
- id
- type
- deps
- run
- verify

Scenario contract also requires:
- `outcome_id`, `capability_id`, `linked_nodes`
- `unit_normal_tests` (2), `unit_boundary_tests` (2), `unit_failure_tests` (2), `boundary_smoke_tests` (5)

Source/Runtime split:
- Source scenarios: `.sigee/dag/scenarios/`
- Runtime scenarios: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}/dag/scenarios/` (compiled only)
