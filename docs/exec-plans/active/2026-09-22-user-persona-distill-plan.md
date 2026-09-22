# 2026-09-22-user-persona-distill — 대화 기록에서 사용자 성향을 뽑아 승인된 것만 주입한다

> 출처: OpenHuman(`tinyhumansai/openhuman` HEAD `1ff90dcd`) 정독 — `vendor/tinymemory/vendor/tinycortex/src/memory/persona/`,
> `crates/openhuman-core/src/agent/learning/stability_detector.rs`. 코드는 GPL-3.0 이라 **옮기지 않고 방식만 참고한다.**
> 사용자 결정(2026-09-22): "좋은 기능으로 보여 가져오자."

## 1. 동기 (Why)

- 문서는 `~/.hermes/global.db` 가 "공통 패턴 + **사용자 성향**" 을 담는다고 말한다(`CLAUDE.md` 헤르메스 절, `docs/design-docs/hermes-engineering.md:95`).
  **코드에는 없다.** `global.db` 에는 프로젝트 DB 와 같은 표만 있고 성향 표가 없으며, `scripts/` 에 `persona`·`preference`·`성향` 을 다루는 코드가 0건이다(2026-09-22 확인).
- 지금 사용자 성향은 사람이 손으로 쓴 `~/.claude/CLAUDE.md` 와 Claude Code 고유 메모리(`feedback-*.md`)에만 있다.
  대화 중 반복되는 교정("폼 질문 연발 금지", "끝난 작업은 묻지 말고 커밋")은 사람이 "기억해" 라고 말해야만 남는다.
- 헤르메스 결정화는 **작업 패턴**(`pattern_count`)을 센다. **사람에 대한 관찰**은 세지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 명령: `bash tests/hermes-persona-source-test.sh` + `python3 scripts/hermes-persona.py distill` 두 번.
   `hermes-persona.py distill` 이 `~/.claude/projects/*/*.jsonl` 의 **사용자 발화만** 증분으로 읽어,
  관찰을 7개 면(말투 · 코딩 스타일 · 기술 스택 · 작업 방식 · 환경 · 지시 · 싫어하는 것)으로 `global.db` 에 쌓는다.
  검증: 실제 대화 기록 1개 프로젝트로 돌려 관찰 ≥ 1, 두 번째 실행에서 새로 읽는 줄 0.
- [x] 목표 2 — 명령: `bash tests/hermes-persona-store-test.sh`.
   관찰마다 **근거 인용**과 **신뢰 등급**(t0 명시 지시 · t1 교정/중단 · t2 습관)이 붙는다. 인용 없는 관찰은 저장을 거부한다.
  검증: 인용 빈 관찰을 넣는 시험이 거부로 끝난다.
- [x] 목표 3 — 명령: `bash tests/hermes-persona-score-test.sh`.
   안정성 점수 `Σ 등급가중 · exp(-Δt/반감기) · ln(1+n)` 로 후보/활성을 가른다. 가중·반감기·문턱은 이름 붙은 상수와 근거 주석으로 둔다.
  검증: 같은 관찰이 오래전 1회면 후보에 머물고, 최근 여러 세션에서 반복되면 후보에 오르는 시험.
- [ ] 목표 4 — 명령: `bash tests/hermes-persona-inject-test.sh`.
   **사람이 승인했거나 자동 활성 기준(t0 + 2세션)을 넘은 관찰만** SessionStart 에 주입한다. 후보는 `hermes-persona.py review` 로 보여 주고 `approve`/`reject` 로 정한다.
  검증: 승인 0건이면 주입 출력이 비어 있고, 승인 1건이면 그 문장만 나온다.
- [ ] 목표 5 — 명령: `bash tests/hermes-persona-extract-test.sh`.
   LLM 에 보내기 전 `hermes_redact.py` 로 마스킹하고, 성향 표는 `refs/hermes/sync` 로 **올라가지 않는다.**
  검증: 전화번호가 든 발화가 추출 입력에서 `[REDACTED:PHONE]` 으로 바뀌는 시험, sync 대상 표 목록에 성향 표가 없다는 시험.

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| `global.db` 표 목록 | compaction_log · dream_log · harness_rules · loop_steps · loops · messages · pattern_count · pattern_session · recall_marker · session_history(FTS) · session_reuse · session_summary · skill_index · skill_injection — **성향 표 없음** |
| `scripts/` 의 persona/preference/성향 코드 | 0건 |
| 대화 기록 일괄 읽기 선례 | `scripts/edit_factcheck_rate.py:30,110` 이 `~/.claude/projects/*/*.jsonl` 을 glob 으로 읽는다 |
| 마스킹 | `scripts/hermes_redact.py` 존재(전화·주소·계좌·토큰) |
| 주입 선례·상한 | 에이전트 SOUL 주입이 4096B 상한(`scripts/hooks/claude-sessionstart-agent-soul.sh`) |
| LLM 경로 | R3 — `anthropic` SDK 금지, `claude -p` 구독 CLI 만 |

