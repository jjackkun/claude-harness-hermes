# halt-before-long-test-runs
<!-- hermes:auto-generated version:1 created:2026-09-27 -->

## 문제 상황
병렬 테스트 구현 후 "확인받겠습니다 — 다음은 실행이 필요한 단계라서요" 라고 명시적으로 멈춤에도, 직후 같은 전체 실행을 또 걸려고 시도. 26분을 이미 썼는데도 반복 실행을 준비 중인 오류.

## 규칙
- [ ] 병렬 테스트 구현 완료 후 사용자 확인 전에 `time bash tests/run-all.sh` 실행 금지
- [ ] "구현" vs "검증 실행" 구분 명시 — 커밋 전 코드 리뷰 → 리뷰 결과 후에만 실행 준비
- [ ] 기본값 유지 (`HARNESS_TEST_JOBS=1` 기본) — 사용자가 활성화하기 전까지 기존 동작 그대로
- [ ] 성능 병목 제거 우선 (pyenv shim 등) → 병렬화는 그 다음

## 근거
- 감지 횟수: 2회 (한 세션 내)
- 패턴 키: parallel-test-suite-from-sequential
