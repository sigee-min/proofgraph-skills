# Scenario Catalog

Place reusable feature scenario notes here.
This folder is for human-readable planning context, not executable DAG inputs.

Executable scenario files are managed at:
- `<runtime-root>/dag/scenarios/*.scenario.yml`

Reference notes in this folder should include:
- objective
- in/out scope
- dependencies
- validation path
- `outcome_id` and `capability_id` linked to `.sigee/product-truth/`
- mandatory test bundles:
  - `unit_normal_tests` (2)
  - `unit_boundary_tests` (2)
  - `unit_failure_tests` (2)
  - `boundary_smoke_tests` (5)