## 3. 비목표 (Out of Scope)

- `~/.claude/CLAUDE.md` 나 Claude Code 메모리 파일을 **자동으로 고치지 않는다.** 승인된 성향을 그쪽으로 옮기는 것은 사람이 한다.
- 에이전트별 성향(에이전트 SOUL 자동 수정)은 하지 않는다 — 사용자 한 사람의 성향만.
- 결정화 키워드 품질(`backlog/crystallize-stability-score.md`)은 별개 작업.
- 도구 출력·어시스턴트 발화는 읽지 않는다. 사람의 말만.

## 4. 영향 영역

- 코드: `scripts/` 신규 모듈, `scripts/hooks/` SessionStart 훅 1개, `.claude/settings.json` 훅 등록, `assets/` 복사본.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes_persona_source.py` — 대화 기록에서 사용자 발화만 파일·줄 위치 워터마크로 증분 추출한다.
  - `scripts/hermes_persona_extract.py` — 마스킹한 발화 묶음을 `claude -p`(haiku)에 보내 7면 관찰 JSON 으로 받는다.
  - `scripts/hermes_persona_score.py` — 관찰 반복 이력으로 안정성 점수와 등급(후보/활성/퇴출)을 계산한다.
  - `scripts/hermes_persona_store.py` — `global.db` 의 성향 표 읽기·쓰기와 스키마 자가수리.
  - `scripts/hermes-persona.py` — CLI: `distill` · `review` · `approve` · `reject` · `render`. (`distill` 은 Step 2 에서 먼저 — 목표 1 검증에 필요)
  - `scripts/hooks/claude-sessionstart-persona.sh` — 승인된 관찰만 상한 안에서 주입한다.
  - `tests/hermes-persona-{source,store,score,extract,inject}-test.sh` — 위 모듈별 시험(저장소 관례: bash + `tests/run-all.sh` 등록).
- 룰: R3(LLM 경로), R-iface(새 파일 공개 심볼 8 미만), R-declare(이 §4 가 선언).
- 데이터: `global.db` 에 새 표 2개(`persona_observation`, `persona_source_watermark`). 기존 표 변경 없음 — `CREATE TABLE IF NOT EXISTS`.
- 외부 의존: 없음(표준 라이브러리 + `claude` CLI).

## 5. 단계 (Steps)

### Step 1. 발화 추출 + 워터마크 [Impl] — ✅ 2026-09-22 (`18cfaa5`)
- 산출: `hermes_persona_source.py`, `hermes_persona_store.py`(워터마크 표만).
- 검증: 실제 대화 기록 한 개 프로젝트로 추출 → 두 번째 실행 신규 0. `<task-notification>`·`Another Claude session` 같은 기계 메시지 제외 시험.

### Step 2. 관찰 추출 [Plan/Impl/Review] — ✅ 2026-09-22 (공장 기록: 발화 985 → 관찰 68 · 키 29 · 반복 키 18)
- 산출: `hermes_persona_extract.py` — 프롬프트는 "근거 인용 없이는 관찰을 만들지 말 것, 등급 t0/t1/t2 판정 기준" 을 담는다.
- 검증: 마스킹 시험, JSON 형식 어긋남 시 그 묶음만 버리고 오류를 stderr 로 남기는 시험.

### Step 3. 점수·등급 [Impl] — ✅ 2026-09-22 (공장 실데이터 키 29 → 자동 활성 7 · 질문 8 · 쌓기만 14 · 자동 병합 1쌍)
- 산출: `hermes_persona_score.py`. 상수 초깃값은 OpenHuman 값(활성 1.5 · 후보 0.7 · 퇴출 0.4, 명시 지시 2배)을 출발점으로 두고 근거 주석에 출처를 적는다.
- 검증: 목표 3 시험. 실측 뒤 조정하면 §6 에 기록.

### Step 4. 검토·승인 CLI + 주입 훅 [Impl/Review]
- 산출: `hermes-persona.py`, `claude-sessionstart-persona.sh`, 설정 등록.
- 검증: 목표 4 시험. 실제 세션 1회에서 주입 확인.

### Step 5. 문서 정합
- `CLAUDE.md`·`hermes-engineering.md` 의 "사용자 성향" 문구를 실제 구현에 맞춘다. 소우주 전파 여부는 완료 뒤 따로 정한다.

## 6. 의사결정 로그

- 2026-09-22: 추론 관찰은 승인 전 주입하지 않는다 — 근거: OpenHuman 도 추론 성향을 사실로 넣던 방식을 버리고 "사용자에게 제안만" 으로 바꿨다(`session_host/turn/context.rs`). 틀린 성향이 매 세션 박히면 되돌리기 어렵다.
- 2026-09-22: 성향 표는 기억 운반(sync)에서 뺀다 — 근거: 사람에 대한 서술은 작업 기억보다 민감하다. 여러 컴퓨터에서 쓰려면 잠금 모드로 따로 정한다.
- 2026-09-22: 코드는 옮기지 않는다 — 근거: GPL-3.0.
- 2026-09-22: 사람 발화 판정은 `entrypoint == "cli"` + 기계 접두어 목록 — 근거: §7 실측(sdk-cli 전부 한 턴 기계 프롬프트). `/compact` 같은 사람이 친 명령은 남긴다(성향 추출 단계에서 무시된다).
- 2026-09-22: 시험은 pytest 가 아니라 저장소 관례대로 `tests/*-test.sh` + `run-all.sh` 등록.
- 2026-09-22: 모델이 준 인용이 그 발화 안에 **글자 그대로** 있어야 관찰로 받는다 — 근거: 지어낸 성향 차단. 변이 시험(대조 삭제 → 시험 2개 실패)으로 확인.
- 2026-09-22: LLM 실패는 `None`, 성향 없음은 `[]` 로 구분하고 실패한 묶음부터 워터마크를 멈춘다 — 근거: 둘을 합치면 실패한 발화가 다시 안 읽혀 조용히 사라진다.
- 2026-09-22: `distill` 기본 대상은 현재 프로젝트 기록만, `--all-projects` 로 넓힌다 — 근거: 사용자 결정 "우리가 테스트 해야하니 우리 프로젝트".
- 2026-09-22: **스스로 정할 수 있는 것은 묻지 않는다** (사용자: "추론으로 또는 스스로도 가능한 것들을 모두 사용자에게 물으면 안 된다").
  실측(키 29개) 기준 세 갈래 — 정한 것은 기록에 남기고 `reject` 로 되돌린다:
  - 합치기: 키 접두어 일치 또는 유사도 ≥ 0.8 → **자동 병합** · 0.6~0.8 → 승인 때 질문 · < 0.6 → 별개. 근거: 실측 쌍 0.86(1쌍) 과 ≤ 0.50(나머지) 사이의 틈.
  - 활성화: 사람이 직접 말한 지시(t0)가 있고 2세션 이상 → **자동 활성**(세션 시작에 "자동 활성 N건" 한 줄) · 추론만(t1·t2) → 승인 때 한 번에 묶어 질문 · 1세션뿐 → 묻지 않고 쌓기만.
  - 이 기준으로 첫 승인에서 물을 것은 29개 중 6개, 합치기 질문 0건.
- 2026-09-22: 상한은 요약기와 같게(haiku · 60초 · 묶음 6,000자), 발화 하나는 500자 — 근거: 사람 발화 p90 89자(실측), 긴 것은 붙여 넣은 글.

## 7. 발견·예외

- **60초로는 모자랐다** (2026-09-22): 요약기에서 가져온 60초 제한에 파일 3개가 걸렸다. 발화 53개(프롬프트 4,961자) 묶음이 90.4초·79.1초 → 180초로(최댓값×2). 실패한 파일은 워터마크가 멈춰 있어 다시 돌리니 이어서 읽혔다(설계대로).
- **rc=0 인데 해석 실패** 1/2 — 모델이 JSON 앞뒤에 설명을 붙였다. 첫 `[` ~ 마지막 `]` 재시도로 받는다.
- **실패 로그에 프롬프트가 통째로 찍혔다** — `TimeoutExpired` 문자열에 명령 인자가 실린다. 종류만 남기게 고쳤다(시험 있음).
- **키가 갈라진다**: `clarification-seeking` 과 `clarification-seeking-direct` 처럼 같은 성향이 다른 키로 쌓인다. Step 3 점수 전에 합치기(사람 검토에서 병합 또는 문장 유사도) 필요.

- **대화 기록의 98% 는 사람이 아니다** (2026-09-22 실측): `~/.claude/projects/*/*.jsonl` 5,006개 중 `entrypoint=sdk-cli` 4,895개는 전부 한 턴짜리 기계 프롬프트다
  (요약기 3,771 · 결정화 881 · 드리밍 69 · 스킬 진화 65 · PRD 작성 등). 사람 대화는 `entrypoint=cli` 108개. → 추출은 `cli` 기록만 읽는다.

- 문서의 "global.db 사용자 성향" 은 구현된 적이 없다 — Step 5 에서 바로잡는다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
