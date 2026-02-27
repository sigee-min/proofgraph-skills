# Windows Cross-Platform Governance Gate Runbook

## Purpose

- Keep release quality equivalent across macOS/Linux/Windows.
- Ensure deployment is blocked whenever any OS verification fails.
- Give operators a short, deterministic rollback path.

## Gate Model

### Job 1: Governance Matrix
- Runs the same governance verification on:
  - `ubuntu-latest`
  - `macos-latest`
  - `windows-latest`
- Includes:
  - install/deploy parity dry-run check
  - governance verification bundle

### Job 2: Deployment Gate
- Depends on Governance Matrix result.
- If matrix result is not `success`, the gate fails and deployment must stop.

## Operator Decision Flow

1. Check `Deployment Gate` result.
2. If failed, open failed OS lane in Governance Matrix.
3. Classify failure:
   - dependency setup issue (tool install/bootstrap)
   - governance verification issue (policy/traceability/validation)
   - runtime regression issue (build/run/changed-only behavior)
4. Apply rollback level based on blast radius.
5. Re-run Governance Matrix on all three OS before re-opening deployment.

## Rollback Levels

### Level A: Fast Safety Rollback (Preferred)
- Goal: stop risky release quickly.
- Action:
  - revert the latest CI/workflow change that introduced the failure.
  - keep governance gate blocking behavior unchanged.
- Exit criteria:
  - Governance Matrix passes on all three OS.
  - Deployment Gate returns to `success`.

### Level B: Targeted Runtime Rollback
- Goal: restore previous known-good runtime path while preserving gate strictness.
- Action:
  - restore previous known-good wrapper/core path for the failing component only.
  - avoid broad rollback unrelated to the failing lane.
- Exit criteria:
  - failing lane returns to pass.
  - no new failures in other OS lanes.

### Level C: Full Wave Rollback
- Goal: recover service when failure is systemic.
- Action:
  - roll back to the last release point that passed all three OS lanes.
  - re-run full governance bundle and confirm gate pass before new release.
- Exit criteria:
  - full matrix green.
  - deployment gate green.

## Release Readiness Checklist

- all matrix lanes green (ubuntu/macos/windows)
- deployment gate green
- no unresolved rollback action item
- operator handoff note updated with root cause and prevention action

## Communication Template (Operator)

- What failed: `<lane + failing stage>`
- User impact: `<release blocked / no live regression / live mitigation>`
- Immediate action: `<rollback level A/B/C + owner>`
- Re-open condition: `<all three OS lanes green + deployment gate green>`
