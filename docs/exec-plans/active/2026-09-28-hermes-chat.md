# hermes-chat — 명부 에이전트와 따로, 이어지는 대화방

> 작성일: 2026-09-28
> 목적: 메인 대화에서 `@` 으로 부르는 대신, 명부 에이전트(예: 백로그 관리자)와 **직접** 이어서 대화하는 방을 둔다.
> 출처: `auto-owner-summon.md` 목표 후보 7 을 떼어 온 것. 조사: `docs/audits/2026-09-28-agent-chat-room-research.md`.

## 개요

사용자 문제(2026-09-28): "여기서 내가 백로그 에이전트를 호출할 거야. 그럼 사용이 너무 힘들어."
지금(목표 6, C-27)은 메인 대화에서 `@back…` 으로 부른다. 부를 때마다 새로 시작하고, 메인이 말을 옮겨 적는다.
원하는 것은 그 에이전트가 **대화 상대 자체**인 방 — 말하면 그 에이전트가 직접 듣고, 나갔다 와도 이어진다.

`hermes-chat` 은 이 기능의 이름이자 **방을 여는 명령**이다(2026-09-28 뒤집음 — 아래 목표 7). `claude --agent` 는 에이전트 이름을 알아야만 열린다(이름 없이 실행 → `Error: option '--agent <agent>' argument missing`, 실측). 사용자는 이름을 모른다.

## 1. 쓰는 모양 (목표)

| 하고 싶은 것 | 터미널 |
| --- | --- |
| 누구와 대화할지 골라 방 열기 | `hermes-chat` → 번호 선택 (목표 7) |
| 백로그 관리자와 대화 시작 | `claude --agent backlog-manager --name 백로그방` (hermes-chat 이 대신 부르는 명령) |
| 그 방으로 돌아가기 | `claude --resume 백로그방` |
| 방 안에서 다른 에이전트 부르기(손님) | `@gate…` → 목록에서 고르기 (목표 6 그대로) |
| 방에 누가 있는지 | 상태줄 "지금: … · 이 방에서 불림: …" + `/hermes-room` (agent-room-view 그대로) |

## 2. 확인된 사실 (공식 문서, 2026-09-28 받은 사본)

| 사실 | 근거 |
| --- | --- |
| `--agent` 세션은 메인 자체가 그 에이전트(시스템 프롬프트·도구·모델) | sub-agents.md "the main thread itself takes on that subagent's system prompt…" |
| `--resume` 하면 같은 에이전트로 이어진다 | sessions.md "a session started with `--agent` … continues as that agent" |
| settings.json 훅이 `--agent` 메인 세션에서도 돈다 | sub-agents.md "they run alongside any hooks defined in `settings.json`" |
| **SessionStart 입력에 `agent_type` 이 온다** | hooks.md 1140줄 "`agent_type` — The agent name, present when you start Claude Code with `claude --agent <name>`" |
| 공통 층(CLAUDE.md·프로젝트 기억)은 `--agent` 메인에도 그대로 실린다 | sub-agents.md 856줄 |
| Claude Code 내부 에이전트(입력 추천·`/btw`)가 끝날 때도 SubagentStop 이 오고, 이때 `agent_type` = 세션의 `--agent` 값 | hooks.md 2387줄 |

## 3. 지금 빠진 것

1. **방 주인에게 SOUL·기억이 안 들어간다.** `scripts/hooks/claude-sessionstart-agent-soul.sh:18` 은 `HERMES_AGENT_ID` 환경변수만 본다.
   지금 `claude --agent backlog-manager` 로 열면 얇은 에이전트 파일만 실려 "정체성 주입 없음" 으로 답한다(실측 전 — 파일 본문 기준 예상).
2. **호출 횟수가 부풀려진다.** 위 2절 마지막 줄 때문에 방 안의 내부 보조 호출이 `agent_type=backlog-manager` 로 SubagentStop 에 온다.
   `claude-subagentstop-journal.sh` 는 이를 "백로그 관리자가 불린 것" 으로 적는다(C-27 에서 slug→명부 id 로 바꾼 자리).
