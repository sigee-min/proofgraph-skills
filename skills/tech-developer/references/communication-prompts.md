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
Then add traceability details (plan path, changed file list, verification commands).
```

## Long-form verification narrative
```text
Explain verification as a narrative, not just PASS/FAIL lines:
- what was validated,
- what scenarios were covered (happy path + negative path),
- why this evidence is sufficient,
- what risk remains.
Keep command logs in a separate traceability block.
```

## Mandatory response order
```text
Final response order must be:
1) behavior/user impact narrative,
2) verification narrative and confidence,
3) remaining risks/follow-ups,
4) traceability appendix (plan path, files, commands, evidence paths).
Never open with IDs, file paths, command logs, or task numbers.
```
