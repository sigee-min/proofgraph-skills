# Execution Checklist

Apply this checklist while executing each plan.

## Before Coding
- [ ] Plan path is `<runtime-root>/plans/<plan-id>.md` (default: `${SIGEE_RUNTIME_ROOT:-.codex}`).
- [ ] `.sigee` gitignore guard has been applied to project root (`sigee_gitignore_guard.sh`).
- [ ] Plan/task scope is clear.
- [ ] Target files are identified.
- [ ] Dependency and side-effect risk is understood.

## During Implementation
- [ ] Changes stay within scope.
- [ ] Existing code patterns are followed.
- [ ] Tests are added or updated for behavior changes.

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
