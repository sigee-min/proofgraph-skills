#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  citation_lint.sh <response-file> [--min-urls <n>]

Examples:
  citation_lint.sh response.md
  citation_lint.sh response.md --min-urls 3
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET_FILE="$1"
shift
MIN_URLS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-urls)
      MIN_URLS="${2:-}"
      shift 2
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

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "ERROR: file not found: $TARGET_FILE" >&2
  exit 1
fi

if ! [[ "$MIN_URLS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --min-urls must be an integer" >&2
  exit 1
fi

if rg -n "TODO|TBD|\\[TODO\\]" "$TARGET_FILE" >/dev/null 2>&1; then
  echo "ERROR: unresolved placeholder found (TODO/TBD)." >&2
  exit 1
fi

if ! rg -n "Evidence matrix|Evidence Matrix" "$TARGET_FILE" >/dev/null 2>&1; then
  echo "ERROR: missing 'Evidence matrix' section." >&2
  exit 1
fi

url_count="$(rg -o "https?://[^[:space:])>]+" "$TARGET_FILE" | wc -l | tr -d ' ')"
if [[ "$url_count" -lt "$MIN_URLS" ]]; then
  echo "ERROR: expected at least $MIN_URLS URL(s), found $url_count." >&2
  exit 1
fi

echo "citation_lint passed: urls=$url_count file=$TARGET_FILE"

