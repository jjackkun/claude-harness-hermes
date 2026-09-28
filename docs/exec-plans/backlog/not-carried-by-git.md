# git 으로 안 올라가는 것

- 배운 것·가르친 것 (MEMORY.md, 기억 이벤트)
- 나와 나눈 대화 요약 (`@hag`·방)
- 작업 이력
- 세션 요약·패턴 수
- 대화 원문
- 방·세션 자체 (`--resume`)
- `@hag` 상태·캐시
- (이 공장 저장소만) 공통 결정화 스킬 `.hermes/skills/`

## 1. 배운 것·가르친 것 (MEMORY.md, 기억 이벤트)

### 올려야 하는 이유

- 기억은 SOUL·개인 스킬과 같은 **그 에이전트의 일부**다. SOUL·스킬은 git 으로 따라가는데 기억만 안 따라가면, 다른 컴퓨터의 에이전트는 자기가 누구인지는 알지만 배운 것은 모른다.
- 지금 설계(A-10, `memory-events.md` 125행)는 git 대신 **기억 운반**(`refs/hermes/sync` `memory/`)으로 옮기게 했다. 그런데 운반은 공개 저장소에서 꺼진다(T-18). 결과적으로 공개 저장소에서는 기억이 **어디로도** 안 간다.
- 안 올린 이유였던 **민감정보**는 이미 해결돼 있다 — 기억은 저장하기 **전에** 마스킹된다(`hermes_review_chain.record_teaching` 의 `redact`). 남는 위험은 탐지가 놓친 것뿐이고, 이는 SOUL·코드와 같은 수준이다.
- 안 올린 다른 이유였던 **충돌**은 `MEMORY.md`(파생물)를 올릴 때의 문제다. 원본을 추가만 하는 한 줄씩 기록으로 두면 충돌이 거의 없다.

### 어떻게 할 것인가

- 기억 원본(`memory_events`)을 에이전트 폴더의 파일 `.hermes/agents/<id>/memory.jsonl` 로 **커밋**한다 — 한 줄 = 이벤트 하나, 추가만 한다(`memory.added`·`memory.revised`·`memory.retracted` 그대로).
- `MEMORY.md` 는 지금처럼 git 에 안 올리고, 받은 컴퓨터가 `memory.jsonl` 에서 다시 만든다.
- `state.db` 의 `memory_events` 는 `memory.jsonl` 의 색인으로 둔다 — 세션 시작 때 파일에 있고 DB 에 없는 줄을 넣는다(`memory_id` 로 중복 제거).
- `.gitignore` 에 `!.hermes/agents/*/memory.jsonl` 예외를 더한다(설치기 마커 블록).
- 기억 운반의 `memory/` 조각은 이 파일로 대신하므로 걷어 내거나 남길지 착수 때 정한다.
- 결정 원장에 A-10 을 고치는 새 결정으로 남긴다.

## 2. 나와 나눈 대화 요약 (`@hag`·방)

### 올려야 하는 이유

- 1번과 같다 — 대화 요약(C-29)은 그 에이전트가 "누구와 무엇을 이야기했는지" 의 기억이다. 운반이 꺼진 공개 저장소에서는 어디로도 안 간다.
- 막는 이유는 민감정보가 아니다 — 요약은 저장 **전에** 마스킹된다(`hermes-summarize.py` 의 `redact`). 올릴 때 한 번 더 거친다(`hermes_sync_learning.py`).
- 안 올라가는 까닭은 `state.db` 안에만 있고 파일로 꺼내는 길이 없어서다.

### 빠진 것: 누구와의 대화인가

- `session_summary` 칸은 `session_id · project_id · slots_json · last_msg_count · turn_count · updated_at · agent_id` 뿐이다. `agent_id` 는 상대 **에이전트**다. **사람 칸이 없다.**
- 운반은 git `user.name` 을 잠금 모드 열쇠 경로(`keys/<사람>/`)에만 쓰고 요약에는 붙이지 않는다.
- 결과: 팀원 둘이 같은 에이전트와 이야기하면, 공유된 뒤 두 사람의 대화가 한 사람 것처럼 섞인다. 에이전트가 "당신과 전에 이야기한" 것을 다른 사람에게 꺼낸다.
- 기억(`memory_events`)에도 사람 칸이 없다. 작업 이력(`journal_events`)에만 `requested_by` 가 있다.

### 어떻게 할 것인가

- 요약에 **사람 칸**(`person`)을 더한다. 값은 요약을 만들 때 그 컴퓨터의 git `user.name`. 없으면 `unknown`. 기존 행은 빈 칸으로 둔다.
- 파일로 커밋한다 — `.hermes/agents/<id>/conversations/<person>/<session_id>.json` (세션 하나 = 파일 하나, 사람별 폴더). 내용은 **요약(`slots_json` 5칸)만** 이다 — 대화 원문은 넣지 않는다. 같은 세션 요약이 갱신되면 그 파일만 바뀐다. 두 컴퓨터가 같은 세션을 만들 일은 없어 파일 충돌이 거의 없다. 사람별 폴더라 거를 때 파일 안 칸에만 기대지 않는다.
- `.gitignore` 에 `!.hermes/agents/*/conversations/` · `!.hermes/agents/*/conversations/**` 예외를 더한다(설치기 마커 블록). 지금은 54행 `.hermes/agents/*/*` 가 막는다(`git check-ignore -v` 로 확인).
- 운반의 `summary/` 조각과 겹친다 — 에이전트 요약(`agent_id` 있는 행)은 이 파일이 대신하고, 운반에는 공통 요약만 남길지 착수 때 정한다(1번 `memory/` 와 같은 결정).
- 부를 때 주입(C-29 "나와 나눈 최근 대화")은 **지금 부른 사람과 같은 `person` 의 요약만** 넣는다. 다른 사람과의 대화는 넣지 않는다.
- `person` 은 이름표일 뿐 신원 증명이 아니다(`user.name` 은 누구나 바꾼다). "나만 보기" 는 여전히 못 한다 — 저장소를 읽는 사람은 파일을 다 본다(T-18 그대로).
- 공통 요약(`agent_id` 빈 칸)은 에이전트 것이 아니므로 이 파일에 넣지 않는다.
- 1번 기억에도 같은 `person` 칸을 둘지 착수 때 함께 정한다. 결정 원장에 C-29 를 보완하는 새 결정으로 남긴다.
