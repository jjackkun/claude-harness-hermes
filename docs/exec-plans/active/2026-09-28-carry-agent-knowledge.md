# 2026-09-28-carry-agent-knowledge — 에이전트 지식이 컴퓨터를 따라가게 한다

> 근거: `docs/exec-plans/backlog/not-carried-by-git.md` 1~8번(사용자 결정 2026-09-28). 이 계획이 착수되면 백로그 문서는 이 계획으로 대신한다.

## 1. 동기 (Why)

- 명부 에이전트를 다른 컴퓨터에서 부르면 SOUL·스킬은 따라가지만 **배운 것·나와 나눈 대화·인계 대기는 모른다.** 이것들이 `state.db` 에만 있고, 옮기는 길인 기억 운반은 공개 저장소에서 꺼진다(T-18). 이 공장도 공개라 꺼져 있다(`sync.json` `"push": false`).
- 대화 요약·기억에 **누구와의 대화인지** 칸이 없어, 팀원이 같은 에이전트와 이야기하면 섞인다.
- 대화 원문을 DB·파일에 쌓지만 읽는 곳 셋이 모두 전문 검색이고, 대신할 것이 이미 있다. 파일(`.hermes/history/`)은 매 턴 다시 써지지만 어디에도 가지 않는다.
- 커밋하면 공개 저장소에서는 누구나 본다. 마스킹은 비밀값 **형태**만 가리고 "개인적·업무 무관" **내용**은 못 거른다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — **사람 칸.** 대화 요약(`session_summary`)에 `person`(요약 때 git `user.name`, 없으면 `unknown`)이 붙고, 에이전트를 부를 때 "나와 나눈 최근 대화" 에는 **부른 사람과 같은 `person`** 의 요약만 들어간다. 검증: `bash tests/hermes-carry-knowledge-test.sh` §1 — person 이 다른 요약 두 개를 넣고 주입 본문에 한쪽만 나온다.
- [ ] 목표 2 — **올리기 전 묻기(판정).** 요약 haiku 호출이 요약과 함께 "개인적 · 업무 무관" 문장을 돌려준다(호출 수 그대로). 걸린 문장·판정 실패는 **검토 대기**로 DB 에 남고 파일로 나가지 않는다. 검증: `bash tests/hermes-privacy-review-test.sh` §1·2 — 걸린 문장은 대기 표에, 판정 실패면 새 내용 전체가 대기. 파일에 없음은 `bash tests/hermes-carry-knowledge-test.sh`.
- [ ] 목표 3 — **묻기(사람).** 확인 명령이 대기 문장을 하나씩 보이고 "지움/둠" 을 받는다. 지움 → 파일로 안 나감(기억은 `memory.retracted` 추가), 둠 → 내보내고 다시 안 묻는다. 검증: `bash tests/hermes-privacy-review-test.sh` §3 — 두 선택 각각의 결과.
- [ ] 목표 4 — **기억 파일(1번).** `memory_events` 가 `.hermes/agents/<id>/memory.jsonl`(추가만)로 나가고, 받은 컴퓨터는 세션 시작 때 없는 줄을 DB 에 넣고(`memory_id` 중복 제거) `MEMORY.md` 를 다시 만든다. 검증: `bash tests/hermes-carry-knowledge-test.sh` §2 — A 가 내보낸 기억을 B 가 들이고 MEMORY.md 가 생긴다.
- [ ] 목표 5 — **대화 요약 파일(2번).** 에이전트 요약(`agent_id` 있음)이 `.hermes/agents/<id>/conversations/<person>/<session_id>.json`(5칸 요약만)으로 나가고 받은 쪽이 들인다. 검증: `bash tests/hermes-carry-knowledge-test.sh` §2 — B 가 게이트QA 를 부르면 A 에서 나눈 대화를 안다.
- [ ] 목표 6 — **작업 이력 파일(3번).** 고르는 규칙 함수 하나가 `task.assigned` · `decision` · `agent.created` · 교훈 줄 · 명부 에이전트 호출 `task.finished` · 올린 인계의 `_CLOSING` 4종만 `.hermes/journal.jsonl` 로 낸다. 검증: `bash tests/hermes-carry-knowledge-test.sh` §2 — B 의 인계 대기가 비어 있고 보조 호출 줄이 파일에 없다.
- [ ] 목표 7 — **git 설정.** 설치기가 `.gitignore` 에 `!.hermes/agents/*/memory.jsonl` · `!.hermes/agents/*/conversations/` · `…/**` · `!.hermes/journal.jsonl` 을 풀고, `.gitattributes` 에 두 jsonl 의 `merge=union` 을 둔다. 검증: `git check-ignore -v` 로 세 경로가 무시되지 않음, 두 브랜치가 같은 jsonl 끝에 줄을 더해 병합이 충돌 없이 양쪽 줄을 갖는 시험.
- [ ] 목표 8 — **R-privacy 게이트.** 스테이징된 에이전트 파일·journal·스킬에 검토 대기가 남아 있으면 pre-commit 이 막고 확인 명령을 알린다. 검증: 대기 1건으로 커밋 차단, 0건이면 통과. 게이트 발화가 `gate-events.jsonl` 에 남는다.
- [ ] 목표 9 — **운반 무조건 켬(4번).** 설치기가 공개·비공개 구분 없이 `sync.json` 을 `push: true` 로 만든다. 지금은 파일이 있으면 손대지 않아(`lib/sync_autoenable.sh:58`) 기존 공개 소우주에 닿지 않으므로, **설치기가 정한 값(`"set_by": "installer"`, `push: false`)만** 켜고 그 소우주 이름을 설치 로그에 한 줄씩 알린다. `set_by` 가 없거나 다른 값(사람이 쓴 값)은 보존한다. 공통 요약·패턴 수가 운반으로 가고 공통 요약도 묻기 검사를 거친다. 에이전트 기억·요약·이력은 git 파일이 원본이고 운반의 `memory/`·에이전트 `summary/`·`journal/` 조각은 걷는다. 검증: ① 공개 가짜 저장소 새 설치 → `push: true` ② 설치기가 쓴 `push: false` 가 있는 저장소 재설치 → `push: true` + 로그 한 줄 ③ 사람이 쓴 `push: false` 재설치 → 그대로 ④ push 한 조각 목록에 `memory/`·`journal/` 가 없음.
- [ ] 목표 10 — **원문 저장 안 함(5번).** `session_history` 쓰기·`.hermes/history/` 내보내기를 멈추고, 패턴 인정은 `pattern_session`, 결정화 증거는 요약(공통)·기억(개인), `/hermes-recall 키워드` 는 요약 검색, 실수 신호는 새 신호 표로 옮긴다. 생애주기 원문 압축·재색인·원문 문지르기·중복 세션 압축·잠금 모드 `"history"` 옵션을 걷는다. 검증: 한 세션을 돌린 뒤 `session_history` 행이 늘지 않고 `.hermes/history/` 가 생기지 않음, 패턴이 2세션에서 인정되고 결정화 증거가 비지 않는 시험.
- [ ] 목표 11 — **공장 스킬 커밋(8번).** 공장 `.gitignore` 에서 `.hermes/skills/` 되무시 줄을 지운다(`history/` 줄은 목표 10 뒤 필요 없으면 함께). 검증: `git check-ignore -v .hermes/skills/<파일>` 출력 없음, 설치기가 `.hermes/skills/` 를 복사하지 않음(grep 0건 유지).
- [ ] 목표 12 — **문서·결정.** 원장에 새 결정(A-10 고침 · C-29 보완(person) · T-17 닫음(원문) · T-18 고침(운반 무조건) · 공장 스킬)을 남기고, `docs/hermes-sync-guide.md` 표와 `raw-transcript.md` §3 을 고친다. 검증: 안내서 표가 목표 4~11 결과와 일치(읽기 대조 리뷰).

