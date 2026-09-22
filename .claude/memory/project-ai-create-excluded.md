---
name: project-ai-create-excluded
description: "ai-create 는 더 쓰지 않는 소우주 — 2026-09-22 전파 대상(.installed-projects)에서 뺐다, 다시 넣거나 풀·커밋을 제안하지 않는다"
metadata:
  type: project
---

ai-create 는 사용자가 더 쓰지 않는다(2026-09-22 "ai-create 소우주에서 삭제해. 안쓸거야").
`.installed-projects`(git 미추적 로컬 파일)에서 그 줄을 지웠다. 이 컴퓨터의 전파 대상은 3곳 → **2곳**(wonil · terminal-shipping).
저장소 자체와 그 안의 미추적 파일·백업(`.hermes/.backup-20260922/`)은 건드리지 않았다.

**Why:** 그 저장소 사본이 origin/master 보다 10 커밋 뒤였고, 들어올 커밋이 `.hermes/agents.json`·`organization.yaml`·`universe.id` 를
추가하는데 같은 경로가 미추적으로 있어 `git pull` 이 거부됐다. 치우려는 `rm` 은 identity-guard 훅이 막았다(상대 경로를 공장 기준으로 풀어 오판).
그 매듭을 푸는 대신 사용자가 소우주에서 제외하기로 결정했다.

**How to apply:** 전파·대시보드·재측정에서 ai-create 를 세지 않는다. 풀·커밋·재설치를 제안하지 않는다.
다시 쓰겠다고 하면 `setup.sh` 로 재등록한다. [[project-rim-office-excluded]] [[feedback-propagate-means-commit-push]]