3. **방 주인이 방 구성원 표시에 안 나온다.** `hermes_room.collect_room` 은 `task.assigned`(match=mention) 만 센다 — 주인은 불린 것이 아니라 방 자체다.

## 목표 후보

- [x] 1 — **`claude --agent <slug>` 로 연 세션에 그 에이전트의 SOUL·기억이 들어간다.**
      SessionStart soul 훅: `HERMES_AGENT_ID` 가 없으면 입력 JSON 의 `agent_type` → `hermes_agent_slug.agent_by_slug` → 은퇴 아닌 명부 id → 같은 렌더러(`hermes_soul_render.py`).
      `HERMES_AGENT_ID` 가 있으면 지금 그대로(소환 경로 우선). `startup`·`resume`·`compact` 모두 넣는다(`--resume` 뒤에도 정체성 유지).
      검증: 픽스처 입력 `{"source":"startup","agent_type":"backlog-manager"}` → stdout 첫 줄에 백로그 관리자 머리줄 · 명부 밖 slug·은퇴자·`Explore` → stdout 0 B.
      실측: 실제 `claude --agent backlog-manager` 에서 "네 SOUL 첫 줄" 에 SOUL 원문 첫 줄로 답한다.
- [ ] 2 — **내부 보조 호출이 방 주인의 호출로 세어지지 않는다.**
      SubagentStop 이력 훅: 같은 `agent_id` 의 SubagentStart(`task.assigned`) 가 없으면 명부 id 로 적지 않는다.
      검증: `--agent` 세션 픽스처에서 SubagentStart 없는 SubagentStop 3건 → 명부 에이전트 호출 0 · 내부 보조 3.
- [x] 3 — **방 주인이 구성원 표시에 보인다.**
      세션 시작 때 주인을 이력에 한 줄(예: `task.assigned` decision `match=owner slug=…`) 남기고, `collect_room`·상태줄이 "주인: 백로그 관리자" 를 따로 보인다.
      검증: 주인 방 + 손님 1명 픽스처 → 상태줄에 주인·손님 둘 다, 손님 횟수만 셈.
- [ ] 4 — **쓰는 법 안내.** `hermes-agent` 스킬·`/hermes-roster` 표 아래에 방 여는 명령 한 줄(`claude --agent <호출명> --name <방>`).
      검증: `/hermes-roster` 출력에 호출명마다 방 여는 명령이 보인다.
- [ ] 5 — **기억 층(사용자 결정 2026-09-28).** 공통이 바탕, 에이전트 기억이 위를 덮는다 — 같은 `about` 키면 에이전트 쪽.
      공통 층은 2절 856줄로 이미 실린다. 남은 것은 "덮어쓴다" 를 SOUL 렌더에서 드러내는 것 — 착수 때 범위를 다시 잰다.
      검증: 같은 `about` 이 공통·개인에 다른 픽스처 → 주입 본문에 개인 쪽만.
- [x] 6 — **`@hag` 약속어: 치는 도중 목록에 명부 에이전트만 뜬다(2026-09-28 사용자 결정).**
      새 트리거 문자(`@@`·`^`)는 공식 문서에 없음, `@` 뒤 기호(`@@ @^ @# @+ @=`)는 목록 자체가 안 뜸(실측).
      공식 `fileSuggestion` 설정(`@` 파일 목록을 스크립트로 **교체**)으로 `@hag…` 이면 명부, 그 밖은 파일을 돌려준다.
      실측(시험 스크립트, `--settings` 세션 한정): `@hh` → 명부 2명만 · Tab → `@"<줄>"` 삽입 · 엔터는 고르지 않고 보냄.
      보낸 뒤: UserPromptSubmit 훅이 `hag:<slug>` 를 알아보고 그 에이전트로 넘기라는 지시를 넣는다. `@hag` 만 보내면 명부 표.
      `hag` 겹침: 등록 프로젝트 10곳 git 파일 이름·경로 0건(실측).
      검증: 시험 — 제안 스크립트(명부 분기·거르기·은퇴자 제외·파일 분기 흩어진 글자 검색·15줄 상한·hermes 아님) · 훅(hag:<slug> → 넘기기, `@hag` → 표, 백틱·메일 무시) · 설정 생성(넣기·사용자 값 보존·프리셋 빠지면 걷기).
      실측: 설치한 세션에서 `@hag` → 명부만 · Tab → 보내기 → 그 에이전트가 불린다. `@doc` → 파일 목록.
      이전 `@hagent`(보낸 뒤만 동작) 는 걷어 냄 — `docs/exec-plans/completed/2026-09-28-hagent-call.md`.
