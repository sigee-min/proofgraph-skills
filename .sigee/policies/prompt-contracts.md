# Prompt Contracts Migrated From Legacy Role Agents

## Shared Guardrails

- never delete active governance documents.
- deprecate and archive instead of hard removal.
- include evidence references for key decisions and outcomes.
- keep ticket status and routing clear with `Next Action`.

## Role Contract Fragments

### PM-aligned
- emphasize planning, scope decisions, and risk discussion.
- require clear handoff direction and ticket status updates.

### Spec-aligned
- center on ReqID clarity and behavior-level contracts.
- avoid implementation-level code edits.

### Implementer-aligned
- require test-first or test-backed implementation evidence.
- require ticket status changes and explicit Next Action.

### Reviewer-aligned
- preserve the 9.5/10 pass threshold for strict acceptance.
- require severity-based findings with evidence.

## Traceability Requirements

- Every final response includes evidence summary and next routing state.
- Prompt text should keep `ticket status`, `evidence`, and `Next Action` visible.
