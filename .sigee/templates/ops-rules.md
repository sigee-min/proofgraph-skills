# 운영규약

## 목적
- 프로젝트 협업 규칙과 상태 전이 규칙을 명시한다.

## 티켓 관리
- 필수 필드: `Status`, `Next Action`, `Lease`, `Evidence Links`
- 라이프사이클 단계: `planned -> ready -> running -> evidence_collected -> verified -> done`
- 실패 분류: `none|soft_fail|hard_fail|dependency_blocked`
- 기본 전이: `planner-inbox -> scientist-todo|developer-todo -> planner-review -> done`
- 예외 전이: `* -> blocked`, `blocked -> planner-inbox|scientist-todo|developer-todo`
- 큐 운영(루프 모드): `planner-inbox -> scientist/developer -> planner-review -> done|requeue`
- `done` 전이는 planner 리뷰에서만 허용

## 글로벌 정책
- 삭제 금지: 문서는 삭제하지 않고 `DEPRECATED` 표기 후 아카이브한다.
- `done` 전이는 planner 전용이다.

## 운영 로그
- 변경 사유
- 결정 사항
- 후속 액션
