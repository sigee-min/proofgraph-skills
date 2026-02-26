# Handoff Prompt Templates

Always provide copy-ready markdown fenced blocks titled `다음 실행 프롬프트`.

## Template: Planner Handoff

```md
$tech-planner
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

아래 과학/공학 설계를 기준으로 실행 가능한 계획을 작성해줘.
요구사항:
1) <runtime-root>/plans/<plan-id>.md 에 PlanSpec v2로 작성
2) 과학적 가정/한계를 명시하고, 검증 게이트(TDD + 수치검증 + smoke/e2e)를 태스크로 분해
3) 성능 예산과 실패 기준을 각 태스크의 Verification에 반영
4) 마지막에 `다음 실행 프롬프트` 블록으로 $tech-developer handoff 제공
```

## Template: Developer Handoff

```md
$tech-developer
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

승인된 계획을 strict 모드로 실행해줘.
요구사항:
1) <runtime-root>/plans/<plan-id>.md 기준 미완료 작업을 끝까지 처리
2) 핵심 의사코드를 실제 코드로 변환하면서 수치 안정성/복잡도 의도를 유지
3) 검증은 TDD -> 수치검증 -> smoke/e2e 순서로 진행
4) 결과 설명은 내용 중심으로 작성하고, 마지막에 traceability를 별도 섹션으로 분리
```

## Template: Planner Handoff (AI/ML)

```md
$tech-planner
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

아래 AI/ML 설계를 기준으로 실행 계획을 작성해줘.
요구사항:
1) <runtime-root>/plans/<plan-id>.md 에 PlanSpec v2로 작성
2) 데이터 계약/누수 방지/학습/평가/서빙/모니터링을 태스크로 분해
3) 오프라인 지표 임계값, 온라인 SLO, 롤백 기준을 Verification에 명시
4) 마지막에 `다음 실행 프롬프트` 블록으로 $tech-developer handoff 제공
```

## Template: Developer Handoff (AI/ML)

```md
$tech-developer
runtime-root=${SIGEE_RUNTIME_ROOT:-.codex}

승인된 AI/ML 계획을 strict 모드로 실행해줘.
요구사항:
1) <runtime-root>/plans/<plan-id>.md 기준 미완료 작업을 끝까지 처리
2) 데이터 파이프라인/학습 루프/평가/서빙 통합을 단계별로 구현
3) 검증은 데이터 무결성 -> 학습 검증 -> 성능/추론 검증 -> smoke/e2e 순서로 진행
4) 결과는 내용 중심 설명 + 마지막 traceability 섹션으로 보고
```

## Handoff Quality Rules
- 명령 나열보다 작업 의도를 먼저 설명.
- runtime-root를 항상 명시.
- 리포트 파일 생성은 사용자 요청 시에만 포함.
- AI/ML handoff에는 반드시 데이터 누수 방지와 롤백 기준을 포함.
