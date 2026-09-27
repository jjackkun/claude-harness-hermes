# auto-owner-summon — 일이 들어오면 담당이 자동으로 불려 와 진행하고, 끝나면 배운 것이 자동으로 남는다

> 사용자 결정 2026-09-22: **"설계상 만들어야 한다. 그래야 에이전트가 자동으로 불려 와서 진행된다.
> 물론 사람이 불러서 써도 되는 것이고."** — 자동 경로를 기본으로 두되 수동 호출도 남긴다.
>
> 사용자 결정 2026-09-27: 자동은 **두 가지**다 — ① 담당 자동 소환·진행 ② 작업 뒤 기억 자동 적립.
> 둘 다 지금은 수동(사람이 소환 · 에이전트가 `note` · 사람이 `teach`)으로도 하고 있으며, 수동 경로는 남긴다.
> 한 문서로 합친다 — 기억은 소환된 세션이 끝나는 자리에서 생기므로 같은 훅 지점을 두 번 설계하지 않는다.

## 1. 동기 (Why)

**실측 2026-09-22.** 이 세션에서 백로그 문서 2건을 썼는데 명부에 있는
`백로그 관리자`(01a0c77a, 기획/리드/공통, `product-manager@factory`, probation)가
**한 번도 불리지 않았다.** 사람이 "그 에이전트 불렀어?" 라고 묻고서야 드러났다.

빠뜨린 게 아니라 **그 경로가 아직 없다.** 설계 문서에 두 군데로 적혀 있다
(`docs/hermes-universe/design/agent/creation-and-organization.md`):

- **56줄** — "사람만 부른다. … **요청 문장을 축 값으로 판별하는 모델 호출은 두지 않는다** —
  에이전트가 인자를 채우고, 매칭 결과는 `task.assigned` 에 남겨 나중에 대조한다."
- **179줄** — "저장소 밖 산출물(예: 디자인 도구 파일)과 **경로가 없는 일(문서 정리, 배포 설정)의
  담당 표현은 미정이다.**"

즉 (a) 자동 판별을 **안 두기로** 했고, (b) 백로그·문서 정리처럼 **경로가 없는 일**은 담당을
표현할 방법 자체가 미정이다. 백로그 문서 쓰기는 정확히 (b) 에 해당한다.

## 2. 이미 있는 조각 (다시 만들지 말 것)

| 조각 | 위치 | 상태 |
| --- | --- | --- |
| 담당 찾기 | `hermes-agent.py match` (축 값을 **사람이** 줘야 함) | 있음 |
| 담당 두지 않음 기억 | `hermes-agent.py no-owner` → `match` 가 `ask:` 대신 `no-owner:` | 있음 |
| 봉투(인계) | `hermes_handoff.open_handoff` — `goal`·`done_when` 강제 | 있음 |
| 우선순위 대기열 | `hermes_handoff.queue(db, agent)` — 지시 → 협업 → 요청 | 있음 |
| 즉시 소환 | `hermes-summon.py run` (nonce, 러너 경유) | 있음 |
| 무인 세션 폴백 | `HERMES_HEADLESS=1` → `main` 수행 + "담당 없음" 제안 + 세션 시작 훅 알림 | 있음 |
| 기억 적립(수동) | `hermes-agent.py note`(에이전트) · `teach`(사람) · 리뷰 교정(`hermes_review_chain`) → `memory.added` + MEMORY.md 재생성 | 있음 |
| 소환 세션의 작업 이력 | `hermes_journal` — `HERMES_AGENT_ID` 세션의 작업을 에이전트 id 로 기록 | 있음 |
| **작업 → 담당 자동 연결** | — | **없음** |
| **경로 없는 일의 담당 표현** | — | **미정** |
| **소환 세션 종료 → 기억 자동 적립** | — | **없음** |

## 3. 목표 후보 (검증 가능한 형태로 다듬을 것)

