---
name: project-rim-office-excluded
description: "rim-office 는 더 쓰지 않는 소우주 — 2026-09-22 전파 대상(.installed-projects)에서 뺐다, 다시 넣거나 커밋하지 않는다"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3744fefb-8003-401a-b6e8-cf0b4ccaac19
  modified: 2026-09-22T05:13:43.905Z
---

rim-office 는 사용자가 더 쓰지 않는다(2026-09-22 "rim-office 제외하자. 안쓸거야").
`.installed-projects`(git 미추적 로컬 파일)에서 그 줄을 지워 `update-all` 대상이 11곳이 됐다. 저장소와 그 안의 미커밋 변경 107개는 건드리지 않았다.

**Why:** 다른 설치기(`ai-dev-setting`) 산출물과 우리 설치물이 섞여 커밋 여부가 계속 미정으로 남던 곳이다.

**How to apply:** 전파·대시보드·재측정에서 rim-office 를 대상으로 세지 않는다("12곳" → 11곳). 커밋·정리를 제안하지 않는다.
사용자가 다시 쓰겠다고 하면 `setup.sh` 로 재등록한다. [[feedback-propagate-means-commit-push]]
