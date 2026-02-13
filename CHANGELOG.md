# Changelog

## Unreleased
- 없음

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
