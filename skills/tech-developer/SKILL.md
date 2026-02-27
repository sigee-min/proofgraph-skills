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
- Use `.sigee` governance docs as the source of policy/template truth with runtime root `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`.
- Execute through an explicit developer profile. If no profile hint is present, default to `generalist`.

## Developer Profiles (Mandatory)
- Supported profiles:
  - `generalist`
  - `backend-api`
  - `frontend-ui`
  - `data-engineering`
  - `infra-automation`
  - `refactoring-specialist`
- Profile selection order:
  1. Queue metadata hint in `next_action` (preferred), format `profile=<slug>` or `profile:<slug>`
  2. Queue metadata hint in `note`
  3. Plan/task explicit instruction text
  4. Fallback to `generalist`
- Profile contracts:
  - `generalist`: balanced implementation for mixed scope.
  - `backend-api`: API contracts, error semantics, backward compatibility, latency budgets.
  - `frontend-ui`: interaction correctness, accessibility, rendering regressions, state consistency.
  - `data-engineering`: schema evolution safety, idempotent pipelines, data quality guards.
  - `infra-automation`: reproducibility, rollback safety, environment drift prevention.
  - `refactoring-specialist`: aggressively remove residue paths (`A -> B -> C` detours, dead/stale/orphan code), but only with behavior-lock verification evidence.

## Workflow
1. Intake:
   - locate and read the full plan file
   - enforce `<runtime-root>/plans/<plan-id>.md` path (`runtime-root=${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`)
   - if no plan is provided, request one or call `$tech-planner`
   - if the plan depends on scientific/numerical method choice, require `$tech-scientist` evidence output before implementation
   - if `.sigee/dag/scenarios/*.scenario.yml` exists, prefer DAG mode (`dag_compile` -> `dag_build` + `dag_run`) before completion
   - inspect scenario scope via `../tech-planner/scripts/dag_scenario_crud.sh` (`list/show/summary`) from `.sigee/dag/scenarios` to keep execution context focused
   - if queue mode is enabled, claim work from `<runtime-root>/orchestration/queues/developer-todo.tsv` before execution (via queue helper flow)
   - queue mode 기본값은 "single ticket 처리 후 종료"가 아니라 "같은 호출에서 가능한 범위까지 queue drain"이다
   - resolve effective developer profile from queue metadata (`next_action`/`note`) and keep the selected profile in execution trace
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
   - queue handoff for planner review (`developer-todo -> planner-review`)
   - loop 상태와 무관하게 copy-ready `다음 실행 프롬프트` block을 planning review 목적으로 제공
   - 종료/의사결정 필요 상태에서는 다음 사이클 시작 또는 의사결정 해소를 요청하는 프롬프트를 제공
7. Generate execution artifacts:
   - evidence logs in `<runtime-root>/evidence/<plan-id>/`
   - final report in `<runtime-root>/reports/<plan-id>-report.md` only when explicitly requested
8. Update dashboard (when report is generated):
   - `<runtime-root>/reports/index.md` summary table refreshed automatically

## Queue Handoff Guardrails
- developer는 완료 항목을 `planner-review`까지만 이동한다.
- developer는 `done` 전이를 직접 수행하지 않는다.
- handoff 시 evidence 링크를 반드시 첨부한다 (planner done gate 입력값).
- lease는 queue helper가 자동으로 관리한다 (`claim` hold, review handoff release).
- queue lifecycle phase를 유지한다 (`planned -> ready -> running -> evidence_collected -> verified -> done`).
- 실패 시 `error_class`를 명시하고 `retry_budget` 내에서만 재시도한다.
- planner/developer 라우팅 시 profile 의도를 `next_action` 또는 `note`에 남긴다 (권장 형식: `profile=<slug>`).
- handoff 이후 `../tech-planner/scripts/orchestration_queue.sh loop-status --user-facing`를 내부 판정 기준으로 사용한다.
  - 작업 지속 가능 상태: planning review 라우팅 프롬프트 제공
  - 종료/의사결정 필요 상태: 종료 요약과 함께 다음 사이클 또는 결정 요청 프롬프트 제공

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

