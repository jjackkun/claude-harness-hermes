---
name: feedback-review-docs-after-writing
description: 문서(계획서·설계·안내서)를 만들면 묻지 말고 바로 리뷰 에이전트를 돌린다
metadata:
  node_type: memory
  type: feedback
  originSessionId: f9c31f06-c2f9-448a-8196-32bb16be98fc
  modified: 2026-09-28T08:56:15.153Z
---

문서를 새로 만들거나 크게 고치면, 사용자에게 "리뷰할까요?" 묻지 말고 바로 리뷰를 돌리고 결과를 코드로 가려서 반영한다.

**Why:** 2026-09-28 사용자가 "문서는 만들었으면 리뷰 돌려봐." 라고 지시했다. 그날 계획서 리뷰(planner-lite·architect-lite)가 "생성 지점 2곳(실제 5곳)" 같은 사실 오류와 누출 경로를 실제로 잡았다.

**How to apply:** 계획서·설계는 planner-lite / architect-lite, 안내서·사실 표는 읽기 전용 대조(Explore 등). 받은 지적은 그대로 옮기지 않고 코드·실측으로 성립 여부를 가린 뒤 보고한다. [[feedback-full-suite-once]] 와 같은 결 — 검증은 내가 먼저 한다.
