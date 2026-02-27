#!/usr/bin/env bash

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

queue_file_path() {
  local project_root="$1"
  local queue="$2"
  printf "%s/%s/orchestration/queues/%s.tsv" "$project_root" "$RUNTIME_ROOT" "$queue"
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

history_dir_path() {
  local project_root="$1"
  printf "%s/%s/orchestration/history" "$project_root" "$RUNTIME_ROOT"
}

retry_history_file_path() {
  local project_root="$1"
  printf "%s/retry-events.tsv" "$(history_dir_path "$project_root")"
}

weekly_retry_summary_file_path() {
  local project_root="$1"
  local weeks="${2:-1}"
  local week_token
  week_token="$(date -u '+%G-W%V')"
  printf "%s/weekly-retry-summary-%s-last%sw.md" "$(history_dir_path "$project_root")" "$week_token" "$weeks"
}

normalize_queue_file_schema() {
  local queue_file="$1"
  local queue_name
  queue_name="$(basename "$queue_file" .tsv)"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -F'\t' -v OFS='\t' -v queue_name="$queue_name" '
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
        else if ($2=="pending" && queue_name=="planner-inbox") $11="planned"
        else if ($2=="pending") $11="ready"
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
  ' "$queue_file" > "$tmp_file"
  mv "$tmp_file" "$queue_file"
}

ensure_queue_file() {
  local queue_file="$1"
  mkdir -p "$(dirname "$queue_file")"
  if [[ ! -f "$queue_file" ]]; then
    printf "%s\n" "$QUEUE_HEADER" > "$queue_file"
    return 0
  fi
  local header
  header="$(head -n1 "$queue_file" || true)"
  if [[ "$header" != "$QUEUE_HEADER" ]]; then
    normalize_queue_file_schema "$queue_file"
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
          else if ($2=="pending") $11="ready"
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

ensure_retry_history_file() {
  local history_file="$1"
  mkdir -p "$(dirname "$history_file")"
  if [[ ! -f "$history_file" ]]; then
    printf "%s\n" "$RETRY_HISTORY_HEADER" > "$history_file"
    return 0
  fi
  local header
  header="$(head -n1 "$history_file" || true)"
  if [[ "$header" != "$RETRY_HISTORY_HEADER" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    awk -F'\t' -v OFS='\t' '
      BEGIN {
        print "ts_utc","event_type","id","from_queue","to_queue","status","error_class","attempt_count","retry_budget","priority","actor","note"
      }
      NR==1 { next }
      {
        for (i=1; i<=12; i++) {
          if (i > NF) $i=""
        }
        if ($1=="") $1="1970-01-01T00:00:00Z"
        if ($2=="") $2="retry_event"
        if ($6=="") $6="blocked"
        if ($7=="") $7="dependency_blocked"
        if ($8=="" || $8 !~ /^[0-9]+$/) $8="0"
        if ($9=="" || $9 !~ /^[0-9]+$/ || $9 < 1) $9="3"
        if ($10=="") $10="P2"
        if ($11=="") $11="planner"
        print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
      }
    ' "$history_file" > "$tmp_file"
    mv "$tmp_file" "$history_file"
  fi
}

append_retry_history_event() {
  local project_root="$1"
  local event_type="$2"
  local id="$3"
  local from_queue="$4"
  local to_queue="$5"
  local status="$6"
  local error_class="$7"
  local attempt_count="$8"
  local retry_budget="$9"
  local priority="${10}"
  local actor="${11}"
  local note="${12}"
  local history_file
  history_file="$(retry_history_file_path "$project_root")"
  ensure_retry_history_file "$history_file"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$(timestamp_utc)")" \
    "$(sanitize_field "$event_type")" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$from_queue")" \
    "$(sanitize_field "$to_queue")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" \
    "$(sanitize_field "$priority")" \
    "$(sanitize_field "$actor")" \
    "$(sanitize_field "$note")" >> "$history_file"
}

priority_label_for_row() {
  local title="${1:-}"
  local note="${2:-}"
  local next_action="${3:-}"
  local error_class="${4:-none}"
  local attempt_count="${5:-0}"
  local retry_budget="${6:-3}"
  local merged lowered tag

  merged="$title $note $next_action"
  lowered="$(to_lower "$merged")"
  for tag in p0 p1 p2 p3; do
    if [[ "$lowered" == *"$tag"* ]]; then
      case "$tag" in
        p0) printf "P0" ;;
        p1) printf "P1" ;;
        p2) printf "P2" ;;
        p3) printf "P3" ;;
      esac
      return 0
    fi
  done

  if [[ ! "$attempt_count" =~ ^[0-9]+$ ]]; then
    attempt_count="0"
  fi
  if [[ ! "$retry_budget" =~ ^[0-9]+$ || "$retry_budget" -lt 1 ]]; then
    retry_budget="3"
  fi

  if [[ "$error_class" == "hard_fail" ]]; then
    printf "P1"
    return 0
  fi
  if [[ "$attempt_count" -ge "$retry_budget" ]]; then
    printf "P1"
    return 0
  fi
  if [[ "$error_class" == "dependency_blocked" || "$error_class" == "soft_fail" ]]; then
    printf "P2"
    return 0
  fi
  printf "P3"
}