## 2-bis. 착수 전 확인한 사실 (2026-09-28)

| 확인한 것 | 결과 |
| --------- | ---- |
| `session_summary` 칸 | `session_id · project_id · slots_json · last_msg_count · turn_count · updated_at · agent_id` — 사람 칸 없음 |
| `memory_events` 칸 | 사람 칸 없음, 추가만(UPDATE 트리거 ABORT, `hermes_memory_events.py:34`) |
| `journal_events` | 635줄 — `task.finished` 623(명부 에이전트 6), `task.assigned` 10, `decision` 1, `agent.created` 1. `requested_by` 있음 |
| 인계 대기 닫힘 종류 | `_CLOSING` = `task.finished · handoff.declined · handoff.expired · handoff.question` (`hermes_handoff_queue.py:15`) |
| `.gitignore` 가 막는 경로 | `.hermes/agents/*/*`(54행)가 `conversations/` 를, `.hermes/*`(46행)가 `journal.jsonl` 을 막음 — `git check-ignore -v` |
| `.gitignore` 예외 목록 원본 | `presets/workflow/hermes.conf` (설치기 마커 블록 `lib/harness_installers.sh:623`) |
| `.gitattributes` | 이 저장소에 없음 |
| 운반 켜짐 판정 | `lib/sync_autoenable.sh` (공개면 꺼짐) |
| 원문 | `session_history` 3,003줄·24세션, `.hermes/history/` 25개·4.5MB. 요약기는 원문을 안 읽음(`hermes-summarize.py:60`, transcript 직접) |
| 원문을 읽는 곳 | `hermes-recall.py:180` · `hermes_crystallize_evidence.py:47` · `hermes_save_session_patterns.py:148` (모두 FTS5 `MATCH`) |
| 원문에 쓰는 곳 | `hermes_save_session_storage.py` · `hermes_save_session_signals.py:147` · `hermes-reindex.py` · `hermes_lifecycle_apply.py` |
| 대신할 표 | `pattern_session` 1,016행·563키 (`hermes_save_session_storage.py:138`) |
| 공장 스킬 | `.hermes/skills/` 43개, `.gitignore:73` 이 되무시. 설치기는 `.hermes/skills/` 를 복사 안 함(grep 0건) |
| 소우주 스킬 추적 | zeroday-frontend `.claude/skills/` 305/314 · `.hermes/skills/` 1,090/1,101 |

