# 2026-09-28-hag-rooms-ui — `@hag` 로 에이전트 방을 만들고 ← 로 직접 대화

> 작성일: 2026-09-28
> 목적: 입력창의 `@hag` 약속어만으로 명부 에이전트의 방을 만들고(← 목록), 상태줄에서 방을 보고, ← 로 골라 **직접**(토큰 한 번) 대화한다.
> 상위: `2026-09-28-hermes-chat.md` 목표 6(`@hag`) 이어서 · 기억: `2026-09-28-agent-conversation-memory.md`(C-29)

---

## 1. 동기 (Why)

- 사용자 제안(2026-09-28): "`@hag` 로 에이전트를 고르면 그냥 골라져야 한다. 상태줄에 고른 에이전트가 나와야 한다. `@hag-on`·`@hag-off` 로 켜고 끄고, `@hag-add` 로 이 방에 초대할 목록을 추가한다. 고르면 그다음 대화는 그 에이전트와."
- 그 뒤 실측으로 바뀐 전제 두 가지:
  - 이 채팅 안에서 에이전트와 말하면 **메인이 전달**한다 — 메시지마다 모델이 두 번 일한다. 에이전트가 대화 상대 자체인 방이면 한 번.
  - 상태줄의 `← for agents` 는 **세션 목록(agent view)** 이다. `claude --bg --agent <slug> --name <방>` 으로 연 방이 그 목록에 뜨고, SOUL 주입·방 주인 기록도 된다(실측). 그 목록에서 고른 세션에 쓴 말은 그 세션에 직접 간다(agent-view.md · cross-session-messaging.md).
- 그래서 "고르면 그 에이전트와 대화" 는 **이 채팅의 대화 상대를 바꾸는 것**이 아니라 **그 에이전트 방을 만들어 두고 ← 로 옮겨 가는 것**으로 만든다. 한 세션의 에이전트는 시작 때(`--agent`) 정해지고 도중에 바꾸는 옵션은 없다(도움말 확인).
- 사용자: "새 방이 열리건 여기서 대화하건 에이전트는 기억을 가지고 있어야지" → 기억은 C-29 계획이 맡는다(이 계획은 UI).

## 2. 목표 (What — 검증 가능한 형태)

모든 `@hag-*` 명령은 **보내는 순간** UserPromptSubmit 훅이 처리하고 프롬프트를 막는다 — 모델은 답하지 않는다(토큰 0).

- [x] 목표 1 — **명령이 목록에 뜬다.** `@hag` 를 치면 목록에 명부 에이전트와 함께 `@hag-on`·`@hag-off`·`@hag-add`·`@hag-rm` 이 보인다. `@hag-a` 처럼 이어 치면 거른다.
      검증: 제안 스크립트 시험(`hag-` 로 시작하면 명령 줄) · 실측: `-` 가 든 `@hag-on` 에도 목록이 뜬다.
- [x] 목표 2 — **켜고 끈다.** `@hag-on` 보냄 → 이 세션의 상태줄에 방 줄이 생긴다(`방: 없음 · ← 로 이동`). `@hag-off` → 사라진다. ~~세션마다 따로~~ → **프로젝트마다**(2026-10-06 수정 — 방에 갔다 오면 세션 id 가 바뀌어 세션별 상태가 사라졌다).
      검증: 훅 시험(상태 파일) · 실측: 보낸 뒤 모델 답이 없고(막힘) 안내 한 줄만 보인다.
