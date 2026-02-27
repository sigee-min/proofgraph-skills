# DAG Assets

- `schema/`: node and pipeline schema contracts
- `pipelines/`: executable pipeline definitions
- `scenarios/`: tracked UX DAG scenario source catalog (planner SSoT).
- Runtime scenarios under `<runtime-root>/dag/scenarios/` are compiled outputs from `.sigee/dag/scenarios/`.
- Mandatory per-scenario test contract: `unit_normal=2`, `unit_boundary=2`, `unit_failure=2`, `boundary_smoke=5`.
