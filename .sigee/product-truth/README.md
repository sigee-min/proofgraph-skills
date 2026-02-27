# Product Truth SSoT

This folder is the single source of truth for planning intent.

## Files
- `vision.yaml`: product vision (top-level direction)
- `pillars.yaml`: long-lived strategic pillars under vision
- `objectives.yaml`: delivery objectives under pillars
- `outcomes.yaml`: final product outcomes (what must be true when delivered)
- `capabilities.yaml`: user-visible capabilities required to realize outcomes
- `traceability.yaml`: enforced links between outcome/capability/scenario/DAG node set
- `core-overrides.yaml`: time-bounded overrides for protected `core` layer changes

## Authority Rules
- Planner must update this folder before generating or revising execution plans.
- Developer and scientist consume this data; they do not redefine outcome/capability intent.
- If scenario/DAG work conflicts with this folder, execution is blocked until planner resolves it.

## Contradiction Rules
- Every pillar must reference exactly one existing `vision_id`.
- Every objective must reference exactly one existing `pillar_id`.
- Every outcome must reference exactly one existing `objective_id`.
- Every capability must reference exactly one existing `outcome_id`.
- Every scenario must map to exactly one existing `capability_id` and one `outcome_id`.
- `traceability.yaml` links must be unique by `scenario_id`.
- Each `traceability` link and scenario must define `stability_layer` in `{core, system, experimental}`.
- `core` layer changes require an active, non-expired override entry in `core-overrides.yaml` when layer guard is enforced.
- Required test contract is fixed:
  - `unit_normal = 2`
  - `unit_boundary = 2`
  - `unit_failure = 2`
  - `boundary_smoke = 5`

## Freshness Rules
- `revision` must increase on every approved intent change.
- `updated_at` must be set in UTC (`YYYY-MM-DDTHH:MM:SSZ`).
- Planner review owns final freshness approval.