- [x] 목표 3 — **초대하면 방이 생긴다.** `@hag-add` → 목록에 **아직 방이 없는** 명부 에이전트만 → 골라 보냄 → `claude --bg --agent <slug> --name <이름>방` 으로 백그라운드 방이 열리고 ← 목록에 뜬다. 이미 방이 있으면 새로 열지 않고 "이미 있음" 안내.
      "방이 있다" 는 **이름이 아니라 에이전트로** 판정: `claude agents --json` 의 `sessionId` → 방 주인 기록(journal `match=owner`)의 slug. `hermes-chat` 등 다른 이름으로 연 방도 잡힌다.
      자식 방은 **환경변수 허용목록**으로 연다 — 부모 훅의 `HERMES_AGENT_ID`·`HERMES_SUMMON_NONCE`·`HERMES_ACTOR` 등 `HERMES_*` 와 `CLAUDE_ENV_FILE` 을 넘기지 않는다(soul 훅이 `HERMES_AGENT_ID` 를 최우선으로 봐서 새 방이 부모 정체성으로 오염된다). cwd 는 프로젝트 루트.
      검증: 가짜 `claude` 로 시험(인자·cwd·**넘어간 환경변수에 HERMES_* 없음**·에이전트 기준 중복 방지 — 다른 이름의 같은 에이전트 방이 있으면 안 연다) · 실측: ← 목록에 `<이름>방` 이 보인다.
- [x] 목표 4 — **상태줄에 방과 상태.** 켜져 있으면 `방: 게이트QA 대기 · 백로그 관리자 일하는 중 · ← 로 이동`. 상태는 `claude agents --json` 의 status(idle/busy)에서.
      상태줄은 **`claude` 를 직접 부르지 않는다** — 방 목록 캐시(`.hermes/hag/rooms.json`)만 읽고, 캐시가 상태줄 갱신 간격(4초, `hermes_statusline_setup.py` REFRESH_SECONDS)보다 오래됐으면
      백그라운드로 새로 받게 던진 뒤 옛 값을 그린다. 그래서 기존 `timeout 1` 예산에 `claude` 기동 시간이 얹히지 않는다.
      방 목록은 매번 `claude agents --json` 에서 새로 만든다(상태 파일에 방을 적지 않는다) — 닫힌 방이 죽은 채 남지 않는다.
      다른 프로젝트 세션 거르기: 세션 `cwd` 가 프로젝트 루트와 **같거나 그 아래**(경로 구분자 기준 접두)인 것만.
      검증: 가짜 목록 JSON 으로 줄 모양 · cwd 거르기(형제 폴더 `…/proj-other` 는 빠짐) · 캐시 오래됨 → 옛 값 그리고 새로 받기 1회 · 목록 못 읽음 → `방: 목록을 못 읽었습니다` 한 줄.
- [x] 목표 5 — **방을 닫는다.** `@hag-rm` → 목록에 열린 방 → 골라 보냄 → `claude stop <id>`(대화는 남음, `claude --resume` 가능). 지우기(`rm`)는 하지 않는다.
      닫은 뒤 방 목록 캐시를 바로 새로 받는다(상태줄에 닫힌 방이 남지 않게).
      검증: 가짜 `claude` 로 `stop` 인자 · 캐시 갱신 시험.
