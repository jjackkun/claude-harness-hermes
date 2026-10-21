---
name: project-rim-kanban-excluded
description: rim-kanban 은 2026-10-21 부터 전파(update-all) 대상에서 뺐다 — 깨진 가상환경 후속 작업도 제안하지 않는다
metadata:
  node_type: memory
  type: project
  originSessionId: 0e6b7c97-81eb-4bcc-967c-c8a3cff87854
  modified: 2026-10-21T04:36:09.742Z
---

rim-kanban 은 2026-10-21 사용자 지시로 `.installed-projects` 에서 뺐다(전파 대상 10곳). 설치·전파·커밋·푸시와 `backend/venv` 재생성(3.10 venv 가 3.12 를 가리켜 깨짐)을 제안하지 않는다.

**Why:** 같은 날 전파 뒤 "backend/venv 를 확인하고 다시 만들자" 는 다음 행동을 내자 사용자가 "제외해 — rim-kanban" 이라고 했다. 그날 전파분(커밋 3bd7997)은 이미 푸시돼 있고 되돌리라는 지시는 없었다.

**How to apply:** update-all·전파 보고에서 이 저장소를 빼고 센다. 다시 넣으라는 말이 있을 때만 `setup.sh` 로 재등록한다. 같은 처리: [[project-zeroday-frontend-excluded]].
