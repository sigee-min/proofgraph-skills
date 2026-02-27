# Product Truth SSoT Policy

## Purpose
- Keep planning intent non-contradictory, current, and executable.
- Make planner/developer/scientist consume one source of truth before queue execution.

## Authoritative Source
- `.sigee/product-truth/vision.yaml`
- `.sigee/product-truth/pillars.yaml`
- `.sigee/product-truth/objectives.yaml`
- `.sigee/product-truth/outcomes.yaml`
- `.sigee/product-truth/capabilities.yaml`
- `.sigee/product-truth/traceability.yaml`
- `.sigee/product-truth/core-overrides.yaml`

## Linkage Contract
- `vision_id -> pillar_id -> objective_id -> outcome_id -> capability_id -> scenario_id -> dag_node_prefix` must be explicit.
- Source scenario files under `.sigee/dag/scenarios/` must include:
  - `outcome_id`
  - `capability_id`
  - `stability_layer` (`core|system|experimental`)
  - mandatory test bundles (`2/2/2 + smoke 5`)
- Runtime scenario files under `<runtime-root>/dag/scenarios/` are compiled artifacts and must not be hand-edited.
- Runtime-only scenario catalog is invalid for completion gates; source catalog under `.sigee/dag/scenarios/` is mandatory.
- Scenario catalog interaction must prefer CRUD interface script:
  - `skills/tech-planner/scripts/dag_scenario_crud.sh`
- Automated semantic validation gate:
  - `skills/tech-planner/scripts/product_truth_validate.sh`
  - enforced by planner/developer flows (`plan_lint.sh`, `dag_build.sh`, `dag_scenario_crud.sh validate`)

## Mandatory Test Contract
- Per scenario:
  - `unit_normal_tests`: exactly 2
  - `unit_boundary_tests`: exactly 2
  - `unit_failure_tests`: exactly 2
  - `boundary_smoke_tests`: exactly 5
- Any mismatch blocks DAG build/execution.

## Ownership
- Planner owns intent updates and contradiction resolution.
- Scientist/developer can propose changes, but planner review is required before truth update.
- Protected `core` layer changes require planner-approved override with expiration metadata.

## Freshness
- `revision` increments on approved intent changes.
- `updated_at` is required in UTC.
- Planner-review gate confirms freshness before `done`.

## Bootstrap Starter Guard (Hard)
- Preflight bootstrap starter ids are allowed only for initial scaffold creation:
  - `VIS-BOOT-*`, `PIL-BOOT-*`, `OBJ-BOOT-*`, `OUT-BOOT-*`, `CAP-BOOT-*`, `bootstrap_foundation_*`
- Starter scaffold is not production intent and must be replaced before first `planner-review -> done`.
- Any done/release flow with starter scaffold remaining is policy violation and must be blocked.
