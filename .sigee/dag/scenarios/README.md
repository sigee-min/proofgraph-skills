# UX DAG Scenarios (SSoT)

- This directory is the tracked source of truth for planning-grade DAG scenarios.
- Planner updates happen here first.
- Runtime scenarios under `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}/dag/scenarios/` are compiled artifacts only.
- Do not hand-edit runtime scenario files.
- Each scenario must declare `stability_layer: core|system|experimental`.
- `core` layer scenarios are protected by governance layer guard.

## Compile Path

1. Source (`.sigee/dag/scenarios/*.scenario.yml`)
2. Compile (`skills/tech-developer/scripts/dag_compile.sh`)
3. Runtime (`${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}/dag/scenarios/*.scenario.yml`)
4. Pipeline build/run (`dag_build.sh` -> `dag_run.sh`)
