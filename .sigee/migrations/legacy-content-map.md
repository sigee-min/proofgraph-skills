# Legacy Content Map: sigee-* -> .sigee

This map captures reusable content from removed role skills.

## Source Inventory

| Legacy source | Key content | Target in .sigee |
| --- | --- | --- |
| `skills/sigee-project-manager/SKILL.md` | PM role boundary, decision package, bootstrap, root hygiene | `.sigee/migrations/legacy-policy/outline-v1-role-boundaries.md` |
| `skills/sigee-spec-author/SKILL.md` | Cleanroom spec boundary, ReqID discipline, Decision Required | `.sigee/migrations/legacy-policy/outline-v1-role-boundaries.md` |
| `skills/sigee-implementer/SKILL.md` | Clean Code/Clean Architecture, strong typing, unit-test mandate | `.sigee/migrations/legacy-policy/outline-v1-role-boundaries.md` |
| `skills/sigee-reviewer/SKILL.md` | 9.5/10 pass bar, severity model, done gate | `.sigee/migrations/legacy-policy/outline-v1-role-boundaries.md` |
| `skills/*/references/workload-v1.md` | Ticket workflow contract and lease protocol | `.sigee/migrations/legacy-policy/outline-v1-workload-discipline.md` |
| `skills/sigee-project-manager/references/template-seeds/*` | 운영규약, 에이전트 티켓, 핸드오프, 주간보드 seed | `.sigee/templates/*` (consumer repo: local auto-generated + ignored by default, skill-pack: seed templates may be tracked) |
| `skills/*/agents/openai.yaml` | role default prompt contract | `.sigee/policies/prompt-contracts.md` |

## Role Tag Coverage

- `sigee-project-manager`
- `sigee-spec-author`
- `sigee-implementer`
- `sigee-reviewer`

## Legacy Artifact Coverage Checklist

- workload-v1 references mapped
- template-seeds mapped
- openai.yaml prompt contracts mapped

## Migration Notes

- Role execution behavior is preserved as policy text, not runtime role binding.
- Legacy names remain in this map for traceability during transition.
- New runtime should reference `.sigee` policy files as source of truth.
