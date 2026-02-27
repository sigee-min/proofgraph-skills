## Non-technical summary
- We design an AI training and inference pipeline with leakage controls and rollback readiness.

## Verification confidence
- Confidence: High for workflow design, Medium for model-specific threshold tuning.
- Basis: operational debt + leakage references, explicit offline/online fail criteria.

## Remaining risks, unknowns, and open decisions
- Risk: concept drift in seasonal traffic segments.
- Unknown: robustness for long-tail categories.

## Problem formulation
- Objective: improve F1 while keeping inference p95 latency within service SLO.
- Constraints: temporal split, weekly retraining budget, strict artifact versioning.

## Evidence matrix
| Source | URL | Year | Core Contribution | Key Assumptions | Complexity | Validation Setup | Reproducibility | Project Applicability | Confidence |
|---|---|---:|---|---|---|---|---|---|---|
| Hidden technical debt in ML systems | https://papers.nips.cc/paper_files/paper/2015/hash/86df7dcfd896fcaf2674f757a2463eba-Abstract.html | 2015 | ML pipeline debt and operational risks | Production system context | System-level | Industrial case analysis | High | Strong for workflow safeguards | High |
| Data leakage overview | https://arxiv.org/abs/2307.01283 | 2023 | Leakage taxonomy and prevention patterns | Supervised learning setup | N/A | Survey comparisons | Medium | Useful for split and feature policy | Medium |

## Recommended approach and alternatives
- Recommended: feature-store based train/serve consistency with temporal split and signed artifacts.
- Alternative 1: ad-hoc notebook pipeline (rejected due to reproducibility risk).
- Alternative 2: single offline metric gate only (rejected due to online drift risk).

## Project-ready pseudocode
```text
Algorithm: train_eval_serve_pipeline
Inputs:
  - dataset_v: versioned dataset
  - config_v: training config
Outputs:
  - model_artifact_v
  - evaluation_report_v
Parameters:
  - seed
  - split_policy
  - threshold_f1
Procedure:
  1. Validate schema and leakage guards.
  2. Split data with temporal policy.
  3. Train baseline and candidate models.
  4. Evaluate by slice and overall metrics.
  5. Publish candidate only if thresholds and latency SLO pass.
Complexity:
  - Time: O(training_epochs * samples)
  - Space: O(model + feature cache)
Stability/Convergence Notes:
  - Track variance across seeds and enforce retry budget.
```

## Integration plan
- Integration boundaries: planning artifacts, evidence collection, deployment safeguards.
- Modules: data validation, trainer, evaluator, serving adapter, drift monitor.
- Tests: data integrity, deterministic replay, inference budget checks.

## Validation and benchmark plan
- Offline: F1/AUC by slice with minimum thresholds.
- Online readiness: latency p95, error rate, rollback trigger tests.
- Fail criteria: metric regression beyond guardrail or SLO breach.

## training/inference pipeline blueprint (data, train, eval, serve, monitor)
- Data: versioned ingest + leakage checks.
- Train: reproducible job with pinned seed/env.
- Eval: baseline delta + slice report.
- Serve: signed artifact rollout with canary.
- Monitor: drift alarms and rollback gate.

## 다음 실행 프롬프트
```md
위 AI/ML 파이프라인 설계를 실행 계획으로 분해해줘.
```
