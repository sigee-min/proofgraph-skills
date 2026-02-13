# Changelog

## Unreleased
- 없음

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
