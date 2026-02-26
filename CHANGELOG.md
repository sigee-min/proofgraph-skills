# Changelog

## Unreleased
- Enforced hard TDD mode across planner/developer runtime flow:
  - Removed effective `fast` execution path; `plan_run.sh` and `codex_flow.sh` now accept strict mode only.
  - `plan_lint.sh` now requires `mode: strict` and per-task executable `Execute`/`Verification` command blocks.
  - `dag_build.sh` now fails on missing scenario chain commands (`red_run`, `impl_run`, `green_run`, `verify`) and missing `changed_paths`.
  - `test_smoke.sh`/`test_e2e.sh` now fail when project test commands are not configured (no no-op fallback).
- Updated planning/developer references and templates to match hard TDD contract.
- Resolved `.sigee` storage decisions:
  - `.sigee/reports` ignored by default, release snapshots tracked only under `.sigee/migrations/release-report-snapshots/`.
  - `.sigee/evidence` always ignored; only curated summaries should be tracked.
- Added shared `.sigee` gitignore guard script: `skills/tech-planner/scripts/sigee_gitignore_guard.sh`.
- Enforced automatic `.sigee` gitignore check/apply in both planner and developer flows:
  - `skills/tech-planner/scripts/plan_lint.sh`
  - `skills/tech-developer/scripts/plan_run.sh`
- Updated planner/developer checklists and agent prompts to require gitignore guard policy enforcement.
- Added `.sigee` governance baseline docs (policy/template/scenario/DAG/migration) and root `.gitignore` rules that track long-lived assets while ignoring runtime artifacts.
- Added legacy `sigee-*` role content migration maps into `.sigee` (role boundaries, workload discipline, template seeds, prompt contracts).
- Added `.codex` -> `.sigee` compatibility and cutover playbooks (`dual-read`, `dual-write`, `cutover`, `rollback`).
- Updated `README`, `tech-planner`, and `tech-developer` docs to prefer `.sigee` governance references while preserving current `.codex` runtime executability.
- Enforced `tech-planner` handoff command policy: default next step is `skills/tech-developer/scripts/codex_flow.sh .codex/plans/<plan-id>.md --mode strict`, with `--write-report` suggested only on explicit persistent-report requests.
- Enforced `tech-developer` final response order policy: content/impact -> verification narrative -> risks/follow-up -> traceability appendix (no ID/path/log-first responses).
- Synced planner/developer communication prompt references and agent default prompts with the same UX policy wording.
- Changed `tech-developer` report persistence to opt-in: `plan_run.sh`/`codex_flow.sh` now skip report file generation by default and only write report/dashboard artifacts with `--write-report` (or explicit `report_generate.sh`).
- Fixed `codex_flow.sh` argument contract to align with `plan_run.sh` optional report mode.
- Added content-first user communication policy to `tech-planner` and `tech-developer` (long-form explanation first, IDs/paths as traceability only).
- Added reusable communication prompt packs:
  - `skills/tech-planner/references/communication-prompts.md`
  - `skills/tech-developer/references/communication-prompts.md`
- Updated developer report template to lead with user-facing narrative before traceability metadata.
- Added `.codex` single-entry workflow script: `skills/tech-developer/scripts/codex_flow.sh` (lint -> run -> report).
- Added resume support to execution loop: `plan_run.sh --resume` now surfaces previous fail context and archives prior verification results.
- Added reports dashboard generator: `skills/tech-developer/scripts/reports_index.sh` producing `.codex/reports/index.md`.
- Updated report generation to refresh dashboard automatically after each run.
- Updated README and tech-developer skill docs with single-entry and resume UX examples.
- Added new `.codex` workflow skill: `tech-planner` (interview-first planning, PlanSpec v2 template, planning checklist).
- Added new `.codex` workflow skill: `tech-developer` (plan-driven execution loop, verification checklist, delivery report template).
- Added planner lint script: `skills/tech-planner/scripts/plan_lint.sh` for path/spec/task structure validation.
- Added developer run script: `skills/tech-developer/scripts/plan_run.sh` for strict/fast execution-verification loop with checkbox progress update.
- Added developer report script: `skills/tech-developer/scripts/report_generate.sh` to emit `.codex/reports/<plan-id>-report.md` from plan/evidence.
- Added `.codex` UX guidance and command examples to `README.md`.
- Enforced Implementer commit discipline: each processed ticket must produce at least one dedicated commit before leaving `InProgress`.
- Added explicit prohibition on mixing multiple tickets in a single commit for Implementer runs.
- Required commit hash evidence in ticket handoff (`Evidence Links`) before moving tickets to `Review`.
- Added mandatory one-ticket-one-responsibility gate in PM routing and board operation.
- Added reviewer fail-level ticket-scope audit: mixed-scope tickets must be split before approval.
- Added HR KPI/rubric enforcement for mixed-scope ticket violations and split-quality follow-up routing.
- Added new orchestrator skill: `$sigee-pipeline-orchestrator` for closed-loop PM/Spec/Implementer/Reviewer/HR execution.
- Enforced Spec Author re-entry loop in orchestration when review/implementation finds requirement ambiguity.
- Added pipeline guardrails and stop conditions (`all done` or `decision-required only`) to prevent premature single-role exits.

