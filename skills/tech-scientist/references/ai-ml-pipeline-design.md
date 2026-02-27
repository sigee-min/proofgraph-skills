# AI/ML Pipeline Design Contract

Use this template when the task involves model training, fine-tuning, or inference workflow design.

## 1) Task and Objective
- Problem type (`classification`, `regression`, `generation`, `control`, `forecasting`):
- Primary target metric:
- Business/engineering objective:

## 2) Data Contract
- Data sources and ownership:
- Labeling strategy and quality checks:
- Split strategy (`train/val/test`, temporal split, group split):
- Leakage prevention rules:
- Dataset/version identifier:

## 3) Model Candidate Set
- Baseline model(s):
- Candidate model(s):
- Selection rationale:
- Complexity and serving constraints:

## 4) Training Workflow
- Preprocessing/feature pipeline:
- Training loop outline:
- Hyperparameter search strategy:
- Early stopping / regularization policy:
- Reproducibility controls (seed, environment, artifact version):

## 5) Evaluation Workflow
- Offline metrics and thresholds:
- Robustness checks (OOD, perturbation, edge slices):
- Fairness/safety checks (if applicable):
- Ablation and error analysis plan:

## 6) Inference and Serving Workflow
- Inference topology (batch/stream/online):
- Latency and throughput budgets:
- Caching, fallback, retry strategy:
- Model versioning and rollback policy:

## 7) Monitoring and Operations
- Online metrics:
- Drift detection signals:
- Retrain trigger policy:
- Incident response and rollback steps:

## 8) Output Requirements
- Project-ready pseudocode for data->train->eval->serve.
- Integration mapping to module boundaries and verification hooks (runtime path details are optional appendix).
- One `다음 실행 프롬프트` block for planning review intent.
