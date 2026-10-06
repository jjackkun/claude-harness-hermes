---
name: project-teulankkae-excluded
description: "teulankkae 는 전파 대상이 아니다 — 2026-10-06 .installed-projects 에서 뺐다(git 저장소 아님), 다시 넣거나 커밋·설치를 제안하지 않는다"
metadata:
  type: project
---

teulankkae 는 전파에서 뺀다(2026-10-06 "틀안깨 빼자").
`.installed-projects`(git 미추적 로컬 파일)에서 그 줄을 지워 `update-all` 대상이 9곳이 됐다(공장 포함). 디렉터리와 그 안의 파일은 건드리지 않았다.

**Why:** git 저장소가 아니고(`.git` 없음) hag 스크립트 같은 소우주 산출물이 들어간 흔적도 없다 — 커밋·푸시로 전파를 마칠 수 없는 곳이었다.

**How to apply:** 전파·대시보드·재측정에서 teulankkae 를 대상으로 세지 않는다. 설치·커밋·정리를 제안하지 않는다. 사용자가 다시 쓰겠다고 하면 `setup.sh` 로 재등록한다. [[project-rim-office-excluded]] [[feedback-propagate-means-commit-push]]
