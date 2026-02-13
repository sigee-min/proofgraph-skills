# Sigee Skill Pack

커스텀 스킬 4종(`sigee-spec-author`, `sigee-implementer`, `sigee-reviewer`, `sigee-project-manager`)을 한 곳에서 버전 관리하고, 배포할 때 `~/.codex/skills`로 동기화하기 위한 저장소입니다.

## 구성
- `skills/`: 배포 대상 스킬 소스
- `scripts/deploy.sh`: 배포 스크립트
- `pack.toml`: 패키지/스킬 버전 선언
- `CHANGELOG.md`: 배포 릴리스 기록

## 빠른 배포
```bash
cd /Users/sigee/Dev/sigee-skill-pack
./scripts/deploy.sh --all
```

기본 대상은 `${CODEX_HOME:-$HOME/.codex}/skills` 입니다. 필요하면 `--target`으로 덮어씌웁니다.

## 배포 원칙
- 삭제는 하지 않고 `Done`/`Deprecated`/삭제 대신 아카이빙 등 운영 규칙은 스킬 문서 자체 규칙을 따릅니다.
- 배포 시 `--all` 또는 `--skill <name>`으로 필요한 항목만 푸시합니다.
- 배포는 스킬 폴더 단위로 `rsync --delete` 동기화하므로, 특정 스킬 내부에서 삭제한 파일은 대상 경로에서도 제거됩니다.

## 버전 관리
현재 `pack.toml`에 버전이 정의됩니다.

- 큰 스킬 변경: `pack` 과 해당 스킬 버전 동시 증가
- 자잘한 문구 수정: 스킬 패치 버전 증가
- 규칙 변경(워크플로우/템플릿 정책): 스킬 메이저/마이너 정책에 맞춰 증가

릴리스 절차(권장):
1. `pack.toml`과 변경된 스킬 파일 수정
2. `CHANGELOG.md`에 항목 추가
3. Git 커밋 + 태그
   ```bash
   git add .
   git commit -m "chore(release): bump skill pack to x.y.z"
   git tag vx.y.z
   git push --follow-tags
   ```
4. 대상 장비에서 태그 체크아웃 후 배포
   ```bash
   git fetch --tags
   git checkout vx.y.z
   ./scripts/deploy.sh --all
   ```

## 브랜치/버전 가이드
- 브랜치명은 `main` 기준 릴리스 브랜치 운용 권장(필요 시 `release/*`, `hotfix/*` 사용)
- 되돌릴 때는 `git checkout <이전태그>` + 재배포

## 다중 환경 적용
- 팀 공통 사용 시 동일 레포지토리를 clone 한 뒤 `deploy.sh` 실행
- 개인별 커스텀 경로 사용 시 `--target /path/to/.codex`로 설치

## 참고
- `pack.toml`은 사람이 수정하기 쉬운 단일 소스입니다.
- 스킬 자체의 운영 규약은 각 스킬의 `SKILL.md`를 참고해 주세요.
