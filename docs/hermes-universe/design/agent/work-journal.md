# 작업 이력 — 불변 이벤트, 결과 3층, 저장 2층

> 작성일: 2026-09-15
> 목적: 에이전트가 무엇을 어떻게 했고 성공·실패했는지 정확히 남겨, 스레드·그래프·문서화의 원천으로 삼는다.

## 개요

작업 한 건은 **같은 `task_id`를 가진 불변 이벤트들이 한 줄씩 쌓인 스레드**다. 결과는 에이전트의
주장 · 기계의 검증 · 사람의 수용으로 나눠 적는다. 원본은 로컬 DB에 즉시 기록하고, 코드 브랜치와
분리된 git 참조에 보존한다. 원문은 담지 않고, 자유 글 칸 세 개는 암호화한다.

## 1. 지금 있는 기록 (2026-09-15 실측)

| 기록 | 칸 | 한계 |
|---|---|---|
| `loop_steps` | `action_summary`, `verdict`, `objective_signal`, `progressed` | 헤르메스 루프 안에서만 쌓인다. 이 저장소에는 0행 |
| `loop_decisions` (`scripts/hermes_loop_decisions.py`, 진행 중) | `loop_id`, `iteration`, `kind`, `text` | 위와 같음. `hermes_loop_report.py` 가 이 테이블을 읽어 보고서를 만들므로 **유지**한다(2절 `decision` 참고) |
| `.harness/gate-events.jsonl` | `ts`, `rule`, `verdict`, `stage` | 게이트 장치의 관측 기록이지 작업 이력이 아니다. 따로 둔다 |

하네스는 이미 작업 결과를 `result:` / `failed:` / `needs input:`으로 표기한다. 이 어휘를 이어받는다.

## 2. 이벤트 종류 (합의, J-05 · RV-10 · H-03 · H-04 · RV-08)
| 이벤트 | 언제 |
|---|---|
| `task.assigned` | 누가(`requested_by`) 누구에게(`actor`) 일을 맡김 |
| `task.started` | 수행 시작 |
| `step` | 의미 있는 중간 행동(선택) |
| `decision` | `결정 — 이유 — 손해`. decision-ledger 는 **병기 후 단계적 흡수**(G-9): 루프 결정은 기존 `loop_decisions` 에도 그대로 남기고(`hermes_loop_report.py` 가 읽음) 같은 내용을 이 이벤트로도 기록한다. 완전 대체는 별도 계획 |
| `task.handoff` | 다른 에이전트에게 넘김 → 상대 쪽에 새 `task.assigned` |
| `task.finished` | 결과 |
| `correction` | 앞선 이벤트를 정정. 원래 이벤트는 고치지 않는다 |
| `tombstone` | 비상 삭제 표시(9절) |
| `handoff.declined` | 받는 쪽이 협업 · 요청을 사유와 함께 거절([handoff-contract.md](handoff-contract.md) 3절) |
| `handoff.question` | 봉투가 불충분해 되물음. 답이 올 때까지 시작하지 않음 |
| `handoff.expired` | 기한이 지났는데 `task.started` 도 `handoff.question` 도 없음. 세션 시작 훅이 남김 |
| `handoff.external` | 다른 소우주에 있는 일을 사람에게 문의([handoff-contract.md](handoff-contract.md) 4절) |

- `step` 은 **heartbeat** 로도 쓴다. 긴 작업은 120분(8절, 2026-09-16 실측 확정)마다 `step` 을 남겨 살아 있음을 보이고, 끊기면 8절의 누락 감지가 세션 종료를 기다리지 않고 잡는다. N 은 근거 있는 값이 없어 미정이다(cumora 는 60초 heartbeat · 90초 부재 판정).

## 3. 결과는 세 층 (합의, J-04 · RV-09)
| 층 | 칸 | 누가 | 값 |
|---|---|---|---|
| 주장 | `claimed` | 에이전트 | `success` / `failure` / `partial` / `blocked` / `abandoned` |
| 검증 | `verified` | 기계(`system:`) | 테스트 종료 코드·게이트 판정·커밋 존재 → `pass` / `fail` / `none`(검증 수단 없음) |
| 수용 | `accepted` | 사람(`human:`) | 나중에 받아들임 또는 되돌림 |

