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
