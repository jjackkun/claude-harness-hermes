# 2026-09-28-hagent-call — `@hagent` 로 명부 에이전트 찾고 부르기

> 작성일: 2026-09-28
> 목적: 호출명을 몰라도 `@hagent` 한 마디로 명부 에이전트를 보고, 이름·할 일을 붙여 부른다.
> 상위: `docs/exec-plans/backlog/hermes-chat.md` 목표 6.

## 1. 동기 (Why)

- 사용자(2026-09-28): "이 대화에서 에이전트를 호출하고 싶어. 그런데 에이전트가 뭐뭐가 있는지 몰라."
- `@agent` 입력 목록은 Claude Code 기본·플러그인·하네스 도구·명부 에이전트를 **섞어** 보인다(스크린샷 실측). 명부만 거를 수 없다.
- slug 머리말(`h-`)로 거르기는 실측 실패 — `@agent-h-` 는 흩어진 글자 검색이라 파일만 나오고, 읽혀 있는 `h-probe` 에이전트도 안 나왔다.
- 입력 목록에 새 종류를 넣는 설정은 찾지 못했다. 남은 길은 **보낸 뒤** 훅이 글을 읽는 것.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `@hagent` 만 보내면 명부 표가 문맥에 들어가고, "표를 그대로 보여라" 지시가 붙는다.
      검증: 픽스처 프롬프트 `@hagent` → stdout 에 명부 표(이름·호출) + 보이기 지시.
- [x] 목표 2 — `@hagent <이름|할 일>` 이면 "명부에서 골라 그 slug 의 에이전트로 넘겨라" 지시가 붙는다.
      검증: `@hagent 백로그 관리자 정리해` → stdout 에 표 + 넘기기 지시 + 사용자가 붙인 말.
- [x] 목표 3 — `@hagent` 가 없거나, hermes 프로젝트가 아니면 아무것도 내지 않는다.
      검증: `@agent-gate-qa 봐줘`·`hagent 설명해`(앞 `@` 없음)·`me@hagent.com` → stdout 0 B · agents.json 없는 프로젝트 → 0 B.
- [ ] 목표 4 — 실제 세션 실측: 입력창에 `@hagent` 를 치고 엔터를 쳤을 때 파일이 대신 들어가지 않는가.
      검증: 사용자 화면에서 한 번. 파일이 끼면 우회 표기(예: `@hagent ` 뒤 한 칸)를 안내에 적는다.

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| UserPromptSubmit 등록 | `claude-userpromptsubmit-dispatch.sh` 하나. 같은 폴더 `claude-userpromptsubmit-*.sh` 를 이름순으로 부름 → 새 파일만 두면 불린다 |
| 설치 목록 | `presets/workflow/hermes.conf` `HARNESS_HOOK_SOURCES+=(…)` (예: soul-approval-intent 59줄) |
| 명부 표 | `python3 scripts/hermes-agent.py --project . roster` → 2명(게이트QA `@agent-gate-qa`, 백로그 관리자 `@agent-backlog-manager`) |
| 부르기 경로 | 명부 slug = `.claude/agents/<slug>.md` → Agent 도구 `subagent_type=<slug>` → SubagentStart 훅이 SOUL 주입 (C-27) |

## 3. 비목표 (Out of Scope)

- 입력 중 목록(`@` 팝업)에 명부만 띄우기 — 설정 경로 없음.
- 상태줄 명부 표시 — 사용자 결정으로 하지 않음(2026-09-28).
- 할 일을 훅이 판별해 자동 배정 — 판별은 에이전트가 한다(C-19 과 같은 이유).

## 4. 영향 영역

