# Test Gate Wrappers

## smoke
- Wrapper: `skills/tech-developer/scripts/test_smoke.sh`
- Purpose: fast regression confidence gate
- Hard gate: fails when no executable smoke command is configured

## e2e
- Wrapper: `skills/tech-developer/scripts/test_e2e.sh`
- Purpose: high-level flow validation gate
- Hard gate: fails when no executable e2e command is configured

Both wrappers support `--dry-run`.