- [x] 7 — **`hermes-chat` 명령: 이름을 몰라도 방을 연다(2026-09-28 사용자 승인).**
      `hermes-chat` → 명부(은퇴자·slug 없는 사람 제외)를 번호로 보이고, 고르면 `claude --agent <slug> --name <이름>방`.
      `hermes-chat <이름 일부>` 가 한 명에 맞으면 번호 없이 바로. 어느 폴더에서 치든 위로 올라가 `.hermes/agents.json` 있는 프로젝트를 찾는다.
      검증: 픽스처 명부 2명 → 번호 목록 · `2` 입력 → `--dry-run` 이 `claude --agent backlog-manager --name 백로그관리자방` · 은퇴자 안 보임 · 명부 0명·hermes 아님 → 안내 후 exit 1.
      실측: tmux 에서 `hermes-chat` → 번호 → 방이 열리고 "네 SOUL 첫 줄" 에 SOUL 원문 첫 줄로 답한다(목표 1 과 함께).

- [ ] 8 — **어디서 대화하든 그 에이전트가 자기와 나눈 대화를 기억한다(2026-09-28 사용자 결정).**
      → 별도 계획: `docs/exec-plans/completed/2026-09-28-agent-conversation-memory.md` (C-29 — 대화 요약에 에이전트 키).
      "배운 것 한 줄"(답 끝 줄을 훅이 옮기기) 안은 접음 — 사용자: 이미 대화 핑퐁을 요약해 DB 에 넣고 있으니 그것을 에이전트 기억으로.

## 3-bis. 비목표

- ~~러너 스크립트(`hermes-chat` 명령)~~ → 목표 7 로 뒤집음. 단 **소환 러너가 아니다** — 사람이 자기 터미널에서 방을 여는 것이고 비대화형 실행·nonce 를 쓰지 않는다(C-28).
- 방 하나에 주인 둘. 공식 `--agent` 는 세션당 하나다. 둘째부터는 손님(`@`).
- Agent Teams(실험 기능, `/resume` 이 팀원을 되살리지 않음 — 조사 문서 1절).
- 공식 `memory:` 필드. 에이전트별 저장소라 헤르메스 MEMORY.md 와 겹친다(auto-owner-summon 목표 7 결정).

## 5. 착수 전 정할 것

| 정할 것 | 왜 |
| --- | --- |
| ~~RV-06 과의 관계 — 새 결정(C-28 후보)~~ **결정됨 2026-09-28: C-28 — 주인 이력 `actor` 는 `agent:<slug>`** (`docs/hermes-universe/decision-log.md`) | RV-06 은 **세션 안에서** `claude -p` 로 다른 세션을 띄우는 소환을 러너로만 허용한다. 사람이 자기 터미널에서 `--agent` 로 여는 것은 소환이 아니다. 대신 nonce 가 없어 "이 세션이 정말 그 에이전트인가" 를 명부 id 로 보증하지 못한다 — 주인 이력의 `actor` 를 명부 id 로 찍을지, `agent:<slug>` 처럼 구분해 찍을지 |
| 목표 1 실측 순서 | 훅만 고치고 실제 `claude --agent` 를 열어 봐야 끝난다. 세션 안 `claude -p` 는 summon-guard 가 막으므로 스크립트 파일 경유(2026-09-28 목표 6 실측 방식) |
| 내부 보조 호출 판별(목표 2) | "SubagentStart 없음" 이 유일한 표지인지 — `agent_transcript_path` 유무 등 다른 표지가 있는지 픽스처로 잰다 |

## 4. 영향 영역 (이번 착수: 목표 1 · 7)

