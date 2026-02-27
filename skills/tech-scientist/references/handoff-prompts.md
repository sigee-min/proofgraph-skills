# Handoff Prompt Templates

Always provide one copy-ready markdown fenced block titled `다음 실행 프롬프트`.
Default handoff intent is planning review.

## Template: Planner Handoff

```md
아래 과학/공학 설계를 기준으로 실행 가능한 계획을 작성해줘.
요구사항:
1) 제품 목표와 사용자 시나리오를 기준으로 실행 계획을 작성
2) 과학적 가정/한계를 명시하고, 검증 게이트(TDD + 수치검증 + smoke/e2e)를 태스크로 분해
3) 성능 예산과 실패 기준을 각 태스크의 검증 기준에 반영
4) 검토 결과에 따라 구현 실행 또는 추가 과학 검증으로 다음 라우팅을 결정
```

## Template: Planner Handoff (AI/ML)

```md
아래 AI/ML 설계를 기준으로 실행 계획을 작성해줘.
요구사항:
1) 제품 목표에 맞는 학습/평가/서빙 실행 계획 작성
2) 데이터 계약/누수 방지/학습/평가/서빙/모니터링을 태스크로 분해
3) 오프라인 지표 임계값, 온라인 SLO, 롤백 기준을 검증 기준에 명시
4) 검토 결과에 따라 구현 실행 또는 추가 과학 검증으로 다음 라우팅을 결정
```

## Handoff Quality Rules
- 명령 나열보다 작업 의도를 먼저 설명.
- shell 명령, 스크립트 경로, CLI 옵션은 handoff 블록에 노출하지 않는다.
- runtime 경로, queue 명, ticket/plan ID, 내부 상태 키는 handoff 블록에 노출하지 않는다.
- 리포트 파일 생성은 사용자 요청 시에만 포함.
- AI/ML handoff에는 반드시 데이터 누수 방지와 롤백 기준을 포함.
- scientist 최종 응답에는 planning review 목적의 `다음 실행 프롬프트`를 정확히 1개 포함한다.
