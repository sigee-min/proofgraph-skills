# ProofGraph Skills

A skill-only workflow pack for Codex that standardizes **planning -> implementation -> validation** without relying on AGENTS.md or multi-agent runtime features.

## Concept

This repository is built around four principles:

1. **Skill-only operation**
   - The workflow is enforced by skill contracts and helper scripts.
   - Users can drive the system through natural-language requests.

2. **Planner-centric orchestration**
   - `tech-planner` owns loop control and final completion authority.
   - `tech-developer` and `tech-scientist` hand work back to planner review.

3. **Strict test-first execution**
   - Runtime flow is strict by default.
   - Verification evidence is mandatory for completion.

4. **Governance vs runtime separation**
   - Governance and long-lived intent live in `.sigee/`.
   - Volatile execution artifacts live in `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`.

## Included Skills

- `tech-planner`
  - Requirement interview, plan definition, scenario/DAG planning, queue orchestration, done-gate review.
- `tech-developer`
  - Plan-driven implementation, strict validation, wave-based execution in queue mode, evidence-first handoff.
- `tech-scientist`
  - Paper-backed science/engineering/math/AI-ML method translation into project-ready pseudocode and validation plans.

## Operating Model

### 1) Product Truth SSoT

Planning truth is anchored in `.sigee/product-truth/`:

- `outcomes.yaml`
- `capabilities.yaml`
- `traceability.yaml`

This maps outcome -> capability -> scenario -> DAG node contract.

### 2) Orchestration Queues

Queue root:

- `<runtime-root>/orchestration/queues/`

Standard queues:

- `planner-inbox`
- `scientist-todo`
- `developer-todo`
- `planner-review`
- `blocked`
- `done` (transient completion lane)

### 3) Done and Archive Behavior

Completion is planner-gated and archive-backed:

- Only `planner-review -> done` is allowed.
- `done` transition requires:
  - planner actor authority,
  - non-empty evidence links,
  - passing verification gate.
- Completed rows are automatically archived to:
  - `<runtime-root>/orchestration/archive/done-YYYY-MM.tsv`
- Archive maintenance is internal via `orchestration_archive.sh` (`status`, `flush-done`, `clear`).

### 4) Mandatory DAG Test Contract

Per scenario, the following counts are enforced:

- `unit_normal = 2`
- `unit_boundary = 2`
- `unit_failure = 2`
- `boundary_smoke = 5`

## Runtime and Paths

Default runtime root:

- `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`

Typical runtime outputs:

- plans: `<runtime-root>/plans/`
- scenarios: `<runtime-root>/dag/scenarios/`
- pipelines: `<runtime-root>/dag/pipelines/`
- state: `<runtime-root>/dag/state/`
- evidence: `<runtime-root>/evidence/`
- queues: `<runtime-root>/orchestration/queues/`
- done archive: `<runtime-root>/orchestration/archive/`

## Install

Default installation target:

- `${CODEX_HOME}/skills`

Recommended UX is chat-first (let Codex install internally), for example:

```md
$skill-installer
Install tech-planner, tech-developer, and tech-scientist from this repository into my Codex skills path.
```

Maintainer scripts are available in `scripts/` for local deployment automation.

## Minimal Usage (Chat-First)

### Planning

```md
$tech-planner
runtime-root=${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}

Create an execution-ready plan for improving our checkout flow.
Include acceptance criteria, validation gates, and risks.
```

### Implementation

```md
$tech-developer
runtime-root=${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}

Execute the approved plan end-to-end in strict mode,
then report results in content-first language with evidence summary.
```

### Scientific / AI-ML Design

```md
$tech-scientist
runtime-root=${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}

For this simulation + AI pipeline problem, provide literature-backed pseudocode,
validation design, and handoff prompts for planner and developer.
```

## Git Hygiene

This repository uses deny-by-default policy for `.sigee`.

Tracked by default:

- governance and intent assets under `.sigee/policies`, `.sigee/product-truth`, `.sigee/scenarios`, `.sigee/dag/schema`, `.sigee/dag/pipelines`, `.sigee/migrations`.

Ignored by default:

- runtime and volatile artifacts under `.sigee/.runtime/**` (including queues and archives), `.sigee/evidence/**`, `.sigee/reports/**`, `.sigee/templates/**`.

## Repository Layout

- `skills/tech-planner/`
- `skills/tech-developer/`
- `skills/tech-scientist/`
- `.sigee/` (governance and product-truth baseline)
- `scripts/` (deployment/install helpers)
- `CHANGELOG.md`

## Notes

- This pack is optimized for natural-language operation.
- Users should not need to run queue/archive scripts manually.
- When users request cleanup (for example archive purge), the skills should execute it internally.
