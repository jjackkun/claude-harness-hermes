# 2026-09-28-agent-mention-bridge — 명부 에이전트를 `@agent-<slug>` 로 부른다

> 출처 백로그: `docs/exec-plans/backlog/auto-owner-summon.md` 목표 후보 6 (목표 7 에이전트 대화방의 바닥).
> 조사: `docs/audits/2026-09-28-agent-chat-room-research.md`

## 1. 동기 (Why)

- 2026-09-28 사용자 질문 "클로드 코드에 에이전트 호출 명령어 있을 걸? 스킬은 `/` 로 부르잖아." → 공식 답은 `@agent-<name>`.
  그런데 `@` 는 `.claude/agents/*.md` 에 파일이 있는 에이전트만 부른다. 명부 에이전트 `게이트QA`·`백로그 관리자` 는
  `.hermes/agents/<id>/` 에만 있어 `hermes-summon.py run`(별도 `claude -p` 세션) 으로만 불린다.
- 두 층을 나눈 것은 설계다(`creation-and-organization.md` §1 — 직무 템플릿은 "부를 때마다 백지", 개인은 "소환될 때마다 폴더를 읽고 출근").
  그래서 SOUL·MEMORY.md 를 `.claude/agents` 파일에 **굳혀 넣으면 안 된다** — 기억이 낡는다.
- 공식 `SubagentStart` 훅이 서브에이전트 첫 프롬프트 앞에 `additionalContext` 를 넣을 수 있다(hooks.md 원문 확인).
  → 얇은 에이전트 파일(이름·설명) + 훅이 부를 때마다 최신 SOUL·기억을 넣으면, 두 층 분리를 지키면서 `@` 로 부를 수 있다.
- 목표 7(에이전트 대화방 — 주인 `--agent`, 손님 `@`)이 이 연결 위에 선다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **명부 에이전트가 영문 slug 를 가진다.** `agents.json` 항목에 선택 칸 `slug`.
      규칙: `^[a-z][a-z0-9-]{1,39}$` · 명부 안에서 유일 · 공장 에이전트 이름(`assets/agents/*.md`)·`main` 과 겹치지 않음.
      `hire --slug <s>` 와 `set-slug <이름> <s>` 로 준다. 기존 두 명에게 `gate-qa`·`backlog-manager` 를 준다.
      검증: 규칙 위반 3종(한글·중복·`code-reviewer`)이 각각 거부 + 이유 한 줄 · 정상 slug 는 저장 · slug 없는 기존 명부도 그대로 읽힌다.
      ✅ 2026-09-28: `tests/hermes-agent-mention-test.sh` §1 24/24 · 전체 묶음 106/109 → 등록·문서 수치 맞춘 뒤 실패 3건 재실행 통과 · 실제 명부에 `gate-qa`·`backlog-manager`.
- [ ] 목표 2 — **slug 가 있으면 `.claude/agents/<slug>.md` 가 있다.** frontmatter `name: <slug>` · `description` 에 한글 명부 이름·조직·
      "사용자가 '<한글 이름>' 을 말하면 이 에이전트를 쓴다" · `tools`/`model` 은 입사 템플릿(`assets/agents/<template>.md`)에서 물려받는다.
      본문에는 SOUL·기억을 **넣지 않는다**(훅 몫) — 머리말 주석으로 "생성물, 손으로 고치지 말 것 · 원본 agents.json".
      hire(slug 있을 때)·set-slug·reinstate 가 만들고, retire 가 지운다. `sync-mention-files` 로 명부 전체를 다시 맞춘다(멱등).
      검증: 파일 생성·삭제가 명령마다 일어난다 · 두 번 돌려도 diff 0 · 파일 본문에 SOUL 문구가 없다.
- [ ] 목표 3 — **`@agent-<slug>` 로 부르면 그 에이전트의 SOUL·기억이 들어간다.** 새 훅 `claude-subagentstart-agent-soul.sh` 가
      입력 `agent_type` → slug → 명부 id 로 풀고, 세션 시작 훅과 **같은 본문**(SOUL + 선별 기억, 각 4,096 B 상한, 은퇴자 제외)을
      `hookSpecificOutput.additionalContext` 로 돌려준다. 명부 slug 가 아니면(공장 에이전트·내장 에이전트) 아무것도 하지 않는다.
      검증: 픽스처 명부 + 입력 JSON → 출력 JSON 의 `additionalContext` 에 SOUL 첫 줄 · MEMORY 핀 기억 · `agent_type=code-reviewer` 는 빈 출력 · 은퇴자는 빈 출력.
