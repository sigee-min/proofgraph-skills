# Pseudocode Contract

Use this contract to convert research into implementation-ready logic.

## Required Format

```text
Algorithm: <name>
Inputs:
  - <name>: <type/unit/range>
Outputs:
  - <name>: <type/unit>
Parameters:
  - <name>: <meaning/default/range>
Assumptions:
  - <critical assumptions>

Procedure:
  1. ...
  2. ...
  3. ...

Complexity:
  - Time: ...
  - Space: ...

Stability/Convergence Notes:
  - ...

Failure Modes:
  - ...
```

## Translation Rules
- Keep notation consistent with the selected paper.
- Rename symbols only if clarity improves integration.
- Include parameter default strategy when paper leaves it open.
- Annotate any heuristic additions not present in source.
