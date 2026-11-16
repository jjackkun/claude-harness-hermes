---
name: feedback-git-add-own-files
description: "git add -A 금지 — 이 세션이 만든 파일만 경로로 올리되, 내 작업이 낳은 헤르메스·설치 산출물은 빠뜨리지 않는다"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 2dfe6f11-2f06-4280-9649-8db9c0ec0cce
  modified: 2026-11-16T04:31:18.555Z
---

커밋할 때 `git add -A` / `git add .` 를 쓰지 않는다. 이 세션이 만들거나 고친 파일만 경로를 나열해 올린다.
단, 내 작업의 부산물(`.hermes/factory.json`, `.claude/.factory-manifest.json`, sync-doc-counts 가 고친 `CLAUDE.md`·`README.md`·`harness.conf`,
설치 영수증에 오른 파일 등 헤르메스·하네스 산출물)은 "내 것" 이므로 함께 올린다.

**Why:** 2026-09-21 `git add -A` 가 다른 세션이 막 만든 `docs/typesafe-jev/` 를 쓸어 담았다. 사용자: "왜 git add 를 해 자신의 세션것을 해야지. (물론 그렇다고 해서 또 hermes 관련 안하지말고)".
같은 작업 폴더를 여러 세션이 동시에 쓴다.

**How to apply:** 커밋 전 `git status --short` → 내가 만든 경로만 `git add <path> ...` → `git diff --cached --name-status` 로 재확인.
모르는 파일이 보이면 건드리지 않고 보고에 한 줄 남긴다. [[feedback-commit-without-asking]]

**예외 — 공장 커밋·푸시 때 오래 묵은 미커밋분 (2026-11-16):** 공장 main 에 다른 세션이 남기고 끝난 파일(하루 이상 손대지 않은 수정,
`.claude/memory/*`, `.hermes/skills/*` 자동 생성분)이 있으면 "남겨 뒀다" 고 보고하지 말고 묶음별로 커밋·푸시한다.
사용자: "왜 남았어? 올려야 되는 것들을 안올린거야?" — 이 규칙을 남긴 파일을 방치하는 핑계로 쓰면 안 된다.
방금(몇 분 안) 고쳐진 파일만 진행 중일 수 있으니 수정 시각을 보고 판단한다. `.hermes/skills/` 커밋이 R-privacy 로 막히면
`python3 scripts/hermes-knowledge-files.py export` 뒤 다시 커밋한다.
