# 2026-09-17-design-gaps-tier2 — 설계에 확정됐으나 코드가 없던 기능 보강 9건

> 작성일: 2026-09-17
> 목적: backlog `design-gaps-tier2.md` 의 9건(설계 문서 확정 문장 ↔ 코드 0건)을 설계 문장 그대로 구현한다.
> 선행: 계획 `design-coverage-gaps`(보안·계약 7건), 룰 `R-design-cover`(같은 유형의 재발 방지).

## 1. 동기 (Why)

- 설계 9개 문서 전수 대조(2026-09-17)에서 남은 9건. 보안·계약이 아니라 **기능 보강**이지만 전부 "(확정)"·"(합의)" 문장이다 — 설계가 약속한 동작을 코드가 안 하고 있다.
- 기준선 `.design-cover-baseline` 71건 중 이 9건과 겹치는 항목은 구현하며 계획서에 결정 ID/절을 인용해 기준선에서 뺀다.

## 2. 목표 (What — 검증 가능한 형태)

> 설계 결정 인용(2026-09-18 소급, R-design-cover): C-05 · C-19 — 이 계획의 목표가 구현한 원장 결정(docs/audits/2026-09-18-decision-id-mapping.md).

> 검증 명령: `bash tests/hermes-handoff-test.sh` · `bash tests/hermes-journal-test.sh` · `bash tests/hermes-memory-events-test.sh` · `bash tests/hermes-summon-guard-test.sh` · `bash tests/hermes-roster-test.sh` · `bash tests/hermes-skill-inject-test.sh` · `bash tests/run-all.sh`.

- [x] 목표 1 — **매칭 근거 기록**(`creation-and-organization.md:59`): `hermes-summon.py run` 이 축 값으로 매칭했으면 `task.assigned` 의 `decision` 에 `match=<축:값,…> chosen=<이름> among=<후보 수>` 를 남긴다(이름 지정이면 `match=by-name`). 검증: `bash tests/hermes-summon-guard-test.sh` — 매칭 소환 뒤 행의 decision 에 `match=` 와 `among=`.
- [x] 목표 2 — **출처 불명 표시**(`identity.md:198,209`): `hermes_journal_views.thread/graph` 의 각 행에 `origin` 칸 — `actor` 가 `agent:` 인데 같은 `task_id` 에 `task.assigned` 가 없으면 `unknown`, 있으면 `paired`, 사람·시스템은 `n/a`. 검증: `bash tests/hermes-journal-test.sh` — 짝 없는 agent 행 `unknown` 1, 짝 있는 행 `paired` 1.
- [x] 목표 3 — **전에 철회됨 표시**(`memory-events.md:119`): `current_memories` 가 각 기억에 `previously_retracted`(같은 `content_hash` 의 기억이 전에 `memory.retracted` 됐으면 그 철회 사유) 를 붙인다. 검증: `bash tests/hermes-memory-events-test.sh` — 철회 뒤 같은 본문을 다시 배우면 표시 1, 다른 본문은 없음.
- [x] 목표 4 — **만료 원인 판정**(`handoff-contract.md:79`): `check_expired` 가 `evidence.reason` 에 `expired:key-missing`(sync 설정은 있는데 이 컴퓨터에 열쇠 없음) · `expired:runner-dead`(그 봉투의 소환 pending 파일이 남아 있음) · `expired:unstarted`(둘 다 아님) 중 하나를 남긴다. 검증: `bash tests/hermes-handoff-test.sh` — 세 케이스 각 1.
- [x] 목표 5 — **2차 되묻기는 사람에게**(`handoff-contract.md:83`): 같은 봉투에 두 번째 `resolve(how="question")` 은 `handoff.question` 을 남기되 `decision=escalate=human` 을 붙이고, `hermes_journal_views.gaps` 가 그것을 `escalations` 로 돌려준다. 검증: 테스트 — 1차 되묻기 escalate 없음, 2차 있음, gaps 에 1건.
- [x] 목표 6 — **우선순위 대기열**(`handoff-contract.md:66`): `hermes_handoff.queue(db, agent)` 가 그 에이전트의 열린 봉투(assigned 이후 finished/declined/expired 없음)를 지시 → 협업 → 요청, 같은 종류는 `ts` 순으로 돌려준다. 검증: 테스트 — 요청·지시·협업 순으로 열고 queue 가 지시·협업·요청 순.
- [x] 목표 7 — **주입 순서**(`skill-layers.md:53`): `hermes-search.py` 의 최종 정렬이 층(개인 0 → 단위 1 → 소우주 공통 2 → 우주 공통 3)을 첫 키로, 점수를 둘째 키로 쓴다. 검증: `bash tests/hermes-skill-inject-test.sh` — 점수가 낮은 개인 스킬이 점수 높은 공통 스킬보다 앞.
- [x] 목표 8 — **담당 두지 않음 기억**(`creation-and-organization.md:95`): `hermes-agent.py no-owner --discipline … [--unit …]` 이 `decision` 이벤트(`intent=no-owner <축:값>`)를 남기고, `match` 가 같은 축 값에 그 기억이 있으면 `ask:` 대신 `no-owner: 이 영역은 담당을 두지 않기로 함(<날짜>)` 을 출력한다. 검증: `bash tests/hermes-roster-test.sh` — no-owner 뒤 match 출력 변화.
- [x] 목표 9 — **무인 세션 이월**(`creation-and-organization.md:103`): `hermes-summon.py run` 이 매칭 `ask:` 상태이고 `HERMES_HEADLESS=1`(러너·크론이 설정) 이면 `main` 을 소환하고 `decision` 이벤트 `intent=owner-proposal <축:값>` 을 남긴다; 세션 시작 훅 `claude-sessionstart-owner-proposals.sh` 가 답하지 않은 제안 수를 한 줄 알린다. 검증: `bash tests/hermes-summon-guard-test.sh` — HEADLESS 에서 main 소환·제안 1건, 훅이 "담당 없음 제안 1건" 출력.