## 0.4.0
- Added new role skill: `$sigee-hr-evaluator` for evidence-based KPI/SLA performance evaluation and improvement routing across PM/Spec/Implementer/Reviewer.
- Added HR evaluator rubric reference for default role metrics, hard gates, and score interpretation.
- Added proactive execution contracts across core role skills so each role must identify and act on delivery risks, quality gaps, and improvement opportunities every run.
- Updated role agent prompts to reinforce proactive, evidence-driven execution behavior.

## 0.3.4
- Upgraded `$sigee-project-manager` to mandatory E2E scenario-driven planning and ticket decomposition.
- Added PM gap triage model per scenario: `Implemented | Missing | Needs Reinforcement`.
- Added PM ambiguity gate: ask users only for critical ambiguities; apply best-practice defaults for minor UI/UX ambiguities with logged assumptions.
- Added E2E scenario document management policy with per-scenario progress and test-readiness tracking.
- Added new PM template seeds:
  - `/references/template-seeds/e2e-scenario-catalog.md`
  - `/references/template-seeds/e2e-scenario.md`
- Expanded PM bootstrap/workload references with E2E scenario lane/template expectations and governance.

## 0.3.3
- Added 3 new internal implementer overlay profiles:
  - `api-contract-compatibility`
  - `event-streaming-reliability`
  - `test-automation-quality`
- Expanded implementer routing signals and overlay selection rules to include API schema compatibility, async event reliability, and test automation robustness concerns.
- Updated implementer default prompt to apply the new overlay quality gates in black-box routing mode.

## 0.3.2
- Added 4 new internal implementer overlay profiles:
  - `db-migration-reliability`
  - `platform-devops-sre`
  - `security-appsec`
  - `performance-reliability`
- Upgraded implementer routing model to select one primary domain profile plus required cross-cutting overlays.
- Expanded routing signals to include infra/deploy, migration, security, and performance cues.
- Updated implementer default prompt to enforce combined profile quality gates while keeping routing black-box by default.

## 0.3.1
- Converted implementer specialization into internal black-box routing profiles under `skills/sigee-implementer/references/profiles/`.
- Removed standalone specialization skills from published skill list so users only see core role skills.
- Updated implementer routing docs/prompts to auto-select internal profile by repository signals and keep routing details hidden by default.
- Kept domain-specific quality gates (web/go/spring/ai) as internal references enforced by `sigee-implementer`.

## 0.3.0
- Added domain-specialized implementer skills:
  - `sigee-implementer-web-nextjs`
  - `sigee-implementer-server-go`
  - `sigee-implementer-server-spring`
  - `sigee-implementer-ai-engineer`
- Upgraded `sigee-implementer` to act as a specialization router/orchestrator and require specialization selection before coding.
- Added explicit specialization routing rules and handoff evidence requirements (`Selected Specialization`, `Why This Match`, `Specialized Quality Gates`).
- Added web specialization standards for `pnpm`, `zod`, Playwright-driven verification, and shadcn/tailwind-first UI composition.
- Added Go and Spring server specialization quality gates focused on boundary integrity, typed contracts, and service-level reliability.
- Added AI specialization quality gates for schema-safe outputs, reproducibility, evaluation regression, and quality/cost/latency tradeoff reporting.

## 0.2.10
- Added a mandatory content-first user communication rule across PM/Spec Author/Implementer/Reviewer skills.
- Enforced that user-facing updates explain feature intent, implementation approach, and user impact in natural language instead of ticket ID/code-first phrasing.
- Clarified that ticket/ReqID identifiers should be mentioned only when the user explicitly requests traceability.
- Updated PM reporting contract and output templates to prioritize human-readable feature summaries before process details.
- Updated all role `agents/openai.yaml` default prompts to keep this communication style consistent at runtime.

