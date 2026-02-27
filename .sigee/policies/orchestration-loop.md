# Planner-Centric Orchestration Loop

## 목적

- 사람은 기능 목표를 설명하고, 실행 루프는 planner 중심 큐 프로토콜로 자동 반복한다.
- 멀티 에이전트 기능 의존 없이 스킬 계약만으로 동작한다.

## 런타임 루트

- 기본: `${SIGEE_RUNTIME_ROOT:-.sigee/.runtime}`
- 큐 경로: `<runtime-root>/orchestration/queues/`
- 완료 아카이브 경로: `<runtime-root>/orchestration/archive/`

## 표준 큐

- `planner-inbox`: 사용자 요청을 planner가 분해하기 전 상태
- `scientist-todo`: 과학/수학/시뮬레이션 검토가 필요한 작업
- `developer-todo`: 구현/테스트 실행 작업
- `planner-review`: scientist/developer 완료 후 planner 리뷰 대기
- `blocked`: 외부 의사결정 또는 실패로 진행 중단
- `done`: planner 승인 완료

## 티켓 상태

- `pending`
- `in_progress`
- `review`
- `done`
- `blocked`

## 라이프사이클 단계 (필수)

- `planned`
- `ready`
- `running`
- `evidence_collected`
- `verified`
- `done`

전이 규칙:
- 기본 순서: `planned -> ready -> running -> evidence_collected -> verified -> done`
- 재작업 루프: `running|evidence_collected|verified -> ready`
- `blocked` 이동 시 현재 phase를 유지하거나 합리적인 phase로 명시한다.
- planner done gate는 `evidence_collected -> done` 전이를 허용하며 내부 검증을 통해 `verified`를 충족한 것으로 간주한다.

## 실패 분류와 재시도 예산

- `error_class`:
  - `none`
  - `soft_fail` (재시도 가능)
  - `hard_fail` (즉시 의사결정 필요)
  - `dependency_blocked` (선행 작업 대기)
- `attempt_count`: 현재까지 시도 횟수 (0 이상 정수)
- `retry_budget`: 최대 재시도 허용 횟수 (1 이상 정수, 기본 3)
- `attempt_count >= retry_budget` 인 항목은 자동 claim 대상에서 제외한다.
- claim 시 retry 예산 소진 항목은 자동으로 `blocked` 큐로 에스컬레이션한다.
- 재시도 예산 소진 항목은 planner가 재기획/우회/중단 중 하나를 결정한다.

## 큐 레코드 필드 (필수)

- `id`
- `status`
- `worker`
- `title`
- `source`
- `updated_at`
- `note`
- `next_action`
- `lease`
- `evidence_links`
- `phase`
- `error_class`
- `attempt_count`
- `retry_budget`

권장 메타 규약:
- developer 라우팅에서 도메인 프로필 의도를 `next_action` 또는 `note`에 포함한다.
- 권장 형식: `profile=<slug>` (예: `profile=refactoring-specialist`).

## 반복 규약

1. planner가 `planner-inbox`를 읽고 작업을 분해한다.
   - 분해 전에 `.sigee/product-truth/`를 최신 SSoT로 동기화한다.
2. 과학적 검증이 필요한 항목은 `scientist-todo`로 이동한다.
3. 구현 가능한 항목은 `developer-todo`로 이동한다.
4. scientist/developer는 작업 완료 후 반드시 `planner-review`로 이동한다.
5. planner는 리뷰 후 `done` 또는 재작업 큐(`scientist-todo`/`developer-todo`)로 재배치한다.
   - 리뷰 승인 직전에는 `phase=verified` 또는 done gate 조건을 만족해야 한다.
6. 단일 진입 규칙:
   - 사용자 직접 요청으로 scientist/developer가 독립 실행을 시작하지 않는다.
   - 실행은 planner 라우팅 컨텍스트(큐/계획 기반)에서만 시작한다.

## 정지 조건 (필수)

- 정지 판정 전에 pending plan backlog를 자동 동기화한다.
  - `<runtime-root>/plans/*.md`에서 unchecked task(`- [ ]`)가 남은 plan은 `planner-inbox`로 자동 시드한다 (`source=plan:<plan-id>`).
- `STOP_DONE`: actionable queue가 모두 비어 있으면 루프 종료
  - actionable queue: `planner-inbox`, `scientist-todo`, `developer-todo`, `planner-review`, `blocked(non-user-confirmation)`
  - pending plan backlog가 남아 있으면 `STOP_DONE`으로 종료하지 않는다.
- `STOP_USER_CONFIRMATION`: blocked 항목에 사용자 확정 신호가 있으면 루프 종료
  - 신호 예시: `needs_user_confirmation`, `external_decision_required`, `user_decision_required`
- `max_cycles` 초과
- `2회 연속 무진전` (완료/리뷰 승인 없음)
- 필수 테스트 계약 위반으로 재기획이 필요한 상태
- 핵심 큐 항목의 재시도 예산 소진 누적

## 내부 실행 규약

