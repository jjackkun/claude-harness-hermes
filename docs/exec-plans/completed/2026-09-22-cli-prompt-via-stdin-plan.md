# 2026-09-22-cli-prompt-via-stdin — 구독 CLI 에 프롬프트를 인자가 아니라 stdin 으로 넘긴다

> 출처: backlog `cli-prompt-via-stdin.md`(2026-09-22 code-reviewer MEDIUM, 성향 추출 Step 2 리뷰). 사용자: "남은 백로그 진행하자".

## 1. 동기 (Why)

- 헤르메스는 구독 CLI 를 `[claude, -p, <프롬프트>, …]` 로 부른다. 프롬프트에는 (마스킹된) 사람 발화·세션 요약·작업 지시가 들어 있고,
  호출이 도는 동안(최대 180초) 같은 컴퓨터의 다른 계정·프로세스가 `ps -ef` · `/proc/<pid>/cmdline` 으로 전문을 본다.
- **실측(2026-09-22)에서 하나 더 나왔다**: `-p` 인자와 stdin 을 **둘 다** 주면 CLI 는 두 입력을 **이어 붙여** 처리한다
  (인자 "1+1", stdin "5+5" → 응답 "2 … 10"). 지금 호출 11곳은 `input=` 을 주지 않아 부모의 stdin 을 물려받는다 —
  훅 안에서 부르면 훅 stdin(JSON)이 프롬프트 뒤에 붙을 수 있다. stdin 을 명시하면 이 길도 닫힌다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 명령: `bash tests/cli-prompt-stdin-test.sh`.
  `scripts/*.py` 에서 구독 CLI 호출이 프롬프트를 argv 에 싣지 않는다(정적 검사) · `hermes-cron-run.sh` 도 stdin 으로 넘긴다.
- [x] 목표 2 — 명령: `bash tests/run-all.sh`.
  가짜 claude 를 쓰는 기존 시험이 stdin 으로 받은 프롬프트로도 전부 통과한다.
- [x] 목표 3 — 명령: 실측 1회(요약기·성향 추출 경로) — 실제 CLI 가 stdin 프롬프트로 같은 형식의 응답을 낸다.

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| stdin 프롬프트 동작 | 인자 방식 rc=0 · 6.7초 · "대한민국의 수도는 서울입니다." / stdin 방식 rc=0 · 8.9초 · 같은 답 |
| 인자 + stdin 동시 | 두 입력을 이어 붙여 처리("2 … 10") |
| 호출 지점 | 파이썬 11곳(crystallize · summon · loop · summarize · evolve-skill · lifecycle · mesh_gate · dream · search_fallback · persona_extract · harness-eval) + 셸 1곳(`hermes-cron-run.sh`). `hermes_sync_ref.py` 의 `-p` 는 git 옵션 — 대상 아님 |
| 가짜 claude 를 쓰는 시험 | 15개. 그중 프롬프트를 인자(`$*`·`$2`)에서 읽어 응답을 고르는 것: dream · lifecycle · pipeline · precompact-summary · loop · persona-distill |

## 3. 비목표 (Out of Scope)

- `harness-eval.py` — 프롬프트가 저장소에 고정된 시나리오 문장(사용자 데이터 없음)이고, 행동을 재는 도구라 호출 방식이 측정에 섞이면 안 된다.
- 호출 공통 헬퍼로 합치기(리팩터) — 각 지점의 옵션이 달라 이번 변경의 이득보다 위험이 크다. 지점마다 `input=` 한 줄로 바꾼다.

## 4. 영향 영역

- 코드: 위 파이썬 10곳 + `scripts/hermes-cron-run.sh`. 각 호출에서 프롬프트를 argv 에서 빼고 `input=prompt` 를 준다.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `tests/cli-prompt-stdin-test.sh` — 구독 CLI 호출이 프롬프트를 argv 에 싣지 않는지 정적으로 지킨다.
- 시험: 가짜 claude 가 `"$*"` 와 stdin 을 함께 읽게 고친다(프롬프트 위치가 바뀌어도 같은 응답).
- 룰: R3(구독 CLI 경로 유지). 데이터: 없음. 외부 의존: 없음.

## 5. 단계 (Steps)

### Step 1. 정적 검사 시험 먼저 [Impl]
- 산출: `tests/cli-prompt-stdin-test.sh` — 지금은 실패해야 한다(RED).

### Step 2. 호출 11곳 바꾸기 + 가짜 claude 고치기 [Impl/Review]
- 검증: 목표 1 · 목표 2(전체 시험).

### Step 3. 실측 [단순]
- 검증: 목표 3.

## 6. 의사결정 로그

- 2026-09-22: 공통 헬퍼로 합치지 않고 지점마다 `input=` — 근거: §3.
- 2026-09-22: harness-eval 은 제외 — 근거: §3.

## 7. 발견·예외

- **실측(목표 3)**: 성향 추출 — 새 발화 8 → 관찰 2 · 실패 0 (53.7초). 요약기 — `state.db` 사본에 5슬롯 요약 저장(27.2초). 두 경로 모두 stdin 프롬프트로 같은 형식의 응답.
- **가짜 claude 의 거짓 통과**: persona-distill 가짜는 프롬프트를 `$2` 로 기록했다 — 바꾼 뒤 `$2` 가 `--model` 이 되어 "남의 프로젝트 기록 0" 단언이 무엇이 오든 참이 됐다.
  기록에 우리 발화가 실제로 남는다는 단언을 더해 부재 단언이 우연히 0 이 되지 않게 했다(앞 계획 회고의 룰 후보 — 이번이 3번째 사례).
- **잘못 바꿀 뻔했다**: loop 가짜의 `VERIFY: $2` 는 프롬프트가 아니라 `emit` 함수의 둘째 인자였다 — 일괄 치환 뒤 25개 실패로 드러나 되돌렸다.

- **전체 시험**: 104개 중 103 통과. 실패 1(`hermes-keywords-test.sh`)은 cron 호출 문자열을 글자 그대로 찾던 단언 — 새 형태로 고치고 재실행 20/20.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 바꾸기 전에 실측했다 — stdin 동작이 같은지(같은 답), 그리고 **인자 + stdin 을 둘 다 주면 이어 붙인다**는 숨은 위험까지 먼저 봤다.
  - 정적 검사를 먼저 써서 RED 13 → GREEN 13. 리뷰 LOW(작은따옴표 스타일)도 탐침 파일로 확인하고 넓혔다.
  - 실제 CLI 로 두 경로(성향 추출·요약기)를 돌려 목표 3 을 닫았다.
- 잘못된 것:
  - 가짜 claude 일괄 치환에서 `$2` 를 무조건 프롬프트로 봤다 — loop 가짜의 `$2` 는 함수 인자였다(25개 실패로 드러나 되돌림).
  - `hermes-keywords-test.sh` 가 cron 호출 문자열을 **글자 그대로** 찾는 줄 몰랐다 — 전체 시험에서야 나왔다. 영향 받는 시험을 "가짜 claude 쓰는 것" 으로만 좁힌 탓.
- 다음 룰 후보:
  - "부재를 단언하는 시험은 우연히 0 이 되는 길이 없는지 본다" — 이번 계획에서 3번째 사례(persona-distill 가짜의 `$2` → `--model`). **승격 조건 충족** — 다음 작업으로 `harness-promote-rule` 검토.
  - "호출 형태를 바꾸면 그 문자열을 grep 하는 시험도 찾는다" — 사례 1건, 보류.
