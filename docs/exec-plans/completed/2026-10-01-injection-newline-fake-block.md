# 세션 주입·기억 보기에서 저장된 본문의 줄바꿈이 가짜 블록을 만든다

> 작성일: 2026-10-01
> 목적: 요약·기억 본문에 줄바꿈과 `■`/제목 줄을 넣으면 세션 시작 주입(`render_agent_summaries`)과 기억 보기에서 진짜 블록처럼 보인다.

## 무엇

`hermes_agent_summaries._block` 은 슬롯 항목을 `  결정: a / b` 한 줄로 이어 붙이는데 **항목 안의 줄바꿈을 그대로 둔다.**
요약기(Haiku)가 만든 항목이나 가르친 기억 본문에 `\n■ 2099-01-01 · 방\n  결정: …` 가 들어 있으면 주입 본문에 가짜 블록이 별개 항목처럼 나온다.

2026-10-01 `agent-recall` 구현 리뷰에서 발견했다. 검색(`hermes_agent_recall`)은 자기 출력에서만 `■`·`[기억 검색]` 로 시작하는 본문 줄을 막았다(`_defang`).
**세션 주입 쪽은 아직 같은 노출이 남아 있다.**

## 후보

공통 렌더러(`_block`)에서 항목 안의 줄바꿈을 공백으로 접거나, 줄 앞의 표지를 막는다. 그러면 검색의 `_defang` 도 필요 없어진다.
세션 주입은 모든 세션의 시작이라 바뀌면 `hermes-soul-inject-test` · `hermes-agent-summary-test` 의 본문 대조가 모두 영향받는다 — 계획서를 쓰고 한다.

근거: `docs/exec-plans/completed/2026-10-01-agent-recall.md` §7 (구현 리뷰 N4).

## 회고

착수·완료 계획 `docs/exec-plans/completed/2026-10-03-injection-newline-fold.md` §8.
