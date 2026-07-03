---
name: hermes-loop
description: Run a goal-based autonomous loop inside the current session. Use when the user types /hermes-loop <goal>. Creates GOAL.md and a loops row via the shared core CLI, then repeats work, verify, and step reporting until the deterministic driver returns a stop decision. Destructive actions must go through the standard permission prompts.
---

# hermes-loop

목표 기반 자율 루프를 현재 세션에서 구동한다 (설계 G10).
헤드리스 실행(`scripts/hermes-loop-run.sh`)과 판정 코어(CLI `step`)를 공유한다.

## 트리거

사용자가 `/hermes-loop <목표>` 를 입력할 때.

## 동작 순서

1. **초기화** — 목표로 루프를 생성하고 LOOP_ID 를 확보한다:
   ```bash
   python3 scripts/hermes-loop.py init --goal "<목표>" \
     [--condition "<완료 조건>" ...] [--verify "<검증 명령>"]
   ```
   출력의 `LOOP_ID:` 와 `GOAL_MD:` 를 기록한다.

2. **루프 브랜치** — 커밋 격리용 전용 브랜치를 만든다 (G14):
   ```bash
   git checkout -b loop/<LOOP_ID>
   ```
   git 저장소가 아니면 생략한다. 커밋은 이 브랜치에서만 하고,
   머지·push 는 하지 않는다 — 종료 후 사용자가 검토하고 직접 수행한다.

3. **반복** — `DECISION:stop` 이 나올 때까지:
   1. GOAL.md 를 읽는다. 완료 조건이 비어 있으면 검증 가능한 체크박스로 먼저 작성한다.
   2. 미완료 조건 1개를 골라 작업한다. 파괴적 작업(삭제·force push·배포)은
      표준 권한 프롬프트 승인 없이는 실행하지 않는다.
   3. 검증 명령을 직접 실행해 pass/fail 을 확인한다.
   4. 조건 달성 시 GOAL.md 체크박스를 `- [x]` 로 갱신한다
      ('## 진행 로그' 섹션은 CLI 가 기록하므로 직접 수정 금지).
   5. 반복 결과를 판정 코어에 보고한다:
      ```bash
      python3 scripts/hermes-loop.py step <LOOP_ID> \
        --action "<한 일 한 줄>" \
        --verdict <continue|goal-met|blocked> \
        --signal <pass|fail|none>
      ```
   6. 출력이 `DECISION:continue` 면 1 로 돌아가고,
      `DECISION:stop:<이유>` 면 반복을 멈춘다.

4. **종료 보고** — finish_reason(goal-met/max-iter/no-progress/blocked)과
   GOAL.md 진행 로그 요약, 루프 브랜치명(`loop/<LOOP_ID>`)을 사용자에게
   보고한다. 머지 여부는 사용자가 diff 검토 후 결정함을 안내한다.
   blocked/no-progress 면 무엇이 막혔고 사람이 무엇을 결정해야 하는지 명시한다.

## 주의

- 완료판정·안전캡은 CLI(결정적 코드)가 내린다 — DECISION 출력을 임의로 무시하지 않는다.
- verdict 는 정직하게: 모든 완료 조건이 충족됐을 때만 goal-met.
- 상태 확인: `python3 scripts/hermes-loop.py status <LOOP_ID>`
