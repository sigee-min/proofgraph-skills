## Non-technical summary
- We choose a stable integration approach for rigid-body collision simulation with bounded drift.

## Problem formulation
- Objective: minimize penetration and energy drift under fixed compute budget.
- Constraints: real-time step at 60Hz, deterministic replay required.

## Evidence matrix
| Source | URL | Year | Core Contribution | Key Assumptions | Complexity | Validation Setup | Reproducibility | Project Applicability | Confidence |
|---|---|---:|---|---|---|---|---|---|---|
| Baraff and Witkin | https://www.cs.cmu.edu/~baraff/sigcourse/ | 1997 | Constraint-based dynamics foundations | Rigid body assumptions | O(n^3) worst-case solve | Analytical and simulation examples | Partial | High for baseline design | Medium |
| Hairer et al. summary | https://arxiv.org/abs/1807.05224 | 2018 | Geometric integration properties | Hamiltonian-like system structure | Method-dependent | Numerical experiments | Reproducible preprint | Useful for drift control strategy | Medium |

## Recommended approach and alternatives
- Recommended: semi-implicit integration + iterative constraint solve.
- Alternative 1: explicit Euler (rejected due to instability under stiff contacts).
- Alternative 2: high-order non-symplectic solver (rejected for runtime budget risk).

## Project-ready pseudocode
```text
Algorithm: rigid_body_step
Inputs:
  - state_t: state
  - contacts_t: list
Outputs:
  - state_t1: state
Parameters:
  - dt: timestep
  - max_iter: constraint iterations
Procedure:
  1. Predict velocity and position with semi-implicit update.
  2. Resolve contacts iteratively with projected corrections.
  3. Clamp correction and finalize state.
Complexity:
  - Time: O(max_iter * contacts)
  - Space: O(objects + contacts)
Stability/Convergence Notes:
  - Keep dt within stability budget and monitor drift.
```

## Integration plan
- Runtime path: `<runtime-root>/dag/scenarios/` and `<runtime-root>/plans/`.
- Modules: solver core, contact resolver, validation harness.
- Tests: deterministic replay + invariant checks.

## Validation and benchmark plan
- Metrics: penetration depth, energy drift, frame time p95.
- Baseline: explicit Euler implementation.
- Fail criteria: drift above threshold or p95 latency budget violation.

## Risks, unknowns, and open decisions
- Risk: high-contact scenes may violate latency budget.
- Unknown: sensitivity of stability to contact ordering.

## 다음 실행 프롬프트
```md
$tech-planner
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

위 시뮬레이션 설계를 실행 계획으로 분해해줘.
```

```md
$tech-developer
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

승인된 계획 기준으로 strict 실행하고 검증 근거를 남겨줘.
```

