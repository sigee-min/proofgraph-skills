# Planning Checklist

Use this checklist before finalizing any plan.

- [ ] Plan file path is `<runtime-root>/plans/<plan-id>.md` (default: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`).
- [ ] `.sigee` gitignore guard has been applied to project root (`sigee_gitignore_guard.sh`).
- [ ] `.sigee/product-truth/` has been reviewed as the latest planning SSoT.
- [ ] In loop mode, `<runtime-root>/orchestration/queues/` auto-bootstrap is handled internally (no user script execution required).
- [ ] In loop mode, planner routing rule is explicit (`planner-inbox -> scientist-todo|developer-todo -> planner-review`).
- [ ] `다음 실행 프롬프트` is intent-only (no shell command, script path, or CLI flag exposure).
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
- [ ] Rollback path is documented.
- [ ] Next-step handoff target and routing reason are explicit.
