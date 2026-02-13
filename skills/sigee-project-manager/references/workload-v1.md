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

## Global Policies

- No-delete: never delete Outline tickets/specs/handoffs/boards. Deprecate with reason and archive.
- Done exclusivity: only `$sigee-reviewer` may move tickets to `Done`.

## Role-State Guidance (Recommended)

- Project Manager: `Backlog` and `Ready` (use `Blocked` for missing decisions/scope/evidence)
- Spec Author: `Backlog` and `Ready` (use `Blocked` for Decision Required / missing evidence)
- Implementer: `InProgress` (enter from `Ready`, submit to `Review`, use `Blocked` for blockers)
- Reviewer: `Review` (PASS to `Done`, FAIL to `Blocked` with Next Action)

## Collaboration Model (Tickets First)

- Users/stakeholders discuss through `$sigee-project-manager`.
- PM routes work to roles via tickets (`Next Action` + Evidence Links).
- Default routing for new work: create/update a ticket in `Backlog` and set `Next Action` to `$sigee-spec-author`.
- Roles coordinate by updating the ticket (not by direct user negotiation).

## Outline Templates (v1)

When creating new Outline documents, always use `create_document_from_template` with the canonical template names:

- Ops rules: `운영규약`
- Agent ticket: `에이전트 티켓`
- Handoff note: `핸드오프 노트`
- Weekly board: `주간 업무 보드`

Recommended implementation:
- Resolve each name via the project's template registry in the collection first.
- If unresolved, resolve from this policy file and record the resolved template document IDs.

## Template Registry (Project-local)

Project-local template registry is required before creating new role documents.

- Canonical document name: `템플릿 레지스트리`
- Minimal fields per row:
  - `template_name`: canonical template title used in this project.
  - `template_doc_id`: created document id in the project collection.
  - `source_reference`: source pointer for rebuild (`template_id` fallback or template description).
  - `status`: `active` | `deprecated`.
  - `created_at`: ISO timestamp.
  - `last_refreshed_at`: ISO timestamp.
  - `last_actor`: user/role who last refreshed.
- On every create/update cycle: use only rows with `status=active`.
- If registry is missing required rows, PM creates/refreshes them before work begins.