## 3. 비목표 (Out of Scope)

- 방·세션(`--resume`)과 `@hag` 상태·캐시는 올리지 않는다(백로그 6·7번).
- 이미 쌓인 원문(DB `session_history`, `.hermes/history/`)과 과거 운반 조각을 **지우지 않는다** — 삭제는 사람이 정한다.
- `@hag` 상태 파일 정리, 패턴 수 동시 증가분 합산(max 한계)은 따로.
- 전파(`update-all`)는 하지 않는다 — 공장에서 시험까지. 전파는 사용자 지시 때.
- "나만 보기"(사람별 읽기 권한)는 하지 않는다 — `person` 은 이름표이고 저장소를 읽는 사람은 다 본다(T-18 선).

## 4. 영향 영역

- 코드(수정): `scripts/hermes-summarize.py`(판정·person) · `scripts/hermes_summary_owner.py` · `scripts/hermes_agent_summaries.py`(person 거르기) · `scripts/hermes_memory_events.py`(내보내기 훅) · `scripts/hermes_save_session_storage.py` · `scripts/hermes_save_session_patterns.py` · `scripts/hermes_save_session_signals.py` · `scripts/hermes_crystallize_evidence.py` · `scripts/hermes-recall.py` · `scripts/hermes-lifecycle.py` · `scripts/hermes_lifecycle_apply.py` · `scripts/hermes-sync.py` · `scripts/hermes_sync_fragments.py` · `scripts/hermes_sync_learning.py` · `lib/sync_autoenable.sh` · `lib/harness_installers.sh`(`.gitattributes`·게이트 설치) · `presets/workflow/hermes.conf` · `assets/hooks/pre-commit.sh` · 훅 `claude-stop-retrospective.sh`(export 호출 제거) · `.gitignore`(공장).
- 코드(걷기): `scripts/hermes-export-history.py` · `scripts/hermes-reindex.py` · `scripts/hermes-scrub-history.py` · `scripts/hermes_history_fragments.py` · `assets/hooks/claude-sessionstart-history-reindex.sh`(+`scripts/hooks/` 사본) · `hermes-cleanup.py` (c).
- **신규 파일 목록**:
  - `scripts/hermes_memory_file.py` — 기억 이벤트를 에이전트 폴더 `memory.jsonl` 로 내보내고 들인다.
  - `scripts/hermes_conversation_file.py` — 에이전트 대화 요약을 `conversations/<person>/<session>.json` 으로 내보내고 들인다.
  - `scripts/hermes_journal_file.py` — 작업 이력에서 올릴 줄을 고르고 `.hermes/journal.jsonl` 로 내보내고 들인다.
  - `scripts/hermes-knowledge-files.py` — 세션 끝 내보내기(판정 → 세 파일)와 세션 시작 들이기(세 파일 → DB, MEMORY.md)를 순서대로 부른다.
  - `scripts/hermes_jsonl_lock.py` — 추가만 하는 jsonl 에 새 줄을 잠근 채(잠근 뒤 다시 읽어) 붙인다.
  - `scripts/hermes_privacy_pending.py` — 검토 대기 문장과 사람의 결정(지움/둠)을 DB 에 적고 읽는다.
  - `scripts/hermes_privacy_judge.py` — 요약 호출을 거치지 않는 문장(기억·이력 교훈·스킬)을 haiku 한 번으로 묶어 판정해 적는다.
  - `scripts/hermes-privacy-review.py` — 검토 대기를 하나씩 보이고 지움/둠을 받는 확인 명령.
  - `assets/hooks/check-privacy.py` — R-privacy: 스테이징된 파일에 검토 대기가 있으면 커밋을 막는다.
  - `scripts/hermes_signal_store.py` — 실수 신호를 원문 표 대신 신호 표에 적고 읽는다.
  - `scripts/hermes_person.py` — 이 컴퓨터의 사람 이름표(git `user.name`)를 한 곳에서 돌려준다(`hermes-sync.py:53 _person` 을 옮김).
  - 시험: `tests/hermes-carry-knowledge-test.sh` · `tests/hermes-privacy-review-test.sh` · `tests/hermes-no-raw-test.sh`.
