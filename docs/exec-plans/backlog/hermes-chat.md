# hermes-chat — 명부 에이전트와 따로, 이어지는 대화방

> 작성일: 2026-09-28
> 목적: 메인 대화에서 `@` 으로 부르는 대신, 명부 에이전트(예: 백로그 관리자)와 **직접** 이어서 대화하는 방을 둔다.
> 출처: `auto-owner-summon.md` 목표 후보 7 을 떼어 온 것. 조사: `docs/audits/2026-09-28-agent-chat-room-research.md`.

## 개요

사용자 문제(2026-09-28): "여기서 내가 백로그 에이전트를 호출할 거야. 그럼 사용이 너무 힘들어."
지금(목표 6, C-27)은 메인 대화에서 `@back…` 으로 부른다. 부를 때마다 새로 시작하고, 메인이 말을 옮겨 적는다.
원하는 것은 그 에이전트가 **대화 상대 자체**인 방 — 말하면 그 에이전트가 직접 듣고, 나갔다 와도 이어진다.

`hermes-chat` 은 이 기능의 **이름**이다. Claude Code 명령이 아니다. 아래 확인대로 **새 명령 없이 기본 명령으로** 방을 열 수 있으면 러너를 만들지 않는다.

## 1. 쓰는 모양 (목표)

| 하고 싶은 것 | 터미널 |
| --- | --- |
| 백로그 관리자와 대화 시작 | `claude --agent backlog-manager --name 백로그방` |
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

- [ ] 1 — **`claude --agent <slug>` 로 연 세션에 그 에이전트의 SOUL·기억이 들어간다.**
      SessionStart soul 훅: `HERMES_AGENT_ID` 가 없으면 입력 JSON 의 `agent_type` → `hermes_agent_slug.agent_by_slug` → 은퇴 아닌 명부 id → 같은 렌더러(`hermes_soul_render.py`).
      `HERMES_AGENT_ID` 가 있으면 지금 그대로(소환 경로 우선). `startup`·`resume`·`compact` 모두 넣는다(`--resume` 뒤에도 정체성 유지).
      검증: 픽스처 입력 `{"source":"startup","agent_type":"backlog-manager"}` → stdout 첫 줄에 백로그 관리자 머리줄 · 명부 밖 slug·은퇴자·`Explore` → stdout 0 B.
      실측: 실제 `claude --agent backlog-manager` 에서 "네 SOUL 첫 줄" 에 SOUL 원문 첫 줄로 답한다.
- [ ] 2 — **내부 보조 호출이 방 주인의 호출로 세어지지 않는다.**
      SubagentStop 이력 훅: 같은 `agent_id` 의 SubagentStart(`task.assigned`) 가 없으면 명부 id 로 적지 않는다.
      검증: `--agent` 세션 픽스처에서 SubagentStart 없는 SubagentStop 3건 → 명부 에이전트 호출 0 · 내부 보조 3.
- [ ] 3 — **방 주인이 구성원 표시에 보인다.**
      세션 시작 때 주인을 이력에 한 줄(예: `task.assigned` decision `match=owner slug=…`) 남기고, `collect_room`·상태줄이 "주인: 백로그 관리자" 를 따로 보인다.
      검증: 주인 방 + 손님 1명 픽스처 → 상태줄에 주인·손님 둘 다, 손님 횟수만 셈.
- [ ] 4 — **쓰는 법 안내.** `hermes-agent` 스킬·`/hermes-roster` 표 아래에 방 여는 명령 한 줄(`claude --agent <호출명> --name <방>`).
      검증: `/hermes-roster` 출력에 호출명마다 방 여는 명령이 보인다.
- [ ] 5 — **기억 층(사용자 결정 2026-09-28).** 공통이 바탕, 에이전트 기억이 위를 덮는다 — 같은 `about` 키면 에이전트 쪽.
      공통 층은 2절 856줄로 이미 실린다. 남은 것은 "덮어쓴다" 를 SOUL 렌더에서 드러내는 것 — 착수 때 범위를 다시 잰다.
      검증: 같은 `about` 이 공통·개인에 다른 픽스처 → 주입 본문에 개인 쪽만.

## 4. 비목표

- **러너 스크립트(`hermes-chat` 명령).** 목표 1 이 되면 필요 없다. 목표 1 실측이 실패할 때만 다시 연다.
- 방 하나에 주인 둘. 공식 `--agent` 는 세션당 하나다. 둘째부터는 손님(`@`).
- Agent Teams(실험 기능, `/resume` 이 팀원을 되살리지 않음 — 조사 문서 1절).
- 공식 `memory:` 필드. 에이전트별 저장소라 헤르메스 MEMORY.md 와 겹친다(auto-owner-summon 목표 7 결정).

## 5. 착수 전 정할 것

| 정할 것 | 왜 |
| --- | --- |
| RV-06 과의 관계 — 새 결정(C-28 후보) | RV-06 은 **세션 안에서** `claude -p` 로 다른 세션을 띄우는 소환을 러너로만 허용한다. 사람이 자기 터미널에서 `--agent` 로 여는 것은 소환이 아니다. 대신 nonce 가 없어 "이 세션이 정말 그 에이전트인가" 를 명부 id 로 보증하지 못한다 — 주인 이력의 `actor` 를 명부 id 로 찍을지, `agent:<slug>` 처럼 구분해 찍을지 |
| 목표 1 실측 순서 | 훅만 고치고 실제 `claude --agent` 를 열어 봐야 끝난다. 세션 안 `claude -p` 는 summon-guard 가 막으므로 스크립트 파일 경유(2026-09-28 목표 6 실측 방식) |
| 내부 보조 호출 판별(목표 2) | "SubagentStart 없음" 이 유일한 표지인지 — `agent_transcript_path` 유무 등 다른 표지가 있는지 픽스처로 잰다 |

## 관련

- `docs/exec-plans/backlog/auto-owner-summon.md` 목표 후보 7 (이 문서로 옮김)
- `docs/exec-plans/completed/2026-09-28-agent-mention-bridge.md` (C-27, `@` 부르기)
- `docs/exec-plans/completed/2026-09-28-agent-room-view.md` (방 구성원 표시·상태줄)
- `docs/audits/2026-09-28-agent-chat-room-research.md`
