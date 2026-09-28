# asset-preset-distribution-pattern
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
새로운 규칙(rule)·스킬·훅을 만들 때마다 저장 위치와 등록 절차가 불명확함. 원본을 어디에 두고, 어떻게 프리셋으로 선언하고, 각 프로젝트에 어떻게 적용할지 설치기 구조를 직접 확인하지 않으면 알 수 없음.

## 규칙
- [ ] 원본 파일을 `assets/` 하위에 배치: 규칙은 `assets/rules/<name>/`, 스킬은 `assets/skills/`, 훅은 `assets/hooks/`
- [ ] `presets/workflow/<name>.conf` 파일 생성: `RULES+=<name>`, `SKILLS+=<name>`, `HOOKS+=<name>` 으로 등록
- [ ] 전파 대상 프로젝트의 `.claude/presets.lock` 에 프리셋명 추가
- [ ] `./update-all.sh` 실행 시 각 프로젝트가 기존 선택을 유지한 채 자동 재설치됨
- [ ] 새 세션 시작 시점에야 규칙/스킬이 로드됨 (진행 중인 세션에는 미적용)

## 근거
- 감지 횟수: 3회 (adhd 규칙 설치, fluent-korean 프리셋 생성, update-all.sh 전파 검증)
- 패턴 키: assets