- 하네스 표기 대응: `result:` → `success`, `failed:` → `failure`, `needs input:` → `blocked`.
- 에이전트 입력으로 `verified` 를 넘기면 기록기가 무시하고 기계 값을 남긴다.

| `verified` 근거 (이번 범위) | 기계가 보는 것 |
|---|---|
| `exit_code` | 러너 · Bash 훅이 받은 종료 코드 |
| 커밋 존재 | `done_when` 의 `commit:<해시\|HEAD>` 가 저장소에 있는가 |
| 게이트 판정 | `.harness/gate-events.jsonl` 의 해당 규칙 결과 |

- `done_when` 이 `manual` 이면 `verified: none` 이 **정상**이다 — 사람이 재는 조건이라 기계가 잴 것이 없다. 봉투 없이 시작한 대화형 세션의 직접 작업도 같다. 허용 형식은 [handoff-contract.md](handoff-contract.md) 2절.
- **`claimed=success`인데 `verified=fail`인 줄이 가장 값진 기록이다.** 에이전트가 틀리게 판단한 지점이고, 에이전트 성적의 기준이 된다(G-12).

> ✅ 리뷰 확정 (2026-09-15, RV-09) — `verified: none` 은 에이전트가 고르는 값이 아니다 (근거: 리뷰 R-9, cumora K-1)
>
> `none` 을 에이전트가 쓸 수 있으면 검증 층이 무력해진다 — "검증 수단 없음" 이라고 적고 `success` 를 주장하면 된다. cumora 는 공짜 우회 플래그(`--send-anyway`)가 선제 사용으로 게이트를 없애는 것을 겪었고, 고친 방법은 "책임감 있게 쓰라" 는 프롬프트가 아니라 서버가 실제로 보여 준 상태에만 유효한 1회성 토큰이었다(`docs/COORDINATION.md` §5d).
>
> | 규칙 | 내용 |
> |---|---|
> | `none` 은 기계만 찍는다 | 봉투의 `done_when` 이 기계가 검증할 수 있는 형식(G-21: 테스트 이름 · 파일 존재 · 게이트 판정 · 커밋 존재)이 아닐 때만 |
> | `done_when` 없이 시작 불가 | 이미 확정(H-02). 따라서 `none` 은 "형식은 있으나 기계가 못 재는 경우" 로 좁혀진다 |
> | `none` 비율은 성적 | `none` 이 많은 에이전트 · 봉투 작성자는 검증 가능한 `done_when` 을 쓰지 않는다는 뜻이다. 보기에서 드러낸다 |

## 4. 칸 구성

```json
{
  "event_id": "<UUIDv7>",
  "ts": "<시각>",
  "kind": "task.finished",
  "universe_id": "<소우주 id>",
  "task_id": "<작업 id>",
  "parent_task_id": "<상위 작업 id 또는 null>",
  "caused_by": ["<원인 이벤트 id>"],
  "actor": "agent:<id>",
  "requested_by": "human:<id>",
  "claimed": "success",
  "verified": "fail",
  "accepted": null,
  "evidence": {"exit_code": 1, "commit": null, "files": ["<경로>"], "command": "pytest"},
  "intent": "<암호문>",
  "lesson": "<암호문>",
  "decision": "<암호문>"
}
```

### 확정 스키마 (`state.db`)

> ✅ **구현 완료 (2026-09-16, 계획 2 Step 3)** — 이 스키마는 `scripts/hermes_journal_schema.py`
> 의 `SCHEMA_SQL` 이 유일한 원천이고, 아래 블록은 그 사본이다. 인덱스 두 개
> (`journal_task_idx` · `journal_universe_idx`)가 추가됐다. 검증: `tests/hermes-journal-test.sh`.


