#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dag_compile.sh [--project-root <path>] [--source <ux-scenario-dir>] [--out <runtime-scenario-dir>] [--check-only]

Examples:
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_compile.sh
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_compile.sh --source .sigee/dag/scenarios --out .sigee/.runtime/dag/scenarios
  SIGEE_RUNTIME_ROOT=.sigee/.runtime dag_compile.sh --check-only
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

PROJECT_ROOT=""
SOURCE_DIR=".sigee/dag/scenarios"
OUT_DIR="${RUNTIME_ROOT}/dag/scenarios"
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --source)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --help|-h)
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

if [[ -z "$PROJECT_ROOT" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
  else
    PROJECT_ROOT="$(pwd)"
  fi
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

resolve_path() {
  local value="$1"
  if [[ "$value" == /* ]]; then
    printf "%s" "$value"
  else
    printf "%s/%s" "$PROJECT_ROOT" "$value"
  fi
}

sha256_of() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "ERROR: shasum/sha256sum not found." >&2
    exit 1
  fi
}

to_repo_rel() {
  local abs="$1"
  local normalized
  normalized="$(cd "$(dirname "$abs")" && pwd)/$(basename "$abs")"
  if [[ "$normalized" == "$PROJECT_ROOT/"* ]]; then
    printf "%s" "${normalized#$PROJECT_ROOT/}"
  else
    printf "%s" "$normalized"
  fi
}

trim() {
  local value="$1"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf "%s" "$value"
}

extract_scenario_id() {
  local file="$1"
  local value
  value="$(sed -nE 's/^id:[[:space:]]*"?([A-Za-z0-9._-]+)"?[[:space:]]*$/\1/p' "$file" | head -n1)"
  printf "%s" "$(trim "$value")"
}

SOURCE_DIR_ABS="$(resolve_path "$SOURCE_DIR")"
OUT_DIR_ABS="$(resolve_path "$OUT_DIR")"
MANIFEST_FILE="$OUT_DIR_ABS/.compiled-manifest.tsv"

run_check() {
  if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "ERROR: compiled manifest not found: $MANIFEST_FILE" >&2
    exit 1
  fi

  local runtime_count=0
  while IFS= read -r _f; do
    runtime_count=$((runtime_count + 1))
  done < <(find "$OUT_DIR_ABS" -maxdepth 1 -type f -name '*.scenario.yml' | sort)

  local row_count=0
  local id source_rel source_sha runtime_rel runtime_sha generated_at
  while IFS=$'\t' read -r id source_rel source_sha runtime_rel runtime_sha generated_at; do
    if [[ "$id" == "id" ]]; then
      continue
    fi
    [[ -z "$id" ]] && continue
    row_count=$((row_count + 1))

    local source_path runtime_path source_actual runtime_actual header
    source_path="$PROJECT_ROOT/$source_rel"
    runtime_path="$PROJECT_ROOT/$runtime_rel"

    if [[ ! -f "$source_path" ]]; then
      echo "ERROR: source scenario missing for compiled row '$id': $source_path" >&2
      exit 1
    fi
    if [[ ! -f "$runtime_path" ]]; then
      echo "ERROR: runtime scenario missing for compiled row '$id': $runtime_path" >&2
      exit 1
    fi

    source_actual="$(sha256_of "$source_path")"
    runtime_actual="$(sha256_of "$runtime_path")"
    if [[ "$source_actual" != "$source_sha" ]]; then
      echo "ERROR: source scenario changed after compile for '$id'. Rebuild DAG pipeline first." >&2
      exit 1
    fi
    if [[ "$runtime_actual" != "$runtime_sha" ]]; then
      echo "ERROR: runtime scenario drift detected for '$id' (manual edit suspected): $runtime_path" >&2
      exit 1
    fi

    header="$(head -n 1 "$runtime_path")"
    if [[ "$header" != "# GENERATED_FROM: $source_rel" ]]; then
      echo "ERROR: generated header mismatch for '$id': $runtime_path" >&2
      exit 1
    fi
  done < "$MANIFEST_FILE"

  if [[ "$row_count" -ne "$runtime_count" ]]; then
    echo "ERROR: compiled manifest/runtime file count mismatch (manifest=$row_count runtime=$runtime_count)" >&2
    exit 1
  fi

  echo "DAG compile check passed: source=$SOURCE_DIR_ABS runtime=$OUT_DIR_ABS files=$row_count"
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  run_check
  exit 0
fi

if [[ ! -d "$SOURCE_DIR_ABS" ]]; then
  echo "ERROR: source scenario directory not found: $SOURCE_DIR_ABS" >&2
  exit 1
fi

SCENARIO_FILES=()
while IFS= read -r file; do
  SCENARIO_FILES+=("$file")
done < <(find "$SOURCE_DIR_ABS" -maxdepth 1 -type f -name '*.scenario.yml' | sort)

if [[ ${#SCENARIO_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no source scenarios found in $SOURCE_DIR_ABS" >&2
  exit 1
fi

mkdir -p "$OUT_DIR_ABS"
find "$OUT_DIR_ABS" -maxdepth 1 -type f -name '*.scenario.yml' -delete

TMP_MANIFEST="$(mktemp)"
cleanup() {
  rm -f "$TMP_MANIFEST"
}
trap cleanup EXIT

printf "id\tsource_rel\tsource_sha256\truntime_rel\truntime_sha256\tcompiled_at\n" > "$TMP_MANIFEST"

SEEN_IDS=""
has_seen_id() {
  local target="$1"
  local item
  local -a ids=()
  IFS=',' read -r -a ids <<<"$SEEN_IDS" || true
  for item in "${ids[@]:-}"; do
    [[ -z "$item" ]] && continue
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

for source_file in "${SCENARIO_FILES[@]}"; do
  scenario_id="$(extract_scenario_id "$source_file")"
  if [[ -z "$scenario_id" ]]; then
    echo "ERROR: missing scenario id in source file: $source_file" >&2
    exit 1
  fi
  if has_seen_id "$scenario_id"; then
    echo "ERROR: duplicate scenario id in source catalog: $scenario_id" >&2
    exit 1
  fi
  if [[ -z "$SEEN_IDS" ]]; then
    SEEN_IDS="$scenario_id"
  else
    SEEN_IDS="${SEEN_IDS},${scenario_id}"
  fi

  source_rel="$(to_repo_rel "$source_file")"
  source_sha="$(sha256_of "$source_file")"
  runtime_file="$OUT_DIR_ABS/${scenario_id}.scenario.yml"
  runtime_rel="$(to_repo_rel "$runtime_file")"
  compiled_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  {
    echo "# GENERATED_FROM: $source_rel"
    echo "# SOURCE_SHA256: $source_sha"
    echo "# GENERATED_AT: $compiled_at"
    cat "$source_file"
  } > "$runtime_file"

  runtime_sha="$(sha256_of "$runtime_file")"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$scenario_id" "$source_rel" "$source_sha" "$runtime_rel" "$runtime_sha" "$compiled_at" >> "$TMP_MANIFEST"
done

mv "$TMP_MANIFEST" "$MANIFEST_FILE"

run_check
echo "DAG scenarios compiled: source=$SOURCE_DIR_ABS runtime=$OUT_DIR_ABS"
