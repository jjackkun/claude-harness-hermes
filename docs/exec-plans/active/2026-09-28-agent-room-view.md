# 2026-09-28-agent-room-view — 전체 명부와 "이 방" 구성원을 명령·UI 로 본다

> 출처: 사용자 요청 2026-09-28 "에이전트 명부를 전체 볼 수 있는 명령어와 이 방에서 볼 수 있는 명령어. 그리고 UI 로 추가할 수 있나?" → "진행하자"
> 앞 작업: `docs/exec-plans/completed/2026-09-28-agent-mention-bridge.md` (C-27) · 백로그 `auto-owner-summon.md` 목표 7(대화방)

## 1. 동기 (Why)

- `@agent-<slug>` 로 명부 에이전트를 부를 수 있게 됐지만(C-27), **누가 있는지·이 방에 누가 불렸는지 볼 길이 없다.**
  `hermes-agent.py list` 는 있으나 `@` 호출명(slug)·최근 활동이 없고, 방(세션) 단위 보기는 아예 없다.
- 사용자 결정(2026-09-28): 방은 1:1 이 아니라 최소 한 명, **몇 명이 있는지 보이는 기능·UI 가 있어야** 한다. 손님의 "방에 있다" = **이 방에서 불린 적 있음**.
- 데이터는 이미 쌓인다 — `journal_events` 에 `session_id` 칸이 있고, 이 세션(`372676a8…`)의 task 이벤트 47건이 조회된다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **전체 명부 명령.** `hermes-agent.py roster` 가 명부 전원을 이름 · `@`호출명 · 상태 · 분야/직급/조직 · 최근 불린 때(소환·`@` 모두, `task.finished` actor 기준)로 보인다. 은퇴자는 맨 아래.
      검증: 픽스처 명부(slug 있는 재직자·slug 없는 재직자·은퇴자) + 이력 → 표에 세 줄, 호출명 `@agent-<slug>` / `-`, 최근 시각이 이력 최댓값과 같음.
      ✅ 2026-09-28: 시험 §1 6건 · 실제 저장소 2명(게이트QA -, 백로그 관리자 10:37 현지)
- [x] 목표 2 — **이 방 명령.** `hermes-agent.py room --session <id>` 가 그 세션 이력에서
      ① 명부 에이전트를 이름·횟수·마지막 시각으로, ② 명부 밖 에이전트(`code-reviewer` 등)를 종류·횟수로, ③ 내부 보조 호출(`claude`)을 **건수 한 줄로** 보인다.
      `--line` 은 상태줄용 한 줄(`방: 백로그 관리자(2) · 도구 4 · 보조 40`), 불린 명부 에이전트가 없으면 `방: 명부 에이전트 없음`.
      검증: 두 세션이 섞인 픽스처 이력 → 다른 세션 이벤트는 안 셈 · 명부 id·slug 로 적힌 finished 모두 명부로 묶임 · `--line` 한 줄 · 세션 없음/DB 없음 rc 0.
      ✅ 2026-09-28: 시험 §2 11건(누계 19/19) · 이 방: 백로그 관리자 2회 · 도구 4 · 보조 39 · `--line` 45ms · 전체 111/111
- [ ] 목표 3 — **슬래시 명령 `/hermes-roster` · `/hermes-room`.** 스킬 본문의 `` !`…` `` 동적 주입으로 명령 결과가 그대로 들어간다
      (모델이 추측하지 않는다). `/hermes-room` 은 `${CLAUDE_SESSION_ID}` 로 현재 방을 넘긴다. `disable-model-invocation: true` — 사람이 칠 때만(“명부 보여줘” 자연어는 기존 hermes-agent 스킬 몫, 발동 겹침 방지).
      검증: 스킬 파일의 `!` 줄을 셸로 돌린 결과가 목표 1·2 출력과 같다 · 설치본에 스킬 2개 · 실제 세션에서 `/hermes-room` 이 이 방 구성원을 보임(사람 확인 1회).
- [ ] 목표 4 — **대시보드.** `/hermes-dashboard` 의 명부 표에 `@`호출명·최근 불린 때 칸.
      검증: 대시보드 시험 · 생성 HTML 에 `@agent-backlog-manager`.
- [ ] 목표 5 — **상태줄(사람 승인 뒤).** 사용자 전역 `~/.claude/statusline.sh` 끝에 `room --line` 한 줄을 **덧붙인다**(덮지 않음).
      상태줄 입력 JSON 의 `session_id`(statusline.md 197줄)를 넘긴다. 헤르메스가 없는 프로젝트에서는 아무것도 안 찍는다.
      검증: 기존 출력 줄 그대로 + 방 줄 · 헤르메스 없는 폴더에서 추가 출력 0 · 실행 시간 측정(상태줄은 300ms 로 묶이고 느리면 취소된다 — statusline.md 152줄).

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| 이력의 세션 칸 | `journal_events.session_id` 있음 · 이 세션 task 이벤트 47건 |
| 이 세션의 에이전트 | 명부 backlog-manager 2(`match=mention`) · code-reviewer 1 · claude-code-guide 2 · general-purpose 1 · `claude` 약 40 |
| `claude` 40건의 정체 | 세션 폴더 `subagents/` 대화 파일 6개 = 내가 Agent 도구로 부른 6건과 정확히 일치. `claude` 는 대화 파일이 없는 **내부 보조 호출** → 이름 없이 건수로 접는다 |
| 스킬 동적 주입 | skills.md: `` !`명령` `` 은 Claude Code 가 먼저 실행해 결과로 바꾼다 · `${CLAUDE_SESSION_ID}` 치환(로컬 세션) |
| 상태줄 입력 | statusline.md 197줄 `session_id` · 이벤트 구동 + 300ms 디바운스 · 느린 스크립트는 취소 |
| 기존 상태줄 | 사용자 전역 `~/.claude/settings.json` → `bash /home/jjackkun/.claude/statusline.sh`. 프로젝트 설정에는 없음 → 프로젝트 상태줄을 새로 두면 **덮는다** |
| `/agents` | Claude Code 기본 명령(파일 위치 안내) — 이름 겹침 피해 `hermes-` 접두어 |
| `hermes-agent.py` | 383줄 — 명령 본체는 새 모듈로 |

