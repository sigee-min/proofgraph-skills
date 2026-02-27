#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sigee_gitignore_guard.sh <project-root>

Example:
  sigee_gitignore_guard.sh /path/to/repo
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

PROJECT_ROOT="$1"
if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "ERROR: Project root not found: $PROJECT_ROOT" >&2
  exit 1
fi

GITIGNORE_FILE="$PROJECT_ROOT/.gitignore"
BLOCK_START="# >>> SIGEE_GITIGNORE_POLICY >>>"
BLOCK_END="# <<< SIGEE_GITIGNORE_POLICY <<<"

if [[ ! -f "$GITIGNORE_FILE" ]]; then
  : > "$GITIGNORE_FILE"
fi

POLICY_FILE="$(mktemp)"
TMP_FILE="$(mktemp)"
cleanup() {
  rm -f "$POLICY_FILE" "$TMP_FILE"
}
trap cleanup EXIT

cat > "$POLICY_FILE" <<'EOF'
# >>> SIGEE_GITIGNORE_POLICY >>>
# .sigee governance: deny-by-default for git hygiene; allow only governed assets.
.sigee/*

# Keep repository-governed assets tracked (allow-list).
!.sigee/README.md
!.sigee/policies/
!.sigee/policies/**
!.sigee/product-truth/
!.sigee/product-truth/**
!.sigee/scenarios/
!.sigee/scenarios/**
!.sigee/dag/
!.sigee/dag/schema/
!.sigee/dag/schema/**
!.sigee/dag/pipelines/
!.sigee/dag/pipelines/**
!.sigee/dag/scenarios/
!.sigee/dag/scenarios/**
!.sigee/migrations/
!.sigee/migrations/**

# Local/generated assets must remain ignored.
.sigee/templates/
.sigee/.runtime/
.sigee/tmp/
.sigee/locks/
.sigee/evidence/
.sigee/reports/
# <<< SIGEE_GITIGNORE_POLICY <<<
EOF

if grep -Fq "$BLOCK_START" "$GITIGNORE_FILE"; then
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" -v policy_file="$POLICY_FILE" '
    BEGIN {in_block=0; replaced=0}
    $0 == start {
      if (replaced == 0) {
        while ((getline line < policy_file) > 0) {
          print line
        }
        close(policy_file)
        replaced=1
      }
      in_block=1
      next
    }
    in_block && $0 == end {
      in_block=0
      next
    }
    in_block == 0 { print }
    END {
      if (replaced == 0) {
        if (NR > 0) print ""
        while ((getline line < policy_file) > 0) {
          print line
        }
        close(policy_file)
      }
    }
  ' "$GITIGNORE_FILE" > "$TMP_FILE"
else
  cp "$GITIGNORE_FILE" "$TMP_FILE"
  if [[ -s "$TMP_FILE" ]]; then
    printf "\n" >> "$TMP_FILE"
  fi
  cat "$POLICY_FILE" >> "$TMP_FILE"
fi

if cmp -s "$GITIGNORE_FILE" "$TMP_FILE"; then
  echo "SIGEE gitignore policy already up to date: $GITIGNORE_FILE"
else
  cp "$TMP_FILE" "$GITIGNORE_FILE"
  echo "SIGEE gitignore policy applied: $GITIGNORE_FILE"
fi

REQUIRED_LINES=(
  ".sigee/*"
  ".sigee/templates/"
  ".sigee/.runtime/"
  ".sigee/tmp/"
  ".sigee/locks/"
  ".sigee/evidence/"
  ".sigee/reports/"
  "!.sigee/README.md"
  "!.sigee/policies/"
  "!.sigee/product-truth/"
  "!.sigee/scenarios/"
  "!.sigee/dag/schema/"
  "!.sigee/dag/pipelines/"
  "!.sigee/dag/scenarios/"
  "!.sigee/migrations/"
)

for line in "${REQUIRED_LINES[@]}"; do
  if ! grep -Fqx "$line" "$GITIGNORE_FILE"; then
    echo "ERROR: Missing required .gitignore rule: $line" >&2
    exit 1
  fi
done

echo "SIGEE gitignore policy verification passed: $GITIGNORE_FILE"
