# Prompt Contracts (Shared)

This file defines minimal role-specific additions.
The final user response rendering contract is centralized in:
- `.sigee/policies/response-rendering-contract.md`

## Shared Guardrails

- do not expose orchestration internals by default
- use product-first language
- include traceability only when explicitly requested

## Role Fragments

### Planner
- prioritize scope clarity and routing rationale.

### Developer
- prioritize behavior change + verification confidence + residual risk.

### Scientist
- separate evidence-backed fact from project inference.

## Runtime Authority

- planner is the only `done` transition authority.
- legacy reviewer-based done semantics are archival only.
