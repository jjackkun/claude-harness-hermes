# headless-permission-allowlist
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
무인 실행 환경(cron, scheduled task, background agent)에서 도구 호출 시 권한 프롬프트 차단. `--dangerously-skip-permissions` 플래그로 우회하거나, allowlist 설정으로 사전 승인하는 선택지 사이에서 부담.

## 규칙
- [ ] 무인 모드에서 `--dangerously-skip-permissions` 절대 사용 금지 — 권한 기록 상실
- [ ] 세션 **시작 전** `.claude/settings.json`의 `allowedTools` 배열에 필요 도구 사전 등록
- [ ] 환경별 분리 필요 시 `.claude/settings.local.json` 사용 (read-only 설정)
- [ ] 삭제·강제푸시·머지 등 파괴적 도구는 allowlist 제외 유지
- [ ] 필요 도구 추가 시 `/update-config allow <tool>` 또는 `/fewer-permission-prompts` 스킬로 감사 진행

## 근거
- 감지 횟수: 0회
- 패턴 키: permission-prompts-block-headless
