# Outline v1 Workload Discipline

## Ticket Flow

- Canonical transition: `Backlog -> Ready -> InProgress -> Review -> Done`
- Exception transitions: `* -> Blocked`, `Blocked -> Ready|InProgress`
- Folder state and field state must remain aligned.

## Ownership Contract

- Use `Status + Next Action + Lease + Evidence Links` as the operational contract.
- Avoid owner-only assignment models.

## Lease Protocol

- Acquire lease before editing ticket state.
- Renew for long tasks.
- Release on handoff or completion.

## Failure Handoff Schema

- Failure Reason
- Evidence Links
- Repro/Command
- Required Decision
- Next Action

## Done Gate

- Done exclusivity is enforced by reviewer flow only.
- Any bypass is treated as process failure and must be reverted.
