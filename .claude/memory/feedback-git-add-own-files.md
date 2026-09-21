---
name: feedback-git-add-own-files
description: git add -A 금지 — 이 세션이 만든 파일만 경로로 올리되, 내 작업이 낳은 헤르메스·설치 산출물은 빠뜨리지 않는다
metadata:
  type: feedback
---

커밋할 때 `git add -A` / `git add .` 를 쓰지 않는다. 이 세션이 만들거나 고친 파일만 경로를 나열해 올린다.
단, 내 작업의 부산물(`.hermes/factory.json`, `.claude/.factory-manifest.json`, sync-doc-counts 가 고친 `CLAUDE.md`·`README.md`·`harness.conf`,
설치 영수증에 오른 파일 등 헤르메스·하네스 산출물)은 "내 것" 이므로 함께 올린다.

**Why:** 2026-09-21 `git add -A` 가 다른 세션이 막 만든 `docs/typesafe-jev/` 를 쓸어 담았다. 사용자: "왜 git add 를 해 자신의 세션것을 해야지. (물론 그렇다고 해서 또 hermes 관련 안하지말고)".
같은 작업 폴더를 여러 세션이 동시에 쓴다.

**How to apply:** 커밋 전 `git status --short` → 내가 만든 경로만 `git add <path> ...` → `git diff --cached --name-status` 로 재확인.
모르는 파일이 보이면 건드리지 않고 보고에 한 줄 남긴다. [[feedback-commit-without-asking]]
