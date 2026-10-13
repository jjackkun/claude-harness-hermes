# pytest-gate-silent-skip-alert
<!-- hermes:auto-generated version:1 created:2026-10-07 -->

## 문제 상황
테스트 게이트(R-test)가 특정 환경 조건(venv 부재, uv 프로젝트 구조)에서 조용히 테스트를 건너뛰었고, 실제 테스트 커버리지 문제를 파악하지 못함. 또한 `.git/hooks`의 낡은 `pytest_gate.sh` 사본이 원본(`assets/hooks`)과 동기화되지 않아 게이트 규칙이 불일치.

## 규칙
- [ ] 테스트 게이트 설정 파일(`pytest_gate.sh` 등) 수정 후 `.git/hooks/pre-commit`에 즉시 반영 (문서 싱크)
- [ ] venv 격리 규칙(venv-only)과 실제 실행 환경 간 불일치 발생 시 경고 발생 (INFO 이상 로깅)
- [ ] 테스트 건너뜀(skip) 상황을 명시적으로 로깅 — 조용한 건너뜀 금지
- [ ] pytest 실행 전 환경 검증: `--base-url`, `--model` 같은 커스텀 옵션 지원 확인
- [ ] uv 프로젝트에서 시스템 pytest 사용 시 venv 격리 체크 활성화

## 근거
- 감지 횟수: 3회
- 패턴 키: r-test-gate-venv-only-uv-projects-system-pytest