## 3. 비목표 (Out of Scope)

- 방 이름 붙이기·`--resume` 대화방 러너(`hermes-chat`) — 백로그 목표 7.
- 공통/개인 기억 층 덮어쓰기 — 백로그 목표 7.
- 내부 보조 호출(`claude`)의 출처 추적·억제 — Claude Code 내부 동작.
- 다른 프로젝트 전파 — 완료 뒤 별도.

## 4. 영향 영역

- 코드 (수정):
  - `scripts/hermes-agent.py` — `roster`·`room` 파서와 얇은 호출만.
  - `scripts/hermes_dashboard_data.py`(+ html) — 명부 표에 호출명·최근 불린 때.
  - `presets/workflow/hermes.conf` — 새 스크립트·스킬 등록.
  - `~/.claude/statusline.sh` (사용자 전역, **승인 뒤**) — 한 줄 덧붙임.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes_room.py` — 이력에서 명부 에이전트 활동(한 방의 구성원 · 모든 방에서 최근 불린 때)을 모은다.
  - `scripts/hermes_roster_view.py` — 명부 전원 표(이름·호출명·상태·조직·최근 불린 때)와 방 구성원을 글자(표·한 줄)로 그린다.
  - `assets/skills/hermes-roster/SKILL.md` — `/hermes-roster`: 전체 명부 명령 결과를 동적 주입으로 보인다.
  - `assets/skills/hermes-room/SKILL.md` — `/hermes-room`: 현재 세션의 방 구성원을 동적 주입으로 보인다.
  - `tests/hermes-agent-room-test.sh` — 목표 1~4 픽스처 시험.
- 룰: R-iface · R-declare · R-cx · R-dep(`.deprc` tier) · RV-06(읽기만 — 세션을 띄우지 않음).
- 데이터: 없음(읽기 전용).
- 외부 의존: 스킬 `!` 주입·`${CLAUDE_SESSION_ID}`(v2.1.228+ 문서), 상태줄 `session_id`.

## 5. 단계 (Steps)

### Step 1. 방·명부 모으기와 그리기 [Plan/Impl/Review]
- 산출: `hermes_room.py`, `hermes_roster_view.py`, `roster`·`room` 명령. 검증: 시험 먼저.

### Step 2. 슬래시 명령 스킬 2개 [Plan/Impl]
- skill-creator 절차를 따른다(CLAUDE.md "새 스킬 작업 시 필수"). 산출: 스킬 2개 + 설치 등록. 검증: `!` 줄 셸 실행 = 명령 출력.

### Step 3. 대시보드 칸 [Impl]
- 검증: 대시보드 시험 · 생성 HTML.

### Step 4. 상태줄 [사람 승인 → Impl]
- 바뀔 줄을 먼저 보이고 승인받는다. 검증: 기존 출력 보존 · 헤르메스 없는 폴더 무출력 · 실행 시간.

### Step 5. 사람 확인 + 마무리
- `/hermes-room`·상태줄을 사용자 화면에서 한 번. 회고 → `completed/`.

## 6. 의사결정 로그

- 2026-09-28: 시각은 이 컴퓨터 현지 시각으로 보인다(이력은 UTC 저장) — 근거: 첫 출력이 01:37(UTC)이라 한국 시각 10:37 과 어긋나 읽는 사람이 헷갈린다. 시험은 TZ=UTC 고정.
- 2026-09-28: `last_seen` 을 hermes_room.py 에 같이 둔다 — 근거: 둘 다 "이력에서 명부 에이전트 활동을 읽는다" 한 책임, 같은 SQL 헬퍼.

- 2026-09-28: 방 = 세션 id — 근거: 이력에 이미 있는 칸이고 "이 방에서 불린 적 있음"(사용자 결정)과 1:1. 이름 붙인 방은 목표 7(대화방) 몫.
- 2026-09-28: `claude` 내부 보조 호출은 이름 없이 건수 한 줄 — 근거: 대화 파일이 없는 호출 40건이 명부 에이전트를 덮는다. 사용자가 부른 것이 아니다.
- 2026-09-28: 상태줄은 기존 전역 스크립트에 덧붙인다 — 근거: 프로젝트 상태줄은 전역 것을 덮는다. 전역 파일이라 승인 뒤.
- 2026-09-28: 두 스킬은 `disable-model-invocation: true` — 근거: "명부 보여줘" 자연어는 hermes-agent 스킬이 이미 잡는다. 발동이 겹치면 둘 중 무엇이 불릴지 흐려진다.

## 7. 발견·예외

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
