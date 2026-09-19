# .claude/ 설정 보안 스캔 — 권한 와일드카드·훅·MCP·CLAUDE.md 인젝션 점검

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #8 (가치 중)

## 문제

`check-secrets.py` 는 코드 속 비밀만 본다. 우리가 12곳에 배포하는 `settings.json` 권한 allowlist·훅 명령·`.mcp.json`·CLAUDE.md
관리 블록 자체는 아무도 훑지 않는다. `fewer-permission-prompts` 는 allowlist 를 **늘리는** 쪽 도구다.

## ECC 의 실체

`skills/security-scan/`(AgentShield) — 권한 와일드카드(`Bash(*)` 류), 위험 훅 명령, MCP 서버 출처, CLAUDE.md 의 프롬프트 인젝션 패턴 점검.

## 고칠 때 후보

- `scripts/hooks/claude_config_scan.py`: (1) 권한 allow 에 광역 와일드카드 (2) 훅 command 가 저장소 밖 경로·`curl|sh` (3) `.mcp.json` 이
  원격 URL 이면 출처 표시 (4) CLAUDE.md·rules 에 "ignore previous"·숨은 HTML 주석 지시 — 네 항목만. 모델 호출 0.
- pre-commit **경고** 게이트로 시작(R-cov 처럼). 공장 `assets/` 와 소우주 `.claude/` 둘 다 대상.

## 착수 조건

없음. 반나절. 먼저 공장 자기 설치에서 돌려 오탐률을 본다.