- [x] 목표 6 — **짧게 맡기기는 그대로.** `@hag` → 에이전트 고르고 할 말 → 지금처럼 메인이 넘긴다(목표 6 of hermes-chat, 시험 39개 유지).
- [x] 목표 7 — **실측(사용자 화면).** `@hag-on` → `@hag-add` 로 백로그 관리자 → 상태줄에 "백로그 관리자 대기" → ← ← 로 방에 들어가 한 마디 → ← 로 돌아오면 상태줄이 "대기"(또는 일하는 중) → `@hag-rm` 으로 닫기.

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| 백그라운드 방 | `claude --bg --agent backlog-manager --name …` → 즉시 돌아옴, `idle — send a prompt to start`, `claude agents --json` 에 뜸, SOUL 주입(`room slug=…`)·방 주인 기록 됨(실측, 시험 방은 stop·rm) |
| 목록 형식 | `claude agents --json` → `id`·`name`·`status`(idle/busy)·`cwd` · 다른 프로젝트 세션도 섞여 나온다 → `cwd` 로 거른다 |
| 목록 속도 | 0.25 · 0.28 · 0.25 초(3회) |
| 상태줄 | `scripts/hermes-statusline.sh:23` 이 `hermes-agent.py room --line` 을 `timeout 1` 로 부른다 |
| `@` 목록 | fileSuggestion 이 `@hag…` 을 우리 스크립트로 받는다 · `@` 바로 뒤 기호는 목록이 안 뜬다 · 줄 첫 글자가 모두 같으면 Tab 이 공통 앞부분만 넣는다(실측) |
| 세션 안 `claude` | summon-guard 는 Bash 도구의 `claude -p` 만 막는다 — 훅에서 `claude --bg` 는 해당 없음. 방은 사람의 명령으로 여는 것(C-28 범주, 소환 아님) |
| 목록 칸 | `claude agents --json` 한 줄: `cwd`·`id`·`kind`·`name`·`pid`·**`sessionId`**·`startedAt`·`state`·`status` — 에이전트 이름 칸은 없다 → `sessionId` 로 방 주인 기록과 잇는다 |
| 막기 전파 | 디스패처(`claude-userpromptsubmit-dispatch.sh:24`)는 이름순으로 돌고 exit 2 면 즉시 멈춘다 — `…-hag.sh` 가 `…-mistake-detect`·`…-reminders`·`…-soul-approval-intent` 보다 앞이라 막으면 뒤 훅은 안 돈다(planner-lite 확인) |
| 상태 파일 | `.hermes/hag/` 는 `.gitignore:46` `.hermes/*` 로 이미 무시(`git check-ignore` 확인) |
| **미확인** | ① exit 2 로 막을 때 모델 답이 정말 없고 안내가 사용자에게 보이는가 ② `@hag-on`(`-` 포함)에 목록이 뜨는가 ③ 상태줄이 실제로 몇 초마다 불리는가 — Step 1 에서 먼저 잰다 |

## 3. 비목표 (Out of Scope)

- 이 채팅의 대화 상대를 에이전트로 바꾸기 — 공식 기능 없음.
- 방의 대화를 이 채팅에 되비추기(중계) — 토큰 두 번이 되는 길이라 하지 않는다.
- 방 지우기(`claude rm`) — 대화가 사라진다. 사람이 직접.
- 에이전트 기억 — C-29 계획.

## 4. 영향 영역

