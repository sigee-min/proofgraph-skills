# Execution Checklist

Apply this checklist while executing each plan.

## Before Coding
- [ ] Plan path is `<runtime-root>/plans/<plan-id>.md` (default: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`).
- [ ] `.sigee` gitignore guard has been applied to project root (`sigee_gitignore_guard.sh`).
- [ ] If queue mode is active, task was claimed from `developer-todo` queue before implementation.
- [ ] If queue mode is active, processing follows queue-drain contract in the same invocation until hard stop or empty queue.
- [ ] Effective developer profile is selected and recorded (`profile=<slug>` metadata or `generalist` fallback).
- [ ] Plan/task scope is clear.
- [ ] Target files are identified.
- [ ] Dependency and side-effect risk is understood.
- [ ] DAG scenario contract is valid (`unit_normal=2`, `unit_boundary=2`, `unit_failure=2`, `boundary_smoke=5`).
- [ ] DAG source scenarios are maintained in `.sigee/dag/scenarios/` and runtime scenarios are compiler-generated.
- [ ] Runtime DAG drift check passed before `dag_run`.

## During Implementation
- [ ] Changes stay within scope.
- [ ] Existing code patterns are followed.
- [ ] Tests are added or updated for behavior changes.
- [ ] If profile is `refactoring-specialist`, residue inventory is documented before deletion.
- [ ] If profile is `refactoring-specialist`, behavior-lock tests are fixed before cleanup.

## Verification Order
1. Targeted checks for changed module/service.
2. Lint or static analysis for changed language stack.
3. Type checks/build checks where applicable.
4. Relevant test suite (or targeted tests if full suite is too heavy).

## Completion Gate
- [ ] Verification commands passed or documented with blocker reason.
- [ ] Plan progress updated.
- [ ] No hidden TODOs or placeholders left in changed code.
- [ ] Evidence logs are saved in `<runtime-root>/evidence/<plan-id>/`.
- [ ] Final summary prepared with evidence.
- [ ] In loop mode, completion was handed back to `planner-review` (not `done` directly).
- [ ] Mandatory boundary smoke bundle (5 tests) passed for linked scenarios.
- [ ] Final response always includes one `다음 실행 프롬프트` block for `$tech-planner`.
- [ ] `다음 실행 프롬프트` is intent-only (no shell/script/flag exposure).
- [ ] Traceability includes selected profile and profile-specific safety rationale.
