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
| `loop_decisions` (`scripts/hermes_loop_decisions.py`, 진행 중) | `loop_id`, `iteration`, `kind`, `text` | 위와 같음 |
| `.harness/gate-events.jsonl` | `ts`, `rule`, `verdict`, `stage` | 게이트 장치의 관측 기록이지 작업 이력이 아니다. 따로 둔다 |

하네스는 이미 작업 결과를 `result:` / `failed:` / `needs input:`으로 표기한다. 이 어휘를 이어받는다.

## 2. 이벤트 종류 (합의)

| 이벤트 | 언제 |
|---|---|
| `task.assigned` | 누가(`requested_by`) 누구에게(`actor`) 일을 맡김 |
| `task.started` | 수행 시작 |
| `step` | 의미 있는 중간 행동(선택) |
| `decision` | `결정 — 이유 — 손해`. **decision-ledger를 이 이벤트로 흡수한다**(G-9) |
| `task.handoff` | 다른 에이전트에게 넘김 → 상대 쪽에 새 `task.assigned` |
| `task.finished` | 결과 |
| `correction` | 앞선 이벤트를 정정. 원래 이벤트는 고치지 않는다 |
| `tombstone` | 비상 삭제 표시(6절) |

## 3. 결과는 세 층 (합의)

| 층 | 칸 | 누가 | 값 |
|---|---|---|---|
| 주장 | `claimed` | 에이전트 | `success` / `failure` / `partial` / `blocked` / `abandoned` |
| 검증 | `verified` | 기계(`system:`) | 테스트 종료 코드·게이트 판정·커밋 존재 → `pass` / `fail` / `none`(검증 수단 없음) |
| 수용 | `accepted` | 사람(`human:`) | 나중에 받아들임 또는 되돌림 |

- 하네스 표기 대응: `result:` → `success`, `failed:` → `failure`, `needs input:` → `blocked`.
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

### 스레드와 그래프

- **스레드:** 같은 `task_id`의 이벤트를 시간순으로 나열한다.
- **그래프 간선:** `parent_task_id`(하위 작업), `task.handoff`(넘김), `caused_by`(이 실패 때문에 이 재시도가 생김).

### 기계 칸과 에이전트 칸

| 누가 쓰나 | 칸 |
|---|---|
| 기계 | `event_id`, `ts`, `kind`, `universe_id`, `actor`, `requested_by`, `verified`, `evidence` |
| 에이전트 | `claimed`, `intent`, `lesson`, `decision` |

> ✅ 리뷰 확정 (2026-09-15, RV-10) — heartbeat 는 확정, `usage` 칸은 V-8(훅 입력에 토큰 수가 오는가)이 예일 때만 (근거: cumora K-9)
>
> - `evidence.usage`: `{input_tokens, output_tokens, cached_input_tokens, model}` — 기계 칸, 평문. cumora 는 클라우드·로컬을 가리지 않고 한 원장 `llm_calls` 에 적어 비교한다. 우리는 작업 단위로 붙이면 "이 작업에 얼마가 들었나" 가 스레드에서 바로 나온다. 백로그 `platform-cost-performance-levers` 의 실측 근거가 된다. Claude Code 훅 입력에 토큰 수가 오는지는 V-4 와 함께 확인한다.
> - `step` 을 **heartbeat** 로도 쓴다: 긴 작업은 N분마다 `step` 을 남겨 살아 있음을 보인다. `task.started` 뒤 heartbeat 가 끊기면 8절의 누락 감지가 세션 종료를 기다리지 않고 잡는다. cumora 의 run 은 60초마다 heartbeat 를 보내고 90초 없으면 오프라인으로 본다.

## 5. 원문을 담지 않는 허용목록 스키마 (합의)

비밀값 유출이 반복된 원인은 원문을 통째로 기록한 뒤 걸러내는 구조였다([raw-transcript.md](../protection/raw-transcript.md)).
작업 이력은 **애초에 원문을 담을 칸을 두지 않는다.**

| 칸 | 담는 것 | 담지 않는 것 |
|---|---|---|
| `evidence` | 종료 코드, 바뀐 파일 경로, 커밋 해시, 바이트 수, **명령 이름만**(`pytest`) | 명령 인자 전체(예: 인증 헤더가 든 `curl` 인자), **출력 본문** |
| 대화 | `session_id` 참조만 | 사용자 입력과 응답 원문 |
| `intent`·`lesson`·`decision` | 에이전트가 쓴 한 줄 요약 | 줄바꿈, 원문 덩어리 붙여넣기 |

- **스키마 검증기가 모르는 칸은 거부한다.** 훅이 실수로 원문을 넘겨도 기록되지 않는다.
- 남는 위험은 자유 글 칸 세 개다. 여기에는 기존 방어(`.env` 값 대조, 형태 마스킹, 줄 길이 제한, 보존 전 스캐너)를 적용하고, 원격에는 암호화해 올린다(7절).

## 6. 저장 — 원본 단위와 두 층 (합의)

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

### 폐기된 안 — 작업 트리 안 jsonl을 원본으로

| 위험 | 설명 |
|---|---|
| 이력이 코드 브랜치에 묶임 | 실험 브랜치를 버리면 그 브랜치의 이력도 사라진다. **가장 값진 실패 기록이 먼저 지워진다** |
| 동시 쓰기 | 여러 훅이 같은 파일에 덧붙이면 줄이 섞이거나 반쯤 쓴 줄이 남는다 |
| git 충돌 | 두 브랜치·두 컴퓨터가 같은 파일 끝에 덧붙이면 충돌한다 |
| 커밋 소음 | 코드 커밋마다 이력 파일이 바뀌고 게이트에 걸린다 |
| 비밀값 | 코드 이력에 들어가면 코드 이력 전체를 재작성해야 지운다 |

## 7. 칸별 암호화 (확정)

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

## 8. 누락 감지 (합의)

세션이 끝났는데 `task.started`만 있고 `task.finished`가 없으면, 훅이 `actor: system:<훅 이름>`,
`claimed: null`, `verified: none`인 "기록 누락" 이벤트를 붙인다. 적히지 않은 작업이 조용히 사라지지 않게 한다.

## 9. 보존 규칙

- **로테이션·truncate 금지.** 작업 이력은 원본이다. 결정화 스킬 `rotate-ephemeral-work-logs`("jsonl 로그는 로테이션한다")에서 명시적으로 제외한다(G-10).
- **비상 삭제:** 비밀값이 새어 들어간 경우에만 쓴다.
  1. `tombstone` 이벤트를 남긴다.
  2. 사람(`human:`) 승인을 받아 해당 파일을 물리적으로 지우고 `refs/hermes/sync`만 재작성한다. 코드 이력은 건드리지 않는다.
  - 세부 절차는 G-5.