```sql
CREATE TABLE IF NOT EXISTS journal_events (
  event_id        TEXT PRIMARY KEY,          -- UUIDv7
  ts              TEXT NOT NULL,             -- ISO-8601 UTC
  kind            TEXT NOT NULL CHECK (kind IN ('task.assigned','task.started','step','decision',
                                                'task.handoff','task.finished','correction','tombstone',
                                                'handoff.declined','handoff.question','handoff.expired','handoff.external')),
  universe_id     TEXT NOT NULL,
  task_id         TEXT NOT NULL,
  parent_task_id  TEXT,
  caused_by       TEXT,                      -- JSON 배열(event_id)
  actor           TEXT NOT NULL,             -- human:|agent:|system:
  requested_by    TEXT,
  session_id      TEXT,                      -- 참조만
  claimed         TEXT CHECK (claimed IN ('success','failure','partial','blocked','abandoned') OR claimed IS NULL),
  verified        TEXT CHECK (verified IN ('pass','fail','none') OR verified IS NULL),
  accepted        TEXT,
  evidence        TEXT,                      -- 허용목록 JSON: exit_code, commit, files[], command(이름만), bytes, template, usage, reason
  intent          TEXT, lesson TEXT, decision TEXT   -- 한 줄. 원격 사본만 암호화(7절)
);
CREATE TRIGGER IF NOT EXISTS journal_no_update BEFORE UPDATE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
CREATE TRIGGER IF NOT EXISTS journal_no_delete BEFORE DELETE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
```

- `kind` · `claimed` · `verified` 의 값 집합은 `CHECK` 로 DB 가 강제한다. 모르는 값은 INSERT 자체가 실패한다.
- `evidence` 는 허용목록 JSON 이다(5절). `usage` 는 헤드리스 러너 경로에서만 채워진다 — 훅 입력에 토큰 수가 오지 않는다(V-8 확인).
- `evidence.template` 은 하위 에이전트의 직무 템플릿 이름(`SubagentStop` 의 `agent_type`, V-4 확인).

### CLI

사람 대면 진입점은 `hermes-journal.py` 하나다.

| 명령 | 하는 일 |
|---|---|
| `emit` | 이벤트 한 건을 허용목록으로 검증해 INSERT (훅 · 러너가 부름) |
| `thread <task_id>` | 같은 `task_id` 의 이벤트를 시간순으로 |
| `graph` | `parent_task_id` · `caused_by` 간선 |
| `gap-check` | `task.started` 만 있고 `task.finished` 없는 작업 찾기(8절) |
| `mismatch` | `claimed=success` 인데 `verified=fail` 인 줄 목록 |

### 스레드와 그래프

- **스레드:** 같은 `task_id`의 이벤트를 시간순으로 나열한다.
- **그래프 간선:** `parent_task_id`(하위 작업), `task.handoff`(넘김), `caused_by`(이 실패 때문에 이 재시도가 생김).

### 기계 칸과 에이전트 칸

| 누가 쓰나 | 칸 |
|---|---|
| 기계 | `event_id`, `ts`, `kind`, `universe_id`, `actor`, `requested_by`, `verified`, `evidence` |
| 에이전트 | `claimed`, `intent`, `lesson`, `decision` |

> ✅ 리뷰 확정 (2026-09-15, RV-10) — heartbeat 는 확정(2절 · 8절 본문), `usage` 칸은 V-8 이 예일 때만 (근거: cumora K-9)
>
> - `evidence.usage`: `{input_tokens, output_tokens, cached_input_tokens, model}` — 기계 칸, 평문. cumora 는 클라우드·로컬을 가리지 않고 한 원장 `llm_calls` 에 적어 비교한다. 우리는 작업 단위로 붙이면 "이 작업에 얼마가 들었나" 가 스레드에서 바로 나온다. 백로그 `platform-cost-performance-levers` 의 실측 근거가 된다.
> - V-8 확인 결과(2026-09-15): Claude Code 훅 입력에 토큰 수는 **없다**. 그래서 `usage` 는 러너가 `claude -p --output-format json` 의 값을 받는 헤드리스 경로에서만 채운다. 대화형 비용은 실측 불가로 남는다.

## 5. 원문을 담지 않는 허용목록 스키마 (합의, J-06)
비밀값 유출이 반복된 원인은 원문을 통째로 기록한 뒤 걸러내는 구조였다([raw-transcript.md](../protection/raw-transcript.md)).
작업 이력은 **애초에 원문을 담을 칸을 두지 않는다.**

| 칸 | 담는 것 | 담지 않는 것 |
|---|---|---|
| `evidence` | 종료 코드, 바뀐 파일 경로, 커밋 해시, 바이트 수, **명령 이름만**(`pytest`) | 명령 인자 전체(예: 인증 헤더가 든 `curl` 인자), **출력 본문** |
| 대화 | `session_id` 참조만 | 사용자 입력과 응답 원문 |
| `intent`·`lesson`·`decision` | 에이전트가 쓴 한 줄 요약 | 줄바꿈, 원문 덩어리 붙여넣기 |

