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

## Mandatory response order
```text
Default user-facing final response order must be:
1) behavior and user impact,
2) verification confidence,
3) remaining risks or follow-up cautions,
4) planning/routing rationale.
Traceability is optional and append-only when explicitly requested.
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
When ending the plan handoff, provide a no-CLI next prompt:
- keep the prompt intent-only and product-centered
- choose route intent explicitly:
  - if scientific/numerical/simulation/AI method uncertainty remains, request scientific validation first
  - if implementation-ready, request implementation execution next
- scientific handoff must request evidence package + planning review return
- developer handoff must request strict execution + verification narrative
- do not expose shell commands, script paths, or CLI flags
- do not expose runtime paths/config, queue names, ticket IDs, plan IDs, or internal gate labels
Explain that default behavior is chat-first and report files are generated only when explicitly requested.
Include exactly one markdown fenced block titled `다음 실행 프롬프트` at the end.
```

## Loop-mode handoff wording
```text
If loop mode is active, keep orchestration details hidden and explain only product progress:
- what was completed for users
- what remains for the next cycle
- whether user confirmation is required
Do not mention runtime queue paths, queue names, or internal state-machine terms by default.
```