- [ ] 목표 4 — **세션 시작 훅과 서브에이전트 훅이 한 렌더러를 쓴다.** 지금 `claude-sessionstart-agent-soul.sh` 의 파이썬 heredoc(약 60줄)을
      `scripts/hermes_soul_render.py` 로 옮기고 두 훅이 부른다. 세션 시작 훅의 출력은 바뀌지 않는다.
      검증: `tests/hermes-soul-inject-test.sh` 무변경 통과.
- [ ] 목표 5 — **`@` 로 부른 일도 그 에이전트 이름으로 이력에 남는다.** 새 훅 `claude-subagentstart-journal.sh` 가 `task.assigned`
      (`actor`·`evidence.via=mention`) 를, 기존 `claude-subagentstop-journal.sh` 가 명부 slug 일 때 `actor=agent:<명부 id>` 로 `task.finished` 를 남긴다.
      nonce 는 발급하지 않는다 — 서브에이전트는 세션이 아니라 이미 검증된 부모 세션 안의 호출이다(RV-06 은 **세션** 규칙).
      검증: 픽스처에서 Start·Stop 훅을 차례로 부르면 이력 2건, 둘 다 `agent:<명부 id>` · 명부 밖 에이전트는 기존과 같은 기록.
- [ ] 목표 6 — **설치로 번진다.** 설정 생성기가 `SubagentStart` 배열을 받고(`settings_gen.sh`·`generate_settings_json.py`),
      `hermes.conf` 가 두 새 훅과 새 스크립트를 등록한다. 공장 자기 설치 뒤 `.claude/settings.json` 에 `SubagentStart` 가 생긴다.
      검증: 생성기 단위 시험 · 자기 설치 뒤 `jq '.hooks.SubagentStart'` 가 두 명령을 보인다 · 매니페스트 정리(`_cleanup_stale_assets`)가 명부 에이전트 파일을 지우지 않는다(공장 이름이 아니므로).
- [ ] 목표 7 — **실제 세션에서 된다(사람 확인 1회).** 이 저장소 대화창에서 `@agent-backlog-manager` 자동완성이 뜨고, 불린 서브에이전트가
      자기 SOUL 첫 줄을 말한다 · "백로그 관리자한테 …" 한글 자연어로도 불린다. `-p` 로는 자동완성 화면을 못 잰다 → 사용자 확인.

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| 한글 `name` 의 `@` 멘션 (claude 2.1.283, haiku, 임시 폴더) | ❌ 세 형식 모두 훅 0건. 목록·Agent 도구 호출·SubagentStart 주입은 ✅ |
| 영문 slug + 한글 description | `@agent-backlog-manager` ✅ · "백로그 관리자한테 …" ✅ · 둘 다 MARKER 도달 |
| SubagentStart 주입 | hooks.md: "can't block … but they can inject context into the subagent" · 매처는 frontmatter `name` |
| `--agent` 메인 세션에서도 훅이 도나 (목표 7 대화방용) | sub-agents.md: "when the agent runs as the main session via `--agent` … alongside any hooks defined in `settings.json`" |
| 명부 | `.hermes/agents.json` git 추적 · 2명(`01a0b728…` 게이트QA, `01a0c77a…` 백로그 관리자) · `slug` 칸 없음 |
| 설정 생성기 | `SubagentStop` 만 있음 · `SubagentStart` 없음 (`generate_settings_json.py:267`) |
| 설치기의 `.claude/agents` 정리 | 매니페스트 기준(`lib/installers.sh:114` → `_cleanup_stale_assets`) — 공장이 깐 이름만 지운다 |
| 세션 시작 SOUL 훅 | `HERMES_AGENT_ID` 만 본다(nonce 검사 없음) · 본문 파이썬 heredoc 60여 줄 · 시험 `tests/hermes-soul-inject-test.sh` |
| SubagentStop 기록 훅 | `actor = "agent:" + <Claude 서브에이전트 id>` — 명부 id 아님 (`claude-subagentstop-journal.sh:31`) |
| `hermes-agent.py` 크기 | 369줄 — 명령 추가 시 400줄 경고선 근처. 명령 본체는 새 모듈로 뺀다 |

