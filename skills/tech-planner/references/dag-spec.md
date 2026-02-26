# DAG Spec

## Required Pipeline Fields
- pipeline id
- node id
- node type
- deps
- run
- verify
- changed-only selection signal (`changed_paths`)

## Node Field Semantics
- `id`: stable unique key
- `type`: execution lane classification
- `deps`: predecessors that must pass first
- `run`: command run in repo root
- `verify`: post-run check
- `changed_paths`: impacts matching for changed-only mode

## Validation Expectations
- unknown deps are invalid
- cycles are invalid
- run/verify must be non-empty
