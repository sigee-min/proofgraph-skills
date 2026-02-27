# Response Rendering Contract (Shared)

This contract is mandatory for final user-facing responses from:
- `tech-planner`
- `tech-developer`
- `tech-scientist`

## Default Response Order (Mandatory)

In default user mode, final responses must appear in this order:
1. Behavior and user impact
2. Verification confidence
3. Remaining risks or follow-up cautions

Domain-specific detail sections may follow, but these first three sections must not be reordered.

## Internal-Term Blocking (Mandatory)

Default user mode must automatically block internal orchestration wording.
Do not expose:
- queue names
- ticket/plan identifiers
- runtime path/config strings
- helper state keys and machine key-value outputs
- internal script or artifact names
- lifecycle/meta keys such as `phase`, `error_class`, `attempt_count`, `retry_budget`, `evidence_links`
- orchestration source markers such as `source=plan:*`, `plan:*`
- runtime path fragments such as `.sigee/.runtime`, `/orchestration/`

Only include internal traceability when the user explicitly requests operational detail.

## Next-Prompt Block Rule (Mandatory)

Every final response must end with exactly one markdown fenced block titled `다음 실행 프롬프트`.

Block requirements:
- intent-only natural language
- no shell commands
- no script paths
- no CLI flags/options
- no runtime paths/config
- no queue names or internal IDs
- include one sentence starting with `왜 지금 이 작업인가:` to explain immediate product value context

## Functional Safety

This contract must not change execution semantics.
It only constrains how final responses are rendered and what is visible by default.