### Queue-Wide Step Design (When Queue Mode Is Active)
- Queue-wide wave execution is an orchestration-level contract.
- Queue mode defaults to continuous wave drain in one invocation:
  - continue `claim -> execute -> planner-review handoff` until queue is empty or a hard stop is reached
  - hard stops: `STOP_USER_CONFIRMATION`, retry budget exhaustion requiring planner decision, explicit scope ambiguity
- Build `update_plan` steps by queue waves:
  1. preflight and policy guards
  2. queue snapshot and dependency grouping
  3. wave 1 execution (unblockers)
  4. wave 2 execution (parallelizable group)
  5. wave N execution (repeat while queue has remaining eligible tasks)
  6. integration and regression verification
  7. final report and traceability
- If queue size is large, group items into waves of 3-5 tasks and update `update_plan` after each wave completion.
- If failures occur, keep current wave as `in_progress`, report the blocker, and do not mark downstream waves as completed.
- `plan_run.sh` and `codex_flow.sh` are plan-file execution primitives; queue claim/move automation must be handled by orchestration flow (for example `orchestration_queue.sh`) before/after these scripts.

## Execution Rules
- Do not silently rewrite plan objectives.
- If implementation reveals a missing requirement, pause and ask for a decision.
- Prefer existing patterns over introducing new abstractions.
- Add or adjust tests when behavior changes.
- Never claim completion without running verification relevant to changed areas.
- Hard TDD mode is mandatory: do not use or propose non-strict/fast execution.
- Every task must include executable `Execute` and `Verification` commands.
- In DAG mode, do not skip `changed_paths` matching logic or dependency closure; use `--changed-only` for default iterative runs.
- In changed-only mode, include global smoke/e2e gates only when broad regression is required (`--include-global-gates`).
- For controlled regression, provide explicit changed path inputs (`--changed-file <path>`).
- Use `--only <node-id>` rerun mode for targeted failure recovery instead of ad-hoc command drift.
- Mandatory DAG test contract must pass for each scenario:
  - `unit_normal_tests = 2`
  - `unit_boundary_tests = 2`
  - `unit_failure_tests = 2`
  - `boundary_smoke_tests = 5`
- `refactoring-specialist` profile 추가 규칙:
  - cleanup 전에 residue inventory를 만든다 (detour/dead/stale/orphan 분류).
  - behavior-lock test를 먼저 고정한 뒤 제거를 수행한다.
  - `A -> B -> C` 경로를 `A -> C`로 단축할 때 관측 가능한 동작 동일성을 검증 근거로 남긴다.
  - 삭제/정리 변경은 반드시 rollback 경로를 설명한다.

## User Communication Policy
- Explain implementation results in content-first language before traceability metadata.
- Start with:
  - what behavior changed
  - what users will notice
  - why the change is safe and how it was verified
- Provide long-form explanations for important changes, not one-line summaries.
- Treat orchestration internals as black box in default user responses.
  - do not expose queue names, gate labels, lease/state fields, or helper key-value logs unless explicitly requested
  - do not expose runtime path/config lines (for example `runtime-root=...`) in default user-facing prompts
- Keep IDs/paths/internal execution traces in a separate traceability section at the end, and omit that appendix by default unless requested.
- Never expose internal artifact names in default user mode:
  - queue names, ticket IDs, plan IDs, backlog/report file names, script file names
- Final response에서 `다음 실행 프롬프트`는 항상 제공한다.
- 루프 종료 상태에서는 내부 상태 키를 노출하지 말고, 종료 영향과 다음 사이클/의사결정 해소용 프롬프트를 제품 언어로 제공한다.
- `다음 실행 프롬프트` must be intent-only:
  - do not include shell command lines
  - do not include internal script paths
  - do not include CLI flags/options
  - do not include runtime path/config lines, queue names, or internal IDs

