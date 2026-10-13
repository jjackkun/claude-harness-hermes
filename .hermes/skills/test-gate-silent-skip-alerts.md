# test-gate-silent-skip-alerts
<!-- hermes:auto-generated version:1 created:2026-10-07 -->

## 문제 상황
pytest 게이트에서 특정 조건(제외된 에이전트, 불명확한 상태)을 만날 때 조용히 건너뛰고 아무 피드백도 주지 않음. 나중에 테스트 실패를 발견해도 게이트가 묵묵히 지나갔는지 명시적으로 실패했는지 구분 불가능.

## 규칙
- [ ] pytest_gate.sh 에서 `exit 0` (silent pass)를 찾아내기 전에 경고 메시지 출력
- [ ] 스킵 사유(excluded agent, 판정불가 등)를 stderr로 명시적 기록
- [ ] "조용한 건너뜀"이 아니라 "경고와 함께 통과" 형태로 통일
- [ ] `.git/hooks/pre-commit` 에서도 같은 패턴 적용 — 게이트는 서로 다른 버전을 쓰지 않기

## 근거
- 감지 횟수: 1회 (세션 내 R-test 조용한 건너뜀 → 경고로 변경)
- 패턴 키: r-test-gate-backend-1465-excluded-agent-runs-pnpm
