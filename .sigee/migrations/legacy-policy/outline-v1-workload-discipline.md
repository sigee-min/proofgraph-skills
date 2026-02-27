# Outline v1 Workload Discipline (Archived)

> Archived legacy reference.
> This file is retained for migration traceability only.
> Current governance source: `.sigee/policies/orchestration-loop.md`.

## Ticket Flow

- Canonical transition: `Backlog -> Ready -> InProgress -> Review -> Done`
- Exception transitions: `* -> Blocked`, `Blocked -> Ready|InProgress`
- Folder state and field state must remain aligned.

## Ownership Contract

- Use `Status + Next Action + Lease + Evidence Links` as the operational contract.
- Avoid owner-only assignment models.

## Lease Protocol

- Historical description only.
- Current runtime automatically applies lease in queue helper (`claim` acquire, handoff release).

## Failure Handoff Schema

- Failure Reason
- Evidence Links
- Repro/Command
- Required Decision
- Next Action

## Done Gate

- Done exclusivity (legacy): reviewer flow only.
- Current runtime override: planner review flow only.
- Any bypass is treated as process failure and must be reverted.
