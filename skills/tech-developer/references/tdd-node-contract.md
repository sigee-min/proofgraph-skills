# TDD Node Contract

Every feature scenario chain must follow:
- red: failing test signal
- impl: implementation step
- unit_normal: mandatory happy-path unit tests
- unit_boundary: mandatory boundary unit tests
- unit_failure: mandatory negative/failure unit tests
- green: passing test signal
- verify: explicit post-condition command per scenario chain (`red/impl/green` must use executable checks)
- boundary_smoke: mandatory linked-boundary smoke coverage

Required node types:
- `tdd_red`
- `impl`
- `unit_normal`
- `unit_boundary`
- `unit_failure`
- `tdd_green`
- `smoke_boundary`

Hard-mode constraints:
- scenario definitions must provide `red_run`, `impl_run`, `green_run`, `verify`
- scenario definitions must provide:
  - `unit_normal_tests` (exactly 2 commands)
  - `unit_boundary_tests` (exactly 2 commands)
  - `unit_failure_tests` (exactly 2 commands)
  - `boundary_smoke_tests` (exactly 5 commands)
- `red_run`, `impl_run`, `green_run` must be executable commands (no-op values such as `true` or `:` are invalid)
- scenario `verify` must be an executable check command (no-op values such as `true` or `:` are invalid)
- generated helper nodes (`unit_*`, `smoke_boundary`, shared gates) may use wrapper-level `verify: true` because their `run` command is already the executable test gate
