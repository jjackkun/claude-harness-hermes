---
name: feedback-propagate-means-commit-push
description: "전파" 는 update-all 설치로 끝이 아니라 12곳 소우주 각각에서 설치물을 커밋하고 푸시하는 것까지다
metadata:
  type: feedback
---

"전파하자" = 공장 푸시 → `update-all.sh` 로 12곳 설치 → **각 소우주에서 설치물 커밋 + 푸시**.
설치만 하고 끝내면 전파가 아니다.

**Why:** 2026-09-21 사용자: "전파한다라는것은 그곳도 커밋 푸시한다라는것이야". 그 전까지 설치만 하고 끝내 12곳에 미커밋 설치물이 쌓였다.

**How to apply:** 소우주마다 `.claude/.last-install.txt`(설치 영수증)에 오른 경로만 올린다 —
`git add $(git ls-files -co --exclude-standard $(cat .claude/.last-install.txt))`. 사용자 작업 파일은 건드리지 않는다([[feedback-git-add-own-files]]).
**영수증만으로는 모자란다(2026-09-29 실측):** `.last-install.txt` 에는 헤르메스 스크립트가 적히지 않는다(scripts/ 는 2줄뿐) —
설치 목록 `.claude/.factory-manifest.json` 의 `items[].name` 중 바뀐 경로도 함께 올린다. 추적 중인 `__pycache__` 는 건드리지 않는다.
공장에서 걷은 파일은 설치기가 지우므로 `git ls-files --deleted` 로 그 경로만 올린다.
push 가 원격 앞섬으로 거절되면 `pull --rebase`(force 금지), 생성물 충돌은 새 설치본으로. pre-commit 이 막으면 우회하지 말고 그 소우주를 보고.

**예외 — zeroday-frontend:** 푸시하지 않는다(2026-09-21 사용자 "제로데이는 놔둬"). 사용자가 `develop` 에 미푸시 작업 커밋을 두고
다른 세션에서 작업 중인 저장소다. 전파 때는 설치까지만 하고, 커밋·푸시 여부는 사용자가 정한다.
