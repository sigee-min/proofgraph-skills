# Changelog

## Unreleased
- 없음

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
