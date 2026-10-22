# Isolate Authored Changes Before Commit
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
커밋 전 presets·scripts 같은 공유 파일에서 다른 세션의 변경과 현재 세션의 변경이 섞여있어, 출처를 명확히 하지 못한 채 불필요한 변경까지 스테이징하거나 변경 범위를 파악하기 어려움.

## 규칙
- [ ] 커밋 전 `git diff` 로 각 파일 변경 내용 확인 (라인별 출처 검증)
- [ ] 다른 세션 변경(설정 자동화·설치 결과물)과 현재 작업 변경 명확히 구분
- [ ] `git add -A` 금지 — 수정한 파일을 명시적으로 나열 (경로 지정)
- [ ] 큰 파일(400줄 이상) 변경은 라인 범위 재확인 후 필요한 것만 스테이징
- [ ] 출처 불명 변경은 `git show` 로 커밋 이력 확인 — 다른 세션이면 되돌리기

## 근거
- 감지 횟수: 3회 이상
- 사례: presets/workflow/harness.conf 다른 세션 변경 제거·zeroday-frontend pre-commit 396줄 변경 출처 미확인
- 패턴 키: pre-commit-measure
