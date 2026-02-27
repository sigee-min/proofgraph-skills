# Template Migration Spec

## Source

Legacy template-seeds source:
- `skills/sigee-project-manager/references/template-seeds/ops-rules.md`
- `skills/sigee-project-manager/references/template-seeds/agent-ticket.md`
- `skills/sigee-project-manager/references/template-seeds/handoff-note.md`
- `skills/sigee-project-manager/references/template-seeds/weekly-board.md`

## Target

- `.sigee/templates/ops-rules.md`
- `.sigee/templates/agent-ticket.md`
- `.sigee/templates/handoff-note.md`
- `.sigee/templates/weekly-board.md`
- `.sigee/templates/queue-ticket.md`

## 운영 정책 변경

- 템플릿은 큐 런타임 부트스트랩 시 자동 생성한다(내부 실행).
- `.sigee/templates/**`는 소비자 저장소 기준으로 로컬 전용(기본 ignore)이다.
- 스킬팩 저장소는 부트스트랩 기준선을 유지하기 위해 seed 템플릿을 추적할 수 있다.

## 필수 필드 검수

- 운영규약: 상태 전이, 글로벌 정책
- 에이전트 티켓: 메타/요구사항/작업기록/핸드오프
- 핸드오프 노트: 컨텍스트/리스크/다음 액션
- 업무 보드(주간): 상태 lane + 주간 보고

## Acceptance Checklist

- Legacy structure preserved
- Wording adjusted only for clarity
- No required section removed
