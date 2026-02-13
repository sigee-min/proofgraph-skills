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
- Root hygiene: root-level documents are structural anchors only:
  - `00_운영규약`, `01_스펙`, `10_티켓`, `20_핸드오프`, `30_업무보드`, `90_아카이브`
- Never create project documents at root; always pass `parent_document_id`.

## New Server Bootstrap Standard (PM)

When migrating to a new Outline server/workspace, PM must run bootstrap in this order:

1. Ensure root anchors exist:
  - `00_운영규약`, `01_스펙`, `10_티켓`, `20_핸드오프`, `30_업무보드`, `90_아카이브`
2. Ensure required child lanes:
  - `10_티켓` -> `Backlog`, `Ready`, `InProgress`, `Review`, `Done`, `Blocked`
  - `01_스펙` -> `10_핵심스펙`, `20_오라클`, `90_아카이브`
  - `30_업무보드` -> `10_주간보드`, `20_진행리포트`, `90_아카이브`
3. Ensure official templates exist (resolve via `list_templates`, bootstrap if missing).
4. Create baseline project docs only with explicit `parent_document_id`.
5. Persist IDs into:
  - `구조 레지스트리` (anchors/lanes)
  - `템플릿 레지스트리` (templates + default parents)

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

When creating new Outline documents, always use `create_document_from_template` with Outline official templates (workspace template library) and canonical names:

- Ops rules: `[공식 템플릿] 무소유권 운영규약`
- Agent ticket: `[공식 템플릿] 무소유권 에이전트 티켓`
- Handoff note: `[공식 템플릿] 무소유권 핸드오프 노트`
- Weekly board: `[공식 템플릿] 무소유권 업무 보드(주간)`

Recommended implementation:
- Resolve each name by exact match from `list_templates`.
- If a canonical template is missing, PM must bootstrap it as an official template:
  - Create/reuse workspace collection `무소유권 템플릿 카탈로그`.
  - Create source doc from local seed in `/references/template-seeds/`.
  - Register as official template with `create_template_from_document`.
  - Re-run `list_templates` to verify resolution.
- Never create template source documents inside the project collection.
- Always create from template with explicit `parent_document_id` (no collection-root creation).

## Template Registry (Project-local)

Project-local template registry is required before creating new role documents, but it is a cache.

- Canonical document name: `템플릿 레지스트리`
- Minimal fields per row:
  - `template_name`: canonical official template title.
  - `template_id`: resolved template id from `list_templates`.
  - `source_collection`: template source collection name (for rebuild).
  - `source_document_id`: source document id used to create the official template.
  - `source_seed_path`: local seed path under `/references/template-seeds/`.
  - `default_parent_anchor`: one of `00_운영규약|01_스펙|10_티켓|20_핸드오프|30_업무보드|90_아카이브`.
  - `default_parent_document_id`: resolved parent doc id for creation target.
  - `status`: `active` | `deprecated`.
  - `created_at`: ISO timestamp.
  - `last_refreshed_at`: ISO timestamp.
  - `last_actor`: user/role who last refreshed.
- On every create/update cycle: use only rows with `status=active`.
- Source of truth is `list_templates` by canonical name.
- If cache rows are missing or stale, PM refreshes registry from `list_templates` before work begins.

## Root Guard Routine (PM)

Before normal routing/creation:

- Read tree via `get_collection_structure`.
- If non-anchor docs are found at root, move them:
  - spec/oracle -> `01_스펙`
  - PM plan/report -> `30_업무보드`
  - handoff -> `20_핸드오프`
  - ticket instance -> `10_티켓` under correct status
  - unknown legacy -> `90_아카이브`
- Record all move operations in Evidence Links.
- If anchors/lanes are missing, create and then write IDs into `구조 레지스트리`.
