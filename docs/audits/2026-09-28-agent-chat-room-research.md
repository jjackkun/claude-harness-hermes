# 에이전트 전용 대화방 — 공식 기능·커뮤니티 구현 조사

> 작성일: 2026-09-28
> 목적: 명부 에이전트 한 명과 채팅방처럼 따로, 계속 이어지는 대화를 두는 방법이 있는지 조사한다.

## 개요

사용자 질문(2026-09-28): "채팅처럼 특정 에이전트만 따로 있게 하는 방법론을 설계할 수 있나? 클로드코드로 그런 걸 한 개발자가 있는지."
배경: `auto-owner-summon` 목표 6 실측 — 한글 `name` 은 `@` 멘션이 안 되고, 영문 slug + 한글 description 이면 된다.

결론: **공식 기능 조합으로 된다.** `claude --agent <slug> --name <방>` 으로 열고 `claude --resume <방>` 으로 돌아온다.
커뮤니티도 거의 전부 "세션 하나 = 대화방 하나" 로 풀었고, 정체성·기억은 파일·외부 저장소에 맡겼다.

## 1. 공식 기능 (code.claude.com/docs)

| 기능 | 에이전트 전용 대화방으로 | 근거 (문서 원문) |
| --- | --- | --- |
| `claude --agent <name>` | ✅ 세션 전체가 그 에이전트 | sub-agents.md "Run the whole session as a subagent … the main thread itself takes on that subagent's system prompt, tool restrictions, and model" |
| `--resume` / `--name` | ✅ 이어짐 | sessions.md "a session started with `--agent` … continues as that agent, keeping its tool restrictions and model" |
| 훅 | ✅ `--agent` 메인 세션에서도 돈다 | sub-agents.md "when the agent runs as the main session via `--agent` … they run alongside any hooks defined in `settings.json`" |
| 서브에이전트 `memory` 필드 | 참고 | `memory: project` → `.claude/agent-memory/<name>/MEMORY.md` 앞 200줄 자동 주입. 헤르메스 MEMORY.md 와 겹친다 |
| Agent Teams | ❌ | 실험 기능(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), "/resume and /rewind do not restore in-process teammates" |
| Agent View / `--bg --name` | 부분 | 이름 있는 배경 세션을 다시 붙일 수 있음. `--bg` 와 `--agent` 조합 예시는 문서에 없음(미확인) |
| 서브에이전트 재개 | ❌ | 부모 세션 안에서만 |
| 세션 간 메시지(cross-session messaging) | ✅ **(2026-10-02 정정)** | 처음엔 ❌ 로 적었으나 오류였다. 인용문 "A message is a piece of text … never the sender's conversation history" 가 바로 이 기능의 문서(code.claude.com/docs/en/cross-session-messaging)에서 온 것이다. `ListAgents` · `SendMessage` 로 같은 PC 의 다른 세션에 텍스트를 보내고, 받는 세션이 쉬고 있으면 새 턴이 시작된다. 실측은 `docs/audits/2026-10-02-multi-agent-collab-direction.md` §9 |

## 2. 커뮤니티 구현 (README 기준, 소스 미검증, 2026-09-28)

| 프로젝트 | ★ / 라이선스 | 나누는 방법 | 정체성·기억 |
| --- | --- | --- | --- |
| baryhuang/claude-code-by-agents | 893 / MIT | 한 방에서 `@frontend` 멘션 → 에이전트별 독립 프로세스 | 채널 기록만. 에이전트별 기억 미확인 |
| xvirobotics/metabot | 988 / MIT | 봇 하나 = 에이전트 하나(Feishu·Slack), `--session <id>` 고정 | MetaMemory (세션 넘어 검색) |
| firstintent/ccteam | 623 / MIT | 데몬이 세션을 띄우고 Telegram·웹에서 `@s2 …` 로 직접 말함 | 세션 단위 `--resume`, 페르소나 기억 없음 |
| 10000DOO/discord-agent-bridge | 2 / MIT | "One channel = one project = one session", `/agent resume` | CLAUDE.md 그대로 |
| chenhg5/cc-connect | 15,682 / 표기 없음 | 프로젝트마다 에이전트+메신저(13종), `--continue` | `/memory` 로 CLAUDE.md 편집 |
| letta-ai/claude-subconscious | 2,899 / MIT | 플러그인 — 배경 Letta 에이전트가 조언 | 기억 블록 8개, 단 모든 프로젝트가 뇌 하나 공유 |
| Qizhan7/claude-imprint | 90 / NOASSERTION | 공식 Telegram 채널 플러그인 + 기억 MCP | FTS5+벡터 DB, 에이전트 하나 |
| smtg-ai/claude-squad · kbwo/ccmanager | 8,537 AGPL · 1,251 MIT | tmux·worktree 별 세션 | 이름·기억 개념 없음 |
| winfunc/opcode (구 claudia) | 22,410 / AGPL | GUI 에서 에이전트 정의 → 별도 프로세스 | 정의만, 기억 미확인 |

미확인: Conductor, Reddit·HN 원문, 코드 검색(gh 미인증으로 `search/code` 불가).

## 3. 공통 패턴

1. 나누는 단위는 거의 항상 **세션 id 하나 = 대화방 하나** 다. `--resume`/`--continue` 나 Agent SDK 세션으로 잇는다.
2. **정체성·기억은 파일에 맡긴다** — CLAUDE.md, 에이전트 정의 본문, 외부 기억 저장소. 이름별로 기억을 나눈 것은 공식 `memory` 필드와 metabot 정도.
3. `@` 멘션형(한 방·여러 에이전트)과 1:1 방형(채널 = 세션)으로 갈린다. 명부 에이전트와 따로 대화하려는 목적에는 1:1 방형이 맞다.

## 4. 이 저장소에 이미 있는 조각

- `scripts/hooks/claude-sessionstart-agent-soul.sh` — `HERMES_AGENT_ID` 만 있으면 SOUL.md·MEMORY.md 를 넣는다(18·24줄, nonce 검사 없음).
- `scripts/hooks/claude-sessionstart-summons-verify.sh` — nonce 가 없으면 검증을 건너뛴다(14줄). 이 경우 작업 이력의 행위자 기록은 미확인.
- 관련 백로그: `auto-owner-summon` 목표 6, `intent-md-chat-bridge`(비개발자 채팅앱 경로 — 다른 주제, cc-connect·metabot 참고 가치).
