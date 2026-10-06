# test-gate-venv-selection-before-phase-b
<!-- hermes:auto-generated version:1 created:2026-10-02 -->

## 문제 상황
멀티 프로젝트 환경에서 테스트 실행 시 phase A (환경 준비)를 건너뛰고 phase B (규칙 적용)로 진입하면, 가상환경 경로 오류·패키지 미설치·환경변수 누락으로 연쇄 실패가 발생합니다. 세션에서 3회 반복 (venv 경로 인식 실패, DATABASE_URL 누락, auto-mode classifier 실패).

## 규칙
- [ ] 테스트 phase 실행 전 현재 프로젝트 디렉토리 확인 (`git rev-parse --show-toplevel`)
- [ ] `.venv` 또는 `venv/` 활성화 상태 확인; 미활성화면 `source .venv/bin/activate` 실행
- [ ] 프로젝트 환경변수 로드 (`.env` 파일 존재 확인 후 `source .env`)
- [ ] venv 내 필수 패키지 설치 확인 (`pip list | grep -E 'anthropic|pytest'`)
- [ ] phase B (규칙·게이트 적용)는 위 4가지 확인 후 진행
- [ ] 실패 메시지에 "가상환경 미활성화" 포함되면 즉시 중단하고 phase A 재실행

## 근거
- 감지 횟수: 3회
- 패턴 키: r-test-gate-phase-a-venv-lookup-phase-b-rules
