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
When ending the plan handoff, provide a no-CLI next prompt:
- include runtime-root context (`runtime-root = ${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`)
- choose route target explicitly:
  - if scientific/numerical/simulation/AI method uncertainty remains, ask `$tech-scientist` first
  - if implementation-ready, ask `$tech-developer`
- scientist handoff must request evidence package + return to planner-review
- developer handoff must request strict execution internally
- do not expose shell commands, script paths, or CLI flags
Explain that default behavior is chat-first and report files are generated only when explicitly requested.
```

## Loop-mode handoff wording
```text
If orchestration loop mode is active, include queue routing context:
- planner owns orchestration and review decisions
- developer/scientist must return to planner-review queue
- done transition is planner-only
Mention runtime queue path:
<runtime-root>/orchestration/queues/
```
