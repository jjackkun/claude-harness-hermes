# 2026-09-22-evolve-hint-false-positive — 진화 힌트는 사람이 친 이번 턴의 말에서만

출처: `docs/audits/2026-09-21-evolve-hint-false-positive.md` (2026-09-21 조사, 소우주 3곳 실측)

---

## 1. 동기 (Why)

세션 끝 훅이 만드는 `EVOLVE:<키워드>|<피드백>` 힌트가 사람이 쓰지 않은 글에서 나온다.
소우주 3곳에서 스킬 19개가 96번 고쳐졌고, 재현한 48번은 **전부** 근거가 스킬 본문·서브에이전트 반환·압축 요약이었다.
진화는 고른 스킬을 승인 없이 덮어쓴다. 결과가 해로웠다는 증거는 아직 없지만(표본 1개), 근거가 엉뚱한 채로 계속 돈다.

진화 자체는 옳은 장치다 — 사용자의 교정을 스킬에 반영한다. 고칠 것은 **입력**이다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 사람이 친 메시지가 아니면 힌트를 만들지 않는다. 검증: `tests/evolve-hint-source-test.sh` 1절 — `isMeta`(스킬 본문·서브에이전트 반환) · `isCompactSummary` · `origin.kind` 가 `human` 이 아닌 것 · 도구 결과 · `<` 로 시작하는 주입 글에서 힌트 0건, `origin.kind == "human"` 메시지에서는 힌트 1건.
- [x] 목표 2 — 키워드는 단어로만 잡는다. 검증: 같은 시험 2절 — `pipeline`·`pipefail`·`R-pipe` 는 `pip` 가 아니고, `pip install`·`버전을` 은 잡힌다.
- [x] 목표 3 — 같은 교정은 한 번만 힌트가 된다. 검증: 같은 시험 3절 — 교정 메시지 뒤에 사람 메시지가 이어지면 힌트 0건(가장 최근 사람 메시지만 본다).
- [x] 목표 4 — 실제 기록에서 오탐이 사라지고 진짜 교정은 남는다. 검증: 2026-09-21 재현에 쓴 세션(terminal-shipping `64deea5f` 등)의 대화 기록에 고친 추출을 다시 돌려 비인간 근거 힌트 0건. 실제 기록에서 찾은 사람의 교정 메시지 1건이 여전히 힌트가 되는지 확인(만든 예문 금지).

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| 힌트 생성 위치 | `scripts/hermes_save_session_patterns.py:171` `extract_evolution_hints` → `scripts/hermes-save-session.py:80-82` → `scripts/hooks/claude-stop-retrospective.sh:90` (앞 2줄) |
| 대화 기록 로더 | `scripts/hermes_save_session_storage.py:29` `load_transcript` 가 `obj["message"]` 만 남기고 바깥 표시(`isMeta` 등)를 버린다 |
| 턴마다 전체를 다시 읽는가 | 예 — `hermes_save_session_storage.py:70` 주석 "매 턴 Stop 훅이 전체 transcript 를 다시 보내므로" |
| 비인간 글의 표시 (전체 기록 실측) | 사람 입력 `origin.kind == "human"` 4,374건 · 서브에이전트 반환 `origin.kind == "peer"` + `isMeta` · 작업 알림 `origin.kind == "task-notification"` 238건 · 스킬 본문 `isMeta` 46건 · 압축 요약 `isCompactSummary` 9건 |
| `origin` 이 없는 옛 기록 | 있다(표본 400파일 중 사람 입력으로 보이는 401건) — 표시 기반 판정만으로는 부족, 옛 기록 대체 규칙 필요 |
| 기존 시험 | `extract_evolution_hints` 를 직접 겨냥한 시험 없음 |

## 3. 비목표 (Out of Scope)

- 피드백 낱말 목록(`수정`·`대신` …)과 기술어 목록 자체를 바꾸지 않는다. `수정` 이 요청에도 쓰여 과탐일 수 있지만, 입력을 사람 말로 좁힌 뒤에 다시 잰다.
- 드림 경로(`hermes_dream_evolve.py`)의 진화 대상 선정은 건드리지 않는다.
- 이미 고쳐진 소우주 스킬 19개를 되돌리지 않는다(결과가 해롭다는 증거 없음).
- 진화 전 백업·승인 장치는 이번에 넣지 않는다 — 입력을 고친 뒤 필요성을 다시 본다.

