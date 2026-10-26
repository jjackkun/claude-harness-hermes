# session-start-defer-mod-layer
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
세션 시작 훅이 mod 레이어를 자동으로 로드/활성화하여, 사용자가 명시적으로 요청하지 않았을 때도 mod 상태가 열리는 문제가 반복됨. 커밋 066d8ff에서 수정되었으나, 훅 구조 변경 시마다 같은 버그가 재발할 위험.

## 규칙
- [ ] `startup` 훅과 `resume` 훅은 mod 레이어를 자동으로 열지 않기 (lazy loading)
- [ ] mod 레이어는 사용자가 `/mod` 커맨드 또는 명시적 호출로 요청할 때만 활성화
- [ ] 훅이 현재 mod 상태를 조회할 때는 상태만 읽고, 로드하거나 변경하지 않기
- [ ] mod 레이어 로드는 사용자 의도의 신호가 있을 때만 실행하도록 가드 추가

## 근거
- 감지 횟수: 3회 (자동 로드 발견 → 수정 → 확인)
- 패턴 키: mod-session-start-hook
- 관련 커밋: 066d8ff
