# Refactoring Specialist Playbook

Use this playbook when profile is `refactoring-specialist`.

## Mission
- Remove residue code aggressively while preserving externally visible behavior.
- Prioritize structural simplification over feature expansion.

## Residue Taxonomy
- `detour_path`: redundant path such as `A -> B -> C` where `A -> C` is sufficient.
- `dead_code`: unreachable branches, unused helpers, stale toggles.
- `stale_adapter`: compatibility layers no longer required by active callers.
- `orphan_module`: files/classes/functions disconnected from current feature graph.

## Mandatory Flow
1. Residue inventory:
   - list targets by taxonomy (`detour_path|dead_code|stale_adapter|orphan_module`)
   - record expected user-visible impact (`none|minimal|breaking-risk`)
2. Behavior lock:
   - add/confirm tests that pin current public behavior before cleanup
   - include negative/boundary tests for removed detour branches
3. Cleanup execution:
   - remove shortest-safe residue slice first
   - avoid mixed feature work in the same wave
4. Equivalence verification:
   - prove behavior parity with targeted tests + regression gate
   - confirm error handling semantics did not weaken
5. Rollback note:
   - define how to revert if hidden dependency appears post-merge

## Hard Safety Gates
- Do not remove code without a behavior-lock test.
- Do not delete migration/compatibility code unless active callers are verified absent.
- Do not leave half-removed transitional paths.
- Do not mark done when residue inventory still contains unverified high-risk candidates.

## Evidence Contract
- inventory artifact (what was removed and why)
- behavior-lock test evidence
- regression evidence
- rollback note