- [ ] 목표 후보 1 — **경로 없는 일에 담당을 표현할 수 있다.** `organization.yaml` 의 수평 단위에
      경로뿐 아니라 **일의 종류**(예: `backlog`·`docs`·`deploy`)를 붙일 수 있다.
      검증: 그 값을 준 픽스처에서 `match --kind backlog` 가 백로그 담당을 돌려준다.
- [ ] 목표 후보 2 — **모델 호출 없이** 작업에서 축 값을 얻는다. 56줄의 금지를 깨지 않는 길:
      편집된 **파일 경로**(`docs/exec-plans/backlog/*` → `backlog`)와 **호출된 CLI/스킬** 로 규칙 매핑.
      검증: `docs/exec-plans/backlog/x.md` 를 Write 하면 규칙만으로 `backlog` 가 나온다.
- [ ] 목표 후보 3 — **담당이 잡히면 자동으로 소환해 진행한다.** 봉투(`goal`·`done_when`)를 자동으로 열고
      `hermes-summon.py run` 으로 그 담당 세션을 띄운다. 파괴적 작업은 소환된 세션에서도 표준 승인 게이트를 탄다.
      검증: 백로그 문서 Write 픽스처 → 봉투 1건 자동 열림 + 소환 1회(가짜 claude) + 소환 세션의 `HERMES_AGENT_ID` = 백로그 담당.
      (2026-09-22 초안은 "알림까지, 실행은 사람" 이었다 — 같은 날 사용자 결정 "자동으로 불려 와서 진행된다" 와 어긋나 09-27 고침.)
- [ ] 목표 후보 4 — 수동 경로(`match` · `hermes-summon.py run` · `note` · `teach`)는 그대로 남는다.
      검증: 기존 테스트 무변경 통과.
- [ ] 목표 후보 5 — **소환된 세션이 끝나면 배운 것이 기억 이벤트로 자동으로 남는다.** `note` 를 부르지 않아도
      세션 종료 지점에서 그 세션의 작업 이력(`hermes_journal`)을 근거(`source_event`)로 `memory.added` 를 적고 MEMORY.md 를 다시 만든다.
      `memory-events.md` 규칙을 따른다 — 근거 하나짜리는 "단일 사례", 충돌은 사람에게 보이고 최신 자동 승리 없음.
      검증: 소환 픽스처 세션 종료 → 그 에이전트의 `memory.added` ≥ 1 · `source_event` 가 작업 이력 id · 다음 소환 주입에 포함.
- [ ] 목표 후보 6 — **명부 에이전트를 채팅에서 `@agent-<이름>` 으로 부를 수 있다.** (사용자 결정 2026-09-28 "백로그에 넣어")
      → **착수 2026-09-28: `docs/exec-plans/active/2026-09-28-agent-mention-bridge.md`**
      Claude Code 는 `.claude/agents/*.md` 가 있는 에이전트만 `@` 멘션·자동완성으로 부른다(code.claude.com/docs/en/agents.md).
      지금 `@` 로 불리는 것은 위임용 12종뿐이고, 명부 에이전트(`백로그 관리자`·`게이트QA`)는 파일이 없어 `hermes-summon.py run` 으로만 불린다.
      명부 에이전트마다 `.claude/agents/<slug>.md` 를 만들어 수동 경로를 Claude Code 기본 문법에 맞춘다.
      ⚠️ 이름만 같은 껍데기가 되면 안 된다 — 지금 SOUL·기억은 `hermes-summon.py` 가 넘기는 `HERMES_AGENT_ID`·nonce 를
      **세션 시작 훅**이 받아 주입한다(`scripts/hermes-summon.py:100`). 서브에이전트는 같은 프로세스 안이라 이 환경변수·훅이 없다.
      검증: `@agent-<slug>` 로 부른 서브에이전트의 첫 입력에 그 에이전트의 SOUL 과 MEMORY.md 가 들어 있다 · `task.assigned`/`task.finished` 가 남는다.
