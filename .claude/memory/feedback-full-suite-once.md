---
name: feedback-full-suite-once
description: "전체 시험 묶음(약 5분 30초)을 단계마다 돌리지 말 것 — 바뀐 부분 시험만, 전체는 마지막 한 번"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 372676a8-4c67-4306-b316-ec6e251a2b06
  modified: 2026-09-28T04:56:34.449Z
---

작업 중에는 바뀐 파일에 걸리는 시험만 돌리고, 전체 묶음(`tests/run-all.sh`, 111개·약 5분 30초)은 커밋 묶음 끝에 한 번만 돌린다.

**Why:** 2026-09-28 agent-room-view 목표 6 에서 전체 묶음을 단계마다 반복하다 사용자가 중단시켰다 — "너무 오래 걸려. 뭐 하고 있는 거야." 커밋 게이트(R-test)도 전체를 다시 돈다.

**How to apply:** 새 기능 시험 + 설치 경로를 건드렸으면 `install-closure-test`·`copy-install-test`·`cx-baseline-distribution-test` 정도만. 새 파이썬 함수를 쓰면 전체 묶음 전에 `scripts/hooks/complexity.py` 로 R-cx 부터 잰다(설치 시험 3건이 이것으로 깨진다). 오래 걸리는 명령 전에는 무엇을 왜 도는지 한 줄 알린다. [[feedback-commit-without-asking]]

**파이썬 소우주(2026-10-01):** 느리면 먼저 `/usr/bin/time -f "%e초 CPU %P"` 로 CPU 사용률을 잰다 — 낮으면 기다림(원격 DB)이 원인이다. 작업 중 반복은 `pytest --testmon`(실측: 놓침 0)이 선택지이나 게이트에는 안 넣는다. 근거 `core-beliefs.md#r-test-changed-only`.
