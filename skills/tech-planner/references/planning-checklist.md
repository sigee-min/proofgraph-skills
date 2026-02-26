# Planning Checklist

Use this checklist before finalizing any plan.

- [ ] Plan file path is `<runtime-root>/plans/<plan-id>.md` (default: `${SIGEE_RUNTIME_ROOT:-.codex}`).
- [ ] `.sigee` gitignore guard has been applied to project root (`sigee_gitignore_guard.sh`).
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
- [ ] Rollback path is documented.
- [ ] Next-step handoff to implementation is explicit.