refresh_weekly_retry_summary() {
  local project_root="$1"
  local weeks="${2:-1}"
  local history_file blocked_file output_file

  history_file="$(retry_history_file_path "$project_root")"
  blocked_file="$(queue_file_path "$project_root" "blocked")"
  output_file="$(weekly_retry_summary_file_path "$project_root" "$weeks")"
  ensure_retry_history_file "$history_file"
  ensure_queue_file "$blocked_file"

  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "$history_file" "$blocked_file" "$output_file" "$weeks" <<'PY'
import csv
import datetime as dt
from pathlib import Path
import sys

history_path = Path(sys.argv[1])
blocked_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])
weeks = max(1, int(sys.argv[4]))
window_days = weeks * 7
now = dt.datetime.utcnow()
window_start = now - dt.timedelta(days=window_days)

def parse_ts(value: str):
    if not value:
        return None
    try:
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None

events = []
if history_path.exists():
    with history_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            ts = parse_ts((row.get("ts_utc") or "").strip())
            if ts is None or ts < window_start:
                continue
            events.append((ts, row))

open_exhausted = []
if blocked_path.exists():
    with blocked_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            try:
                attempts = int((row.get("attempt_count") or "0").strip())
                budget = int((row.get("retry_budget") or "3").strip())
            except Exception:
                attempts, budget = 0, 3
            if budget < 1:
                budget = 3
            if attempts >= budget:
                open_exhausted.append(row)

events_total = len(events)
affected_ids = sorted({(row.get("id") or "").strip() for _, row in events if (row.get("id") or "").strip()})

by_queue = {}
by_priority = {}
for _, row in events:
    q = (row.get("from_queue") or "unknown").strip() or "unknown"
    p = (row.get("priority") or "P2").strip() or "P2"
    by_queue[q] = by_queue.get(q, 0) + 1
    by_priority[p] = by_priority.get(p, 0) + 1

def row_updated_at(row):
    return parse_ts((row.get("updated_at") or "").strip()) or dt.datetime(1970, 1, 1)