- 코드: `presets/workflow/hermes.conf` (훅 한 줄 등록)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/hooks/claude-userpromptsubmit-hagent.sh` — 프롬프트에 `@hagent` 가 있으면 명부 표와 보이기/넘기기 지시를 문맥에 넣는다
  - `scripts/hooks/claude-userpromptsubmit-hagent.sh` — 위 파일의 공장 설치본(동일 내용)
  - `tests/hermes-hagent-test.sh` — 목표 1~3 픽스처 시험
- 룰: 해당 없음
- 데이터: 없음 (읽기만)
- 외부 의존: 없음

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [단순]
- 산출: `tests/hermes-hagent-test.sh` — 훅 없는 상태에서 실패 확인.

### Step 2. 훅 [단순]
- 산출: 훅 파일 + hermes.conf 등록. 검증: Step 1 시험 통과.

### Step 3. 실측 [단순]
- 사용자 화면에서 `@hagent` 한 번 (목표 4).

## 6. 의사결정 로그

- 2026-09-28: 머리말 slug(`h-`) 대신 `@hagent` 약속 — 근거: 머리말 실측 실패, 사용자 제안.
- 2026-09-28: 상태줄 명부 표시는 하지 않음 — 근거: `@hagent` 하나로 "누가 있나" 가 풀림(사용자 승인).
- 2026-09-28: hermes-chat 전체를 active 로 옮기지 않고 이 계획만 따로 — 근거: hermes-chat 목표 1~5 는 착수 전, 이 일은 독립.

## 7. 발견·예외

- 2026-09-28 목표 1~3: `tests/hermes-hagent-test.sh` 17/17. 앞 경계 검사를 뺀 변이 → 메일 주소 시험 1건 실패(시험이 잡음). 빈 프로젝트 설치 → `scripts/hooks/` 에 복사되고 디스패처 경유로 `[hagent:list]` 출력(명부 0명이면 "명부에 에이전트가 없습니다" 표시).

- 2026-09-28 목표 4 실측: **입력 중 `@` 목록에는 끝까지 에이전트가 안 나온다**(사용자 화면, 예상대로). 보낸 메시지에서는 훅이 돌아 명부가 주입됐다. 같은 실측에서 결함 발견 — 백틱 안 `@hagent`(불만을 말하는 문장)를 넘기기 요청으로 읽음 → 백틱 안은 무시하도록 고침, 시험 18/18.
- 사용자 기대는 "치는 도중 목록에 에이전트가 뜬다" 였다 — 이 장치로는 못 푼다. 다음 논의 거리.

- 2026-09-28 **플러그인 이름 실측(성공)**: `claude --plugin-dir <시험 플러그인 name=hagent, agents/ 에 명부 파일 2개>` 를 tmux 에서 띄우고 `@hagent` 입력(보내지 않음).
  목록 순서: ① `.hermes/agents/` 폴더(기본 선택) ② `hagent:backlog-manager (agent)` ③ `hagent:gate-qa (agent)` ④ 이하 문서. 에이전트를 골라 엔터 → 입력창 `@"hagent:backlog-manager (agent)"`.
  주의: Tab 은 경로 완성(`@.hermes/agents/`). 1번 폴더가 기본 선택이라 아래 화살표 한 번이 필요하다.
  남은 확인: 플러그인 에이전트의 `agent_type` 이 `hagent:backlog-manager` 로 오면 SubagentStart soul·이력 훅(slug 로 명부 조회)이 못 찾는다 — 실측 전.

## 8. 회고 (완료 시 작성) — 2026-09-28 폐기, `@hag` 로 대체

- 결말: 목표 4 는 달성 못 함 — 보낸 뒤에만 동작해서 "치는 도중 목록" 이라는 사용자 요구를 못 풀었다. 사용자 결정으로 `@hag`(fileSuggestion 교체) 로 대체하고 이 훅·시험은 지웠다. 이어지는 일: `2026-09-28-hermes-chat.md` 목표 6.
- 잘된 것: 백틱 안 `@hagent` 오인을 실측으로 잡았다 — 같은 규칙을 `@hag` 훅이 물려받는다.
- 잘못된 것: 사용자가 원한 것(치는 도중 목록)과 만든 것(보낸 뒤 동작)의 차이를 처음에 분명히 말하지 않았다. `h-` 머리말·플러그인 이름도 실측 전에 권했다.
- 다음 룰 후보: 입력창 UI 동작은 권하기 **전에** tmux 로 먼저 잰다(오늘 세 번 추측이 틀렸다).
