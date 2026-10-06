# validate-before-commit-to-main
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
git revert HEAD가 반복되면 커밋 전 검증을 건너뛴 신호입니다. 계획 없이 커밋한 후 문제를 발견하고 되돌리는 사이클이 반복됩니다.

## 규칙
- [ ] 커밋 전 pre-commit hook 통과 필수 (테스트/린트/타입 체크)
- [ ] 의심 변경은 작은 단위 커밋으로 먼저 테스트
- [ ] 큰 변경(4 파일 이상, 공유 경계)은 code-reviewer 검토 요청
- [ ] --no-verify 금지 — 게이트가 막으면 근본 원인 고치기
- [ ] 커밋 메시지에 변경 이유와 영향 범위 명시

## 근거
- 감지 횟수: 3회 이상
- 패턴 키: revert:HEAD
- 규칙 출처: CLAUDE.md 코드 작성 규칙