- **스키마 검증기가 모르는 칸은 거부한다.** 훅이 실수로 원문을 넘겨도 기록되지 않는다.
- 남는 위험은 자유 글 칸 세 개다. 여기에는 기존 방어(`.env` 값 대조, 형태 마스킹, 줄 길이 제한, 보존 전 스캐너)를 적용하고, 원격에는 암호화해 올린다(7절).

## 6. 저장 — 원본 단위와 두 층 (합의, J-03)
### 원본 단위는 이벤트 한 개

- 이벤트는 한 번 쓰면 바뀌지 않고, 시간순 정렬이 되는 고유 id(UUIDv7)를 가진다.
- 그래서 로컬 DB와 원격, 컴퓨터 A와 B의 기록을 합칠 때 **양쪽을 모으기만 하면 된다(합집합).** 어느 쪽이 맞는지 고를 일이 없어 병합 충돌이 없다.
- "에이전트별 파일이냐 작업별 파일이냐"는 질문은 사라진다. 둘 다 원본에서 뽑은 **보기**다.

### 두 층

```text
기록 순간                              세션 끝 (push 정책에 따라)
에이전트/훅 ──▶ ① state.db journal_events ──▶ ② 그 소우주 원격의 refs/hermes/sync
               - INSERT만 허용 (UPDATE·DELETE 트리거로 차단)   journal/<YYYY>/<MM>/<DD>/<event_id>.json
               - 기록 전 마스킹                              - 이벤트 1개 = 파일 1개
               - 동시 쓰기 안전 (WAL)                        - 작업 트리를 건드리지 않는 저수준 커밋
                     │
                     └──▶ 보기 (파생, 언제든 재생성): 에이전트별 이력 · 작업 스레드 · 그래프
```

### 구버전 DB 호환과 롤백 (확정, J-09)
| 상황 | 동작 |
|---|---|
| `journal_events` · `loops.started_by` 가 없는 기존 `state.db`(zeroday 포함) | 훅(Stop · SubagentStop · 세션 시작)은 죽지 않고 한 줄 알린 뒤 **exit 0**. 첫 실행 때 `CREATE TABLE IF NOT EXISTS` · `ALTER TABLE … ADD COLUMN` 으로 지연 생성한다(`hermes-search.py` 의 `_ensure_injection_source_column` 패턴). 기존 행은 건드리지 않는다 |
| 트리거가 기존 쓰기 경로를 막았을 때 | `hermes-journal.py rollback --confirm` — 테이블 · 트리거를 **지우지 않고** `journal_events_disabled_<ts>` 로 이름만 바꾼다. 이후 훅은 테이블 없음으로 보고 조용히 건너뛴다(exit 0). 이벤트는 보존되므로 되돌릴 수 있다 |

### 폐기된 안 — 작업 트리 안 jsonl을 원본으로

| 위험 | 설명 |
|---|---|
| 이력이 코드 브랜치에 묶임 | 실험 브랜치를 버리면 그 브랜치의 이력도 사라진다. **가장 값진 실패 기록이 먼저 지워진다** |
| 동시 쓰기 | 여러 훅이 같은 파일에 덧붙이면 줄이 섞이거나 반쯤 쓴 줄이 남는다 |
| git 충돌 | 두 브랜치·두 컴퓨터가 같은 파일 끝에 덧붙이면 충돌한다 |
| 커밋 소음 | 코드 커밋마다 이력 파일이 바뀌고 게이트에 걸린다 |
| 비밀값 | 코드 이력에 들어가면 코드 이력 전체를 재작성해야 지운다 |

## 7. 칸별 암호화 (확정, J-07 · T-13)
원격으로 올리는 이벤트는 칸 종류로 나눠 처리한다. **모든 소우주에 같은 규칙**을 적용한다.

