#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy.sh"
DEFAULT_TARGET=""

TARGET_ROOT="$DEFAULT_TARGET"
DRY_RUN=0
ASSUME_YES=0
DEPLOY_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  install-macos.sh [--skill <name>] [--all] [--target <path>] [--dry-run] [--yes]

Options:
  --skill <name>   Install one skill (repeatable)
  --all            Install all skills in this pack (default)
  --target <path>  Override install target (default: ${CODEX_HOME}/skills)
  --dry-run        Show planned actions without copying files
  --yes            Skip confirmation prompt
  --help           Show this message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)
      [[ ${2-} ]] || { echo "--skill requires a value" >&2; exit 1; }
      DEPLOY_ARGS+=("--skill" "$2")
      shift 2
      ;;
    --all)
      DEPLOY_ARGS+=("--all")
      shift
      ;;
    --target)
      [[ ${2-} ]] || { echo "--target requires a value" >&2; exit 1; }
      TARGET_ROOT="${2%/}"
      DEPLOY_ARGS+=("--target" "$TARGET_ROOT")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      DEPLOY_ARGS+=("--dry-run")
      shift
      ;;
    --yes)
      ASSUME_YES=1
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: install-macos.sh is for macOS only (detected: $(uname -s))." >&2
  exit 1
fi

if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
  echo "ERROR: deploy script is missing or not executable: $DEPLOY_SCRIPT" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required. Install it first (e.g. brew install rsync)." >&2
  exit 1
fi

if [[ ${#DEPLOY_ARGS[@]} -eq 0 ]]; then
  DEPLOY_ARGS+=("--all")
fi

echo "Install root: $PACK_ROOT"
echo "Target path: $TARGET_ROOT"

if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Proceed with installation on this macOS machine? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *)
      echo "Installation cancelled."
      exit 0
      ;;
  esac
fi

"$DEPLOY_SCRIPT" "${DEPLOY_ARGS[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "Dry-run completed."
  exit 0
fi

echo
echo "Installed skills under: $TARGET_ROOT"
if [[ -d "$TARGET_ROOT" ]]; then
  ls -1 "$TARGET_ROOT" | sed 's/^/- /'
fi
