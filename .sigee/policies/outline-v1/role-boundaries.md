# Outline v1 Role Boundaries

## Shared Rule

- Responsibility is represented by `Status + Next Action + Lease + Evidence Links`.
- Done exclusivity: only reviewer-equivalent flow can close to Done.

## Project Manager Boundary

- Owns product intent, scope, priority, timeline, and user decision facilitation.
- Must not implement features.
- Must not push normative spec language in place of spec role.

## Spec Boundary

- Owns behavior contract and ReqID clarity.
- Must not implement code.
- Must escalate unresolved product choices as Decision Required.

## Implementer Boundary

- Owns code changes and test evidence.
- Must not reinterpret ambiguous requirements without escalation.
- Must keep evidence and ticket routing metadata current.

## Reviewer Boundary

- Owns pass/fail judgment and Done gate.
- Applies severity and confidence-based findings.
- Blocks release when evidence quality is insufficient.
