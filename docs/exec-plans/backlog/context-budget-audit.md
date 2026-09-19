# context-budget — 매 세션 로드되는 스킬·룰·CLAUDE.md·MCP 의 컨텍스트 비용 표

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #6 (가치 중)

## 문제

세션 시작 시 CLAUDE.md(관리 블록 포함)·룰셋·스킬 description 40여 개·에이전트 정의·MCP 도구 설명이 컨텍스트에 들어간다.
얼마가 어디에 쓰이는지 표가 없다. `R-out` 은 Bash 출력 바이트만 잰다. 2026-09-18 문구 안티패턴 감사는 손으로 했다.

## ECC 의 실체

`skills/context-budget/` — 에이전트·스킬·MCP·룰 각각이 먹는 토큰을 추정해 절감 우선순위를 낸다.

## 고칠 때 후보

- `scripts/hooks/context_budget.py`: 설치된 CLAUDE.md·`.claude/rules/**`·스킬 frontmatter description·에이전트 frontmatter·`.mcp.json` 도구 설명의
  바이트/추정 토큰을 항목별로 합산해 표로. 모델 호출 0(R3). `gate_report.py` 와 같은 자리에서 실행.
- 우주 대시보드 건강 판에 "세션 고정 비용" 한 줄로 합류.
- 문턱은 정하지 않는다 — 먼저 12곳 실측 분포를 본다.

## 착수 조건

hermes-dashboard 계획 Step 1(데이터 수집 모듈) 과 함께. 단독으로도 반나절.
