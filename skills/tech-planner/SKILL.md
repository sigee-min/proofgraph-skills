---
name: tech-planner
description: Evidence-backed technical planning for complex implementation work. Use when requirements are ambiguous, when scope boundaries must be clarified, or when a user asks for a detailed execution plan before coding. Produces executable markdown plans with measurable acceptance criteria, verification steps, and explicit in-scope/out-of-scope boundaries.
---

# Tech Planner

## Operating Mode
- Act as a planner first. Do not implement production code while planning.
- Operate in skill-only mode. Do not depend on `AGENTS.md`, multi-agent roles, or role-specific runtime config.
- Resolve ambiguity early through targeted questions.
- Produce one execution-ready plan document unless the user explicitly requests multiple plans.
- Keep plans concrete enough that an implementation agent can execute with minimal guesswork.
- Treat `.sigee` governance documents as the default policy reference for workflow rules, templates, and runtime orchestration decisions.

## Workflow
1. Classify the request: trivial, feature, refactor, architecture, or research.
2. Gather context from local code and relevant docs before proposing structure.
   - if the task requires complex simulation/numerical/scientific reasoning, request a `$tech-scientist` package first (problem formulation + evidence matrix + pseudocode + validation plan)
   - treat `.sigee/product-truth/` as planning SSoT and reconcile outcome/capability/scenario links before drafting execution waves
3. Interview for missing constraints:
   - business objective
   - scope IN/OUT
   - technical constraints
   - testing and verification expectations
   - rollout and rollback expectations
4. Select a plan path:
   - use `<runtime-root>/plans/<plan-id>.md` (required, default runtime root is `.sigee/.runtime`)
   - align policy/template assumptions with `.sigee` governance docs
   - for scenario-driven delivery, define `<runtime-root>/dag/scenarios/<scenario-id>.scenario.yml` and map `red/impl/green/smoke/e2e` gates
   - for scenario CRUD/inspection, prefer `scripts/dag_scenario_crud.sh` (`list/show/summary/create/set/validate`) instead of direct bulk file reads
5. Write the plan using the required template in `references/plan-template.md`.
   - enforce `mode: strict` (hard TDD baseline)
6. Run the quality gate in `references/planning-checklist.md`.
7. Run lint:
   - `scripts/plan_lint.sh <runtime-root>/plans/<plan-id>.md`
   - this automatically runs `scripts/sigee_gitignore_guard.sh <project-root>` to check/apply `.sigee` gitignore policy
   - this also runs `scripts/product_truth_validate.sh` to enforce product-truth cross-reference consistency (`outcomes/capabilities/traceability` and scenario linkage when present)
