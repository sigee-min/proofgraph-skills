#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestration_archive.sh <command> [options]

Note:
  Internal helper for skill automation only.
  Skills should run this automatically when users request archive cleanup/status.

Commands:
  status [--project-root <path>]
  flush-done [--project-root <path>] [--actor <name>]
  clear --yes [--project-root <path>]

Archive rules:
  - done archive path: <runtime-root>/orchestration/archive/done-YYYY-MM.tsv
  - clear requires explicit --yes
USAGE
}

RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}"
if [[ -z "$RUNTIME_ROOT" || "$RUNTIME_ROOT" == "." || "$RUNTIME_ROOT" == ".." || "$RUNTIME_ROOT" == /* || "$RUNTIME_ROOT" == *".."* ]]; then
  echo "ERROR: SIGEE_RUNTIME_ROOT must be a safe relative path (e.g. .sigee/.runtime)" >&2
  exit 1
fi

QUEUE_HEADER=$'id\tstatus\tworker\ttitle\tsource\tupdated_at\tnote\tnext_action\tlease\tevidence_links\tphase\terror_class\tattempt_count\tretry_budget'
ARCHIVE_HEADER=$'id\tstatus\tworker\ttitle\tsource\tupdated_at\tnote\tnext_action\tlease\tevidence_links\tphase\terror_class\tattempt_count\tretry_budget\tarchived_at\tarchived_by'

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

sanitize_field() {
  printf "%s" "$1" | tr '\t\r\n' '   '
}

resolve_project_root() {
  local candidate="${1:-$(pwd)}"
  if [[ ! -d "$candidate" ]]; then
    echo "ERROR: project root not found: $candidate" >&2
    exit 1
  fi
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel
  else
    (cd "$candidate" && pwd)
  fi
}

done_queue_file_path() {
  local project_root="$1"
  printf "%s/%s/orchestration/queues/done.tsv" "$project_root" "$RUNTIME_ROOT"
}

archive_dir_path() {
  local project_root="$1"
  printf "%s/%s/orchestration/archive" "$project_root" "$RUNTIME_ROOT"
}

archive_file_path() {
  local project_root="$1"
  local archive_dir
  archive_dir="$(archive_dir_path "$project_root")"
  printf "%s/done-%s.tsv" "$archive_dir" "$(date -u '+%Y-%m')"
}

ensure_done_queue_file() {
  local done_file="$1"
  mkdir -p "$(dirname "$done_file")"
  if [[ ! -f "$done_file" ]]; then
    printf "%s\n" "$QUEUE_HEADER" > "$done_file"
    return 0
  fi
  local header
  header="$(head -n1 "$done_file" || true)"
  if [[ "$header" != "$QUEUE_HEADER" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v OFS='\t' '
      BEGIN {
        print "id","status","worker","title","source","updated_at","note","next_action","lease","evidence_links","phase","error_class","attempt_count","retry_budget"
      }
      NR==1 { next }
      {
        for (i=1; i<=14; i++) {
          if (i > NF) $i=""
        }
        if ($11=="") {
          if ($2=="done") $11="done"
          else if ($2=="review") $11="evidence_collected"
          else if ($2=="in_progress") $11="running"
          else if ($2=="blocked") $11="running"
          else $11="ready"
        }
        if ($12=="") {
          if ($2=="blocked") $12="soft_fail"
          else $12="none"
        }
        if ($13=="" || $13 !~ /^[0-9]+$/) $13="0"
        if ($14=="" || $14 !~ /^[0-9]+$/ || $14 < 1) $14="3"
        print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
      }
    ' "$done_file" > "$tmp_file"
    mv "$tmp_file" "$done_file"
  fi
}

ensure_archive_file() {
  local archive_file="$1"
  mkdir -p "$(dirname "$archive_file")"
  if [[ ! -f "$archive_file" ]]; then
    printf "%s\n" "$ARCHIVE_HEADER" > "$archive_file"
    return 0
  fi
  local header
  header="$(head -n1 "$archive_file" || true)"
  if [[ "$header" != "$ARCHIVE_HEADER" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v OFS='\t' '
      BEGIN {
        print "id","status","worker","title","source","updated_at","note","next_action","lease","evidence_links","phase","error_class","attempt_count","retry_budget","archived_at","archived_by"
      }
      NR==1 { next }
      {
        for (i=1; i<=16; i++) {
          if (i > NF) $i=""
        }
        if ($11=="") {
          if ($2=="done") $11="done"
          else if ($2=="review") $11="evidence_collected"
          else if ($2=="in_progress") $11="running"
          else if ($2=="blocked") $11="running"
          else $11="ready"
        }
        if ($12=="") {
          if ($2=="blocked") $12="soft_fail"
          else $12="none"
        }
        if ($13=="" || $13 !~ /^[0-9]+$/) $13="0"
        if ($14=="" || $14 !~ /^[0-9]+$/ || $14 < 1) $14="3"
        print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16
      }
    ' "$archive_file" > "$tmp_file"
    mv "$tmp_file" "$archive_file"
  fi
}

append_archive_from_done() {
  local done_file="$1"
  local archive_file="$2"
  local actor="$3"
  local archived_at="$4"
  awk -F'\t' -v OFS='\t' -v archived_by="$actor" -v archived_at="$archived_at" '
    NR==1 { next }
    {
      for (i=1; i<=14; i++) {
        if (i > NF) $i=""
      }
      if ($11=="") {
        if ($2=="done") $11="done"
        else if ($2=="review") $11="evidence_collected"
        else if ($2=="in_progress") $11="running"
        else if ($2=="blocked") $11="running"
        else $11="ready"
      }
      if ($12=="") {
        if ($2=="blocked") $12="soft_fail"
        else $12="none"
      }
      if ($13=="" || $13 !~ /^[0-9]+$/) $13="0"
      if ($14=="" || $14 !~ /^[0-9]+$/ || $14 < 1) $14="3"
      print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,archived_at,archived_by
    }
  ' "$done_file" >> "$archive_file"
}

done_row_count() {
  local done_file="$1"
  awk 'NR>1{c++} END{print c+0}' "$done_file"
}

archive_total_count() {
  local archive_dir="$1"
  if [[ ! -d "$archive_dir" ]]; then
    printf "0"
    return 0
  fi
  awk 'FNR>1{c++} END{print c+0}' "$archive_dir"/done-*.tsv 2>/dev/null || printf "0"
}

cmd_status() {
  local project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for status: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  project_root="$(resolve_project_root "$project_root")"
  local done_file archive_dir total done_rows file_count
  done_file="$(done_queue_file_path "$project_root")"
  archive_dir="$(archive_dir_path "$project_root")"
  ensure_done_queue_file "$done_file"
  mkdir -p "$archive_dir"
  done_rows="$(done_row_count "$done_file")"
  total="$(archive_total_count "$archive_dir")"
  file_count="$(find "$archive_dir" -maxdepth 1 -type f -name 'done-*.tsv' | wc -l | tr -d ' ')"
  printf "done_queue_rows=%s\narchive_files=%s\narchive_rows_total=%s\n" "$done_rows" "$file_count" "$total"
}

cmd_flush_done() {
  local project_root=""
  local actor="${SIGEE_QUEUE_ACTOR:-system}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --actor) actor="${2:-}"; shift 2 ;;
      *)
        echo "Unknown option for flush-done: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  project_root="$(resolve_project_root "$project_root")"
  local done_file archive_file rows
  done_file="$(done_queue_file_path "$project_root")"
  archive_file="$(archive_file_path "$project_root")"
  ensure_done_queue_file "$done_file"
  ensure_archive_file "$archive_file"
  rows="$(done_row_count "$done_file")"
  if [[ "$rows" -eq 0 ]]; then
    echo "NO_DONE_ROWS"
    return 0
  fi
  append_archive_from_done "$done_file" "$archive_file" "$actor" "$(timestamp_utc)"
  printf "%s\n" "$QUEUE_HEADER" > "$done_file"
  echo "FLUSHED_DONE_ROWS:$rows"
}

cmd_clear() {
  local project_root=""
  local yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --yes) yes=1; shift ;;
      *)
        echo "Unknown option for clear: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  if [[ "$yes" -ne 1 ]]; then
    echo "ERROR: clear requires --yes" >&2
    exit 1
  fi
  project_root="$(resolve_project_root "$project_root")"
  local archive_dir
  archive_dir="$(archive_dir_path "$project_root")"
  mkdir -p "$archive_dir"
  find "$archive_dir" -maxdepth 1 -type f -name 'done-*.tsv' -print -delete | sed 's/^/DELETED: /'
  echo "ARCHIVE_CLEARED"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  status) cmd_status "$@" ;;
  flush-done) cmd_flush_done "$@" ;;
  clear) cmd_clear "$@" ;;
  --help|-h|help) usage ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