## 3. 비목표 (Out of Scope)

- 확인 필요 3건(승격 이력 `universe_id`, 단일 사례 승격 차단, YAML 앵커). 기준선의 나머지 항목.

## 4. 영향 영역

- 수정: `scripts/hermes-summon.py`(목표 1·9), `scripts/hermes_journal_views.py`(2·5), `scripts/hermes_memory_conflicts.py`(3), `scripts/hermes_handoff.py`(4·5·6), `scripts/hermes-search.py`(7), `scripts/hermes-agent.py`(8), `assets/skills/hermes-agent/SKILL.md`(8·9 안내), `presets/workflow/hermes.conf`(훅 등록), `.design-cover-baseline`(해소 항목 제거), 테스트 6개.
- 신규: `scripts/hermes_handoff_queue.py`(열린 봉투 목록·우선순위 정렬만), `scripts/hermes_owner_memory.py`(담당 두지 않음·담당 없음 제안 기록/조회만), `assets/hooks/claude-sessionstart-owner-proposals.sh`(답하지 않은 제안 수 알림만).
- 전파: 스크립트·훅·스킬 → `update-all`.

## 5. 단계 (Steps)

### Step 1. 기록·표시 [Impl] — 목표 1·2·3·4
### Step 2. 행동 규칙 [Impl] — 목표 5·6·7
### Step 3. 매칭 기억·무인 이월 [Impl] — 목표 8·9
### Step 4. 기준선 정리·전파 [단순] — 해소 항목 기준선에서 제거, 회고, completed

각 Step: 테스트 먼저 빨강 → 구현 → 초록. 커밋은 사용자 지시.

## 6. 의사결정 로그

- 2026-09-17: **매칭 근거·제안·담당 두지 않음은 새 kind 가 아니라 기존 `decision`/`task.assigned` 의 `decision` 칸에 적는다.** 근거: kind 를 늘리면 DB 마이그레이션이 또 필요하고, 자유 글 칸은 이미 마스킹·길이 검사를 거친다. 손해: 조회가 `intent LIKE` 에 의존 — 접두어(`no-owner`·`owner-proposal`)를 상수로 고정.
- 2026-09-17: **만료 원인 세 값만.** 근거: 설계가 든 두 원인(열쇠 없음·러너 죽음) + 그 밖. 더 세분하면 근거 없는 분류가 된다.
- 2026-09-17: **주입 순서는 정렬 키 교체로.** 근거: 설계 §2 가 "층 순으로 넣는다" 이고 점수는 층 안에서만 의미. 손해: 점수 높은 공통 스킬이 뒤로 밀려 잘릴 수 있음 — 상한은 기존 그대로.

