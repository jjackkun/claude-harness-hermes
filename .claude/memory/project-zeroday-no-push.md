---
name: project-zeroday-no-push
description: "zeroday-frontend 는 어떤 경우에도 자동으로 푸시하지 않는다 (2026-10-20 사용자 지시, 두 번 말함)"
metadata:
  node_type: memory
  type: project
  originSessionId: e5e8abad-16ba-4cb8-aa05-5a4f963aeb68
  modified: 2026-10-20T08:19:43.803Z
---

zeroday-frontend 는 자동 푸시 금지 — 전파(update-all) 뒤든 다른 작업 뒤든, 사용자가 그 저장소 이름을 대고 푸시하라고 할 때만 푸시한다.
2026-10-20 ui-prototype 전파 중 "제로데이 프론트엔드는 푸시하지마", 이어서 "앞으로 제로데이프론트엔드는 자동 푸시하지마. 기억해둬".

**Why:** 사용자 지시 (사유는 말하지 않음). 그날 이 저장소는 R-lint(ESLint no-undef — 설치된 `.claude/skills/ui-prototype` JS)에 막혀 커밋도 안 됐다.

**How to apply:** 전파할 때 zeroday-frontend 는 설치까지만 하고 푸시하지 않는다. 커밋 여부도 사용자에게 맡긴다. [[feedback-propagate-means-commit-push]] 의 예외. 관련: [[project-zeroday-private-no-rescrub]], [[feedback-push-current-repo-only]].
