# 2026-09-28-agent-conversation-memory — 대화 요약을 에이전트별 기억으로

> 작성일: 2026-09-28
> 목적: 헤르메스가 이미 만드는 대화 핑퐁 요약(`session_summary`)에 에이전트 키를 붙여, 각 에이전트가 **자기와 나눈 대화**를 어디서 불리든 기억으로 갖게 한다.
> 설계 결정: C-29 (`docs/hermes-universe/decision-log.md`) · 상위: `2026-09-28-hermes-chat.md` 목표 8

---

## 1. 동기 (Why)

- 에이전트를 만든 이유는 **각 에이전트가 자기 기억을 갖는 것**이다(사용자, 2026-09-28). 예전 기억은 프로젝트 하나로 통째였고, 그래서 에이전트 키가 추가됐다.
- 그런데 키는 스킬(`skill_index.agent_id`)과 교훈(`memory_events.agent_id`)에만 붙었다. **대화 요약(`session_summary`)·대화 기록(`session_history`)에는 없다**(DB 실측).
- 설계도 그렇게 적혀 있다 — `teaching.md` §6: 세션 요약은 **소우주 공통 층**, 개인 기억은 `memory_events` 뿐.
- 결과: 방(`--agent`)에서 길게 이야기해도, `@` 로 불러 일을 시켜도, 다음에 그 에이전트를 부르면 **자기와 나눈 대화를 모른다.** 요약은 매 턴 만들어지는데 주인이 없다.
- 사용자: "우리 대화 핑퐁을 요약해서 디비에 넣고 있어. 그것을 에이전트의 기억에 넣어야 하는 거야."

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **요약에 에이전트 키.** `session_summary` 에 `agent_id` 칸(비면 소우주 공통 = 지금 그대로). 있는 DB 는 칸만 더한다(데이터 보존, 두 번 돌려도 같음).
      다섯 생성 지점(`hermes-init.py`·`hermes-recall.py`·`hermes-summarize.py`·`hermes-dream.py`·`hermes_sync_learning.py`)이 모두 같은 보장 함수를 부른다.
      검증: 옛 스키마 DB 에 마이그레이션 두 번 → 칸 1개 · 기존 22행 그대로(agent_id NULL) · 다섯 지점 각각이 옛 DB 를 열어도 칸이 생긴다.
- [x] 목표 2 — **방의 요약은 방 주인 몫.** 방 세션(`claude --agent`)의 롤링 요약이 방 주인 기록(journal `match=owner`, 목표 3 of hermes-chat)으로 찾은 명부 id 를 달고 저장된다.
      검증: 주인 기록 있는 세션 픽스처 → 요약 행 agent_id = 주인 id · 주인 기록 없는 세션 → NULL.
- [x] 목표 3 — **`@` 호출의 대화도 그 에이전트 몫으로 요약.** SubagentStop 에서 명부 에이전트면 `agent_transcript_path` 를 같은 요약기로 요약해 `session_id = sub:<서브에이전트 id>`, `agent_id = 명부 id` 로 저장한다. 메인 세션 요약은 지금처럼 공통으로 남는다.
      근거: SubagentStop 입력에 `agent_type`·`agent_transcript_path`·`last_assistant_message` 가 온다(실측 2026-09-28, haiku 시험 세션).
      방(`--agent`) 세션 안에서는 Claude Code 내부 보조(입력 추천·`/btw`)의 SubagentStop 도 `agent_type` = 방 slug 로 온다(hooks.md, hermes-chat 목표 2 미완) —
      같은 서브에이전트 id 의 SubagentStart(`task.assigned` match=mention)가 있을 때만 요약한다(내부 보조는 Start 기록이 없다).
      검증: 픽스처 서브에이전트 기록 → 행 1개(agent_id = 명부 id) · 명부 밖(`Explore`)·은퇴자 → 행 0 · **방 세션의 Start 없는 SubagentStop → 행 0** · 백그라운드로 돌아 SubagentStop 이 기다리지 않는다.
