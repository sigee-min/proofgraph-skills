# Planning Checklist

Use this checklist before finalizing any plan.

- [ ] Plan file path is `<runtime-root>/plans/<plan-id>.md` (default: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`).
- [ ] Planner preflight was executed: `scripts/orchestration_queue.sh init --project-root <project-root>` internally (idempotent).
- [ ] `<runtime-root>/` exists before drafting or linting the plan.
- [ ] Source scenario catalog exists at `.sigee/dag/scenarios/` for scenario-driven flow; runtime-only catalog is treated as invalid.
- [ ] `.sigee` gitignore guard has been applied to project root (`sigee_gitignore_guard.sh`).
- [ ] `.sigee/product-truth/` has been reviewed as the latest planning SSoT.
- [ ] Goal hierarchy files are consistent (`vision.yaml`, `pillars.yaml`, `objectives.yaml`, `outcomes.yaml`, `capabilities.yaml`, `traceability.yaml`).
- [ ] `goal_governance_validate --strict` is included as a mandatory governance gate when scenario catalog exists.
- [ ] Change impact gate has been run for the current change set when product-truth/DAG scenarios are touched.
- [ ] Queue/runtime bootstrap is handled internally by the planner skill (no user script execution required).
- [ ] Bootstrap starter scaffold (`VIS-BOOT-*`, `PIL-BOOT-*`, `OBJ-BOOT-*`, `OUT-BOOT-*`, `CAP-BOOT-*`, `bootstrap_foundation_*`) is fully replaced before `planner-review -> done`.
- [ ] In loop mode, planner routing rule is explicit (`planner-inbox -> scientist-todo|developer-todo -> planner-review`).
- [ ] Single-entry rule is explicit: scientist/developer direct execution without planner-routed context is blocked.
- [ ] Default response order is fixed (`제품 변화/영향 -> 검증 신뢰 -> 잔여 리스크`).
- [ ] Final response ends with exactly one `다음 실행 프롬프트` block.
- [ ] `다음 실행 프롬프트` is intent-only (no shell command, script path, or CLI flag exposure).
- [ ] `다음 실행 프롬프트` does not leak runtime path/config, queue names, or internal IDs.
- [ ] `다음 실행 프롬프트` target matches routing reason:
  - unresolved scientific/numerical/simulation/AI uncertainty -> `$tech-scientist`
  - implementation-ready -> `$tech-developer`
- [ ] PlanSpec v2 exists with `id`, `owner`, `risk`, `mode: strict`, `verify_commands`, `done_definition`.
- [ ] Objective is explicit and testable.
- [ ] Scope IN and OUT are both documented.
- [ ] Every task has concrete targets (files/dirs).
- [ ] Every task has measurable acceptance criteria.
- [ ] Every task has an executable `Execute: \`<command>\``.
- [ ] Every task has an executable `Verification: \`<command>\``.
- [ ] No task uses no-op commands (`true`, `:`) for `Execute` or `Verification`.
- [ ] Waves are dependency-aware and maximize safe parallelism.
- [ ] Risky assumptions are either resolved or surfaced as decisions.
- [ ] Final verification includes functional and regression checks.
- [ ] DAG scenario contracts include mandatory test counts (`unit_normal=2`, `unit_boundary=2`, `unit_failure=2`, `boundary_smoke=5`).
- [ ] DAG scenarios declare `stability_layer` (`core|system|experimental`) and protected-layer policy is respected.
- [ ] Rollback path is documented.
- [ ] Next-step handoff target and routing reason are explicit.
