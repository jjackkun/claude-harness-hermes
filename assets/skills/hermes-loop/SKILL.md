---
name: hermes-loop
description: Goal-based autonomous loop for the CURRENT project. Trigger when the user types /hermes-loop (with or without a goal), or asks in natural language to run/start a Hermes loop (e.g. "헤르메스 루프 하자", "헤르메스 루프 돌려줘", "목표 루프 작업하자", "run a hermes loop"). On trigger, FIRST present the options form and ask the user to fill the required goal, letting them skip any optional field, THEN run. The target is always the current project where this skill is installed — never ask which project. Destructive actions go through the standard permission prompts.
---

# hermes-loop

목표 기반 자율 루프를 **현재 프로젝트**에서 구동한다 (설계 G10·G15).
대상 프로젝트는 이 스킬이 설치된 현재 프로젝트다 — **어느 프로젝트인지 묻지 않는다.**

## 트리거

아래 중 하나면 이 스킬을 실행한다:

- `/hermes-loop` — 목표를 붙이든(`/hermes-loop <목표>`) 안 붙이든(`/hermes-loop`) 모두
- 자연어 — "헤르메스 루프 하자 / 돌리자 / 작업하자", "목표 루프 돌려줘", "run a hermes loop" 등

## 동작 순서

### 1단계 — 옵션 안내 + 수집 (반드시 먼저)

사용자에게 아래 옵션 폼을 **먼저 그대로 보여주고**, 필요한 것만 채우게 한다.
이미 인라인으로 목표를 준 경우(`/hermes-loop <목표>`)는 ①을 그것으로 채우고,
나머지 선택 항목만 짧게 확인한다. 사용자가 "넘겨"라고 하면 기본값을 쓴다.

```text
🔁 헤르메스 루프 설정   (대상: 현재 프로젝트)

① 목표        ▸ 무엇을 시킬지                       [필수]
② 완료 조건    ▸ "이게 되면 끝" 기준 (여러 개 가능)    [선택 — 넘기면 에이전트가 스스로 정함]
③ 검증 명령    ▸ 완료를 확정할 셸 명령 (예: npm test)  [선택]
④ 실행 방식    ▸ 대화형(여기서·웹 보고서) / 헤드리스(백그라운드)   [선택 — 기본: 대화형]
⑤ 최대 반복    ▸ 몇 번까지 시도                       [선택 — 기본: 자동]
```

- **필수는 ① 목표 하나뿐.** 나머지는 넘겨도 된다.
- 대상 프로젝트는 현재 프로젝트로 고정 — 묻지 않는다.
- 목표가 확보되면 ④ 실행 방식을 확인한다(기본: 대화형). 사용자가 자리를 비우고
  오래 돌릴 뜻이면 헤드리스를 권한다.
- ③ 검증 명령에는 비밀(토큰 등)을 넣지 않는다 — 드라이버가 그대로 실행하므로 마스킹되지 않는다.

### 2단계 — 실행 방식 분기

**헤드리스**를 택했으면 백그라운드 래퍼로 넘기고 여기서 끝낸다:

```bash
scripts/hermes-loop-run.sh "$(pwd)" "<목표>" \
  [--condition "<완료 조건>" ...] [--verify "<검증 명령>"] [--max-iter N]
```

출력의 `id=loop-...` 와 로그 경로를 사용자에게 안내한다. 이후는 자율 실행이며,
진행은 `python3 scripts/hermes-loop.py status <id>` 로 확인한다. (**여기서 멈춘다.**)

**대화형**(기본)이면 아래 3~6단계를 이 세션에서 진행한다.

### 3단계 — 초기화

```bash
python3 scripts/hermes-loop.py init --goal "<목표>" \
  [--condition "<완료 조건>" ...] [--verify "<검증 명령>"] [--max-iter N]
```

출력의 `LOOP_ID:` 와 `GOAL_MD:` 를 기록한다.

### 4단계 — 루프 브랜치 (G14)

```bash
git checkout -b loop/<LOOP_ID>
```

git 저장소가 아니면 생략한다. 커밋은 이 브랜치에서만 하고, 머지·push 는 하지 않는다 —
종료 후 사용자가 diff 를 검토하고 직접 머지한다.

### 5단계 — 반복 (`DECISION:stop` 이 나올 때까지)

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
6. 출력이 `DECISION:continue` 면 1 로 돌아가고, `DECISION:stop:<이유>` 면 반복을 멈춘다.

### 6단계 — 종료 보고 + 보고서 게시

- finish_reason(goal-met/max-iter/no-progress/blocked)과 GOAL.md 진행 로그 요약,
  루프 브랜치명(`loop/<LOOP_ID>`)을 사용자에게 보고한다. 머지 여부는 사용자가 diff
  검토 후 결정함을 안내한다. blocked/no-progress 면 무엇이 막혔고 사람이 무엇을
  결정해야 하는지 명시한다.
- 종료 시 CLI 가 `.hermes/loops/<LOOP_ID>/report.html` 을 생성하고 `REPORT_HTML:<경로>`
  를 출력한다. 그 HTML 파일을 읽어 **아티팩트로 게시**해 사용자가 웹에서 결과를 검토하고
  머지 여부를 판단하게 한다. (필요 시 `python3 scripts/hermes-loop.py report <LOOP_ID>` 로 재생성.)

## 주의

- 완료판정·안전캡은 CLI(결정적 코드)가 내린다 — DECISION 출력을 임의로 무시하지 않는다.
- verdict 는 정직하게: 모든 완료 조건이 충족됐을 때만 goal-met.
- 상태 확인: `python3 scripts/hermes-loop.py status <LOOP_ID>`