open_exhausted.sort(key=row_updated_at)

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open("w", encoding="utf-8") as out:
    out.write("# Retry Budget Weekly Summary\n\n")
    out.write(f"- window_days: {window_days}\n")
    out.write(f"- window_start_utc: {window_start.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
    out.write(f"- generated_at_utc: {now.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
    out.write(f"- retry_budget_exhausted_events: {events_total}\n")
    out.write(f"- affected_ticket_count: {len(affected_ids)}\n")
    out.write(f"- open_blocked_exhausted_count: {len(open_exhausted)}\n\n")

    out.write("## Source Queue Distribution\n\n")
    out.write("| queue | events |\n")
    out.write("|---|---:|\n")
    if by_queue:
        for q in sorted(by_queue):
            out.write(f"| {q} | {by_queue[q]} |\n")
    else:
        out.write("| (none) | 0 |\n")
    out.write("\n")

    out.write("## Priority Distribution\n\n")
    out.write("| priority | events |\n")
    out.write("|---|---:|\n")
    if by_priority:
        for p in sorted(by_priority):
            out.write(f"| {p} | {by_priority[p]} |\n")
    else:
        out.write("| (none) | 0 |\n")
    out.write("\n")

    out.write("## Oldest Open Exhausted Blocked Tickets\n\n")
    out.write("| id | updated_at | attempt_count | retry_budget | next_action |\n")
    out.write("|---|---|---:|---:|---|\n")
    if open_exhausted:
        for row in open_exhausted[:20]:
            out.write(
                f"| {(row.get('id') or '').strip()} | {(row.get('updated_at') or '').strip()} | "
                f"{(row.get('attempt_count') or '').strip()} | {(row.get('retry_budget') or '').strip()} | "
                f"{(row.get('next_action') or '').strip()} |\n"
            )
    else:
        out.write("| (none) | - | 0 | 0 | - |\n")
PY
}

ensure_standard_queues() {
  local project_root="$1"
  local queue
  for queue in "${STANDARD_QUEUES[@]}"; do
    ensure_queue_file "$(queue_file_path "$project_root" "$queue")"
  done
}

ensure_template_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  if [[ ! -f "$path" ]]; then
    printf "%s\n" "$content" > "$path"
  fi
}

