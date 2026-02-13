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
- Root hygiene: root-level docs are structural anchors only:
  - `00_운영규약`, `01_스펙`, `10_티켓`, `20_핸드오프`, `30_업무보드`, `90_아카이브`
- On a new server/workspace, PM must bootstrap anchors/lanes first.
- If required anchors/lanes are missing, set `Next Action` to PM and wait for bootstrap completion.

## Role-State Guidance (Recommended)

- Spec Author: `Backlog` and `Ready` (use `Blocked` for Decision Required / missing evidence)
- Implementer: `InProgress` (enter from `Ready`, submit to `Review`, use `Blocked` for blockers)
- Reviewer: `Review` (PASS to `Done`, FAIL to `Blocked` with Next Action)
- Exclusivity: only Reviewer may move tickets to `Done`.

## Collaboration Model (Tickets First)

- Users/stakeholders discuss through `$sigee-project-manager`.
- `$sigee-project-manager` routes work to roles via tickets (`Next Action` + Evidence Links).
- `$sigee-reviewer` is the only role that can move tickets to `Done`.
- Review findings must be written back to the ticket with clear Next Action and evidence links.

## Autonomous Execution Contract (Non-PM)

Goal: allow `$sigee-spec-author`, `$sigee-implementer`, and `$sigee-reviewer` to run correctly from a minimal command such as `진행해`.

- PM is excluded from this autonomous contract; PM remains user-facing and routing-focused.
- One run processes the full eligible queue for the role.
- If no ticket is eligible, run returns no-op and does not modify docs except optional activity note.

### Eligibility Queue By Role

- Spec Author:
  - status in `Backlog|Ready`
  - `Next Action == $sigee-spec-author`
- Implementer:
  - status in `Ready|InProgress|Blocked` (resume path)
  - `Next Action == $sigee-implementer`
- Reviewer:
  - status in `Review`
  - `Next Action == $sigee-reviewer`

### Deterministic Pick Rule

- Pick only tickets meeting role eligibility.
- Exclude tickets with active lease owned by another actor.
- Sort by:
  - oldest `updatedAt` first (or board order when timestamp unavailable)
  - lexical ticket title as tie-breaker
- Process all candidates in sorted order.

### Lease Protocol (Hard Lock)

- For each selected ticket:
  - Before editing, call `acquire_document_lease` (TTL 30m default).
  - While working, renew using `renew_document_lease` every ~10m for long tasks.
  - On completion/handoff, release using `release_document_lease`.
  - If lease acquisition fails, skip that ticket and continue.

### Handoff And Exit Rules

- Every run must update:
  - `Status` + folder alignment
  - `Next Action`
  - `Lease` metadata
  - `Evidence Links`
- Never move ticket to `Done` unless current role is Reviewer and review passed.
- If blocked by missing product decision or missing bootstrap context, set `Next Action` to PM and move to `Blocked`.

## Failure Handoff Schema (Mandatory)

When a run fails or blocks, write this payload to the ticket:

- `Failure Reason`: concise root cause.
- `Evidence Links`: logs, commands, docs, commits, screenshots.
- `Repro/Command`: exact command(s) and environment notes.
- `Required Decision`: what decision is needed and options.
- `Next Action`: target role (`$sigee-project-manager`, `$sigee-spec-author`, `$sigee-implementer`, `$sigee-reviewer`).

## Cleanroom Roles (Boundary)

- Spec Author: writes behavior specs from observed behavior; does not implement or review code.
- Implementer: implements only from the spec package/docs; does not read prohibited reference source code.
- Verifier: runs oracle comparisons; uses acceptance criteria defined in oracle docs only.

## Outline Templates (v1)

When creating new Outline documents, always use `create_document_from_template` with Outline official templates and canonical names:

- Ops rules: `[공식 템플릿] 무소유권 운영규약`
- Agent ticket: `[공식 템플릿] 무소유권 에이전트 티켓`
- Handoff note: `[공식 템플릿] 무소유권 핸드오프 노트`
- Weekly board: `[공식 템플릿] 무소유권 업무 보드(주간)`

Recommended implementation:
- Resolve each name by exact match from `list_templates`.
- If unresolved, do not create project-local template docs; return `Next Action` to PM to bootstrap official templates and retry.
- Never create template source documents inside the project collection.
- Never create documents at collection root; require explicit `parent_document_id`.