- [x] 목표 4 — **부르면 자기 대화 요약이 들어간다.** 출근 본문(`hermes_soul_render.py` — 방·`@`·소환 공통)에 "`--- 나와 나눈 최근 대화 ---`" 구획: 그 에이전트 키가 붙은 요약만, 최근 순, 상한 안에서. 다른 에이전트·공통 요약은 넣지 않는다.
      은퇴자는 렌더 자체가 없다(`hermes_soul_render.py:78` 기존 동작) — 요약은 쌓이되 복직 전까지 안 보인다.
      검증: 두 에이전트·공통 요약이 섞인 픽스처 → 백로그 관리자 본문에 자기 요약만 · 상한 넘으면 잘림 줄 · 은퇴자 → 본문 없음.
- [x] 목표 5 — **개인 대화는 공통 회상에 섞이지 않는다.** 메인 세션의 "[헤르메스 회상]"(`hermes-recall.py`)은 agent_id 가 빈 요약만 쓴다. 소우주로 올리는 것은 C-26 의 승격(허가) 경로로만.
      같은 규칙을 요약을 읽는 다른 곳에도: `hermes-dream.py:110`(결정화·진화 재료 — 개인 대화가 공통 스킬 재료가 되면 C-26 허가 경로를 건너뛴다) ·
      `hermes-recall.py:195·236`(키워드 회상) · `hermes-lifecycle.py:246`.
      검증: 에이전트 키 요약이 최신이어도 회상 주입에 안 나온다 · 드리밍 후보에 안 들어간다.
- [x] 목표 6 — **기억 운반에 키가 따라간다.** `refs/hermes/sync` 로 가는 요약에 agent_id 가 실리고, 받는 쪽이 같은 에이전트 몫으로 넣는다.
      들여오기(`hermes_sync_learning.py:119`)는 `INSERT OR REPLACE` 라 칸을 적지 않으면 로컬 agent_id 가 NULL 로 지워진다 — 칸을 명시하고,
      agent_id 가 없는 구버전 몸통이 오면 로컬 값을 지우지 않는다. 암호화는 기존 규칙 그대로(`slots_json` 은 잠금 모드면 암호문, 평문 모드면 평문 — T-18).
      검증: 내보내기→들여오기 왕복 픽스처에서 agent_id 보존 · 구버전(칸 없는) 몸통 들여오기 → 로컬 agent_id 유지.
- [x] 목표 7 — **실측.** 실제 세션: ① 방에서 두세 마디 → 방을 닫고 `@` 로 같은 에이전트를 부르면 "지난번에 무슨 이야기를 했나" 에 방 대화 요약으로 답한다. ② `@` 로 일을 시킨 뒤 새 방을 열면 그 일을 안다.

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| 에이전트 키가 있는 표 | `skill_index.agent_id` · `memory_events.agent_id`(이 저장소엔 표 아직 없음) · `journal_events.actor` · `messages.from/to_agent` |
| 에이전트 키가 없는 표 | `session_summary`(22행) · `session_history`(2,789행) · `pattern_count`(607행) |
| 요약 스키마 | `session_summary(session_id PK, project_id, slots_json, last_msg_count, turn_count, updated_at)` — **다섯 곳**이 각자 만든다: `hermes-init.py:192` · `hermes-recall.py:57` · `hermes-summarize.py:47` · `hermes-dream.py:55` · `hermes_sync_learning.py:20` (planner-lite 지적, grep 확인) |
| 요약을 읽는 곳 | `hermes-recall.py:97`(LIMIT 1 — 공통 최신 1건만) · `:195`·`:236` · `hermes-dream.py:110`(전체) · `hermes-lifecycle.py:246` · `hermes_dashboard_data.py:140`(개수) |
| 운반 들여오기 | `hermes_sync_learning.py:119` `INSERT OR REPLACE` — 칸을 적지 않으면 새 칸이 지워진다 |
| 요약 시점 | 매 턴 Stop → `claude-stop-retrospective.sh` → `hermes-summarize.py --session-id --transcript`(백그라운드, haiku, 델타 없으면 호출 0) |
| 요약 칸 | 5칸: decisions · open · prefs · facts · next |
| 방 세션도 요약되나 | 예 — `--agent` 로 연 시험 세션 `0b30f9eb` 가 요약돼 있었다 |
| 주입 자리 | `hermes_soul_render.py` 한 곳(방 SessionStart · @ SubagentStart · 소환 공통) — 지금 SOUL.md + MEMORY.md |
| Stop 입력 | `session_id`·`transcript_path`·`last_assistant_message` 있음, **`agent_type` 없음**(실측) → 방은 주인 기록으로 찾는다 |
| SubagentStop 입력 | `agent_type`·`agent_id`·`agent_transcript_path`·`last_assistant_message` 있음(실측) |
| 현재 설계 결정 | `teaching.md` §6(C-26): 세션 요약 = 소우주 공통 층 → C-29 로 보완 |
| **미확인** | 서브에이전트 기록(`agent_transcript_path`)이 `hermes-summarize.py` `load_transcript()`(58~83행, 메인 기록 전제)와 같은 모양인가 — Step 3 전에 실제 파일 하나로 잰다 |

