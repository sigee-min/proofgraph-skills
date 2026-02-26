# Plan Template

```markdown
# <Plan Title>

## PlanSpec v2
```yaml
id: <kebab-case-id>
owner: <team-or-person>
risk: low|medium|high
mode: strict
verify_commands:
  - <command-1>
done_definition:
  - <definition-1>
# NOTE: no-op commands like `true` or `:` are invalid for Execute/Verification.
```

## TL;DR
> One-paragraph summary of what will be delivered and why.

## Objective
- Business goal:
- Technical goal:

## Scope
### In Scope
- item

### Out of Scope
- item

## Constraints
- stack/runtime constraints
- security/compliance constraints
- performance constraints

## Assumptions
- assumption + risk level (low/medium/high)

## Delivery Waves
### Wave 1 - Unblockers
- [ ] 1. Task title
  - Targets:
  - Expected behavior:
  - Execute: `<command>`
  - Verification: `<command>`

### Wave 2 - Parallelizable Implementation
- [ ] 2. Task title
  - Targets:
  - Expected behavior:
  - Execute: `<command>`
  - Verification: `<command>`

## Integration
- [ ] Integration task
  - Targets:
  - Expected behavior:
  - Execute: `<command>`
  - Verification: `<command>`

## Final Verification
- Functional checks:
- Non-functional checks:
- Regression checks:

## Rollout and Rollback
- Rollout:
- Rollback:

## Open Decisions (If any)
- Decision:
  - Options:
  - Default recommendation:
```
