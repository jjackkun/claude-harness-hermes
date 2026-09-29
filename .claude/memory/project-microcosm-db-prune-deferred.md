---
name: project-microcosm-db-prune-deferred
description: 소우주 DB 의 죽은 표 정리(hermes-db-prune.py --apply)는 사용자가 "현재까지 있는 것들은 놔두자"로 보류 — 먼저 제안하지 않는다
metadata:
  type: project
---

2026-09-29 사용자: "아냐. 현재까지 있는것들은 놔두자." — 죽은 표 4개(session_history 색인·harness_rules·compaction_log·session_reuse)를
소우주 DB 에서 걷는 `python3 scripts/hermes-db-prune.py --apply` 를 하지 않기로 했다. 공장 DB 만 정리했다(6,680 → 1,468 KB).
새 DB 는 그 표를 만들지 않고, 옛 DB 에 표가 남아 있어도 새 코드는 동작한다(무해).

**Why:** 옛 표가 무해하고 지금 손댈 이유가 없다는 판단. (용량이 큰 zeroday 48 MB 는 색인 잔재가 80% 이지만 사용자가 보류.)

**How to apply:** 전파·현황 보고에서 소우주 DB 정리를 다시 제안하지 않는다. 사용자가 용량·정리를 물으면 그때 `--apply` 를 안내한다. 전역 DB(`--global`)도 지시 전에는 손대지 않는다.
[[project-zeroday-private-no-rescrub]] [[project-raw-vault-out-of-scope]]
