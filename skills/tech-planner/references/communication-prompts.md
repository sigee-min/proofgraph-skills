# Tech Planner Communication Prompts

Use these prompts to enforce user-facing communication quality.

## Content-first planning explanation
```text
When you explain the plan, do not start with plan IDs or file paths.
Start with the user's goal, what will change, and why this plan is appropriate.
Explain in detail:
1) scope (in/out),
2) main execution strategy,
3) key trade-offs and risks,
4) what the user should expect after implementation.
Put traceability details (plan path, IDs) at the end.
```

## Decision-focused long explanation
```text
For unresolved decisions, provide a long-form explanation per decision:
- decision context,
- available options,
- pros/cons,
- recommendation and rationale,
- impact on delivery risk and timeline.
Do not ask a binary question without context.
```

## Default execution handoff wording
```text
When ending the plan handoff, provide the default next prompt with runtime-root context:
runtime-root = ${SIGEE_RUNTIME_ROOT:-.codex}
skills/tech-developer/scripts/codex_flow.sh <runtime-root>/plans/<plan-id>.md --mode strict
Explain that this default is chat-first and does not persist report files.
Only include the --write-report variant when the user explicitly asks for report files.
```