- 큐 초기화, 라우팅, 상태 전이는 `orchestration_queue.sh`를 통해 스킬 내부에서 자동 실행한다.
- 초기 preflight(`init`)는 queue/runtime뿐 아니라 누락된 governance/product-truth/scenario starter도 시드할 수 있다.
- developer 실행 진입은 `planner_entry_guard.sh`로 강제한다.
  - planner 라우팅 컨텍스트가 없으면 실행을 차단하고 planner로 반환한다.
  - 마이그레이션/디버그 시에만 `SIGEE_ALLOW_DIRECT_ENTRY=1`로 한시적 우회할 수 있다.
- 루프 종료 판정은 `orchestration_queue.sh loop-status --user-facing`를 기본 사용자 보고 기준으로 사용한다.
- `loop-status`/`next-prompt`는 호출 시 pending plan backlog를 먼저 동기화해 queue와 plan 상태를 맞춘다.
- loop mode 기본값으로 planner는 `orchestration_autoloop.sh`를 내부 실행한다.
  - 대상 범위: plan-backed `planner-inbox`를 `developer-todo -> planner-review -> done` 루프로 자동 소진
  - 정지 가드: `STOP_DONE`, `STOP_USER_CONFIRMATION`, `max_cycles`, `no_progress_limit`
- `done` 전이는 즉시 archive 파일(`done-YYYY-MM.tsv`)로 적재되며, `done` 큐는 누적 저장소로 사용하지 않는다.
- `planner-review -> done` 승인 직후 queue helper는 `loop-status --user-facing`를 평가한다.
  - `CONTINUE`: 다음 실행 프롬프트 추천을 출력
  - `STOP_DONE` / `STOP_USER_CONFIRMATION`: 종료 사유와 함께 다음 사이클 시작/의사결정 해소 프롬프트를 출력
- 사용자 보고 렌더링은 `.sigee/policies/response-rendering-contract.md`를 단일 기준으로 따른다.
- 사용자에게는 제품 영향 요약과 다음 실행 프롬프트만 노출하고, 스크립트 실행을 요구하지 않는다.
- 큐/런타임 폴더와 `.sigee/templates/*` 로컬 템플릿은 최초 큐 동작 시 자동 생성한다.
- bootstrap starter(`VIS-BOOT-*`, `PIL-BOOT-*`, `OBJ-BOOT-*`, `OUT-BOOT-*`, `CAP-BOOT-*`, `bootstrap_foundation_*`)는 임시값이며 실사용 전 project-specific 값으로 교체해야 한다.
- queue helper는 lease를 자동 관리한다.
  - `claim`: `held:<worker>:<utc>`
  - handoff(`planner-review`/`blocked`/`done`): `released:<utc>`
- queue helper claim 출력은 developer 큐에 대해 profile hint 해석 결과를 함께 노출할 수 있다 (`CLAIM_PROFILE_HINT`, `CLAIM_PROFILE_SOURCE`).
- blocked triage 뷰는 queue helper의 `triage-blocked` 출력(우선순위 + aging, 오래된 순)으로 제공한다.
- retry budget 소진 이벤트는 history에 누적하고 주간 요약(`weekly-retry-summary`)으로 자동 집계한다.
- archive 운영은 내부 스크립트로 자동화한다.
  - 상태/legacy done flush/삭제: `orchestration_archive.sh`
  - 사용자가 요청한 경우에만 archive clear를 실행한다.

## 품질 게이트

- planner 외 스킬은 `done`으로 직접 종료하지 않는다.
- `done` 전이는 planner 리뷰에서만 허용한다.
- `done` 전이 권한은 planner actor(`--actor` 또는 `SIGEE_QUEUE_ACTOR`)로 강제한다.
- `done` 전이는 증거 필드(`evidence_links`)가 비어 있으면 거부한다.
- `evidence_links`는 `,`, `;`, `|` 구분자를 모두 허용한다.
- `done` 전이는 다음 중 하나의 PASS 게이트가 없으면 거부한다.
  - PASS-only `verification-results.tsv`
  - PASS `dag/state/last-run.json` + evidence dir 존재
- `done` 전이 시 product-truth 검증 외에 goal hierarchy 검증(`goal_governance_validate --strict`)을 함께 통과해야 한다.
- source scenario catalog는 `.sigee/dag/scenarios/`를 기준으로 검증한다.
- runtime-only scenario catalog(`.sigee/dag/scenarios` 없음 + `<runtime-root>/dag/scenarios`만 존재)는 계약 위반이며 `done` 전이를 즉시 차단한다.
- product-truth 또는 source scenario 변경이 포함된 작업은 change impact gate 결과를 검증 근거로 첨부해야 한다.
- 모든 handoff는 근거 링크/검증 로그를 포함한다.
- DAG 테스트 계약(`unit_normal=2`, `unit_boundary=2`, `unit_failure=2`, `boundary_smoke=5`) 미충족 시 `done` 금지.
- `done` 전이는 lifecycle phase 규칙 및 retry budget 규칙을 동시에 만족해야 한다.
- bootstrap starter가 남아 있으면 `done` 금지(강제 교체 후 진행).
