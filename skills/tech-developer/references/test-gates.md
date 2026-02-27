# Test Gate Wrappers

## smoke
- Wrapper: `skills/tech-developer/scripts/test_smoke.sh`
- Purpose: fast product smoke confidence gate
- Modes:
  - `product` (default): run product smoke command
  - `framework`: run framework regression checks
- Hard gate (product mode): fails when no executable smoke command is configured
- Command source priority (product mode): `--cmd` > `SIGEE_SMOKE_CMD` > `package.json` script `smoke` > `Makefile` target `smoke`
- Framework checks: run with `--mode framework` (or `self_check.sh`)
- Mandatory before gate: each scenario must pass `boundary_smoke_tests` 5/5 in DAG nodes (`*_smoke_boundary_1..5`)

## e2e
- Wrapper: `skills/tech-developer/scripts/test_e2e.sh`
- Purpose: high-level product flow validation gate
- Modes:
  - `product` (default): run product e2e command
  - `framework`: run framework regression checks
- Hard gate (product mode): fails when no executable e2e command is configured
- Command source priority (product mode): `--cmd` > `SIGEE_E2E_CMD` > `package.json` script `e2e` > `Makefile` target `e2e`
- Framework checks: run with `--mode framework` (or `self_check.sh`)

Both wrappers support `--dry-run`. `--self-check` is a backward-compatible alias for framework mode.

## Self-Check Mode
- Wrapper: `skills/tech-developer/scripts/self_check.sh`
- Purpose: run framework internal regressions separately from default product validation loops.
- Scope:
  - `--scope smoke`
  - `--scope e2e`
  - `--scope all` (default)

## Scale Harness
- Wrapper: `skills/tech-developer/scripts/dag_stress.sh`
- Purpose: synthetic DAG stress validation (`50`, `200`, `500` node classes)
- Budget gate: optional regression threshold check via `--budget-regression-pct` (+ `--baseline`)

## Refactoring Specialist Gate
- Mandatory when profile is `refactoring-specialist`:
  - behavior-lock tests must run before cleanup implementation.
  - at least one boundary/failure test must cover removed detour path behavior.
  - regression gate must prove no externally visible behavior drift.
