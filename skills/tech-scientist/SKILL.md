---
name: tech-scientist
description: Evidence-backed scientific and engineering translation for complex simulation, numerical methods, math-heavy algorithm design, and AI/ML training pipeline architecture. Use when tasks require paper-grounded reasoning (for example 3D physics simulation, optimization, PDE/ODE, convergence/stability analysis, model training workflow design), and the output must be project-ready pseudocode, validation plans, and integration handoff prompts for tech-planner and tech-developer.
---

# Tech Scientist

## Operating Mode
- Operate in skill-only mode. Do not depend on `AGENTS.md`, multi-agent roles, or role-specific runtime config.
- Treat `.sigee` as governance source (`policy`, `template`, `migration`), and treat runtime execution paths as configurable via `runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}`.
- Prioritize primary sources (papers, RFCs, official docs, standards).
- Separate clearly:
  - research feasibility (theory-level)
  - project applicability (repo/system constraints)
- Never present unsupported claims as facts.

## Trigger Signals
Use this skill when user requests include one or more of the following:
- complex simulation design (`3D`, `physics`, `fluid`, `collision`, `dynamics`)
- math-heavy solution design (`PDE/ODE`, `optimization`, `numerical method`, `stability`, `convergence`)
- AI/ML design (`training pipeline`, `fine-tuning`, `inference workflow`, `model evaluation`, `MLOps`)
- paper-grounded algorithm selection or comparison
- scientific/engineering reasoning that must be converted into implementation-ready pseudocode

## Workflow
1. Formulate the problem precisely.
- Use `references/problem-formulation.md`.
- Fix input/output, constraints, objective, units, tolerances, and compute budget.

2. Build literature evidence.
- Use `references/literature-evidence-matrix.md`.
- Search recent and foundational primary sources; Scholar can be entry point.
- Record source URL, assumptions, complexity, validation setup, and reproducibility status.

3. Evaluate applicability.
- Score each candidate method against project constraints.
- Mark inaccessible papers or unverifiable claims as `Unverified`.

4. Translate into implementation design.
- Use `references/pseudocode-contract.md`.
- Produce pseudocode with parameter definitions, complexity, and stability notes.
- Define module boundaries and data contracts for integration.
- For AI/ML tasks, also use `references/ai-ml-pipeline-design.md` to define data -> train -> evaluate -> serve workflow.

5. Define validation and benchmark plan.
- Use `references/validation-and-benchmarks.md`.
- Include TDD path, numerical verification path, and benchmark gates.

6. Produce handoff prompts.
- Use `references/handoff-prompts.md`.
- Provide copy-ready markdown blocks titled `다음 실행 프롬프트` for:
  - `$tech-planner`
  - `$tech-developer`

## Progress Tracking (Required)
- For non-trivial scientific analysis (2+ meaningful phases), call `update_plan` before deep research starts.
- Keep plan size between 4 and 8 steps.
- Allowed statuses:
  - `pending`
  - `in_progress`
  - `completed`
- Keep exactly one step as `in_progress` at a time.
- Update progress at each major phase:
  - problem formulation
  - literature/evidence matrix completion
  - applicability and trade-off analysis
  - pseudocode/integration design
  - validation and handoff completion
- Before final response, mark all steps `completed`.

## Output Contract (Mandatory Order)
Return sections in this order:
1. Non-technical summary (what problem, why this approach, expected impact)
2. Problem formulation (formalized objective, constraints, assumptions)
3. Evidence matrix (source link, year, contribution, assumptions, limits, applicability)
4. Recommended approach and alternatives (with trade-offs)
5. Project-ready pseudocode (parameterized + complexity + stability comments)
6. Integration plan (module/file boundaries, runtime-root paths, test hooks, performance budget)
7. Validation and benchmark plan (metrics, baseline, fail criteria)
8. Risks, unknowns, and open decisions
9. `다음 실행 프롬프트` markdown blocks (`$tech-planner`, `$tech-developer`)
10. For AI/ML tasks: training/inference pipeline blueprint (data, train, eval, serve, monitor)

## AI/ML Pipeline Rules
- Define task type clearly (`classification`, `regression`, `generation`, `control`, `forecasting`).
- Define split strategy and leakage prevention explicitly.
- Separate offline metrics and online metrics.
- Record reproducibility contract:
  - random seeds
  - dataset version
  - model artifact version
  - environment/toolchain version
- Include rollback and fallback path for model degradation.

## Safety and Quality Rules
- Do not fabricate citations, URLs, benchmarks, or empirical claims.
- Do not cite without links.
- Mark inaccessible or unverified material as `Unverified`.
- Add confidence label per major recommendation: `High`, `Medium`, `Low`.
- Explicitly separate:
  - "paper says"
  - "likely in this project"
- If evidence is insufficient, stop recommendation escalation and explain what evidence is missing.
- For AI/ML tasks, explicitly flag leakage risk, data drift risk, and distribution shift risk.

## Quality Gate
- Run local quality gate before publishing major updates to this skill:
  - `scripts/quality_gate.sh`
- Gate behavior:
  - validates skill schema (`quick_validate.py`)
  - runs citation lint on sample outputs
  - runs output-contract smoke tests for 2 sample responses (simulation + AI/ML)

## Reference Loading Guide
- Always load first:
  - `references/problem-formulation.md`
  - `references/literature-evidence-matrix.md`
- Load by task type:
  - simulation-heavy: `references/simulation-design-checklist.md`
  - pseudocode translation: `references/pseudocode-contract.md`
  - AI/ML training workflow: `references/ai-ml-pipeline-design.md`
  - validation planning: `references/validation-and-benchmarks.md`
  - handoff generation: `references/handoff-prompts.md`
  - stability regression check: `references/samples/*.md` with `scripts/output_contract_smoke.sh`

## References
- Problem framing: `references/problem-formulation.md`
- Literature matrix: `references/literature-evidence-matrix.md`
- Simulation checks: `references/simulation-design-checklist.md`
- Pseudocode contract: `references/pseudocode-contract.md`
- AI/ML pipeline design: `references/ai-ml-pipeline-design.md`
- Validation and benchmarks: `references/validation-and-benchmarks.md`
- Handoff prompt templates: `references/handoff-prompts.md`
- Smoke samples: `references/samples/sample-response-simulation.md`, `references/samples/sample-response-aiml.md`

## Scripts
- Citation lint: `scripts/citation_lint.sh`
- Output-contract smoke check: `scripts/output_contract_smoke.sh`
- Full quality gate: `scripts/quality_gate.sh`