- 코드: `assets/hooks/claude-sessionstart-agent-soul.sh` (+ `scripts/hooks/` 설치본) — `HERMES_AGENT_ID` 없으면 입력 `agent_type` → slug → 명부 id
- 코드: `presets/workflow/hermes.conf` — 새 스크립트 복사 목록 · `~/.local/bin/hermes-chat` 설치 한 줄
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes-chat.py` — 명부에서 대화 상대를 골라 `claude --agent <slug> --name <방>` 을 실행한다
  - `scripts/hermes-chat` — 어느 폴더에서든 가장 가까운 헤르메스 프로젝트를 찾아 그 `scripts/hermes-chat.py` 를 부르는 얇은 실행 파일(`~/.local/bin` 설치용)
  - `tests/hermes-chat-test.sh` — 목표 1(SessionStart agent_type 경로)·목표 7(고르기·dry-run) 픽스처 시험
  - `assets/hooks/claude-sessionstart-room-owner.sh` — `--agent` 방의 주인을 이력에 세션당 한 줄(목표 3)
  - `scripts/hermes_roster_pick.py` — 사람이 고를 수 있는 명부 에이전트 찾기(프로젝트 찾기·slug 있고 은퇴 아님·분야 표기) — hermes-chat 과 `@hag` 가 같이 쓴다
  - `scripts/hermes_file_suggest.py` — `@` 목록 제안: `@hag…` 이면 명부 에이전트, 그 밖은 흩어진 글자 파일 검색(목표 6)
  - `assets/hooks/claude-userpromptsubmit-hag.sh` — 보낸 글의 `hag:<slug>`·`@hag` 를 알아보고 넘기기/명부 표 지시를 넣는다(목표 6)
  - `lib/settings_file_suggestion.py` — 설정 생성기가 `fileSuggestion` 을 넣고 걷는 규칙(사용자 값 보존)
  - `tests/hermes-hag-test.sh` — 목표 6 시험
- 룰: C-28 (주인 이력 표기 — 목표 3 에서 쓴다, 이번 범위 밖)

## 6. 의사결정 로그

- 2026-09-28: C-28 확정 — 주인 이력 `actor` 는 `agent:<slug>`.
- 2026-09-28: 러너 비목표를 뒤집고 `hermes-chat` 명령(목표 7) — 근거: `claude --agent` 는 이름 없이 오류(실측), 사용자는 이름을 모른다.
- 2026-09-28: `@hag` 채택(목표 6) — 근거: 새 트리거 불가·기호 불가(실측), fileSuggestion 교체로 `@hag` 에 명부만 뜸(실측), 사용자가 `hag` 제안. `@hagent` 는 걷어 냄.
- 2026-09-28: 목표 8 은 "배운 것 한 줄" 대신 기존 대화 요약에 에이전트 키(C-29) — 근거: 사용자 정정("이미 핑퐁을 요약해 DB 에 넣고 있다"), 키는 스킬·교훈에만 있고 요약에 없음(DB 실측).
- 2026-09-28: 이번 착수는 목표 1 · 7 만. 2·3·4·5 는 다음. 6(`@hagent`)은 별도 계획 `2026-09-28-hagent-call.md` — 사용자가 `@` 목록 방식은 "불편하다" 로 접음.

## 7. 발견·예외

- 2026-09-28 목표 1 · 7 시험: `tests/hermes-chat-test.sh` 29/29. 훅의 `agent_type` 을 끈 변이 → 목표 1 주입 0 B(시험이 잡음).
  기존 `tests/hermes-soul-inject-test.sh` 35/0 (소환 경로 회귀 없음).
- 2026-09-28 설치 실측: 빈 프로젝트(가짜 HOME)에 설치 → `$HOME/.local/bin/hermes-chat` 배치, 하위 폴더 `.claude/` 에서 실행해도 번호 목록 → `claude --agent test-qa --name 테스트QA방`.
- 2026-09-28 **실제 방 실측(tmux)**: `bash scripts/hermes-chat` → 번호 2 → Claude Code 가 `@backlog-manager` 로 열림.
  "정체성의 '## 역할' 첫 문장" 질문 → **"공통 조직에서 기획 을(를) 맡는 리드이다."** (SOUL.md 원문. `.claude/agents/backlog-manager.md` 에는 없는 문장 — grep 0).
  `.hermes/hooks.log`: `[agent-soul] … room slug=backlog-manager agent=01a0c77a-…`.
  방을 닫고 `claude --resume 백로그관리자방` → 고르기 화면 없이 **바로 그 방**으로, 앞 대화 그대로·`@backlog-manager` 유지.
- 관찰(미해결, 이번 범위 밖): 입력창 오른쪽 위 제목이 `--name` 값이 아니라 "hermes-chat documentation review" 로 보였다 — `--name` 없이 연 세션에서도 같았다. `--resume <이름>` 은 동작하므로 이름 자체는 저장된다.

- 2026-09-28 목표 3: 사용자 지적 — 방을 열었는데 상태줄이 "지금: 없음 · 이 방에서 불린 명부 에이전트 없음".
  새 SessionStart 훅 `claude-sessionstart-room-owner.sh` 가 task.assigned(decision `match=owner slug=… agent=<id>`, actor `agent:<slug>` — C-28)를 세션당 한 번.
  task.assigned 를 고른 이유: gap-check 은 task.started 만 닫고, 방 보기 "일하는 중" 은 match=mention 만 본다(둘 다 코드 확인).
  시험 40/40 · 기존 방 보기 시험 30/0. 공장 자기 설치 → settings.json SessionStart 에 room-owner 등록.
  실측(tmux, 메시지 보내지 않음): `hermes-chat` → 2 → 상태줄 **"주인: 백로그 관리자 · 지금: 없음 · 이 방에서 불린 명부 에이전트 없음"**.
  이미 열려 있던 방은 훅이 없을 때 시작돼 주인 줄이 없다 — `claude --resume` 으로 다시 열면 resume 시작 훅이 적는다(세션당 한 번 규칙).

- 2026-09-28 목표 6: `tests/hermes-hag-test.sh` 39/39 (hag 분기 끈 변이 → 명부 줄 0, 시험이 잡음). 설정 생성기 기존 시험 hook-stdin-dispatch 15/15 · hook-prune 8/0 · preset-integrity 통과.
  자기 설치 → `.claude/settings.json` `fileSuggestion = python3 "${CLAUDE_PROJECT_DIR}/scripts/hermes_file_suggest.py"`.
  **실제 세션 실측(tmux)**: `@hag` → 목록에 명부 2명만 · `@doc` → 우리 스크립트의 파일 목록(이름에 doc 가 든 파일 먼저) ·
  Tab/엔터 → `@"게이트QA · QA/담당/공통 · hag:gate-qa"` 삽입(보내지 않음) · 아래 화살표로 둘째 줄 강조 이동 ·
  할 일 붙여 보냄 → "게이트QA에게 넘깁니다" → `gate-qa` 서브에이전트 → SOUL 역할 첫 문장으로 답.
  발견: 줄이 모두 `hag:` 로 시작하면 Tab 이 공통 앞부분(`@hag:`)만 넣는다 → 줄을 이름으로 시작하게 바꿈.
  발견: 하위 폴더에서 연 세션(`--settings` 시험)에서는 제안 명령이 불리지 않았다 — 모든 훅과 같은 `${CLAUDE_PROJECT_DIR}` 조건. 프로젝트 루트에서 여는 것이 전제.
  대가: `@` 파일 목록은 기본 대신 우리 스크립트(이름 포함 > 경로 포함 > 흩어진 글자, git 추적+미추적 파일, 15줄)가 맡는다. 폴더 항목은 내지 않는다.

## 관련

- `docs/exec-plans/backlog/auto-owner-summon.md` 목표 후보 7 (이 문서로 옮김)
- `docs/exec-plans/completed/2026-09-28-agent-mention-bridge.md` (C-27, `@` 부르기)
- `docs/exec-plans/completed/2026-09-28-agent-room-view.md` (방 구성원 표시·상태줄)
- `docs/audits/2026-09-28-agent-chat-room-research.md`
