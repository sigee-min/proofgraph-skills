# Workload Pattern v1 (Outline)

This file captures stable, cross-project workflow rules used with cleanroom roles and Outline documents.

## Ticket Discipline

- Do not use an "owner" model.
- Represent current responsibility using: `Status + Next Action + Lease + Evidence Links`.
- The document's folder/location is the source of truth for status.

Status transitions:

- Default: `Backlog -> Ready -> InProgress -> Review -> Done`
- Exception: `* -> Blocked`, `Blocked -> Ready|InProgress`
- When changing status: move the document to the matching status folder and update the `Status` field.

Lease:

- On ticket selection, record: `Lease Token`, `Lease Expires At`, `Last Actor`.
- Default TTL: 30 minutes; renew every 10 minutes while working.
- At end of work, update: progress log, `Evidence Links`, `Next Action`.

## No-Delete Policy (Global)

- Never delete Outline tickets/specs/handoffs.
- Deprecation process: mark **DEPRECATED**, write a reason (and replacement link if any), then archive it per the project's convention.

## Role-State Guidance (Recommended)

- Spec Author: `Backlog` and `Ready` (use `Blocked` for Decision Required / missing evidence)
- Implementer: `InProgress` (enter from `Ready`, submit to `Review`, use `Blocked` for blockers)
- Reviewer: `Review` (PASS to `Done`, FAIL to `Blocked` with Next Action)
- Exclusivity: only Reviewer may move tickets to `Done`.

## Collaboration Model (Tickets First)

- Users/stakeholders discuss through `$sigee-project-manager`.
- `$sigee-project-manager` routes work to roles via tickets (`Next Action` + Evidence Links).
- `$sigee-spec-author` is the default first stop for new work; `$sigee-implementer` starts after a ticket is `Ready`.
- Roles communicate by updating the ticket, not by negotiating directly with users.

## Cleanroom Roles (Boundary)

- Spec Author: writes behavior specs from observed behavior; does not implement or review code.
- Implementer: implements only from the spec package/docs; does not read prohibited reference source code.
- Verifier: runs oracle comparisons; uses acceptance criteria defined in oracle docs only.

## Outline Templates (v1)

When creating new Outline documents, always use `create_document_from_template` with the canonical template names:

- Ops rules: `운영규약`
- Agent ticket: `에이전트 티켓`
- Handoff note: `핸드오프 노트`
- Weekly board: `주간 업무 보드`

Recommended implementation:
- Resolve each name via the project's template registry in the collection first.
- If unresolved, resolve from the PM workflow reference and record the resolved template document IDs.
