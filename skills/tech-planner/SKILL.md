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
- Treat `.sigee` governance documents as the default policy reference for workflow rules, templates, and migration decisions.

## Workflow
1. Classify the request: trivial, feature, refactor, architecture, or research.
2. Gather context from local code and relevant docs before proposing structure.
   - if the task requires complex simulation/numerical/scientific reasoning, request a `$tech-scientist` package first (problem formulation + evidence matrix + pseudocode + validation plan)
3. Interview for missing constraints:
   - business objective
   - scope IN/OUT
   - technical constraints
   - testing and verification expectations
   - rollout and rollback expectations
4. Select a plan path:
   - use `<runtime-root>/plans/<plan-id>.md` (required, default runtime root is `.codex`)
   - align policy/template assumptions with `.sigee` governance docs for compatibility tracking
   - for scenario-driven delivery, define `<runtime-root>/dag/scenarios/<scenario-id>.scenario.yml` and map `red/impl/green/smoke/e2e` gates
5. Write the plan using the required template in `references/plan-template.md`.
   - enforce `mode: strict` (hard TDD baseline)
6. Run the quality gate in `references/planning-checklist.md`.
7. Run lint:
   - `scripts/plan_lint.sh <runtime-root>/plans/<plan-id>.md`
   - this automatically runs `scripts/sigee_gitignore_guard.sh <project-root>` to check/apply `.sigee` gitignore policy
8. End with a clear handoff prompt for `$tech-developer`:
   - always provide a copy-ready markdown fenced block (` ```md `) titled `다음 실행 프롬프트`
   - DAG-first handoff prompt (when scenario DAG is defined):
     - ask for `dag_build -> dag_run --dry-run -> dag_run --changed-only`
   - fallback handoff prompt (non-DAG plan):
     - ask for `codex_flow.sh <runtime-root>/plans/<plan-id>.md --mode strict`
   - include report persistence only when the user explicitly requests it.

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
- Each scenario must define:
  - stable scenario id
  - `changed_paths` for `--changed-only`
  - TDD chain commands (`red_run`, `impl_run`, `green_run`)
  - final `verify` command
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
- If DAG scenarios exist, the prompt must request:
  - pipeline build
  - dry-run
  - changed-only run
- Otherwise, the prompt must request strict `codex_flow` execution for the target plan.
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
- one copy-ready `다음 실행 프롬프트` markdown block for `$tech-developer`:
  - DAG mode: request `dag_build` -> `dag_run --dry-run` -> `dag_run --changed-only`
  - non-DAG mode: request strict `codex_flow` plan execution
  - optional report persistence only when requested
- include runtime-root note in handoff prompt:
  - `runtime-root = ${SIGEE_RUNTIME_ROOT:-.codex}`

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
- Compatibility guide: `.sigee/migrations/runtime-path-compatibility-plan.md`