- 코드: `scripts/hermes_file_suggest.py`(명령 줄·방 없는 사람만) · `assets/hooks/claude-userpromptsubmit-hag.sh`(명령 처리·막기) ·
  `scripts/hermes_roster_view.py`·`scripts/hermes-agent.py room --line`(방 줄) · `presets/workflow/hermes.conf`(새 스크립트 복사 목록)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_hag_state.py` — 세션별 `@hag` 켜짐/꺼짐 상태를 읽고 쓴다(`.hermes/hag/<session>.json`)
  - `scripts/hermes_hag_rooms.py` — 이 프로젝트의 에이전트 방을 찾고(`claude agents --json`, cwd·이름으로 거름) 열고(`--bg`) 닫는다(`stop`)
  - `scripts/hermes_hag_commands.py` — 보낸 글의 `@hag-on/off/add/rm` 을 알아보고 상태·방 함수를 불러 안내 한 줄을 돌려준다
  - `scripts/hermes_hag_line.py` — 상태줄 방 줄: 켜진 세션이면 캐시로 `방: …` 을 그리고, 캐시가 갱신 간격보다 오래됐으면 백그라운드 갱신을 던진다(`hermes-agent.py` 가 399줄이라 분리)
  - `tests/hermes-hag-rooms-test.sh` — 목표 1~6 시험(가짜 `claude` 로 방 열기·닫기 인자 확인)
- 룰: C-28(방 = 사람의 명령, 소환 아님) · C-29(방의 대화 기억)
- 데이터: `.hermes/hag/<session>.json`(켜짐/꺼짐만) · `.hermes/hag/rooms.json`(방 목록 캐시) — `.hermes/*` 로 이미 git 무시
- 외부 의존: `claude --bg`·`claude agents --json`·`claude stop` 출력 형식(v2.1.283 실측). 형식이 바뀌면 상태줄은 `방: 목록을 못 읽었습니다`,
  명령은 `[hag] 방 목록을 못 읽었습니다: <오류 첫 줄> — claude agents 를 직접 확인하십시오` 를 보인다(조용히 틀리지 않음).

## 5. 단계 (Steps)

### Step 1. 미확인 두 가지 실측 [단순]
- tmux 시험 세션(`--settings` 한정)에서 ① exit 2 막기 ② `@hag-on` 목록. 결과로 목표 2 의 "막기" 방식을 확정한다(안 되면 계획을 고친다).

### Step 2. 시험 먼저 [Impl]
- `tests/hermes-hag-rooms-test.sh` — 가짜 `claude`(PATH 앞에 둔 스크립트)가 받은 인자를 파일로 남긴다.

### Step 3. 상태·방·명령 모듈 [Impl → 자기 검토]
- 세션 안에서 다른 세션을 여닫는 실제 위험 지점 — 환경변수 허용목록·cwd·에이전트 기준 중복 판정을 구현 직후 스스로 다시 읽고, Step 5 리뷰에도 이 파일을 먼저 보게 한다.
### Step 4. 목록·훅·상태줄 연결 [Impl]
### Step 5. 자기 설치 + 실측(목표 7) [Review]
- 세션 안에서 다른 세션을 여는 경로라 code-reviewer 로 승격.

## 6. 의사결정 로그

- 2026-09-28: "고르면 그 에이전트와 대화" 를 이 채팅의 상대 바꾸기가 아니라 **방 만들기 + ← 이동**으로 — 근거: 도중에 에이전트를 바꾸는 옵션 없음, ← 목록에 `--bg` 방이 뜨고 직접 대화(실측·문서), 토큰 한 번.
- 2026-10-06: `@hag-on` 상태를 **세션별 → 프로젝트별**(`.hermes/hag/on.json`) — 근거: 방으로 `←` 갔다 오면 세션 id 가 바뀌고(데몬이 새 세션을 띄움, 옛·새를 잇는 환경값·인자 없음 — 실측) 방 목록도 이미 프로젝트 단위. 손해: 같은 프로젝트의 다른 세션 상태줄에도 방 줄이 보인다(`@hag-off` 로 끈다).
- 2026-09-28: `@hag-rm` 은 stop 만(대화 보존) — 근거: rm 은 되돌릴 수 없다.
- 2026-09-28: 명령은 모두 훅이 막는다(모델 답 없음) — 근거: 켜고 끄고 초대하는 데 모델이 필요 없다. 막기가 안 되면(Step 1) 계획을 고친다.
- 2026-09-28 리뷰 반영(planner-lite NEEDS_WORK): 자식 방 환경변수 허용목록 · 상태줄은 캐시만 읽음(갱신 간격 4초 기준) · 중복 판정은 에이전트(sessionId→주인 기록) ·
  방은 상태 파일에 적지 않고 매번 목록에서 · 닫으면 캐시 갱신 · cwd 는 루트와 같거나 아래 · 실패 문구 확정 · gitignore 확인됨 · Step 3 자기 검토.

## 7. 발견·예외

- 2026-09-28 **Step 1 실측(tmux, haiku, `--settings` 한정)** — 미확인 세 가지 모두 성립:
  ① exit 2 막기 → 모델 답 없음. 화면: `UserPromptSubmit operation blocked by hook: [<훅 경로>]: <stderr> · Original prompt: @hag-on` — 경로가 앞에 붙으므로 안내 문구는 한 줄로 짧게.
  ② `@hag-on` 치자 제안 스크립트가 `"query":"hag-on"` 을 받았고 목록이 떴다(`-` 괜찮음).
  ③ 상태줄 호출 간격 2.6·4.0 초(12초 동안 3회) — refreshInterval 4 대로.
  덤: 명령을 끝까지 치고 엔터 → 목록 항목을 고르지 않고 **친 글자 그대로 보내졌다**(`@hag-on`). 명령은 쳐서 엔터면 된다. 사람 고르기(`@hag-add` 뒤)는 화살표로.

- 2026-09-28 **Step 2~5**: `tests/hermes-hag-rooms-test.sh` 35/35(허용목록을 끈 변이 → 자식에 HERMES_AGENT_ID 가 샘, 시험이 잡음) · `hermes-hag-test.sh` 39/39(`@hag` 목록에 명령 4줄 추가에 맞춰 기대값 갱신, `@hag<이름>` 은 명부만) · `hermes-chat-test.sh` 40/40 · 고아 0 · 프리셋 무결성 통과.
  자기 검토(Step 3): 공백뿐인 오류 출력에서 IndexError → 막음 · `CLAUDE_CODE_OAUTH_TOKEN` 허용목록에 추가(토큰 로그인 사용자) · API 키는 R3 로 계속 제외.
  **실제 세션 실측(tmux, haiku, 자기 설치 뒤)**: `@hag-on` 엔터 → 모델 답 없이 `[hag] 켰습니다` · 상태줄 `방: 없음 · ← 로 이동` →
  `@hag-add` → 목록 게이트QA·백로그 관리자(방 없는 둘) → 아래 화살표 2번·엔터로 고름 → 엔터 → `[hag] 백로그관리자방 을 열었습니다` · 상태줄 **`방: 백로그 관리자 대기 · ← 로 이동`** →
  `@hag-rm` → 목록 `백로그 관리자방 · 대기 · hag-rm:e219db85` → 고르고 보냄 → `[hag] 백로그 관리자 방을 닫았습니다` · 상태줄 `방: 없음` → `@hag-off` → 방 줄 사라짐. 시험 방은 `claude rm` 으로 지움.
  발견: 안내 앞에 `[${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-dispatch.sh]:` 가 붙어 보인다(Claude Code 표시 형식) — 줄이 길다. 줄일 방법은 없음(디스패처 경로가 곧 등록 명령).
  남은 것: 목표 7(사용자 화면에서 ← ← 로 방에 들어가 한 마디).

- 2026-10-06 **목표 7 실측(tmux, haiku 세션 + 방은 Opus 5.5, 실제 `←` 키)** — 1·2·3·5 통과, 4 는 결함 1건:
  1 `@hag-on` → 모델 답 없이 `[hag] 켰습니다` · 상태줄 `방: 없음 · ← 로 이동` /
  2 `@hag-add` → 백로그 관리자 → `[hag] 백로그관리자방 을 열었습니다` · (약 4초 뒤) `방: 백로그 관리자 대기 · ← 로 이동` /
  3 `←` → 전체 에이전트 목록(내 세션은 "Your conversation moved to the background") → 방 선택·Enter → 헤더 `@backlog-manager`, 상태줄 `주인: 백로그 관리자`, 한 마디에 명부 정체성으로 답함 /
  5 `@hag-rm` → `[hag] 백로그 관리자 방을 닫았습니다` · `방: 없음`.
  **4 결함: 방에서 `←` · `Esc` 로 돌아오면 상태줄 `방:` 줄이 사라진다.** 돌아온 세션의 id 가 달라져(`53a3599e…` → `e7b011f8…`) 켜짐 상태(`.hermes/hag/<세션>.json`)가 새 id 에는 없다. `@hag-on` 을 다시 치면 줄이 돌아온다(방 목록 캐시는 정상 — idle).
  원인: 상태가 세션 id 에 묶임. `←` 는 데몬이 띄운 새 세션(`CLAUDE_CODE_SESSION_KIND=bg`, `--session-id` 새 값)을 포그라운드로 붙이며, 상태줄 프로세스 환경에는 옛 세션·UI·tmux 창을 잇는 값이 없다(덤프로 확인) → id 가 아닌 프로젝트 단위로 바꿨다.
  **수정(같은 날)**: `hermes_hag_state.is_on/set_on` 이 세션 id 를 받지 않고 `.hermes/hag/on.json` 을 읽고 쓴다(StateError·세션 id 검사 제거 — 경로 탈출 여지 없음). `hag_line(project)` · `handle(project, prompt)`. 시험 `hermes-hag-rooms-test.sh` 47/47(RED 9 실패 → GREEN) · `hermes-hag-test` 39/39 · `hermes-chat-test` 40/40.
  **재실측(tmux, 수정 뒤)**: `@hag-on` → `@hag-add` 백로그 관리자 → `←` 로 방 입장(상태줄 `주인: 백로그 관리자` + `방: 백로그 관리자 대기`) → `←` `Esc` 로 복귀 → **`방: 백로그 관리자 대기 · ← 로 이동` 유지** → `@hag-rm` → `방: 없음` → `@hag-off` → 줄 사라짐(`on.json` `{"on": false}`). 시험 방·낡은 세션별 상태 파일 정리함.

- 2026-09-28 **code-reviewer(WARNING: HIGH 1 · MEDIUM 1 · LOW 2) 반영** — 시험 47/47:
  HIGH 문장 속 `@hag-on`·`@hag-add` 언급이 명령으로 실행됐다("그냥 @hag-on 치면 켜져요?" → 켜지고 질문 막힘, `@hag-add 게이트QA` 언급 → 방이 열림) →
  명령은 **메시지 맨 앞**일 때만, on/off/rm 은 뒤에 말 없이·add 는 이름 한 단어까지. 회귀 시험 4건.
  MEDIUM 상태줄 갱신이 겹쳐 `claude agents` 가 쌓일 수 있음 → `rooms.refreshing` 표시(CLI_TIMEOUT 30초 안이면 안 던짐, 갱신 끝에 지움). 시험 3건.
  LOW 방 id 형식 미검사 → `-` 로 시작하면 거부(옵션 오해석 방지). 시험 2건.
  LOW 동시 초대 두 번이면 같은 에이전트 방이 둘 열릴 수 있음(검사와 열기 사이 락 없음) — 확률 낮아 이번엔 두지 않음. 생기면 `@hag-rm` 으로 하나 닫는다.
  기록: 리뷰 본문이 알림과 함께 메인에 오지 않아 두 번 요청했고, 결국 기록 파일의 마지막 보고만 꺼내 읽었다.

## 8. 회고 (완료 시 작성)

> 확정(2026-10-06) — 목표 7 을 tmux 에서 실제 `←` 키로 실측하며 결함 1건을 찾아 고쳤다. 사람 화면 실측은 아니다.

- 잘된 것: 착수 전 미확인 셋(exit 2 막기 표시 · `@` 제안 질의 · 상태줄 간격)을 Step 1 에서 tmux 로 먼저 재서, 설계를 표시 형식(경로 접두)에 맞춰 짧게 정했다. 허용목록을 끄는 변이로 시험이 환경변수 누출을 잡는지 확인했다.
- 잘못된 것: 명령을 "메시지 안 어디든" 으로 받아 문장 속 언급(`그냥 @hag-on 치면 켜져요?`)이 실행됐다 — 리뷰(HIGH)가 잡을 때까지 시험이 문장형 입력을 안 넣었다. 리뷰 본문을 메인으로 받지 못해 두 번 요청했다.
- 목표 7 에서 잡힌 것: 상태를 세션 id 에 묶은 설계가 `←` 왕복에서 깨졌다(복귀 세션은 새 id). 계획 단계의 "세션마다 따로" 는 근거 없이 쓴 문장이었고, 방 목록이 이미 프로젝트 단위라는 사실과 어긋나 있었다. 사람 화면 실측 전에 tmux 실측으로 먼저 잡혔다.
- 다음 룰 후보: "프롬프트 명령은 맨 앞 토큰일 때만" — 같은 결함이 다른 훅(디스패처)에서 다시 나오면 R 룰로 올린다(지금은 1회).
- 다음 룰 후보 2: "외부 도구가 주는 id 를 상태의 열쇠로 쓰기 전에, 화면 이동·재시작 뒤에도 같은 값인지 한 번 잰다" — 1회라 R 룰로 올리지 않고 관찰한다.
