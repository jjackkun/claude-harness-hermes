---
name: project-zeroday-private-no-rescrub
description: zeroday-frontend 는 프라이빗 저장소 — 추적 중인 옛 스킬 18개를 다시 가리라고(scrub files --apply) 제안하지 않는다
metadata:
  type: project
---

2026-09-29 사용자: "괜찮아. 제로데이는 프라이빗이야." — zeroday-frontend 의 `.hermes/skills` 18개(마스킹이 약했을 때 만든 것)를
지금 규칙으로 다시 가리지 않기로 했다. 판정 표 원문 비우기(`scrub db`)만 했다(로컬 파일).

**Why:** 프라이빗 저장소라 노출 위험이 낮다고 사용자가 판단했다. 다른 세션이 작업 중인 저장소라 작업 트리에 손대지 않는 원칙과도 맞는다.

**How to apply:** 전파·정리 때 zeroday 의 `scrub files` 를 제안하지 않는다. 단 R-privacy 게이트는 켜져 있어 사용자가 그 스킬 파일을 커밋하려 하면 "다시 가리면 달라지는 문장" 으로 막힌다 —
그때만 `python3 scripts/hermes-privacy-scrub.py files --apply` 를 안내한다. 소스에 박힌 비밀은 그 팀 소관. [[feedback-propagate-means-commit-push]]
