# separate-test-db-config-by-environment
<!-- hermes:auto-generated version:1 created:2026-10-02 -->

## 문제 상황
로컬 터미널에서 프로젝트별 테스트를 실행할 때, 각 프로젝트가 다른 가상환경과 테스트 DB 설정(포트, 호스트, DB명)을 요구하지만 환경 변수 누락이나 설정 순서 실수로 반복 실패. 특히 terminal-shipping 같은 다중 프로젝트 환경에서 DATABASE_URL_TEST 구성이 뒤바뀌거나 미설정되는 경우 발생.

## 규칙
- [ ] 테스트 실행 전 프로젝트별 가상환경 먼저 활성화 (예: `source backend/.venv/bin/activate`)
- [ ] DATABASE_URL_TEST 환경 변수를 프로젝트마다 분리해 설정 (포트/호스트/DB명 확인)
- [ ] 환경 변수 누락 감지 시 테스트 스킵 또는 명확한 에러 메시지 출력
- [ ] 커스텀 엔드포인트 지원 (`--base-url`, `--model` 플래그) — 로컬 개발 DB와 원격 엔드포인트 겸용

## 근거
- 감지 횟수: 4회 (r-test-venv-test.sh · test_vessel_access.py · 및 DATABASE_URL_TEST 누락 관련 B신호)
- 패턴 키: test-db-local-terminal-shipping-details-factory-rules