| 칸 | 처리 | 이유 |
|---|---|---|
| `event_id`, `ts`, `kind`, `universe_id`, `task_id`, `parent_task_id`, `caused_by` | 평문 | 그래프 뼈대, 글이 없다 |
| `actor`, `requested_by` | 평문 | id만 있다 |
| `verified`, `evidence` | 평문 | 기계가 채운 값. 동료가 이미 코드·커밋에서 보는 정보 |
| `claimed` | 평문 | 정해진 단어 중 하나 |
| **`intent`, `lesson`, `decision`** | **암호화** | 자유 글이라 고객사·업무 맥락 같은 의미상 민감한 내용이 들어갈 수 있다 |

- **내용을 탐지해 고르는 선택 암호화와 다르다.** 칸 종류가 스키마에 고정되어 있어 탐지가 없고, 놓칠 것도 없다.
- 함께 쓰는 저장소의 동료는 "누가 언제 무슨 작업을 했고 성공·실패했는가"라는 뼈대만 볼 수 있다. 이유와 교훈은 볼 수 없다. 교훈을 나누고 싶으면 공개본처럼 사람이 골라 승인한다.
- 혼자 쓰는 저장소에도 같은 규칙을 적용한다. 나중에 공유하게 됐을 때 과거 이력이 평문으로 남아 있지 않게 하기 위해서다.
- 암호화 방식과 열쇠는 [encryption-keys.md](../protection/encryption-keys.md).

## 8. 누락 감지 (합의, J-08)
세션이 끝났는데 `task.started`만 있고 `task.finished`가 없으면, Stop 훅이 `actor: system:claude-stop-journal-gap`,
`claimed: null`, `verified: none`인 "기록 누락" 이벤트를 붙인다. 적히지 않은 작업이 조용히 사라지지 않게 한다.

| 감지 시점 | 조건 | 누가 |
|---|---|---|
| 세션 종료 | `task.started` 있음 · `task.finished` 없음 | Stop 훅 (`hermes-journal.py gap-check`) |
| 세션 도중 (heartbeat) | `task.started` 뒤 N분마다 오던 `step` 이 끊김 | 다음 훅 실행 시 `gap-check` — 세션 종료를 기다리지 않는다 |

- heartbeat 간격 N = **120분** (2026-09-16 실측으로 확정, 계획 2 Step 5).
  근거: zeroday-frontend 의 `loop_steps` 9구간에서 중앙 5.7분 · 정상 최대 13.4분 ·
  이상치 1건 79.7분(사람이 자리를 비운 구간). "끊겼다" 고 부르려면 정상 구간을 넘어야 하므로
  관측 최대의 1.5배로 잡았다. 표본이 9구간뿐이라 소우주마다 `.hermes/journal.json` 의
  `heartbeat_minutes` 로 바꾼다. 표본이 쌓이면 다시 잰다.
- 두 감지는 명령이 다르다: 세션 종료는 `gap-check --all`(간격 무관, 사유 `session-end`),
  heartbeat 는 `gap-check`(간격 초과만, 사유 `heartbeat-timeout`). 플래그를 잘못 쓰면
  진행 중인 작업이 버려진 것으로 기록된다.

## 9. 보존 규칙

- **로테이션·truncate 금지.** 작업 이력은 원본이다. 결정화 스킬 `rotate-ephemeral-work-logs`("jsonl 로그는 로테이션한다")에서 명시적으로 제외한다(G-10).
  ✅ 2026-09-16 반영: 스킬 본문에 제외 문장을 넣고, `hermes-cleanup.py` 실행 후 이력이 남는 것을 실측했다(1건 → 1건).
- **비상 삭제:** 비밀값이 새어 들어간 경우에만 쓴다.
  1. `tombstone` 이벤트를 남긴다.
  2. 사람(`human:`)이 AI 세션 **밖**에서 `hermes-sync.py tombstone` 을 실행한다. 이 명령은 로컬 트리거를 잠시 내려 해당 이벤트를 지우고, 원격 조각을 물리적으로 지운 뒤 `refs/hermes/sync` 만 재작성한다. 코드 이력은 건드리지 않는다.
  - `hermes-sync.py tombstone` 은 열쇠 가드(`hermes-keys.sh init|emergency`)와 **같은 차단 목록**에 있어 AI 세션 안 Bash 에서는 부를 수 없다(G-5 닫힘). 급할 때 세션 밖으로 나가야 하는 것은 의도된 마찰이다.