## 3. 비목표 (Out of Scope)

- 에이전트 대화방(`hermes-chat`, 방 구성원 표시, 기억 층 덮어쓰기) — 목표 7 계획에서.
- 한글 이름 자체로 `@` 멘션되게 하는 것 — Claude Code 쪽 동작이라 못 바꾼다(실측).
- 공식 `memory:` 필드 사용 — 헤르메스 MEMORY.md 와 기억이 갈라진다(백로그 목표 7 결정).
- slug 자동 생성(한글 → 로마자) — 사람이 준다. 틀린 로마자가 이름이 되는 것보다 한 번 묻는 게 싸다.
- 공장 밖 소우주 전파 — 이 계획 완료 뒤 별도 전파(update-all).

## 4. 영향 영역

- 코드 (수정):
  - `scripts/hermes_roster.py` — `_validate_agent` 가 선택 칸 `slug` 를 받는다.
  - `scripts/hermes-agent.py` — `hire --slug`, `set-slug`, `sync-mention-files` 파서와 얇은 호출만. retire/reinstate 뒤 파일 맞추기 호출.
  - `assets/hooks/claude-sessionstart-agent-soul.sh` (+ 설치본 `scripts/hooks/`) — heredoc 을 `hermes_soul_render.py` 호출로.
  - `assets/hooks/claude-subagentstop-journal.sh` (+ 설치본) — 명부 slug 면 actor 를 명부 id 로.
  - `lib/settings_gen.sh`, `lib/generate_settings_json.py` — `SUBAGENT_START_HOOKS` 배열 → `SubagentStart`.
  - `presets/workflow/hermes.conf` — 새 훅 2개·새 스크립트 3개 등록.
  - `assets/skills/hermes-agent/SKILL.md` — `@agent-<slug>` 부르는 법 한 줄.
  - `docs/hermes-universe/design/agent/creation-and-organization.md` §1·§5 — slug 와 `@` 경로. 결정 ID 는 `decision-log.md` 원장 접두어 확인 후 등재.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes_soul_render.py` — 명부 id 하나의 출근 본문(SOUL + 선별 기억, 상한 자르기)을 문자열로 만든다.
  - `scripts/hermes_agent_slug.py` — slug 규칙을 검증하고 slug 로 명부 에이전트를 찾는다.
  - `scripts/hermes_mention_file.py` — 명부 에이전트 하나의 `.claude/agents/<slug>.md` 를 만들고·지우고·명부 전체와 맞춘다.
  - `assets/hooks/claude-subagentstart-agent-soul.sh` — `agent_type` 이 명부 slug 면 출근 본문을 `additionalContext` JSON 으로 돌려준다.
  - `assets/hooks/claude-subagentstart-journal.sh` — 명부 slug 서브에이전트가 뜨면 `task.assigned` 를 남긴다.
  - `tests/hermes-agent-mention-test.sh` — 목표 1~5 픽스처 시험.
  - `.claude/agents/gate-qa.md`, `.claude/agents/backlog-manager.md` — 생성물(목표 2), 손으로 쓰지 않는다.
- 룰: R-iface(새 파일 공개 심볼 < 8), R-declare(위 목록), R-size, R-cx(`generate_settings_json.py` 라쳇 — 표 한 줄 추가로), RV-06(세션 규칙 — 서브에이전트는 대상 아님을 문서화).
- 데이터: `agents.json` 에 선택 칸 추가 — 마이그레이션 없음(없으면 slug 없음). `set-slug` 로 두 명 채움.
- 외부 의존: Claude Code `SubagentStart` 훅·`additionalContext`(v2.1.283 에서 실측). 구버전 claude 에선 훅이 안 돌 뿐 기존 경로는 그대로.

## 5. 단계 (Steps)

### Step 1. slug 규칙 + 명부 칸 [Plan/Impl/Review]

- 입력: 목표 1.
- 산출: `hermes_agent_slug.py`, `hermes_roster.py` 수정, `hire --slug`·`set-slug`.
- 검증: 시험 먼저(거부 3종·저장·구 명부 호환) → 구현 → 통과.

### Step 2. 에이전트 파일 생성·삭제 [Plan/Impl/Review]

- 입력: 목표 2, 입사 템플릿의 `tools`/`model`.
- 산출: `hermes_mention_file.py`, `sync-mention-files`, retire/reinstate 연동.
- 검증: 멱등(두 번 diff 0) · retire 삭제 · 본문에 SOUL 없음.

### Step 3. 렌더러 분리 [단순 — 동작 불변 리팩터]

- 입력: 목표 4.
- 산출: `hermes_soul_render.py`, 세션 시작 훅이 그것을 부름.
- 검증: `tests/hermes-soul-inject-test.sh` 무변경 통과.

### Step 4. SubagentStart 주입 훅 [Plan/Impl/Review]

- 입력: 목표 3, Step 1·3 산출.
- 산출: `claude-subagentstart-agent-soul.sh`.
- 검증: 입력 JSON 픽스처 4종(명부 slug·공장 이름·은퇴자·명부 없음).

### Step 5. 이력 기록 [Plan/Impl/Review]

- 입력: 목표 5.
- 산출: `claude-subagentstart-journal.sh`, `claude-subagentstop-journal.sh` 수정.
- 검증: Start→Stop 순 호출에 이력 2건, actor 일치.

### Step 6. 설치 배선 + 자기 설치 [Plan/Impl/Review]

- 입력: 목표 6.
- 산출: 생성기·`hermes.conf`·SKILL.md·설계 문서.
- 검증: 생성기 시험 · 자기 설치 뒤 `SubagentStart` 두 명령 · 전체 시험 묶음 · `set-slug` 로 두 명 파일 생성.
- 리뷰: 설정 생성기·훅 등록은 공유 경계 → code-reviewer.

### Step 7. 사람 확인 [단순]

- 입력: 목표 7. 새 세션을 열어야 훅·에이전트 목록이 다시 읽힌다.
- 산출: 사용자 화면에서 `@agent-backlog-manager` 자동완성 · SOUL 첫 줄 응답 · 한글 자연어 호출.

## 6. 의사결정 로그

- 2026-09-28: 명부 이름은 한글 그대로 두고 `@` 용 영문 slug 를 따로 둔다 — 근거: 한글 `name` 은 `@` 멘션 불가(실측), description 의 한글 이름으로 자연어 호출은 됨(실측).
- 2026-09-28: 에이전트 파일에 SOUL·기억을 넣지 않고 SubagentStart 훅이 부를 때마다 넣는다 — 근거: 설계 §1 두 층 분리, MEMORY.md 는 파생물·git 비추적.
- 2026-09-28: slug 는 사람이 준다(자동 로마자 변환 안 함) — 근거: 이름은 오래 남는다. 틀린 변환을 고치는 비용이 한 번 묻는 비용보다 크다.
- 2026-09-28: `@` 호출은 nonce 를 발급하지 않는다 — 근거: RV-06 은 명부 id 를 가진 **세션** 규칙이고, 서브에이전트는 부모 세션 안의 호출이다. 대신 이력에 `via=mention` 을 남긴다.
- 2026-09-28: 예약 이름 = 내장 에이전트·main·`.claude/agents`·`assets/agents` 파일 이름 중 **명부 slug 가 아닌 것** — 근거: 목표 2 가 만들 생성 파일은 주인 slug 라 스스로 막히지 않고, 사용자가 손으로 둔 에이전트 파일과는 겹치지 않는다. 표지(마커) 없이 판정된다.
- 2026-09-28: 목표 7(대화방)의 손님 "방에 있다" = "이 방에서 불린 적 있음" — 사용자 결정. 이 계획의 이력(목표 5)이 그 근거 자료가 된다.

## 7. 발견·예외

- 한글 `@` 멘션 불가는 Claude Code 동작이다. 버전이 바뀌면 다시 잴 가치가 있다 → 이 계획 완료 시 `docs/audits/` 실측 기록에 버전과 함께 남긴다.
- 세션 안 `claude -p` 가드(RV-06)가 실측 스크립트를 두 번 막았다. 픽스처 실측은 사용자 지시로 스크립트 파일로 돌렸다 —
  공장 도구로 실측 경로를 둘지(harness-eval 처럼) 는 별도 판단.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