## 4. 영향 영역

- 코드:
  - `scripts/hermes_save_session_storage.py` — `load_transcript` 가 메시지 사본에 사람 여부 표시를 붙인다(원본 dict 는 고치지 않는다).
  - `scripts/hermes_save_session_patterns.py` — `extract_evolution_hints` 가 가장 최근 사람 메시지 하나만 보고, 키워드를 단어 경계로 잡는다.
  - `tests/run-all.sh` — 새 시험 등록.
  - `presets/workflow/hermes.conf` — 소우주로 복사하는 `hermes_scripts` 목록에 새 모듈 추가. 목록 복사라 빠뜨리면 소우주의 세션 끝 훅이 import 오류로 죽는다.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_human_turn.py` — 대화 기록 한 줄이 사람이 직접 친 메시지인지 판정한다.
  - `tests/evolve-hint-source-test.sh` — 진화 힌트가 사람이 친 이번 턴의 말에서만, 단어 단위로 나오는지 시험한다.
- 룰: 없음
- 데이터: 없음(스키마 변경 없음)
- 외부 의존: 없음. 소우주 전파는 재설치 시 — `claude-harness-hermes-install` 규칙대로 사용자 결정.

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [단순]

- 입력: §2 목표 1~3
- 산출: `tests/evolve-hint-source-test.sh` (실패 상태)
- 검증: 지금 코드에서 실행해 실패하는 것을 본다

### Step 2. 판정 모듈 + 로더 + 추출 [Impl]

- 산출: `hermes_human_turn.py`, 로더·추출 수정
- 검증: 새 시험 통과 + `hermes-pipeline-test.sh`·`hermes-evolve-vocab-test.sh` 회귀 없음

### Step 3. 실제 기록 재현 [Review]

- 입력: 2026-09-21 재현 세션들
- 산출: 전후 힌트 비교(§7 에 기록)
- 검증: 목표 4

## 6. 의사결정 로그

- 2026-09-22: 사람 판정은 대화 기록의 표시(`origin.kind`·`isMeta`·`isCompactSummary`)를 먼저 보고, 표시가 없는 옛 기록만 내용 규칙(도구 결과·`<` 주입)으로 대신한다 — 근거: 전체 기록 실측에서 비인간 글 다섯 종류가 모두 표시로 구분됐다. 내용 문자열 목록은 새 주입 형식이 생길 때마다 뒤처진다.
- 2026-09-22: 반복은 상태 저장 없이 "가장 최근 사람 메시지 하나만" 으로 막는다 — 근거: Stop 훅이 턴마다 돌므로 이번 턴의 교정은 이번 턴 끝에 한 번 처리된다. 훅이 한 턴 실패하면 그 교정은 놓치지만, 지금처럼 세션 내내 되풀이되는 것보다 손해가 작다.
- 2026-09-22: planner 에이전트는 부르지 않았다 — 근거: 원인이 코드로 모두 확인된 버그 수정(샌드위치 스킬 표 "버그 수정 (원인 명확) 생략 OK").

## 7. 발견·예외

### 실제 기록 재현 (2026-09-22, 목표 4)

사람이 대화한 세션(`entrypoint: cli`)의 사람 메시지마다 그 지점까지 자른 기록에 고친 추출을 돌렸다 — Stop 훅이 그 턴에 보는 것과 같다.

| 소우주 | 대화 세션 | 사람 메시지 | 고치기 전 진화 | 고친 뒤 힌트 |
|---|---|---|---|---|
| terminal-shipping | 8 | 1,555 | 17번 (재현분 전부 비인간 근거) | **2건, 둘 다 사람 글** |
| zeroday-frontend | 76 | 2,685 | 76번 (재현분 전부 비인간 근거) | **0건** |
| novel-bc | 0 (남은 기록 없음) | — | 3번 | — |

- 남은 2건: 하나는 진짜 교정("…하지말고" + postgres) — 잡혀야 맞다. 하나는 질문("Redis는 왜 썼을까?")이 피드백 낱말에 걸린 과탐이다. **피드백 낱말 목록은 비목표**로 뒀으므로 남긴다. 교정 대 질문의 구분이 다음 개선 후보다.

### 헤르메스가 띄운 백그라운드 세션이 대화 기록의 대부분이다

- terminal-shipping 대화 기록 1,096개 중 **1,088개가 `entrypoint: sdk-cli`** — 요약·결정화·진화가 띄운 `claude -p` 세션이다. 사람이 대화한 세션은 8개.
- 이 세션들의 첫 메시지(헤르메스 프롬프트)는 대화 기록상 "사람 입력" 으로 저장된다. 이번 판정 모듈은 이것을 가리지 못한다.
  그러나 세션 끝 훅이 `HERMES_DISABLED=1` 이면 바로 끝나므로(`claude-stop-retrospective.sh:12`) 실제로는 힌트가 나오지 않는다. 재현도 `cli` 세션으로 좁혔다.
- 파생 영향: 2026-09-21 Playwright 측정(`docs/typesafe-jev/playwright-in-sessions.md`)의 "전체 턴 43,332 · 전체 입력 172.5억" 분모에 이 백그라운드 세션이 섞여 있다. Playwright 쪽 숫자(분자)는 영향이 없다.

### 검증 (2026-09-22)

- 새 시험 `tests/evolve-hint-source-test.sh` 17/17 — 고치기 전 코드에서는 10개 실패를 먼저 확인했다.
- 전체 시험 96개 중 95 통과, 실패 1은 `doc-counts-gate-test.sh`(시험 개수 91 → 92 로 문서 숫자가 낡음) — `scripts/sync-doc-counts.sh` 로 갱신 후 17/17.
- code-reviewer: 버그 없음. `load_transcript` 소비처(save_session·extract_patterns·signals)는 `role`·`content` 만 읽고, `hermes-summarize.py` 는 자기 로더 사본을 써서 영향이 없다. 설치 복사 목록은 `hermes.conf` 하나뿐이고 제거는 `hermes_*.py` glob 이라 새 모듈이 빠지지 않는다.
- 리뷰어의 잔여 우려 "`HERMES_DISABLED` 없이 `hermes-save-session.py` 를 부르는 다른 경로" → 호출처는 둘뿐이다. 세션 끝 훅(가드 있음)과 압축 직전 훅(`claude-precompact-summary.sh:57`)이고, 후자는 `EVOLVE` 줄을 **로그에만** 쓰고 진화를 부르지 않는다. 공장 `hooks.log` 에 `EVOLVE` 줄이 쌓여 있던 이유가 이것이다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 사람 판정을 내용 문자열이 아니라 대화 기록의 표시(`origin.kind`·`isMeta`·`isCompactSummary`)로 했다. 전체 기록 실측으로 표시가 다섯 종류의 비인간 글을 모두 가른다는 것을 먼저 확인한 덕이다. 실제 기록 재현에서 비인간 근거 힌트가 0 이 됐다.
- 잘못된 것: 처음 재현(전체 대화 기록 대상)에서 힌트 2,443건이 나와 고친 코드가 틀린 줄 알았다. 원인은 헤르메스가 띄운 `claude -p` 세션(terminal-shipping 1,096개 중 1,088개)이 기록에 섞인 것이었다. 기록을 셀 때는 `entrypoint` 로 사람 세션과 자동 세션을 먼저 나눠야 한다 — 전날 Playwright 측정의 분모에도 같은 문제가 있다(§7).
- 다음 룰 후보: "대화 기록을 집계할 때는 `entrypoint: cli`(사람 세션)와 `sdk-cli`(자동 세션)를 먼저 나눈다" — 같은 실수가 한 번 더 나오면 R 룰로 올린다.
- 남은 일: 질문("왜 썼을까?")이 피드백 낱말(`수정`·`대신` …)에 걸리는 과탐 1건. 교정과 질문을 가르는 것은 다음 개선 후보로 남긴다. 소우주 전파는 재설치 때(`claude-harness-hermes-install` 규칙, 사용자 결정).
