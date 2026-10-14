---
name: project-wonil-excluded
description: "wonil 은 전파 대상이 아니다 — 2026-10-14 .installed-projects 에서 뺐다(git 저장소 아님), 다시 넣거나 커밋·설치를 제안하지 않는다"
metadata:
  node_type: memory
  type: project
  originSessionId: 98c79ec2-c245-4600-9c86-598033b670bf
  modified: 2026-10-14T13:23:12.313Z
---

wonil 은 전파에서 뺀다(2026-10-14 "원일 빼").
`.installed-projects`(git 미추적 로컬 파일)에서 그 줄을 지워 `update-all` 대상이 3곳(terminal-shipping · 공장 · jj-agent-room)이 됐다. 디렉터리와 그 안의 파일은 건드리지 않았다.

**Why:** git 저장소가 아니고(`.git` 없음, `abc.txt` 같은 시험 흔적) 커밋·푸시로 전파를 마칠 수 없는 곳이었다 — teulankkae 와 같은 경우.

**How to apply:** 전파·대시보드·재측정에서 wonil 을 대상으로 세지 않는다. 설치·커밋·정리를 제안하지 않는다. 다시 쓰겠다고 하면 `setup.sh` 로 재등록한다. [[project-teulankkae-excluded]] [[feedback-propagate-means-commit-push]]
