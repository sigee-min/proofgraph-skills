#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  quality_gate.sh [--skip-validate]

Checks:
  1) quick_validate for the skill folder
  2) output contract smoke check for simulation sample
  3) output contract smoke check for AI/ML sample
USAGE
}

SKIP_VALIDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-validate)
      SKIP_VALIDATE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -z "${CODEX_HOME:-}" ]]; then
  echo "ERROR: CODEX_HOME is required for validator lookup (expected: \$CODEX_HOME/skills/.system/skill-creator/scripts/quick_validate.py)." >&2
  exit 1
fi
SYS_VALIDATOR="$CODEX_HOME/skills/.system/skill-creator/scripts/quick_validate.py"
SIM_SAMPLE="$SKILL_DIR/references/samples/sample-response-simulation.md"
AI_SAMPLE="$SKILL_DIR/references/samples/sample-response-aiml.md"

if [[ "$SKIP_VALIDATE" -eq 0 ]]; then
  if [[ ! -f "$SYS_VALIDATOR" ]]; then
    echo "ERROR: quick_validate.py not found at $SYS_VALIDATOR" >&2
    exit 1
  fi
  python3 "$SYS_VALIDATOR" "$SKILL_DIR"
fi

if [[ ! -x "$SCRIPT_DIR/output_contract_smoke.sh" ]]; then
  echo "ERROR: missing executable output_contract_smoke.sh" >&2
  exit 1
fi

"$SCRIPT_DIR/output_contract_smoke.sh" "$SIM_SAMPLE"
"$SCRIPT_DIR/output_contract_smoke.sh" "$AI_SAMPLE" --ai

echo "quality_gate passed: $SKILL_DIR"