## 3. 비목표 (Out of Scope)

- `session_history`(대화 원문 검색)의 에이전트 키 — 요약이 먼저. 원문 검색을 에이전트별로 나눌 필요가 실측되면 따로.
- `pattern_count`·결정화의 에이전트 분리 — 스킬은 이미 `skill_index.agent_id` 층이 있다.
- 에이전트 대화 요약을 소우주 공통으로 자동 승격 — C-26 허가 경로 그대로.
- "배운 것 한 줄"(답 끝 줄을 훅이 옮기기) — 사용자 결정으로 접음. 교훈은 기존 teach·리뷰·소환 note 그대로.
- **잘못 귀속된 방 대화의 정정(철회) 경로** — 방 주인 귀속은 신원 보증이 없다(C-28, nonce 없음). 잘못 연 방·시험 방의 대화도 그 에이전트 기억이 된다. 이번엔 다루지 않고 후속 과제로 둔다(C-29 손해 칸에 적음).

## 4. 영향 영역

- 코드: `scripts/hermes-init.py`·`scripts/hermes-recall.py`(스키마·칸 추가, 회상은 공통만) · `scripts/hermes-summarize.py`(`--agent-id` 받아 저장) ·
  `scripts/hermes-dream.py`(스키마 + 결정화 재료는 공통만) · `scripts/hermes-lifecycle.py`(공통만) ·
  `assets/hooks/claude-stop-retrospective.sh`(방이면 주인 id 넘김) · `scripts/hermes_soul_render.py`(대화 요약 구획) · `scripts/hermes_sync_learning.py`(운반) · `presets/workflow/hermes.conf`(새 훅 등록)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_summary_owner.py` — 요약의 주인 찾기(세션 → 방 주인 명부 id)와 `session_summary.agent_id` 칸 보장(마이그레이션)
  - `scripts/hermes_agent_summaries.py` — 한 에이전트의 대화 요약을 최근 순·상한 안에서 출근 본문 구획으로 만든다
  - `assets/hooks/claude-subagentstop-summarize.sh` — 명부 에이전트의 서브에이전트 대화를 그 에이전트 몫으로 요약(백그라운드)
  - `tests/hermes-agent-summary-test.sh` — 목표 1~6 픽스처 시험
- 룰: C-29(신규) · C-26 · C-28(주인 기록은 `agent:<slug>` actor, decision 의 명부 id 를 쓴다)
- 데이터: `session_summary` 에 칸 추가(ALTER, 되돌리기 불필요 — 빈 칸 = 예전 뜻)
- 외부 의존: 요약기의 haiku 호출이 `@` 호출마다 한 번 늘어난다(방은 이미 요약되므로 추가 없음)

## 5. 단계 (Steps)

### Step 1. 스키마·주인 찾기 [Plan/Impl]
- 산출: `hermes_summary_owner.py` + **다섯** 생성 지점이 그것을 부른다. 검증: 목표 1 · 2 시험.

### Step 2. 방 요약에 주인 달기 [Impl]
- 산출: summarize 가 `--agent-id` 를 받아 저장, retrospective 훅이 방이면 넘긴다. 검증: 목표 2.

### Step 3. `@` 대화 요약 [Impl]
- 먼저: 실제 서브에이전트 기록 한 개로 `load_transcript()` 가 델타를 뽑는지 잰다(§2-bis 미확인).
- 산출: SubagentStop 요약 훅(백그라운드, Start 기록 있는 호출만). 검증: 목표 3.

### Step 4. 주입·회상 분리 [Impl]
- 산출: 출근 본문 구획, 회상·드리밍은 공통만. 상한은 바이트로 하나 — 기존 SOUL/MEMORY 각 상한 4,096 B(R-out 실측값)와 같은 값을 쓴다(새 숫자를 만들지 않는다).
  개수로 자르지 않고 최근 순으로 그 바이트 안에 드는 만큼 넣는다 — 회상은 `LIMIT 1` 이라 맞출 개수가 없다(planner-lite 지적). 검증: 목표 4 · 5.

### Step 5. 운반 [Impl]
- 검증: 목표 6.

### Step 6. 실측 [Review]
- 목표 7. 큰 변경(스키마·운반·주입 경로)이라 code-reviewer 로 승격.

## 6. 의사결정 로그

- 2026-09-28: 대화 요약에 에이전트 키(C-29) — 근거: 에이전트를 만든 목적(자기 기억)과 달리 요약만 주인이 없다(DB 실측), 사용자 지시.
- 2026-09-28: `@` 호출은 메인 요약을 나누지 않고 서브에이전트 기록을 따로 요약 — 근거: 메인 요약엔 다른 이야기가 섞인다, SubagentStop 이 그 에이전트 몫 기록 경로를 준다(실측).
- 2026-09-28: 개인 대화 요약은 메인 회상에 넣지 않는다 — 근거: C-26 승격은 허가를 거친다. 섞으면 한 에이전트의 사정이 모두의 문맥이 된다.
- 2026-09-28 리뷰 반영(planner-lite NEEDS_WORK · architect-lite): 생성 지점 5곳 · 들여오기 REPLACE 보존 · 드리밍 공통만 · 방 안 내부 보조 제외(Start 기록) ·
  서브에이전트 기록 형식 선확인 · 상한은 바이트 4,096 · 은퇴자 시험 · 귀속 정정은 후속 과제 · 암호화는 기존 T-18 규칙. 운반 암호화(C-20) 지적은 절반만 성립 — 요약은 이미 잠금 모드 암호화 대상.

## 7. 발견·예외

- 2026-09-28 **구현·시험**: `tests/hermes-agent-summary-test.sh` 25/25(주입 구획을 끈 변이 → 대화 구획 없음, 시험이 잡음).
  §2-bis 미확인 해소: 실제 서브에이전트 기록(`…/subagents/agent-<id>.jsonl`)이 메인과 같은 모양 — `load_transcript()` 가 54개 메시지를 읽고 마스킹까지 됨.
  기존 시험 회귀 30여 종 확인. 두 가지를 고침: ① `hermes-sync-test.sh` 준비 코드가 칸 이름 없이 6칸을 넣음 → 칸 이름 명시(실제 코드엔 그런 곳 없음, grep)
  ② 새 함수 3개(`hermes_hag_commands.handle/_add`, `hermes_file_suggest.hag_lines`) 복잡도 12 > 11 → 도우미로 분리. 이것 때문에 `copy-install-test`(R-cx)·`cx-baseline` 이 깨졌다가 56/0·14/0.
  lifecycle(`hermes-lifecycle.py:246`)은 세션 id 로 하나씩 읽는 곳이라 거르지 않았다 — 원문 기록(`session_history`)이 이미 에이전트 구분이 없는 비목표 영역.
- 2026-09-28 **실측(tmux, haiku, 자기 설치 뒤 — 이 저장소 DB 에 agent_id 칸 마이그레이션 확인)**:
  ① 메인 대화에서 `@hag게이트` 로 게이트QA 를 골라 "다음 릴리스 전에 결제 화면 회귀 시험" 을 전함 → 게이트QA 가 불려 답함 →
     `session_summary` 에 `sub:a44982ca0610d91f5 · agent_id=게이트QA` 행(결정·사실·다음 5칸).
     (첫 시도는 시험 문장 "도구 없이 답해" 때문에 메인이 넘기지 않고 직접 답해 무효 — 시험 문장에 넘기기를 막는 말을 넣지 말 것.)
  ② **새 방**(`claude --agent gate-qa`)을 열어 도구 없이 "지난번에 나와 한 약속" → **"다음 릴리스 전에 결제 화면 회귀 시험을 반드시 실행한다"**.
  시험이 만든 게이트QA 기억 2행(①의 sub 행, ②의 방 행)과 vault 노트 2개는 지웠다 — 가짜 약속이 실제 에이전트 기억으로 남지 않게. 지운 뒤 게이트QA 대화 구획 0.

- 2026-09-28 **리뷰 반영 — code-reviewer(WARNING: HIGH 2·MED 1·LOW 1) + database-reviewer(HIGH 2·MED 2·LOW 3)** — 시험 31/31:
  DB HIGH 동시 칸 추가 → `duplicate column` 만 삼킴(`_add_agent_column`) · DB HIGH 이력 `session_id` 인덱스 없음 → `journal_session_kind_idx(session_id, kind, ts)` ·
  DB MED 들여오기 읽기→쓰기 경쟁 → 한 문장 UPSERT(`WHERE 기존 updated_at < 새것`, `COALESCE(agent_id)`) ·
  코드 HIGH 회상의 "도우미 없어도 돈다" 대비책이 `no such column` 으로 죽음 → 칸이 있을 때만 거르는 `_common_only(con)` ·
  코드 HIGH lifecycle 이 에이전트 몫 요약을 공통 LLM 재료로 씀(내가 비목표로 뺀 판단이 틀림) → **세션째 제외**(요약만 거르면 원문 폴백으로 더 많이 샌다) ·
  코드 LOW 기록 경로 줄바꿈 → 거부.
  수정 중 발견: lifecycle 이 501줄(R-size 500 차단) → 도우미를 `hermes_summary_owner.is_agent_session` 으로 옮겨 493줄.
  기록만: DB MED 한 번 붙은 주인은 지울 수 없음(세션 id 는 uuid 라 재사용 확인 안 됨) · DB LOW 되돌리기 `ALTER TABLE session_summary DROP COLUMN agent_id`(SQLite 3.35+, 이 컴퓨터 3.37.2) ·
  DB LOW CREATE 문 5곳 중복 · 회상 인덱스 · 코드 NOTE 요약 재주입은 기존 회상과 같은 프롬프트 주입 표면(별도 과제 후보).

## 8. 회고 (완료 시 작성) — 2026-09-28 목표 1~7 완료

- 잘된 것: 리뷰 네 번(planner-lite·architect-lite·code-reviewer·database-reviewer)이 각각 다른 층을 잡았다 — 생성 지점 5곳, 들여오기 REPLACE, 드리밍·lifecycle 누출, 동시 ALTER.
  실측 한 번(`@hag게이트` → 새 방에서 약속을 기억)으로 사용자 요구("어디서 대화하든 에이전트는 기억을 가져야") 를 직접 보였다.
- 잘못된 것: 처음 설계를 "배운 것 한 줄" 로 잡아 사용자의 원래 뜻(이미 있는 대화 요약을 에이전트 기억으로)을 놓쳤다 — 사용자 정정 뒤 C-29.
  §2-bis 에 "생성 지점 2곳" 을 grep 없이 적었다(실제 5곳). lifecycle 을 비목표로 뺀 판단이 틀렸다(리뷰가 잡음).
  시험 문장 "도구 없이 답해" 가 메인의 넘기기까지 막아 실측 한 번을 버렸다. 실측이 실제 에이전트 기억에 시험 약속을 남겨 지워야 했다.
- 다음 룰 후보: 계획서 §2-bis 의 "몇 곳" 은 grep 결과를 그대로 붙인다(R-precheck 강화) · 실측이 실제 기억·이력에 남는 경로면 끝에 지우는 단계를 계획에 적는다.
