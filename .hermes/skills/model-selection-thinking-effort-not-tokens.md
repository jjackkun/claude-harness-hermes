# model-selection-thinking-effort-not-tokens
<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
프롬프트 지시에 Opus 5.5의 자동 thinking 능력을 무시한 문구가 산재:
- U8: `performance.md` 에 "31,999 tokens 예약", `MAX_THINKING_TOKENS` 환경변수 문구 — thinking 토큰 예산이 없음
- U13: `CLAUDE.md` 에 "(3초 멈춤)", "반드시 3초 멈추고 확인" — thinking은 자동 활성화, 수동 지시 불필요
- thinking 깊이 제어는 effort (low/medium/high/xhigh/max) 파라미터로만 가능

## 규칙
- [ ] 프롬프트에서 thinking 토큰 제약·환경변수 지시 제거 ("31,999 tokens", `MAX_THINKING_TOKENS`, "enable/disable")
- [ ] 수동 사고 유도 체크리스트 제거 ("3초 멈춤", "반드시 멈추고 확인" — thinking은 자동)
- [ ] 모델 선택 문서에서 thinking 깊이 제어 수단을 effort 로만 명시
- [ ] 확인: performance.md "Extended Thinking + Plan Mode" 섹션이 effort 파라미터 중심으로 쓰여 있는지 검증

## 근거
- 감지 횟수: 2회
- 패턴 키: prompt-thinking-reduction-unstable-use-effort
