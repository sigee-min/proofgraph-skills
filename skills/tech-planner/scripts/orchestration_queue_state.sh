#!/usr/bin/env bash

auto_lease_for_transition() {
  local to_queue="$1"
  local status="$2"
  local worker="$3"
  local now="$4"
  if [[ "$to_queue" == "planner-review" || "$to_queue" == "done" || "$to_queue" == "blocked" ]]; then
    printf "released:%s" "$now"
    return 0
  fi
  if [[ "$status" == "in_progress" ]]; then
    if [[ -n "$worker" ]]; then
      printf "held:%s:%s" "$worker" "$now"
      return 0
    fi
    printf "held:unknown:%s" "$now"
    return 0
  fi
  printf "none"
}

default_retry_budget() {
  printf "3"
}

default_phase_for_queue() {
  local queue="$1"
  local status="$2"
  case "$status" in
    done) printf "done" ;;
    review) printf "evidence_collected" ;;
    in_progress) printf "running" ;;
    blocked) printf "running" ;;
    pending)
      case "$queue" in
        planner-inbox) printf "planned" ;;
        *) printf "ready" ;;
      esac
      ;;
    *)
      printf "ready"
      ;;
  esac
}

default_error_class_for_queue() {
  local queue="$1"
  local status="$2"
  case "$queue:$status" in
    blocked:blocked) printf "soft_fail" ;;
    *) printf "none" ;;
  esac
}

validate_phase_transition() {
  local from_phase="$1"
  local to_phase="$2"
  local from_queue="$3"
  local to_queue="$4"
  local to_status="$5"

  if [[ "$from_phase" == "$to_phase" ]]; then
    return 0
  fi

  # Planner done-gate implicitly validates evidence_collected -> done.
  if [[ "$from_phase" == "evidence_collected" && "$to_phase" == "done" && "$to_queue" == "done" && "$to_status" == "done" ]]; then
    return 0
  fi

  case "$from_phase:$to_phase" in
    planned:ready|planned:running|ready:running|running:evidence_collected|running:ready|evidence_collected:verified|evidence_collected:ready|verified:done|verified:ready)
      return 0
      ;;
  esac

  if [[ "$to_queue" == "blocked" ]]; then
    case "$to_phase" in
      planned|ready|running|evidence_collected|verified)
        return 0
        ;;
    esac
  fi

  if [[ "$from_queue" == "blocked" && "$to_queue" != "done" ]]; then
    case "$to_phase" in
      ready|running)
        return 0
        ;;
    esac
  fi

  echo "ERROR: invalid lifecycle transition '${from_phase}' -> '${to_phase}' for move ${from_queue} -> ${to_queue} (status=${to_status})." >&2
  exit 1
}

default_status_for_queue() {
  local queue="$1"
  case "$queue" in
    planner-review) printf "review" ;;
    blocked) printf "blocked" ;;
    done) printf "done" ;;
    *) printf "pending" ;;
  esac
}
