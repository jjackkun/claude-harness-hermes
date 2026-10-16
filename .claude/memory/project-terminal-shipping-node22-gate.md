---
name: project-terminal-shipping-node22-gate
description: terminal-shipping 커밋 게이트(R-test)는 Node 22 가 PATH 에 있어야 통과 — 세션 셸 기본 node 는 12 라 Playwright 시험 3건이 실패한다
metadata:
  node_type: memory
  type: project
  originSessionId: 7de5661a-a097-40df-ae99-797098f35c3a
  modified: 2026-10-16T14:06:23.705Z
---

세션 셸의 `node` 는 시스템 `/usr/bin/node` v12.22.9 다. terminal-shipping 의 `tests/test_render_limit.py` 는
`node_modules/playwright` 가 있으면 돌고, Playwright 는 Node 18+ 를 요구해 3건이 실패 → R-test 가 커밋을 막는다.
nvm 에 v22.22.0 이 있고 저장소 `.nvmrc` 는 `22`.

**Why:** 2026-10-16 전파 커밋이 이 이유로 막혔다. 전파 파일과 무관한 환경 문제였다.

**How to apply:** terminal-shipping 에서 커밋할 때 `export PATH=$HOME/.nvm/versions/node/v22.22.0/bin:$PATH` 를 먼저 둔다(우회가 아니라 같은 시험을 맞는 환경에서 돌리는 것).
pre-commit 이 R-test 로 막히면 실패 시험 이름부터 본다. [[feedback-propagate-means-commit-push]]
