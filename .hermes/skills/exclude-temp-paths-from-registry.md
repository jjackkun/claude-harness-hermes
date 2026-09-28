# exclude-temp-paths-from-registry
<!-- hermes:auto-generated version:1 created:2026-09-18 -->

## 문제 상황

공유 설치기(`project-claude.sh`, `project-codex.sh`)에서 임시 경로(`/tmp`, `$TMPDIR`)의 프로젝트를 설치할 때, 그 경로를 공유 레지스트리(`.installed-projects`)에 등록하면 다른 모든 설치에 영향을 미침. 테스트용 경로 설치가 전체 레지스트리를 오염시켜 공장의 다른 구독 에이전트의 동작을 방해했음(09-16).

## 규칙

- [ ] 공유 설치기 함수(`project-claude.sh`, `project-codex.sh`)에 판정 게이트를 추가: 설치 경로가 `/tmp` 또는 `$TMPDIR` 아래면 `.installed-projects`에 기록하지 않음
- [ ] `HERMES_NO_REGISTER=1` 환경변수로 명시적 제어 가능하게 함
- [ ] 테스트 전용 플래그 `HERMES_FORCE_REGISTER=1`로 강제 등록(test harness용)
- [ ] 모든 공유 설치기에 동일한 가드 함수(예: `_check_temp_path_gate()`) 적용
- [ ] 설치 후 `.installed-projects` 무결성 테스트로 임시 경로 줄이 0임을 검증

## 근거

- 감지 횟수: 3회 이상 (9월 16-18일 기간)
- 패턴 키: register-judgment-gate-in-shared-precommit
- 영향: 레지스트리 오염 → 전파 손상 → 9곳 공장 재구성 필요
