# zeroday-frontend 의 페이지 이름 스킬 — 결정화 품질

> 출처: `docs/audits/2026-09-18-kis-trading-hermes-enable.md` 부하 실측 절

## 관측 (2026-09-18)

zeroday-frontend `skill_index`: 로컬 스킬 1,095개(파일 1,094). 한 턴("로그인 페이지 스타일 고쳐줘")에 주입된 규칙이
`commoncodemanagementpage.md`·`app-layout__content.md` — 컴포넌트/페이지 **이름**이 패턴 키가 돼 스킬로 굳은 것.
`pattern_count.crystallized=1` 943개. 결정화 junk 게이트(SKIP_SENTINEL)가 이런 키를 거르지 못했다.

## 먼저 잴 것

- 1,094개 중 제목이 코드 식별자 꼴(`[a-z]+page`, `__`, 케밥 컴포넌트명)인 비율.
- 그 스킬들의 `skill_injection` 도움 판정(helpful) — 주입만 되고 도움 0 이면 강등 대상(G-8).

## 고칠 때 후보

- 결정화 전 키 판정: 식별자 꼴 키는 결정화 후보에서 제외(어휘 규칙, R3).
- 드림 cleanup 의 junk 기준에 "도움 0 · 식별자 꼴 제목" 추가 → `--apply` 로 정리.