## Response Order (Mandatory)
- Always structure final user-facing explanation in this order:
  1. Behavior and user impact (content-first narrative)
  2. Verification narrative (what was tested, what confidence this gives)
  3. Remaining risks or follow-up actions
  4. Traceability appendix (plan path, changed files, evidence paths) - only when requested
- Do not start the response with IDs, file paths, command logs, or task numbers.

## Verification Baseline
- Follow `references/execution-checklist.md`.
- Discover project verification commands directly from repository files (for example `package.json`, `Makefile`, `pyproject.toml`, CI configs) before using generic defaults.
- `scripts/plan_run.sh` automatically runs `.sigee` gitignore guard before execution to check/apply policy in project root.
- DAG-first execution flow (when scenarios exist):
  - `scripts/dag_compile.sh --source .sigee/dag/scenarios --out <runtime-root>/dag/scenarios`
  - `scripts/dag_build.sh --from <runtime-root>/dag/scenarios --out <runtime-root>/dag/pipelines/default.pipeline.yml`
  - `dag_build.sh` hard-gates product-truth consistency via `../tech-planner/scripts/product_truth_validate.sh` (traceability IDs + mandatory test contract + scenario mapping)
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
- Script responsibility boundary:
  - `plan_run.sh` / `codex_flow.sh` execute one approved plan file end-to-end.
  - queue-wide iteration and routing (`developer-todo -> planner-review`) are orchestration responsibilities, not implicit script behavior.
- Use failure resume:
  - `scripts/plan_run.sh <runtime-root>/plans/<plan-id>.md --resume`
- Use report generator:
  - `scripts/report_generate.sh <runtime-root>/plans/<plan-id>.md`
- Use stress harness (scale validation):
  - `scripts/dag_stress.sh --pipeline-dir <runtime-root>/dag/pipelines --class all --run`

## Output Contract
Return:
- long-form content summary (what changed, user impact, safety/verification rationale)
- verification narrative (coverage, sufficiency, residual uncertainty)
- remaining risks or follow-up actions
- task completion summary
- traceability appendix at the end:
  - plan path executed
  - DAG pipeline path and selected execution mode (dry-run / changed-scope / targeted retry) when DAG mode is used
  - key files changed
  - verification outcomes in plain language (internal command details only when explicitly requested)
- include one copy-ready `다음 실행 프롬프트` markdown block:
  - default intent: planning review
  - if blocked, include required user decision and blocker evidence in the prompt intent
  - write natural-language task intent only (no shell command/script/flag exposure)
- in default user mode, report termination using product-impact language, not queue-state language.
- include selected developer profile and why it was chosen in traceability appendix.

## References
- Execution gate: `references/execution-checklist.md`
- Final report format: `references/report-template.md`
- Execution runner: `scripts/plan_run.sh`
- Single-entry flow: `scripts/codex_flow.sh`
- Report generator: `scripts/report_generate.sh`
- Scale harness: `scripts/dag_stress.sh`
- Dual-layer DAG regression: `scripts/dag_dual_layer_regression.sh`
- Reports dashboard: `scripts/reports_index.sh`
- DAG compiler: `scripts/dag_compile.sh`
- Gitignore guard: `../tech-planner/scripts/sigee_gitignore_guard.sh`
- Communication prompts: `references/communication-prompts.md`
- DAG workflow: `references/dag-workflow.md`
- Refactoring specialist playbook: `references/refactoring-specialist-playbook.md`
- TDD node contract: `references/tdd-node-contract.md`
- Test gates: `references/test-gates.md`
- Governance baseline: `.sigee/README.md`, `.sigee/policies/gitignore-policy.md`
- Product-truth policy: `.sigee/policies/product-truth-ssot.md`, `.sigee/product-truth/README.md`
- Orchestration policy: `.sigee/policies/orchestration-loop.md`
- Queue runtime helper: `../tech-planner/scripts/orchestration_queue.sh` (`loop-status --user-facing`, `next-prompt --user-facing`)
- DAG scenario CRUD helper: `../tech-planner/scripts/dag_scenario_crud.sh`
