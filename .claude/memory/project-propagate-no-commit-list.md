---
name: project-propagate-no-commit-list
description: "전파 때 설치는 하되 커밋·푸시하지 않는 프로젝트 — jj-agent-room, Nbbang-Run, 제로데이 관련 전부"
metadata:
  node_type: memory
  type: project
  originSessionId: c4fbfad0-55b1-4de3-9e5b-4f3f9519e7e7
  modified: 2026-10-22T01:27:20.332Z
---

2026-10-22 사용자 지시: 전파(update-all) 때 **jj-agent-room · Nbbang-Run · 제로데이 관련(zeroday*)** 은 커밋하면 안 된다.
설치는 그대로 하고, 설치 산출물 커밋·푸시만 건너뛴다. 나머지 등록 프로젝트는 영수증 경로만 커밋·푸시([[feedback-propagate-means-commit-push]]).

**Why:** 이 저장소들은 다른 세션의 진행 중 작업이 섞여 있거나(jj-agent-room 의 src/·server/ 미커밋분), 푸시가 곧 배포다([[project-zeroday-frontend-excluded]]).
**How to apply:** 전파 보고에서 이 둘은 "설치만 · 커밋 안 함"으로 따로 적는다. 커밋을 먼저 제안하지 않는다.
