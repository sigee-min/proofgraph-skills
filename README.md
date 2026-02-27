# ProofGraph Skills

Codex에서 쓰는 스킬 3종(`tech-planner`, `tech-developer`, `tech-scientist`)을
설치하고 배포하는 저장소입니다.

## 이 스킬팩의 컨셉

이 스킬팩은 DAG를 단순 실행 그래프가 아니라 제품 목표를 운영하는 제어 레이어로 사용합니다.
`.sigee/product-truth`의 전역 목표(vision, pillar, objective, outcome, capability)를 기준으로
우선순위와 완료 조건을 맞추고, 시나리오 DAG로 계획-구현-검증의 연결을 추적합니다.
핵심은 "작업 목록"보다 "목표 정합성"을 먼저 관리하는 방식입니다.

## 방법론

흐름은 계획, 실행, 리뷰 순서로 돌아갑니다.
`tech-planner`가 요구사항을 실행 가능한 단위로 나누고, `tech-developer`가 strict 모드로 구현과 검증을 진행합니다.
수치 해석, 시뮬레이션, AI 방법론처럼 불확실성이 큰 구간은 `tech-scientist`가 근거와 검증 계획을 먼저 고정합니다.
그다음 리뷰 게이트에서 완료 여부를 판단하고, 필요하면 다시 실행 큐로 되돌립니다.

여기서 중요한 원리는 제어역전(IoC)입니다.
사용자가 매번 절차를 직접 지시하지 않아도, planner가 큐 상태와 검증 근거를 읽어 다음 실행을 결정합니다.
developer와 scientist는 결과와 evidence를 review로 반환하고, `done`은 review 기준을 통과했을 때만 열립니다.

## 장점과 트레이드오프

이 구조의 장점은 전역 목표와 실제 구현이 DAG/traceability로 묶여 방향 이탈이 줄어든다는 점입니다.
또한 완료 기준이 근거 기반이라 "완료라고 했지만 재현되지 않는" 문제를 초기에 줄일 수 있습니다.
역할이 계획/구현/검증으로 분리되어 있어 이슈가 생겼을 때 원인 위치를 좁히기도 쉽습니다.

대신 단점도 분명합니다.
빠른 데모만 필요한 작은 작업에서는 절차가 무겁게 느껴질 수 있고,
저장소에 테스트/검증 명령이 정리되어 있지 않으면 strict 게이트가 속도를 떨어뜨릴 수 있습니다.
초기에는 세팅 비용이 들지만, 반복 개발 구간에서는 안정성이 더 커지는 쪽에 가깝습니다.

## 포함된 스킬

현재 포함된 스킬은 `tech-planner`, `tech-developer`, `tech-scientist`이며,
각각 계획 수립, strict 구현, 과학/수치 검증 보강을 담당합니다.

## 기본 사용 흐름

사용자는 목표와 요구사항 중심으로 요청하면 됩니다.
일반적인 순서는 planner로 계획을 만들고, developer로 구현/검증을 진행하며,
필요하면 scientist를 거쳐 불확실성을 줄인 뒤 review를 통과시켜 완료하는 방식입니다.
내부 큐나 런타임 경로는 기본적으로 사용자 대화에 노출하지 않습니다.

## 실행 환경

- Node.js 20+
- Windows 설치 래퍼 사용 시 PowerShell 7+

## 설치

추천 방식:

```md
$skill-installer
Install tech-planner, tech-developer, and tech-scientist from this repository into my Codex skills path.
```

로컬 스크립트로 직접 설치:

```bash
node scripts/node/skillpack-cli.mjs install --all
```

플랫폼 래퍼:

```bash
bash scripts/install-macos.sh --all
bash scripts/install.sh --all
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/install-windows.ps1 -All
```

## 배포

```bash
node scripts/node/skillpack-cli.mjs deploy --all
```

Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/deploy.ps1 -All
```

## 빠른 시작 프롬프트

기획:

```md
$tech-planner
신규 요구를 제품 기능으로 분해하고 우선순위를 정해줘.
바로 실행할 다음 작업 1건만 제시해줘.
```

구현:

```md
$tech-developer
승인된 계획을 strict 모드로 끝까지 실행해줘.
사용자 영향, 검증 신뢰, 잔여 리스크 순서로 보고해줘.
```

과학/AI 검증:

```md
$tech-scientist
복잡한 시뮬레이션/수학/AI 문제를 논문 근거 기반으로
의사코드와 검증 계획까지 만들어줘.
```

## 운영 메모

- `Governance CI`는 macOS/Linux/Windows를 모두 확인합니다.
- 한 OS라도 실패하면 `Deployment Gate`를 통과할 수 없습니다.
- 상세 런북: `.sigee/migrations/windows-governance-gate-runbook.md`

## 저장소 구조

- `.sigee/`: 정책, 제품 진실(SSoT), 운영 문서
- `.sigee/.runtime/`: 실행 중 생성되는 런타임 산출물(기본 git ignore)
