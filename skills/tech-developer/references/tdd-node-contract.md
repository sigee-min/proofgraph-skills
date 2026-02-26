# TDD Node Contract

Every feature scenario chain must follow:
- red: failing test signal
- impl: implementation step
- green: passing test signal
- verify: explicit post-condition command per node

Required node types:
- `tdd_red`
- `impl`
- `tdd_green`

Hard-mode constraints:
- scenario definitions must provide `red_run`, `impl_run`, `green_run`, `verify`
- `red_run`, `impl_run`, `green_run` must be executable commands (no-op values such as `true` or `:` are invalid)
- `verify` must be an executable check command (no-op values such as `true` or `:` are invalid)