- [ ] 목표 후보 7 — **에이전트 대화방.** 목표 6(slug·얇은 에이전트 파일·SubagentStart 주입) 위에 선다 — 6 먼저.
      조사: `docs/audits/2026-09-28-agent-chat-room-research.md` (공식 `--agent` + `--resume`, 커뮤니티 10건 — 거의 전부 "세션 하나 = 방 하나").
      사용자 결정 2026-09-28:
      - **방은 1:1 이 아니다 — 최소 한 명.** 둘 이상 들어올 수 있고, **방에 누가 몇 명 있는지 보이는 기능·UI** 가 있어야 한다.
      - **기억은 층을 둔다 — 공통이 바탕, 에이전트 기억이 위를 덮는다.** 없는 것은 공통을 쓰고, 자기에게 있는 것은 자기 것으로 덮는다.
      모양(초안): 러너 `hermes-chat <방> [에이전트…]` — 방 주인 한 명은 `claude --agent <slug> --name <방>` / 이후 `--resume <방>`,
      손님은 방 안에서 `@agent-<slug>`(목표 6). 러너가 nonce 를 발급한다(RV-06 — 러너 경유 세션만 명부 id). 방 구성원은 `.hermes/rooms/<방>.json`.
      공통 층은 공식이 이미 깐다 — sub-agents.md 856줄 "`CLAUDE.md` files and project memory still load through the normal message flow"(`--agent` 메인 세션).
      단 손님(서브에이전트)에는 메인의 자동 기억이 안 간다(1077줄 "the main conversation's auto memory isn't loaded").
      공식 `memory:` 필드는 **공통이 아니라 에이전트별**(`.claude/agent-memory/<name>/`)이라 헤르메스 MEMORY.md 와 겹친다 → 쓰지 않는다.
      검증: ① 두 명 방 픽스처 — 주인·손님 둘 다 자기 SOUL 을 받는다 ② 구성원 표시가 두 명을 보인다 ③ 같은 `about` 키가 공통·개인에 다르면 개인 쪽을 따른다 ④ `--resume` 으로 다시 열면 같은 주인으로 이어진다.

## 4. 비목표

- **요청 문장을 모델로 분류하는 것.** 56줄의 명시적 결정이다. 규칙 매핑으로 푼다.
  규칙으로 안 되는 자리는 담당 없음으로 두고 사람에게 묻는다(fail-open 금지).
- 담당이 없을 때 **새 에이전트를 자동 입사**시키는 것. 담당 없음은 지금처럼 제안 → 사람이 `hire`/`no-owner`.
- 무엇을 "배운 것" 으로 뽑을지에 모델 호출을 쓰는 것은 착수 때 정한다(아래 5절) — 56줄의 금지는 **축 값 판별**에 대한 것이다.

## 5. 착수 전 확인할 것

