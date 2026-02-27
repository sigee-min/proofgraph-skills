#!/usr/bin/env bash

_SIGEE_UF_RENDERER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SIGEE_UF_GUARD_SCRIPT="${_SIGEE_UF_RENDERER_DIR}/user_facing_guard.sh"

if ! command -v sigee_user_facing_internal_leak_detected >/dev/null 2>&1; then
  if [[ ! -f "$_SIGEE_UF_GUARD_SCRIPT" ]]; then
    echo "ERROR: missing shared user-facing guard: $_SIGEE_UF_GUARD_SCRIPT" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$_SIGEE_UF_GUARD_SCRIPT"
fi

_sigee_uf_trim_field() {
  local value="${1:-}"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf "%s" "$value"
}

sigee_render_sanitize_summary_line() {
  local summary_line="${1:-}"
  if sigee_user_facing_internal_leak_detected "$summary_line"; then
    printf "%s\n" "요약: 현재 상태를 기준으로 다음 제품 작업을 이어갈 수 있습니다."
    return 0
  fi
  printf "%s\n" "$summary_line"
}

sigee_render_sanitize_prompt_message() {
  local message="${1:-}"
  if sigee_user_facing_internal_leak_detected "$message"; then
    printf "%s" "다음 제품 작업 1건을 제안해줘. 사용자 영향, 검증 신뢰, 잔여 리스크를 중심으로 설명해줘."
    return 0
  fi
  printf "%s" "$message"
}

sigee_render_sanitize_context_text() {
  local text="${1:-}"
  text="$(_sigee_uf_trim_field "$text")"
  if [[ -z "$text" ]]; then
    printf ""
    return 0
  fi

  text="$(printf "%s" "$text" | sed -E \
    -e 's/\$tech-[A-Za-z0-9_-]+//g' \
    -e 's/[A-Z]{2,}-[0-9]{2,}//g' \
    -e 's/\.sigee\/\.runtime\/[^[:space:]]+//g' \
    -e 's/\/orchestration\/[^[:space:]]+//g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^[[:space:][:punct:]]+//; s/[[:space:][:punct:]]+$//')"
  text="$(_sigee_uf_trim_field "$text")"
  if [[ -z "$text" ]]; then
    printf ""
    return 0
  fi
  if sigee_user_facing_internal_leak_detected "$text"; then
    printf ""
    return 0
  fi
  printf "%s" "$text"
}

sigee_render_product_goal_summary_text() {
  local project_root="${1:-}"
  local file candidate
  for file in \
    "$project_root/.sigee/product-truth/outcomes.yaml" \
    "$project_root/.sigee/product-truth/objectives.yaml" \
    "$project_root/.sigee/product-truth/vision.yaml"; do
    if [[ ! -f "$file" ]]; then
      continue
    fi
    candidate="$(sed -nE 's/^[[:space:]]*statement:[[:space:]]*"([^"]+)".*$/\1/p' "$file" | head -n1)"
    if [[ -z "$candidate" ]]; then
      candidate="$(sed -nE 's/^[[:space:]]*title:[[:space:]]*"([^"]+)".*$/\1/p' "$file" | head -n1)"
    fi
    candidate="$(sigee_render_sanitize_context_text "$candidate")"
    if [[ -n "$candidate" ]]; then
      printf "%s" "$candidate"
      return 0
    fi
  done
  printf ""
}

sigee_render_recent_change_summary_text() {
  local project_root="${1:-}"
  local runtime_root="${2:-${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}}"
  local archive_dir latest_archive candidate

  archive_dir="$project_root/$runtime_root/orchestration/archive"
  if [[ ! -d "$archive_dir" ]]; then
    printf ""
    return 0
  fi
  latest_archive="$(ls -1 "$archive_dir"/done-*.tsv 2>/dev/null | sort | tail -n1 || true)"
  if [[ -z "$latest_archive" || ! -f "$latest_archive" ]]; then
    printf ""
    return 0
  fi

  candidate="$(awk -F'\t' '
    NR==1 { next }
    $2=="done" && $1 !~ /^TEST-/ && $4!="" && tolower($4)!="none" { title=$4 }
    END { print title }
  ' "$latest_archive")"
  if [[ -z "$candidate" ]]; then
    candidate="$(awk -F'\t' '
      NR==1 { next }
      $2=="done" && $4!="" && tolower($4)!="none" { title=$4 }
      END { print title }
    ' "$latest_archive")"
  fi
  candidate="$(sigee_render_sanitize_context_text "$candidate")"
  printf "%s" "$candidate"
}

sigee_render_build_why_now_line() {
  local project_root="${1:-}"
  local runtime_root="${2:-${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}}"
  local goal recent
  goal="$(sigee_render_product_goal_summary_text "$project_root")"
  recent="$(sigee_render_recent_change_summary_text "$project_root" "$runtime_root")"

  if [[ -n "$goal" && -n "$recent" ]]; then
    printf "왜 지금 이 작업인가: 현재 제품 목표는 %s이며, 최근에는 %s를 반영해 다음 단계 효과가 가장 큽니다." "$goal" "$recent"
    return 0
  fi
  if [[ -n "$goal" ]]; then
    printf "왜 지금 이 작업인가: 현재 제품 목표인 %s에 직접적으로 기여하는 다음 작업이기 때문입니다." "$goal"
    return 0
  fi
  if [[ -n "$recent" ]]; then
    printf "왜 지금 이 작업인가: 최근 반영된 %s를 기반으로 사용자 가치가 가장 큰 다음 단계를 이어가기 위해서입니다." "$recent"
    return 0
  fi
  printf "왜 지금 이 작업인가: 사용자 가치가 큰 다음 단계를 이어서 제품 완성도를 높이기 위해서입니다."
}

sigee_render_append_context_line() {
  local project_root="${1:-}"
  local message="${2:-}"
  local runtime_root="${3:-${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}}"
  local why_now
  why_now="$(sigee_render_build_why_now_line "$project_root" "$runtime_root")"
  if [[ -z "$why_now" ]]; then
    printf "%s" "$message"
    return 0
  fi
  printf "%s\n\n%s" "$message" "$why_now"
}