- 룰: R3(판정은 구독 CLI 요약 호출에 얹음) · 새 게이트 R-privacy(차단).
- 데이터: `session_summary.person` 칸 추가(기존 행 NULL), 검토 대기 표·신호 표 신설. `session_history` 는 쓰기만 멈추고 표는 남긴다(삭제는 비목표).
- 외부 의존: 없음. 받는 쪽이 옛 버전이면 새 파일을 무시할 뿐이다.

## 5. 단계 (Steps)

순서는 **되돌리기 쉬운 것 → 어려운 것.** 원문 걷기(Step 8)는 대신할 길이 모두 초록인 뒤에.

### Step 1. 사람 칸 [Impl] — 목표 1
- 입력: `hermes-sync.py:53 _person`, C-29 주입(`hermes_agent_summaries.py`).
- 산출: `hermes_person.py`, `session_summary.person` 마이그레이션, 주입 거르기.
- 검증: 목표 1 시험. 기억(`memory_events`)에 person 을 둘지 여기서 정해 §6 에 적는다.

### Step 2. 판정·검토 대기 [Plan/Impl/Review] — 목표 2
- 입력: 요약 프롬프트 `SUMMARY_PROMPT`(`hermes-summarize.py:127`)와 호출·파싱 `generate_slots`(같은 파일 160-187).
- 산출: 응답 형식에 표시 칸 추가, `hermes_privacy_pending.py`, 판정 실패 → 전체 대기.
- 검증: 목표 2 시험. 요약 품질이 떨어지지 않는지 실제 세션 1개로 전후 비교(§6 에 기록).

### Step 3. 확인 명령 [Impl] — 목표 3
- 산출: `hermes-privacy-review.py`. 세션 안에서는 선택지로 묻는 쓰는 법을 스킬 문서에 한 줄.
- 검증: 목표 3 시험.

### Step 4. 세 파일 내보내기·들이기 [Impl/Review] — 목표 4·5·6
- 산출: `hermes_memory_file.py` · `hermes_conversation_file.py` · `hermes_journal_file.py`. 내보내기는 세션 종료 훅, 들이기는 세션 시작 훅. 모두 검토 대기를 거른 뒤에만 쓴다.
- 검증: 목표 4·5·6 시험(두 임시 저장소).

### Step 5. R-privacy 게이트 [Impl] — 목표 8
- 산출: `check-privacy.py`, `pre-commit.sh` 연결, 게이트 개수 문서 갱신(`sync-doc-counts.sh`).
- 검증: 목표 8 시험.
- 순서 이유: `.gitignore` 예외(Step 6)를 풀기 **전에** 게이트를 세워, 파일이 커밋될 수 있게 되는 순간부터 막는 장치가 있게 한다.

### Step 6. git 설정 [Impl] — 목표 7
- 산출: `hermes.conf` 예외 줄, 설치기의 `.gitattributes` 마커 블록.
- 검증: 목표 7 시험(check-ignore · union 병합).

### Step 7. 운반 무조건 켬·겹침 걷기 [Plan/Impl/Review] — 목표 9
- 산출: `sync_autoenable.sh` 공개 판정 제거, 운반 조각에서 `memory/`·에이전트 `summary/`·`journal/` 제외, 공통 요약에 묻기 검사.
- 검증: 목표 9 시험. 이미 켜진 소우주(비공개)의 운반이 계속 도는지 기존 `hermes-sync-test` 초록.

### Step 8. 원문 걷기 [Plan/Impl/Review] — 목표 10
- 순서: ① 신호 표·`pattern_session` 세기·요약 증거·요약 회상으로 **먼저 바꾸고 시험 초록** ② 그다음 쓰기·내보내기 멈춤 ③ 걷을 파일 제거.
- 검증: 목표 10 시험, 결정화 시험 묶음 초록.

### Step 9. 공장 스킬 [단순] — 목표 11
- 산출: 공장 `.gitignore` 줄 제거. 스킬 43개 커밋은 R-privacy 를 거친다.
- 검증: 목표 11.

