#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$PACK_ROOT/skills"
TARGET_ROOT=""
DRY_RUN=0
SKILLS=()

usage() {
  cat <<'USAGE'
Usage:
  deploy.sh [--skill <name>] [--all] [--target <path>] [--dry-run]

Options:
  --skill <name>   Deploy one skill (repeatable)
  --all            Deploy all skills in this pack (default)
  --target <path>  Override install target path (default: ${CODEX_HOME}/skills)
  --dry-run        Show planned rsync operations only
  --help           Show this message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)
      [[ ${2-} ]] || { echo "--skill requires a value" >&2; exit 1; }
      SKILLS+=("$2")
      shift 2
      ;;
    --all)
      SKILLS=()
      shift
      ;;
    --target)
      TARGET_ROOT="${2%/}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ -z "$TARGET_ROOT" ]]; then
  if [[ -z "${CODEX_HOME:-}" ]]; then
    echo "ERROR: CODEX_HOME is not set. Export CODEX_HOME or pass --target <path>." >&2
    exit 1
  fi
  TARGET_ROOT="${CODEX_HOME%/}/skills"
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required. Please install rsync." >&2
  exit 1
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  while IFS= read -r entry; do
    SKILLS+=("$entry")
  done < <(ls -1 "$SKILL_ROOT")
fi

mkdir -p "$TARGET_ROOT"
for skill in "${SKILLS[@]}"; do
  SRC="$SKILL_ROOT/$skill"
  DST="$TARGET_ROOT/$skill"
  if [[ ! -d "$SRC" ]]; then
    echo "Skill not found: $skill" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: rsync -a --delete \"$SRC/\" \"$DST/\""
    continue
  fi

  mkdir -p "$DST"
  rsync -a --delete "$SRC/" "$DST/"
  echo "Deployed: $skill -> $DST"
done

printf '\nDeployment complete. Target: %s\n' "$TARGET_ROOT"
