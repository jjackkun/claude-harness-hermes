# exclude-playwright-from-factory
<!-- hermes:auto-generated version:1 created:2026-11-15 -->

## 문제 상황
Playwright MCP 서버가 공장 저장소(claude-harness-hermes)에 포함되지 않고 사용자 전역 설정(~/.claude.json)에만 관리됩니다. 공장 프로세스에 Playwright 설치·변경을 추가하면 운영 책임이 분산되고 버전 관리가 복잡해집니다.

## 규칙
- [ ] Playwright 설정은 ~/.claude.json 의 mcpServers.playwright 에서만 관리한다
- [ ] 공장 저장소의 설치·변경 프로세스에 Playwright 추가 금지
- [ ] Playwright 러너는 기본값 `--disable-snapshots` (Jev 없음) 로 실행
- [ ] 공용 Playwright 러너 미생성 — 별도 백로그 유지
- [ ] Playwright 기능 요청은 공장이 아닌 사용자 환경 설정으로 안내

## 근거
- 결정 기록: 6d301c6 (러너 미포함), 6023966 (공용 러너 미생성 확정)
- 권한: assets/permissions/node.json:20 (Bash playwright:* 허용)
- 토큰 절감: Jev 없이 도는 러너 별도 백로그
- 감지 횟수: 4회
- 패턴 키: playwright
