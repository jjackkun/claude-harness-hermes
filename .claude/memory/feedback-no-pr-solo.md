---
name: feedback-no-pr-solo
description: 혼자 작업하는 저장소라 PR 을 제안하지 않는다 — 작업 브랜치는 로컬 main 에 fast-forward 로 합친다
metadata:
  node_type: memory
  type: feedback
  originSessionId: 914646ce-a348-406c-afca-24a91ed2cd8f
  modified: 2026-11-12T04:13:15.240Z
---

PR 을 열자고 묻지 않는다. 작업 브랜치(worktree 포함)가 끝나면 로컬 main 에 `merge --ff-only` 로 합친다.

**Why:** 2026-11-12 사용자 — "나 혼자 작업중이잖아. PR안써도돼." (wrap_up 에서 PR 열기를 물은 데 대한 답)

**How to apply:** 마무리 질문·버튼에 create_pr 을 넣지 않는다. 합치기 전 main 작업 트리의 미커밋 파일이 브랜치 변경과 겹치지 않는지 본다. 푸시는 [[feedback-push-current-repo-only]] 대로 따로 지시가 있을 때.