## 0.2.9
- Strengthened Reviewer code-quality gates to require file name/path responsibility alignment and single-dominant-responsibility checks per changed file.
- Added fail-level guidance for multi-responsibility file bundling (god-file risk) unless a bounded exception is documented with evidence.
- Added explicit Clean Architecture boundary-direction checks (domain/core dependency direction and boundary leakage detection).
- Added strict design-pattern fitness checks (over-engineering and missing-pattern risk detection).
- Expanded Reviewer output contract to include file-responsibility map and architecture/pattern audit.
- Updated Reviewer default agent prompt so these stricter checks are consistently enforced.

## 0.2.8
- Added PM planning-advisor mandate for vague user requests: convert ambiguity into concrete planning packet before routing.
- Added strict feasibility gate based on vibe-coding productivity cycles with verdicts (`Feasible|Risky|Unrealistic Now`).
- Added mandatory PM output of assumptions, blockers, and MVP de-scope/re-sequencing recommendations.
- Added mandatory `User Scenario/UI Advisory` output (scenario steps, state matrix, simplification notes).
- Updated PM workload reference so advisory/feasibility format is consistently applied across environments.

## 0.2.7
- Changed autonomous non-PM execution from single-ticket mode to full eligible-queue processing mode per run.
- Updated queue processing semantics to deterministic ordered iteration over all eligible tickets.
- Updated lease protocol wording to per-ticket lock/renew/release while iterating queue.
- Updated Spec Author / Implementer / Reviewer skill docs so `진행해` runs process the full queue, not one ticket.

## 0.2.6
- Added PM decision-response SLA: decision-routed tickets must produce user-facing decision discussion in the same run.
- Enforced PM requirement to request user choice before ending a decision-handling run.
- Added mandatory decision package fields: `Question`, `Options`, `Tradeoff`, `PM Recommendation`, `User Choice`, `Applied At`.
- Updated PM workload reference to keep SLA and decision-packet format consistent across environments.

## 0.2.5
- Enforced PM user-facing response contract: every PM response must include `Recommended Next Actions` and `Decision Discussion`.
- Added PM rule to explicitly provide decision options/tradeoffs/recommendation and request user choice when decision is pending.
- Updated PM workload reference to keep recommendation/discussion format consistent across environments.

## 0.2.4
- Added non-PM autonomous execution contract for `진행해`: one-ticket-per-run, deterministic queue pick, no-op on empty queue.
- Added hard lease protocol requirements (`acquire_document_lease`, `renew_document_lease`, `release_document_lease`) across role workflows.
- Added mandatory failure handoff payload schema (`Failure Reason`, `Evidence Links`, `Repro/Command`, `Required Decision`, `Next Action`).
- Updated Spec Author / Implementer / Reviewer skill docs to execute from queue even without explicit ticket ID.
- Updated PM skill to explicitly require autonomous non-PM execution contract while keeping PM as user-facing coordinator.

## 0.2.3
- Added new-server bootstrap standard so root anchors/lanes are created before normal workflow on fresh Outline servers.
- Added required child-lane policy (`10_티켓`, `01_스펙`, `30_업무보드`) and structure registry requirements.
- Added cross-role guard: Spec Author / Implementer / Reviewer must route back to PM when anchors/lanes are not bootstrapped.

## 0.2.2
- Added collection-root hygiene policy and whitelist anchors to prevent root pollution.
- Enforced explicit `parent_document_id` for all document creation flows (including template-based creation).
- Added PM root guard routine (`get_collection_structure` + `move_document`) and mandatory re-homing policy.
- Extended template registry schema with `default_parent_anchor` and `default_parent_document_id`.
- Applied root-hygiene template/creation constraints across PM/Spec Author/Implementer/Reviewer workload references.

## 0.2.1
- Added strict PM-vs-Spec boundary contract in `sigee-project-manager` and `sigee-spec-author`.
- Added PM Brief gate before routing to Spec Author.
- Added Spec Ready gate before moving ticket to `Ready`.
- Added reviewer boundary-integrity checks to detect PM/Spec ownership violations.

## 0.2.0
- PM bootstrap changed to use Outline official templates (`list_templates`) instead of creating template source docs in project collections.
- Added official-template bootstrap path via `create_template_from_document` and workspace template catalog flow.
- Added template seed files under `skills/sigee-project-manager/references/template-seeds/`.
- Unified template policy across Spec Author / Implementer / Reviewer workload references.

## 0.1.0
- Initial release candidate
