# Cutover Checklist

## pre-cutover

- owner assigned for migration command and rollback authority
- checkpoint list finalized for docs, scripts, and policy references
- compatibility tests green in staging branch

## cutover

- apply planned path switch in controlled order
- record checkpoint after each migration step
- validate ticket and reporting flows immediately

## post-cutover

- confirm governance docs resolve from `.sigee`
- confirm runtime paths still execute as expected
- publish owner-approved migration summary

## rollback

- restore previous path configuration
- restore pre-cutover scripts/config
- re-run smoke checks and mark final checkpoint
