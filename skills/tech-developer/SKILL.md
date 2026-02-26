---
name: tech-developer
description: Plan-driven implementation and verification workflow for approved technical plans. Use when the user asks to execute a plan file, deliver scoped production changes, or complete tasks with test and validation evidence. Focuses on controlled execution, no scope creep, and explicit completion reporting.
---

# Tech Developer

## Operating Mode
- Execute only against an approved plan or explicit scoped task.
- Operate in skill-only mode. Do not depend on `AGENTS.md`, multi-agent roles, or role-specific runtime config.
- Keep behavior aligned with existing architecture and repository conventions.
- Avoid scope expansion. Escalate ambiguities instead of guessing.
- Verify each completed task with concrete evidence.
- Use `.sigee` governance docs as the source of policy/template truth while keeping runtime execution compatibility with the configured runtime root (`${SIGEE_RUNTIME_ROOT:-.codex}`).

## Workflow
1. Intake:
   - locate and read the full plan file
   - enforce `<runtime-root>/plans/<plan-id>.md` path (`runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}`)
   - if no plan is provided, request one or call `$tech-planner`
   - if the plan depends on scientific/numerical method choice, require `$tech-scientist` evidence output before implementation
   - if `<runtime-root>/dag/scenarios/*.scenario.yml` exists, run DAG mode (`dag_build` + `dag_run`) as the default execution path
2. Break down work:
   - convert unchecked tasks into an execution queue
   - respect dependencies and safe parallel opportunities
3. Implement incrementally:
   - complete one logical unit at a time
   - keep edits minimal and scoped to plan intent
4. Verify each unit:
   - run the narrowest reliable checks first
   - run broader checks before final completion
   - when DAG mode is enabled, execute verification through DAG nodes (`tdd_red -> impl -> tdd_green -> smoke -> e2e`)
5. Update progress in the plan:
   - mark completed tasks
   - attach brief evidence notes where useful
6. Final report:
   - changed files
   - verification outcomes
   - unresolved risks or follow-up items
7. Generate execution artifacts:
   - evidence logs in `<runtime-root>/evidence/<plan-id>/`
   - final report in `<runtime-root>/reports/<plan-id>-report.md` when explicitly requested (`--write-report` or `report_generate.sh`)
8. Update dashboard (when report is generated):
   - `<runtime-root>/reports/index.md` summary table refreshed automatically

## Progress Tracking (Required)
- For non-trivial execution, call `update_plan` before editing code.
- Keep plan size between 4 and 8 steps.
- Allowed statuses:
  - `pending`
  - `in_progress`
  - `completed`
- Keep exactly one step as `in_progress` at a time.
- Update progress at every major milestone (preflight, queue classification, each execution wave, integration verification, final reporting).
- Before final response, mark all steps `completed`.

### Queue-Wide Step Design (Mandatory)
- This skill must process the full eligible queue, not a single picked task.
- Build plan steps by queue waves, not by a single item:
  1. preflight and policy guards
  2. queue snapshot and dependency grouping
  3. wave 1 execution (unblockers)
  4. wave 2 execution (parallelizable group)
  5. wave N execution (repeat while queue has remaining eligible tasks)
  6. integration and regression verification
  7. final report and traceability
- If queue size is large, group items into waves of 3-5 tasks and update `update_plan` after each wave completion.
- If failures occur, keep current wave as `in_progress`, report the blocker, and do not mark downstream waves as completed.

## Execution Rules
- Do not silently rewrite plan objectives.
- If implementation reveals a missing requirement, pause and ask for a decision.
- Prefer existing patterns over introducing new abstractions.
- Add or adjust tests when behavior changes.
- Never claim completion without running verification relevant to changed areas.
- Hard TDD mode is mandatory: do not use or propose non-strict/fast execution.
- Every task must include executable `Execute` and `Verification` commands.
- In DAG mode, do not skip `changed_paths` matching logic or dependency closure; use `--changed-only` for default iterative runs.
- Use `--only <node-id>` rerun mode for targeted failure recovery instead of ad-hoc command drift.

