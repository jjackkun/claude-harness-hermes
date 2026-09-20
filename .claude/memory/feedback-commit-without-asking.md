---
name: feedback-commit-without-asking
description: "검증이 끝난 작업은 묻지 말고 커밋한다. 커밋을 나눌지·어떻게 묶을지는 내가 정한다 — 그런 질문 자체가 \"어이없다\""
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e8f48a79-4a6d-4a26-ada2-055e2ffca045
  modified: 2026-09-20T04:24:05.515Z
---

2026-09-20, roundtrip Step 1 + 도구 설치기 작업 뒤 "31개 변경을 두 커밋으로 나눌지 답해 달라" 고 묻자
"이건 물어볼 게 아니잖아 … 커밋을 나눠서 할지 아닐지를 물어보는 게 어이없다" 고 했다.

**Why:** 커밋 묶음은 판단이 정해진 관례(책임 단위로 나눈다)이고, 사용자가 되돌릴 수 있는 일이다. 묻는 것은 일을 사용자에게 넘기는 것이다.

**How to apply:** 테스트가 초록이고 계획서를 갱신했으면 책임 단위로 나눠 **바로 커밋**하고 결과만 보고한다.
푸시·머지·외부 게시는 여전히 지시가 있을 때만. [[feedback-no-template-forms]] 와 같은 결: 결정할 수 있는 것은 묻지 않는다.
