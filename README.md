# Codex Skills Pack

Codex에서 바로 배포/사용 가능한 워크플로 스킬 모음입니다.
목표는 `기획 -> 구현 -> 검증`을 스킬 단위로 표준화하는 것입니다.

## Concept
- Skill-only 운영: AGENTS.md나 멀티 에이전트 의존 없이 스킬 자체 규약으로 동작
- Hard TDD 실행: strict 검증 흐름과 증거 로그 중심 실행
- Runtime/Governance 분리: 런타임은 `.codex`, 정책/자산은 `.sigee` 기준

## Included Skills
- `tech-planner`: 요구사항 인터뷰, PlanSpec v2 작성, 품질 게이트/린트, developer handoff 생성
- `tech-developer`: 계획 기반 큐 전체 실행(웨이브), strict 검증, evidence/report 생성
- `tech-scientist`: 논문/근거 기반 과학·수학·시뮬레이션/AI 설계를 의사코드와 검증 계획으로 변환
- `coolify-cli-infra-manager`: Coolify CLI/API 운영 자동화 및 인프라 작업 가이드

## Install
기본 설치 대상: `${CODEX_HOME:-$HOME/.codex}/skills`

전체 설치:
```bash
./scripts/deploy.sh --all
```

선택 설치:
```bash
./scripts/deploy.sh --skill tech-planner --skill tech-developer --skill tech-scientist
```

macOS 설치 스크립트:
```bash
./scripts/install-macos.sh --all
./scripts/install-macos.sh --all --yes
```

커스텀 설치 경로:
```bash
./scripts/deploy.sh --all --target /path/to/.codex/skills
```

## Minimal Usage
```bash
RUNTIME_ROOT="${SIGEE_RUNTIME_ROOT:-.codex}"
skills/tech-planner/scripts/plan_lint.sh "$RUNTIME_ROOT/plans/<plan-id>.md"
skills/tech-developer/scripts/codex_flow.sh "$RUNTIME_ROOT/plans/<plan-id>.md" --mode strict
```