## User Communication Policy
- Explain implementation results in content-first language before traceability metadata.
- Start with:
  - what behavior changed
  - what users will notice
  - why the change is safe and how it was verified
- Provide long-form explanations for important changes, not one-line summaries.
- Keep IDs/paths/command traces in a separate traceability section at the end.
- When follow-up execution is needed, provide a copy-ready markdown fenced block titled `다음 실행 프롬프트` instead of a "next shell command" line.

## Response Order (Mandatory)
- Always structure final user-facing explanation in this order:
  1. Behavior and user impact (content-first narrative)
  2. Verification narrative (what was tested, what confidence this gives)
  3. Remaining risks or follow-up actions
  4. Traceability appendix (plan path, changed files, commands, evidence paths)
- Do not start the response with IDs, file paths, command logs, or task numbers.

## Verification Baseline
- Follow `references/execution-checklist.md`.
- Discover project verification commands directly from repository files (for example `package.json`, `Makefile`, `pyproject.toml`, CI configs) before using generic defaults.
- During migration, follow compatibility rules in `.sigee/migrations/runtime-path-compatibility-plan.md` before changing runtime paths.
- `scripts/plan_run.sh` automatically runs `.sigee` gitignore guard before execution to check/apply policy in project root.
- DAG-first execution flow (when scenarios exist):
  - `scripts/dag_build.sh --from <runtime-root>/dag/scenarios --out <runtime-root>/dag/pipelines/default.pipeline.yml`
  - `scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --dry-run`
  - `scripts/dag_run.sh <runtime-root>/dag/pipelines/default.pipeline.yml --changed-only`
- DAG gate wrappers:
  - smoke: `scripts/test_smoke.sh` (or node `smoke_gate`)
  - e2e: `scripts/test_e2e.sh` (or node `e2e_gate`)
- Use execution script:
  - `scripts/plan_run.sh <runtime-root>/plans/<plan-id>.md --mode strict`
  - add `--write-report` only when you want persistent report files
- Use single-entry flow:
  - `scripts/codex_flow.sh <runtime-root>/plans/<plan-id>.md --mode strict`
  - add `--write-report` only when you want persistent report files
- Use failure resume:
  - `scripts/plan_run.sh <runtime-root>/plans/<plan-id>.md --resume`
- Use report generator:
  - `scripts/report_generate.sh <runtime-root>/plans/<plan-id>.md`

## Output Contract
Return:
- long-form content summary (what changed, user impact, safety/verification rationale)
- verification narrative (coverage, sufficiency, residual uncertainty)
- remaining risks or follow-up actions
- task completion summary
- traceability appendix at the end:
  - plan path executed
  - DAG pipeline path and selected run mode (`--dry-run` / `--changed-only` / `--only`) when DAG mode is used
  - key files changed
  - exact verification commands and outcomes
- if additional execution is required:
  - include one copy-ready `다음 실행 프롬프트` markdown block
  - write natural-language task intent first, then concrete execution request

## References
- Execution gate: `references/execution-checklist.md`
- Final report format: `references/report-template.md`
- Execution runner: `scripts/plan_run.sh`
- Single-entry flow: `scripts/codex_flow.sh`
- Report generator: `scripts/report_generate.sh`
- Reports dashboard: `scripts/reports_index.sh`
- Gitignore guard: `../tech-planner/scripts/sigee_gitignore_guard.sh`
- Communication prompts: `references/communication-prompts.md`
- DAG workflow: `references/dag-workflow.md`
- TDD node contract: `references/tdd-node-contract.md`
- Test gates: `references/test-gates.md`
- Governance baseline: `.sigee/README.md`, `.sigee/policies/gitignore-policy.md`
- Compatibility guide: `.sigee/migrations/runtime-path-compatibility-plan.md`
