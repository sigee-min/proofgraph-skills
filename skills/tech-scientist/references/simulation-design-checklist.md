# Simulation Design Checklist

Apply when the problem includes simulation, dynamics, or numerical integration.

## Model Definition
- State variables are explicit and unit-consistent.
- Time stepping strategy is defined (`fixed` or `adaptive`).
- Boundary and initial conditions are complete.

## Numerical Stability
- Integrator choice is justified (for example Euler, RK4, symplectic).
- Stability constraints are documented (for example CFL-like bounds).
- Error propagation and drift control are specified.

## Physics and Constraints
- Conservation/invariant targets are listed (if applicable).
- Collision/contact handling policy is explicit.
- Constraint solving order is defined.

## Computational Design
- Complexity per step and total horizon estimate are provided.
- Parallelization opportunities and bottlenecks are identified.
- Determinism strategy (seed, ordering, precision mode) is defined.

## Validation Readiness
- Analytical sanity checks defined.
- Reference scenario tests defined.
- Failure signatures and debug observables defined.