### Step 10. 문서·결정·전체 시험 [Review] — 목표 12
- 산출: 원장 결정 5건, 안내서·설계 문서 갱신, 백로그 문서를 이 계획 링크로 대체.
- 검증: 전체 시험 **한 번**(마지막), 안내서 표 대조 리뷰.

## 6. 의사결정 로그

- 2026-09-28: 기억(`memory_events`)에는 사람 칸을 두지 않는다 — 근거: 기억은 그 에이전트가 배운 것이라 누가 불러도 쓴다. 사람별로 가를 것은 "누구와 나눈 대화"(요약)뿐.
- 2026-09-28: 주입은 `person = 부른 사람 OR person IS NULL` — 근거: 칸이 생기기 전 요약은 모두 그 컴퓨터(한 사람)에서 쌓였다. 칸이 없는 옛 DB 는 읽기 전용이라 칸을 못 더하므로 옛 조회로 물러선다.
- 2026-09-28: 이미 붙은 person 은 바꾸지 않는다(`COALESCE(기존, 새)`) — 근거: 대화를 나눈 사람은 처음 요약한 사람이다. 운반으로 받을 때는 받은 값을 우선(보낸 쪽이 원본).
- 2026-09-28: 내보내기는 판정을 통과한 문장(clean·keep)만 — 근거: "대기가 아니면 허용" 이면 기능 이전에 쌓인 요약·스킬이 판정 없이 나간다. 요약의 새 항목은 걸리지 않으면 clean 으로 적어 다시 판정하지 않는다.
- 2026-09-28: 요약 flagged 는 정규화 비교, 짝이 하나라도 안 맞으면 새 항목 전부 대기 — 근거: 리뷰(code-reviewer) HIGH, 모델이 표시한 문장이 글자 차이로 빠져나간다.
- 2026-09-28: 확인 명령은 해시로만 고른다 — 근거: 리뷰 MEDIUM, 번호는 다른 프로세스가 대기를 더하면 바뀐다.
- 2026-09-28: 판정 묶음은 6,000자 — 근거: 요약 호출의 델타 상한과 같은 값. 기능 이전 요약·스킬을 처음 판정할 때 수백 문장이 한 번에 몰린다.
- 2026-09-28: 들이기는 세션 시작 운반 훅(sync-pull)의 맨 앞에서 — 근거: 새 훅을 더하면 설정 생성·훅 개수가 함께 바뀐다. 운반과 무관하게 먼저 돈다.
- 2026-09-28: 이력의 intent(사람이 준 작업 지시 원문)도 판정한다 — 근거: 리뷰(code-reviewer) HIGH, `hermes-summon.py:97` 이 지시문을 그대로 적는다.
- 2026-09-28: 받은 파일의 agent_id·사람이 폴더와 다르면 버리고, 경로에는 안전한 id 만 — 근거: 리뷰 MEDIUM, git 으로 온 값이 경로가 된다.
- 2026-09-28: jsonl 붙이기는 잠근 뒤 다시 읽고 붙인다 — 근거: 리뷰 MEDIUM, 두 Stop 훅이 같은 줄을 두 번 쓴다. fcntl 없는 Windows 는 잠금 없이(들이기가 id 로 거른다).
- 2026-09-28: 백로그 1~8번 방침을 그대로 목표로 옮김 — 근거: 사용자 결정(백로그 문서 각 절).
- 2026-09-28: 기존 `sync.json` 은 설치기가 쓴 값만 켠다 — 근거: 지금 설치기는 파일이 있으면 손대지 않아 "무조건 켬" 이 기존 공개 소우주에 닿지 않는다(`sync_autoenable.sh:58`). 사람이 쓴 값은 사람의 결정이라 보존. 리뷰(planner-lite)의 "조용히 켜짐" 우려는 로그 한 줄로 알려 막는다.
- 2026-09-28: R-privacy 게이트를 `.gitignore` 예외보다 먼저 세운다 — 근거: 리뷰(planner-lite) 순서 지적.
- 2026-09-28: 에이전트 파일(기억·요약·이력)이 원본, 운반의 같은 조각은 걷는다 — 근거: 두 길로 같은 표를 나르면 한쪽이 낡은 사본이 된다(architect-lite 리뷰), 운반이 무조건 켜져도 git 파일이 더 단순.

## 7. 발견·예외

- 운반의 패턴 수는 키별 max 로 합쳐 동시 증가분이 사라진다(`hermes_sync_learning.py:142`) — 이 계획 밖.
- `.hermes/hag/<세션>.json` 이 끝난 세션 것까지 쌓인다 — 이 계획 밖.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