8. End with a clear handoff prompt for the selected route target (`$tech-scientist` or `$tech-developer`):
   - always provide a copy-ready markdown fenced block (` ```md `) titled `다음 실행 프롬프트`
   - handoff prompt must be intent-first and no-CLI:
     - do not include shell commands, script paths, or CLI flags
   - route-target selection is mandatory:
     - if unresolved scientific/numerical/simulation/AI method uncertainty exists (or required research evidence is missing), hand off to `$tech-scientist` first
     - hand off to `$tech-developer` only when implementation-ready and scientific uncertainty is resolved
   - scientist-first handoff prompt:
     - ask `$tech-scientist` for a project-ready evidence package (problem formulation + literature matrix + pseudocode + validation plan)
     - require return to planner-review with evidence links and confidence
   - developer handoff prompt:
     - DAG-first (when scenario DAG is defined): ask `$tech-developer` to execute the strict DAG workflow internally (build -> dry-run -> changed-only)
     - fallback (non-DAG plan): ask `$tech-developer` to execute the approved plan in strict mode internally
   - include report persistence only when the user explicitly requests it.

## Planner Orchestration Loop (Mandatory)
- Planner is the only orchestrator in loop mode.
- Queue root: `<runtime-root>/orchestration/queues/`.
- Standard queues:
  - `planner-inbox`
  - `scientist-todo`
  - `developer-todo`
  - `planner-review`
  - `blocked`
  - `done`
- Routing rules:
  - unresolved scientific/mathematical method choice -> `scientist-todo`
  - implementation-ready item -> `developer-todo`
  - scientist/developer completion -> `planner-review` (with evidence links)
  - planner review outcome -> `done` or requeue (`scientist-todo` / `developer-todo`)
- Done archive rules:
  - `done` 전이는 완료 즉시 `<runtime-root>/orchestration/archive/done-YYYY-MM.tsv`로 기록한다.
  - `done` 큐는 장기 누적 저장소로 사용하지 않는다.
- Done gate enforcement (queue helper internal rule):
  - `done` is allowed only for `planner-review -> done`
  - run done transition under planner actor (`SIGEE_QUEUE_ACTOR=tech-planner` or `--actor tech-planner`)
  - require non-empty `evidence_links`
  - require passing evidence gate (`verification-results.tsv` PASS-only or `dag/state/last-run.json` PASS)
  - if scenario catalog exists, require `product_truth_validate` pass before done
- Stop conditions are mandatory:
  - max cycle cap
  - 2 consecutive no-progress cycles
  - mandatory test contract failure that requires re-planning
  - external decision required (`blocked`)
- Queue runtime bootstrapping is internal:
  - if queue or template assets are missing, run `scripts/orchestration_queue.sh` internally to auto-bootstrap
  - archive maintenance on user request is internal:
    - check/flush/clear via `scripts/orchestration_archive.sh`
  - never ask the user to execute queue scripts directly

## Progress Tracking (Required)
- For non-trivial planning work (2+ meaningful steps), call `update_plan` before deep work starts.
- Keep plan size between 3 and 7 steps.
- Allowed statuses:
  - `pending`
  - `in_progress`
  - `completed`
- Keep exactly one step as `in_progress` at a time.
- Update progress after each major milestone (context collection, draft complete, lint complete, handoff complete).
- Before final response, mark all steps `completed`.

## DAG Planning Rules
- Treat scenario files as the source for execution graph intent and changed-scope routing.
- For large scenario catalogs, use `scripts/dag_scenario_crud.sh` to query/update focused subsets and preserve context budget.
- Each scenario must define:
  - stable scenario id
  - `outcome_id` and `capability_id` mapped to `.sigee/product-truth/traceability.yaml`
  - `changed_paths` for `--changed-only`
  - TDD chain commands (`red_run`, `impl_run`, `green_run`)
  - final `verify` command
- Each scenario must satisfy mandatory test counts:
  - `unit_normal_tests = 2`
  - `unit_boundary_tests = 2`
  - `unit_failure_tests = 2`
  - `boundary_smoke_tests = 5`
- Require explicit smoke/e2e gate strategy in plan scope:
  - smoke: default required
  - e2e: manual gate or scheduled gate, with rationale

## Plan Quality Rules
- Every task must contain:
  - exact target files or directories
  - explicit expected behavior
  - executable `Execute: \`<command>\`` entry
  - executable `Verification: \`<command>\`` entry
- Use dependency-aware waves:
  - unblocker tasks first
  - parallelizable tasks grouped together
  - integration and final verification last
- Explicitly record assumptions. If an assumption is risky, convert it into a user decision point.
- Avoid vague phrases like "handle edge cases" without concrete examples.

## Handoff Prompt Policy
- Default handoff must be prompt-first (not command-first).
- Always include one section named `다음 실행 프롬프트`.
- `다음 실행 프롬프트` must be a single copy-ready markdown fenced block.
- `다음 실행 프롬프트` must be no-CLI:
  - no shell command lines
  - no script file paths
  - no CLI options/flags
- Handoff target must follow routing decision:
  - scientist-first when scientific/numerical/simulation/AI uncertainty remains
  - developer only when implementation-ready
- If target is `$tech-scientist`, the prompt must request:
  - evidence package generation and planner-review return
- If target is `$tech-developer`:
  - when DAG scenarios exist, request strict DAG workflow execution (build, dry-run, changed-only) as internal skill actions
  - otherwise, request strict plan execution for the target plan as an internal skill action
- Do not default to report file generation.
- Only mention persistent report generation when explicitly requested.

## User Communication Policy
- Explain outcomes in content-first language before referencing IDs or file paths.
- Start with:
  - what the user asked for
  - what will change for users or stakeholders
  - why this approach is selected
- Use long-form explanations for handoff and decision points. Include context, trade-offs, and expected impact.
- Mention IDs (`plan-id`, ticket IDs) only in a final traceability section or when explicitly requested.

## Output Contract
Return:
- long-form content summary (goal, scope, impact, approach)
- key decisions with rationale and trade-offs
- unresolved decisions that require user input
- plan path (traceability)
- one copy-ready `다음 실행 프롬프트` markdown block for the selected target:
  - scientist mode: target `$tech-scientist` when scientific/numerical/simulation/AI uncertainty remains; request evidence package + planner-review return
  - developer mode: target `$tech-developer` only when implementation-ready
    - DAG mode: request strict DAG workflow execution in natural language (no command lines)
    - non-DAG mode: request strict plan execution in natural language (no command lines)
  - optional report persistence only when requested
- include runtime-root note in handoff prompt:
  - `runtime-root = ${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`

## References
- Plan template: `references/plan-template.md`
- Planning quality gate: `references/planning-checklist.md`
- Plan linter: `scripts/plan_lint.sh`
- Gitignore guard: `scripts/sigee_gitignore_guard.sh`
- Communication prompts: `references/communication-prompts.md`
- DAG spec: `references/dag-spec.md`
- Scenario template: `references/scenario-template.md`
- DAG mapping rules: `references/dag-mapping-rules.md`
- Governance baseline: `.sigee/README.md`, `.sigee/policies/gitignore-policy.md`
- Product-truth policy: `.sigee/policies/product-truth-ssot.md`, `.sigee/product-truth/README.md`
- Orchestration policy: `.sigee/policies/orchestration-loop.md`
- Queue runtime helper: `scripts/orchestration_queue.sh`
- Archive maintenance helper: `scripts/orchestration_archive.sh`
- DAG scenario CRUD helper: `scripts/dag_scenario_crud.sh`
