---
name: project-zeroday-frontend-excluded
description: zeroday-frontend 는 2026-10-21 부터 전파(update-all) 대상에서 뺐다 — 푸시하면 자동 배포되는 저장소
metadata:
  node_type: memory
  type: project
  originSessionId: 0e6b7c97-81eb-4bcc-967c-c8a3cff87854
  modified: 2026-10-21T04:13:58.139Z
---

zeroday-frontend 는 2026-10-21 사용자 지시로 `.installed-projects` 에서 뺐다(전파 대상 11곳). 설치·전파·커밋·푸시를 제안하지 않는다.

**Why:** 그 저장소는 푸시하면 자동 배포된다. 2026-10-21 전파 때 설치기가 파이썬 시험(swagger_sync 등 4개)을 보고 `.venv` 를 만들었는데, 사용자는 "원래 없었다면 필요없는 것" 이라고 했다 — 그날 만든 `.venv` 는 지웠다.

**How to apply:** update-all·전파 보고에서 이 저장소를 빼고 센다. 다시 넣으라는 말이 있을 때만 `setup.sh` 로 재등록한다. 이름 대고 시킬 때만 손댄다는 [[project-zeroday-no-push]] 를 넓힌 것이다.
