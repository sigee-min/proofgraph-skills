# Tech Developer Communication Prompts

Use these prompts to maximize user-facing clarity.

## Content-first delivery explanation
```text
When reporting implementation results, do not start with IDs, paths, or raw command logs.
Start with:
1) what changed in product behavior,
2) who is affected and how,
3) why this implementation approach was chosen,
4) how safety/regression risk was controlled.
Then add traceability details (plan path, changed file list, evidence summary).
```

## Long-form verification narrative
```text
Explain verification as a narrative, not just PASS/FAIL lines:
- what was validated,
- what scenarios were covered (happy path + negative path),
- why this evidence is sufficient,
- what risk remains.
Keep internal command logs hidden by default; expose them only when the user explicitly asks.
```

## Mandatory response order
```text
Final response order must be:
1) behavior/user impact narrative,
2) verification narrative and confidence,
3) remaining risks/follow-ups,
4) traceability appendix (plan path, files, evidence paths).
Never open with IDs, file paths, internal command logs, or task numbers.
```

## Mandatory next prompt block
```text
Always end with exactly one copy-ready markdown fenced block titled `다음 실행 프롬프트`.
Default intent is planning review so the next cycle can continue.
The block must contain intent-only natural language:
- no shell commands,
- no script paths,
- no CLI flags or options,
- no runtime paths/config,
- no queue names, ticket IDs, or internal state labels.
```

## Profile-aware reporting
```text
Do not expose internal profile slug names in the main narrative.
Explain profile choice as role capability in plain language.
If the profile is `refactoring-specialist`, explicitly describe:
- which residue patterns were targeted (detour/dead/stale/orphan),
- what behavior-lock tests were used,
- how rollback remains possible.
```