## 7. 발견·예외

- 2026-09-17 Step 1: 메모리 테스트에 붙인 기억이 뒤의 "단일 사례" 집계를 바꿔 기존 단언이 깨졌다 — 블록을 파일 끝으로 옮김. 소환 테스트도 같은 이유로 1절 끝으로 이동(모의 출력·카운트가 누적형).
- 2026-09-17 Step 2: `resolve()` 복잡도 12 → 반환 칸 계산을 `_return_fields` 로 분리. `hermes-search.py` 495줄 — R-size 500 직전. 다음 손질 때 층 판정을 떼어내야 한다.
- 2026-09-17 Step 3: 로케일에서 `grep -E '.*'` 가 한글을 못 건너 단언이 빨갰고, 그것을 확인하려다 `git checkout --` 로 미커밋 테스트 블록을 지웠다(오늘 두 번째 같은 실수, 계획 install-coexistence §7 교훈 위반). 재작성 5줄로 복구. 규칙: 미커밋 파일에 `checkout --`·`stash` 금지 — 임시 편집은 Edit 도구로 넣고 Edit 로 되돌린다.
- 2026-09-17 리뷰(code-reviewer, HIGH 1·MEDIUM 3·LOW 2, 전부 반영): HIGH — 대기열의 `to=` 부분 문자열이 `return_to=` 꼬리에 걸려 보낸 쪽 대기열에 남의 봉투가 뜸 → 정규식(`(?<!return_)\bto=`) + 재발 테스트 2건. MEDIUM — 층을 선별 키로 쓰면 `--max` 가 작을 때 공통 스킬이 0건 → 점수로 뽑고 층 순으로 넣도록 분리(`hermes_skill_layers.inject_order`, `--max 1` 테스트); 무인 폴백이 no-owner 답 뒤에도 제안을 계속 남김 → `no_owner_since` 확인; 조회 열쇠가 마스킹을 안 거쳐 축 값이 전화·메일 꼴이면 어긋남 → 조회도 `redact`. LOW — `with open`, 되묻기 봉투 재개 경로 전제를 주석으로. 이 과정에서 `hermes-search.py` 가 502줄이 되어 층 순서 로직을 `hermes_skill_layers.py` 로 옮김(492줄).
- 2026-09-17: 대기열이 받는 쪽을 알아야 해 봉투 기록에 `to=` 를 추가했다 — 이번 커밋 전 봉투는 `to=` 가 없어 대기열에 안 보인다(안전 방향).
- 2026-09-17: 이 9건의 설계 문장은 결정 ID 도 확정 절 제목도 아니라 `.design-cover-baseline` 은 줄지 않는다 — 기준선 해소는 설계 문서에 ID 를 붙이는 별도 작업.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 9건 전부 테스트 먼저(빨강 확인) → 구현 → 초록. 새 모듈 3개(대기열·담당 기억·제안 훅)는 각각 한 책임으로 분리해 기존 파일의 R-cx·R-size 를 안 건드렸다.
  - 새 kind 를 만들지 않고 `decision` 칸·접두어로 기록해 마이그레이션이 필요 없었다.
- 잘못된 것:
  - `git checkout --` 로 미커밋 작업을 지우는 실수를 같은 날 두 번 했다. 도구 습관 문제라 문서로는 안 잡힌다 — PreToolUse 훅으로 미커밋 파일에 대한 `checkout --`·`restore` 를 막는 것이 룰 후보.
  - 테스트 픽스처가 누적형(전역 카운트·모의 출력)이라 새 케이스를 중간에 끼우면 뒤가 깨진다. 새 케이스는 절 끝에 붙이거나 독립 픽스처를 쓴다.
- 다음 룰 후보: `R-no-discard` — 워킹트리에 미커밋 변경이 있는 파일에 `git checkout -- <file>` · `git restore <file>` · `git stash` 를 PreToolUse(Bash) 훅이 막는다(사용자 명시 시 `HERMES_ALLOW_DISCARD=1`). 근거: 09-17 세 번(reset --hard 1, checkout -- 2).