| 확인할 것 | 왜 |
| --- | --- |
| `organization.yaml` 자체 파서가 새 칸을 받을 수 있나 (평면 목록·2단 맵만 허용) | 스키마를 늘리면 파서부터 |
| `match` 의 축 인자 3개에 넷째(kind)를 붙일 때 C-11 매칭 규칙(더 많은 축이 이김)이 깨지지 않나 | 규칙 충돌 |
| 어느 훅 지점에서 알릴 것인가 (PostToolUse Write/Edit? Stop?) | 매 편집마다 알리면 소음 |
| 이 저장소에서 "경로 없는 일" 이 실제로 몇 종인가 | 규칙 매핑 표의 크기 |
| 자동 소환이 이미 도는 세션 안에서 또 소환을 부르면 겹치지 않나(중첩·재귀 소환 상한) | 한 편집이 소환 사슬을 만들 수 있다 |
| 소환 세션의 "끝" 을 어디서 잡나 (Stop 훅? 러너 종료?) · 무인(`HERMES_HEADLESS`) 세션도 같은가 | 목표 5 의 적립 지점 |
| "배운 것" 추출 — 규칙(작업 이력의 실패→성공 쌍, 리뷰 교정)으로 되나, 요약 모델이 필요한가 | R3·비용. 헤르메스 롤링 요약 경로를 재사용할 수 있나 |
| 자동 적립 기억이 소음이 되지 않게 하는 문턱 | 매 세션 몇 줄씩 쌓이면 주입 예산을 태운다(R-out·context_budget) |
| ~~(목표 6) 서브에이전트에 SOUL·기억을 넣는 길~~ **확인 2026-09-28: `SubagentStart` 훅으로 된다.** 공식 문서 hooks.md: "SubagentStart hooks can't block subagent creation, but they can inject context into the subagent" · `additionalContext` = "added to the subagent's context at the start of its conversation, before its first prompt" · 매처는 "the `name` field from the agent's frontmatter, not the filename". → `.claude/agents/<slug>.md` 는 이름·설명만, SOUL·MEMORY.md 는 훅이 그때그때 주입(세션 시작 훅 `claude-sessionstart-agent-soul.sh` 와 같은 일) | 파일에 굳히면 기억이 낡는다 — 설계 §1 의 두 층 분리를 지킨다 |
| ~~(목표 6) 한글 이름을 `name:` 에 쓸 수 있나~~ **실측 2026-09-28 (claude 2.1.283, haiku, 임시 폴더 픽스처): `@` 멘션에는 영문 slug 가 필요하다.** 한글 `name`(공백 有·無) — 목록 ✅ · Agent 도구 호출 ✅ · SubagentStart 한글 매처·`additionalContext` 도달 ✅ / `@agent-백로그관리자` · `@"백로그 관리자 (agent)"` · `@agent-백로그 관리자` ❌(훅 0건, 서브에이전트 안 뜸). 대조군 영문 `@agent-probe-en` ✅ → 원인은 `-p` 모드가 아니라 한글 이름. 영문 slug `backlog-manager` + description 에 "명부 이름 백로그 관리자" → `@agent-backlog-manager` ✅ · 한글 자연어 "백로그 관리자한테 …" ✅(둘 다 MARKER 도달). → 파일 `name:` 은 영문 slug, 한글 이름은 description 에. 남은 것: 입사·은퇴 때 파일을 누가 만들고 지우나 · 대화형 입력창 `@` 자동완성은 `-p` 로 못 재서 사람이 한 번 본다 | `@` 자동완성 이름과 명부 이름의 대응 |
| (목표 7) "덮어쓰기" 를 무엇으로 강제하나 — 지금은 공통·개인이 문맥에 나란히 들어가고 모델이 고른다. 주입 머리에 "개인 기억이 공통과 어긋나면 개인을 따른다" 한 줄로 되나, 같은 `about` 키를 훅이 걸러야 하나 | `memory-events.md` 의 "최신 자동 승리 없음" 은 한 에이전트 **안의** 충돌 규칙이다 — 층 **사이** 우선순위는 새 결정이라 설계 문서에 적는다 |
| (목표 7) 구성원 표시를 어디에 — 상태줄(statusline) 스크립트가 `.hermes/rooms/<방>.json` 을 읽나 · 상태줄 입력에 `--agent` 이름이 오나(미확인) | 사용자 요구 "몇 명 있는지 가늠" |
| (목표 7) 손님은 부를 때마다 새로 뜬다(서브에이전트) — "방에 있다" 를 '이 방에서 불린 적 있음' 으로 볼지, 상주(Agent Teams, 실험 기능·재개 시 복원 안 됨)가 필요한지 | 두 명 방의 뜻 |
| (목표 6) 서브에이전트 호출이 소환 기록(`task.assigned`·nonce)을 남기게 할 수 있나 | 수습 성적·작업 이력이 소환 경로에만 쌓이면 두 경로 성적이 갈린다 |

## 6. 관련

- `docs/hermes-universe/design/agent/creation-and-organization.md` §5 · §6 · 179줄
- `docs/hermes-universe/design/agent/handoff-contract.md` — 봉투·대기열
- `docs/hermes-universe/design/agent/memory-events.md` — 기억 이벤트 모양·충돌 규칙(목표 5)
- `docs/exec-plans/completed/2026-09-17-design-gaps-tier2.md` 목표 6·8·9 — 대기열·담당 두지 않음·무인 폴백
- 이 세션에서 연 봉투 `01a0c966-8a95-72f0-ae72-183dd313aa5e` (백로그 관리자 앞) — 손으로 연 사례