ensure_default_templates() {
  local project_root="$1"
  local templates_root="$project_root/.sigee/templates"

  ensure_template_file "$templates_root/ops-rules.md" "# 운영규약

## 목적
- 프로젝트 협업 규칙과 상태 전이 규칙을 명시한다.

## 티켓 관리
- 필수 필드: \`Status\`, \`Next Action\`, \`Lease\`, \`Evidence Links\`
- 라이프사이클 단계: \`planned -> ready -> running -> evidence_collected -> verified -> done\`
- 실패 분류: \`none|soft_fail|hard_fail|dependency_blocked\`
- 기본 전이: \`planner-inbox -> scientist-todo|developer-todo -> planner-review -> done\`
- 예외 전이: \`* -> blocked\`, \`blocked -> planner-inbox|scientist-todo|developer-todo\`
- 큐 운영(루프 모드): \`planner-inbox -> scientist/developer -> planner-review -> done|requeue\`
- \`done\` 전이는 planner 리뷰에서만 허용

## 글로벌 정책
- 삭제 금지: 문서는 삭제하지 않고 \`DEPRECATED\` 표기 후 아카이브한다.
- \`done\` 전이는 planner 전용이다.

## 운영 로그
- 변경 사유
- 결정 사항
- 후속 액션"

  ensure_template_file "$templates_root/agent-ticket.md" "# 에이전트 티켓

## 메타
- Ticket ID:
- Summary:
- Queue:
- Status:
- Next Action:
- Lease:

## 요구사항
- ReqIDs:
- Acceptance Criteria:

## 작업 기록
- Progress Log:
- Evidence Links:

## 핸드오프
- Decision Required:
- Blocker:
- Next Step:"

  ensure_template_file "$templates_root/handoff-note.md" "# 핸드오프 노트

## 컨텍스트
- 작업 요약:
- 현재 상태:

## 완료/미완료
- Completed:
- Remaining:

## 리스크
- Risk:
- Mitigation:

## 다음 액션
- Next Action:
- Evidence Links:"

  ensure_template_file "$templates_root/weekly-board.md" "# 업무 보드(주간)

## planner-inbox
-

## scientist-todo
-

## developer-todo
-

## planner-review
-

## done
-

## blocked
-

## 주간 보고
- Highlights:
- Risks:
- Next Week:"

  ensure_template_file "$templates_root/queue-ticket.md" "# Queue Ticket Template

- ID:
- Queue:
- Status:
- Worker:
- Title:
- Source:
- Updated At:
- Note:
- Next Action:
- Lease:
- Evidence Links:
- Phase:
- Error Class:
- Attempt Count:
- Retry Budget:

## Evidence

- Links:
- Verification:

## Next Routing

- Next Queue:
- Reason:"
}

bootstrap_runtime() {
  local project_root="$1"
  mkdir -p \
    "$project_root/$RUNTIME_ROOT/plans" \
    "$project_root/$RUNTIME_ROOT/dag/scenarios" \
    "$project_root/$RUNTIME_ROOT/dag/pipelines" \
    "$project_root/$RUNTIME_ROOT/dag/state" \
    "$project_root/$RUNTIME_ROOT/evidence" \
    "$project_root/$RUNTIME_ROOT/reports" \
    "$project_root/$RUNTIME_ROOT/orchestration/archive" \
    "$project_root/$RUNTIME_ROOT/orchestration/history" \
    "$project_root/$RUNTIME_ROOT/locks"

  ensure_standard_queues "$project_root"
  ensure_archive_file "$(archive_file_path "$project_root")"
  ensure_retry_history_file "$(retry_history_file_path "$project_root")"
  ensure_default_templates "$project_root"

  if [[ -x "$GITIGNORE_GUARD_SCRIPT" ]]; then
    "$GITIGNORE_GUARD_SCRIPT" "$project_root" >/dev/null
  fi
}

append_row() {
  local queue_file="$1"
  local id="$2"
  local status="$3"
  local worker="$4"
  local title="$5"
  local source="$6"
  local updated_at="$7"
  local note="$8"
  local next_action="$9"
  local lease="${10}"
  local evidence_links="${11}"
  local phase="${12:-ready}"
  local error_class="${13:-none}"
  local attempt_count="${14:-0}"
  local retry_budget="${15:-$(default_retry_budget)}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$worker")" \
    "$(sanitize_field "$title")" \
    "$(sanitize_field "$source")" \
    "$(sanitize_field "$updated_at")" \
    "$(sanitize_field "$note")" \
    "$(sanitize_field "$next_action")" \
    "$(sanitize_field "$lease")" \
    "$(sanitize_field "$evidence_links")" \
    "$(sanitize_field "$phase")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" >> "$queue_file"
}

append_archive_row() {
  local archive_file="$1"
  local id="$2"
  local status="$3"
  local worker="$4"
  local title="$5"
  local source="$6"
  local updated_at="$7"
  local note="$8"
  local next_action="$9"
  local lease="${10}"
  local evidence_links="${11}"
  local phase="${12:-done}"
  local error_class="${13:-none}"
  local attempt_count="${14:-0}"
  local retry_budget="${15:-$(default_retry_budget)}"
  local archived_at="${16}"
  local archived_by="${17}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(sanitize_field "$id")" \
    "$(sanitize_field "$status")" \
    "$(sanitize_field "$worker")" \
    "$(sanitize_field "$title")" \
    "$(sanitize_field "$source")" \
    "$(sanitize_field "$updated_at")" \
    "$(sanitize_field "$note")" \
    "$(sanitize_field "$next_action")" \
    "$(sanitize_field "$lease")" \
    "$(sanitize_field "$evidence_links")" \
    "$(sanitize_field "$phase")" \
    "$(sanitize_field "$error_class")" \
    "$(sanitize_field "$attempt_count")" \
    "$(sanitize_field "$retry_budget")" \
    "$(sanitize_field "$archived_at")" \
    "$(sanitize_field "$archived_by")" >> "$archive_file"
}
