# 헤르메스 러닝 루프 노드 실행 원장 — 조용한 실패가 방치되는 결함과 수정 설계

> 작성일: 2026-08-12
> 트리거: [그래프 엔지니어링 적용 여부 감사](../../audits/2026-08-12-graph-engineering-gap.md) 중 발견.
> 소비 프로젝트(zeroday-frontend)에서 export 노드가 **135회 연속 실패한 채 방치**된 것을 실측.
> 성격: **프리셋(claude-harness-hermes) 결함.** 소비 프로젝트가 고칠 수 없다 —
> `claude-stop-retrospective.sh` 는 프리셋이 배포하는 파일이라 로컬 수정은 재설치 시 소실된다.
> 상태: 🟡 계획
>
> 구조는 `docs/exec-plans/template.md` 를 따른다. 실행 계획은
> [plans/2026-08-12-hermes-pipeline-ledger-phase1.md](../plans/2026-08-12-hermes-pipeline-ledger-phase1.md).

---

## 1. 동기 (Why)

세션 종료 시 도는 러닝 루프(`assets/hooks/claude-stop-retrospective.sh`)는 7개 노드를
`setsid` 백그라운드로 순차 실행한다. **어느 노드가 죽어도 파이프라인은 성공한 것처럼 끝난다.**

### 관측된 사실

| # | 사실 | 확인 방법 |
|---|---|---|
| 1 | 7개 노드 전부 `... \|\| true` 로 끝난다 | `grep -c "\|\| true"` → 9 |
| 2 | 노드 간 전달이 **stdout 문자열 grep** 이다 | 훅 80·90행 (`grep "^\[hermes\] CRYSTALLIZE:"`) |
| 3 | `head -1`·`head -2` 로 **말없이 자른다** | 훅 80·90행 |
| 4 | 노드 실행을 기록하는 테이블이 **없다** | 선언 테이블 13개(`hermes-init.py` 11 + `hermes_loop.py` 2) 중 0개 |
| 5 | `hermes_init()` 은 정의만 있고 **호출부가 없다** | `grep -rn "hermes_init" --include=*.sh` → 정의 1건뿐 |

### 실측 — zeroday-frontend 운영 데이터

`.hermes/state.db` 59MB · `session_history` 27,343행 · `hooks.log` 39,841줄.

**① 절단이 실제로 발생한다.** 실제 세션(905 메시지)을 `save-session` 에 통과시키자:

```
[hermes] CRYSTALLIZE:zd-kos-004,hermes-dream
[hermes] EVOLVE:버전|...
[hermes] EVOLVE:eslint|...
[hermes] EVOLVE:prettier|...      ← head -2 에 잘려 사라짐. 로그 없음
```

**② 실패가 방치된다.** 별도 탐지기(`history-reindex` 훅)가 잡아낸 `lagging` 139건을
세션별로 분해하면:

| 같은 세션이 지목된 횟수 | 세션 수 | 해석 |
|---|---|---|
| 1회 | 14 | 다음 사이클에 자가 치유 — **일시적 경합** |
| 2~3회 | 5 | 지연 회복 |
| 8회 | 1 | 회복 지연 |
| **135회** | **1** (`fcd65acc…`) | **영구 고착** |

135회 동안 시스템은 **똑같은 안내 문구를 `hooks.log` 에 반복 출력했을 뿐** 재시도도
에스컬레이션도 하지 않았다. 게다가 그 안내는 `_log()` 로 **파일에만** 나갔다 — 사람 눈에
닿는 경로가 아니다.

### 근본 원인 — 세 겹

| 겹 | 장치 | 왜 뚫렸나 |
|---|---|---|
| 1 | 노드 경계 | 계약이 없다. 종료코드가 `\|\| true` 로 지워진다 |
| 2 | 기록 | 실패가 **실패로 기록된 적이 없다.** 관측할 대상 자체가 생성되지 않는다 |
| 3 | 행동 | 기록이 자유텍스트 로그라 **질의도 자동 행동도 불가능**하다 |

### 핵심 판단

> **관측은 로그를 남기는 것이 아니라, 기계가 질의해 행동할 수 있는 기록을 남기는 것이다.**
>
> 135회 사례는 탐지가 없어서 생긴 게 아니다. 탐지는 매번 정확했다. **탐지 결과가
> 문장이라 아무 일도 일어나지 않았을 뿐이다.** 기록에 SQL 을 걸어 재시도·알림이
> 자동으로 나가지 않으면, 그것은 관측이 아니라 로그를 하나 더 늘린 것이다.

이 결함은 이미 이 저장소 안에 해답이 있다. **루프 레이어는 `loop_steps` 테이블로 반복마다
`verdict`·`objective_signal`·`progressed` 를 남긴다.** 같은 것을 러닝 루프 파이프라인에
적용하는 것이 이 설계다.

---

## 2. 목표 (What — 검증 가능한 형태)

- [ ] **G1. 노드 실행 원장** — `pipeline_run` 테이블에 노드마다 1행(`run_id`·`node`·`status`·
      `reason`·`duration_ms`). 검증: 훅 1회 실행 후 노드 수만큼 행이 쌓임
- [ ] **G2. 실패가 실패로 남는다** — `|| true` 제거. 비정상 종료코드·타임아웃이
      `status='fail'` + `reason` 으로 기록된다. **단 파이프라인은 계속 진행한다**(비차단 유지).
      검증: 노드 하나를 강제 실패시키고 나머지 노드가 전부 `ok` 로 남는지
- [ ] **G3. 절단이 기록된다** — `head` 로 버려진 항목이 `status='truncated'` + `dropped=N`
      으로 남는다. 검증: EVOLVE 3줄 입력 → `dropped=1` 기록
- [ ] **G4. 연속 실패 에스컬레이션** — 같은 `node` 가 임계 회수 연속 `fail` 이면
      **SessionStart stdout(컨텍스트 주입)** 으로 1회 노출된다. 검증: 실패를 임계+1회 주입 →
      다음 세션 시작에 경고 블록 출력, 그다음 세션엔 재출력 안 됨(중복 억제)
- [ ] **G5. 설치 스크립트 변경 없이 전파** — 기존 11개 프로젝트의 DB 에 `pipeline_run` 이
      **첫 훅 실행 때 자동 생성**된다. 검증: 기존 DB 복사본에 훅 1회 → 테이블 생성 확인
- [ ] **G6. 회귀 테스트** — 위 전부 `tests/hermes-pipeline-ledger-test.sh` 로 고정,
      `tests/run-all.sh` 에 등록

---

## 3. 비목표 (Out of Scope)

- **병렬 실행** — 감사 문서 §4 참조. Stop 훅은 `setsid` 비차단이라 **아무도 기다리지 않는다.**
  65초→24초의 이득이 사용자에게 도달하지 않는다. 오히려 `skill_index` 를 4개 노드가 동시에
  쓰게 되어 디버깅 비용만 는다. 1·2순위를 마친 뒤에도 느리면 재검토한다.
- **상태 파일 계약 · 부분 리플레이** — `runs/<run-id>/*.json` 으로 노드 입출력을 보관해
  실패 노드만 재실행하는 것. **Phase 2.** 이 계획은 "무슨 일이 있었나"까지만 다루고
  "그걸 다시 흘려보낸다"는 다루지 않는다.
- **docs 갱신 엣지** — 결정화 산출물을 `docs/` 로 밀어 넣는 학습 엣지. **별건.**
  근거: 원장이 먼저 있어야 학습 엣지가 얼마나 새는지 측정된다. 측정 없이 엣지를 늘리면
  같은 방식으로 조용히 샌다.
- **사람 승인 노드** — 러닝 루프가 백그라운드 비차단이라는 설계 전제와 충돌한다.
  `status='blocked'` 를 남기고 다음 세션에 알리는 비동기 승인이 이 시스템에 맞다(G4 가 그 씨앗).
- **`hermes_init()` 죽은 함수 정리** — 발견했으나 이 계획의 범위가 아니다. §7 발견 3.

---

## 4. 영향 영역

### 수정

- `assets/hooks/claude-stop-retrospective.sh` — 7개 노드를 원장 래퍼로 감싼다.
  `|| true` → `|| _node_fail`. 절단 지점에 `dropped` 계산 추가
- `tests/run-all.sh` — 신규 테스트 등록

### 신규 파일 (파일별 책임 1줄)

- `scripts/hermes_pipeline_ledger.py` — **파이프라인 노드 1건의 실행 결과를 원장에 기록하고
  연속 실패 여부를 판정하는 책임만.** 스키마 자가치유·기록·에스컬레이션 질의를 담당하고,
  파이프라인의 흐름 제어는 하지 않는다
- `assets/hooks/claude-sessionstart-pipeline-alert.sh` — **원장을 질의해 연속 실패를
  세션 컨텍스트에 1회 노출하는 책임만**
- `tests/hermes-pipeline-ledger-test.sh` — **원장이 실패·절단·에스컬레이션을 실제로
  잡는지 고정하는 책임만**

### 룰

- 없음. 다만 §7 발견 2가 `core-beliefs.md` 승격 후보다.

### 데이터

**신규 테이블 `pipeline_run`.** 마이그레이션 스크립트는 만들지 않는다 —
이 저장소의 스키마 전파 방식이 **lazy self-heal** 이기 때문이다(§7 발견 3).

```sql
CREATE TABLE IF NOT EXISTS pipeline_run (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id      TEXT NOT NULL,       -- 훅 1회 실행 = run 1개 (세션 id + 타임스탬프)
  session_id  TEXT,
  node        TEXT NOT NULL,       -- save-session | summarize | crystallize | ...
  status      TEXT NOT NULL,       -- ok | fail | skip | truncated
  reason      TEXT,                -- 종료코드 · timeout · dropped=N 등
  dropped     INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER,
  created_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_pipeline_run_node_time
  ON pipeline_run (node, created_at DESC);
```

`loops`/`loop_steps` 와 동일한 설계라 새 개념이 아니다. 인덱스는 G4 의 "최근 N건 연속 실패"
질의를 위한 것이다.

**보존 정책**: `hermes-cleanup.py` 대상에 포함한다 — 원장이 무한히 자라면 안 된다.

### 외부 의존

- 없음. 표준 라이브러리 + 기존 `hermes_loop.connect_db` (WAL·`busy_timeout`) 재사용.

### 전파

| 대상 | 경로 | 자동 여부 |
|---|---|---|
| 훅 스크립트 | `assets/hooks/*` → `project-claude.sh`(`install_harness_hooks`) → 프로젝트 | `update-all.sh` 1회로 **11개 자동** |
| `pipeline_run` 스키마 | 첫 훅 실행 시 `CREATE TABLE IF NOT EXISTS` | **자동** (설치 변경 불필요) |

> ⚠️ **`hermes-init.py` 를 고쳐도 기존 프로젝트에 퍼지지 않는다.** `hermes_init()` 호출부가
> 없기 때문이다(§1 사실 5). 반드시 lazy self-heal 로 만들 것.

---

## 5. 단계 (Steps)

### Step 1. 원장 모듈 — `hermes_pipeline_ledger.py` [Impl]

- 산출:
  - `ensure_schema(db_path)` — `CREATE TABLE IF NOT EXISTS` (멱등)
  - `record(db_path, run_id, session_id, node, status, reason, dropped, duration_ms)`
  - `consecutive_failures(db_path, node) -> int` — 최근 실행부터 거슬러 연속 `fail` 수
- 규칙:
  - `connect_db` 는 `hermes_loop` 것을 재사용 (WAL + `busy_timeout=5000`)
  - `reason` 은 `redact()` 경유 — 저장 경계 마스킹 관례(G12)
  - **기록 실패가 파이프라인을 죽이면 안 된다.** 모든 예외를 삼키되 stderr 로 남긴다
- 검증: 단위 테스트. 같은 노드 3회 fail → `consecutive_failures == 3`, 이후 ok 1회 → 0

### Step 2. Stop 훅 배선 [Impl]

- 각 노드를 `_run_node <name> <cmd...>` 로 감싼다. 이 함수가:
  1. 시작 시각 기록 → 실행 → 종료코드·경과시간 수집
  2. `timeout` 종료코드 124 는 `reason=timeout` 으로 구분
  3. `record(...)` 호출
  4. **항상 0 으로 돌아온다** — 비차단 유지 (`|| true` 의 의도는 보존, 기록만 추가)
- `run_id` 는 훅 진입 시 1회 생성해 전 노드가 공유
- ⚠️ 회귀 주의: 훅은 `setsid` 백그라운드다. 원장 기록이 느리면 전체가 느려진다 —
  기록은 노드당 INSERT 1건으로 제한한다

### Step 3. 절단 기록 [Impl]

- `head -1`(crystallize) · `head -2`(evolve) 지점에서 **전체 개수와 채택 개수를 함께 센다**
- 차이가 0 이 아니면 `status='truncated'` + `dropped=N`
- 근거: 영상 실습 프롬프트 원칙 — *잘라냈으면 로그로 남겨라.* 조용히 자른 것은
  "전부 처리했다"로 읽힌다
- 검증: EVOLVE 3줄 → `dropped=1`

### Step 4. 에스컬레이션 훅 [Impl]

- `claude-sessionstart-pipeline-alert.sh` — SessionStart 에서 `consecutive_failures` 질의
- 임계 초과 시 **stdout 으로 경고 블록** 출력 → 세션 컨텍스트에 주입된다
- ⚠️ **중복 억제 필수.** 135회 사례의 교훈은 "탐지가 없었다"가 아니라 "같은 것을 135번
  반복 출력했다"이다. 노드별로 1회 알리고 마커를 남긴다. `dream-last-run` 마커 패턴 재사용
- 임계값은 매직넘버 금지 — `NO_PROGRESS_LIMIT=3`(결정화 임계와 동일 근거)을 따른다
- 검증: 임계+1회 실패 주입 → 1회 출력, 재실행 시 미출력

### Step 5. 회귀 테스트 [Impl]

- `tests/hermes-pipeline-ledger-test.sh` — bash. 이 저장소 테스트는 전부 `.sh` 이고
  러너는 `run-all.sh` 다 (secret-masking 회고 §1 교훈)
- 케이스: 정상 7행 / 실패 1건 기록 후 나머지 진행 / 절단 `dropped` / 연속 실패 카운트 /
  **기존 DB 복사본에 테이블 자동 생성(G5)**
- claude 실호출 금지 — LLM 노드는 mock 으로 대체

---

## 6. 의사결정 로그

- 2026-08-12: **병렬 실행을 범위에서 뺀다** — 근거: Stop 훅은 `setsid` 비차단이라 속도
  이득(실측 2.7~4.9×)이 사용자에게 도달하지 않는다. 영상 자체가 그래프의 한계로
  "설계 비용 증가 · 단순 작업엔 과함"을 든다.
- 2026-08-12: **`|| true` 를 없애되 파이프라인은 계속 진행한다** — 근거: 비차단은 의도된
  설계다(세션 종료를 막으면 안 됨). 문제는 계속 진행이 아니라 **기록이 없다**는 것이다.
- 2026-08-12: **에스컬레이션을 파일 로그가 아니라 SessionStart stdout 으로 보낸다** —
  근거: 135회 사례에서 탐지는 정확했으나 `_log()` 로 파일에만 나가 아무도 못 봤다.
- 2026-08-12: **중복 억제를 필수로 둔다** — 근거: 같은 사례에서 실제 피해는 미탐이 아니라
  **동일 문구 135회 반복**이었다. 알림을 붙이면서 억제를 안 붙이면 결함을 바꿔 달 뿐이다.
- 2026-08-12: **스키마를 lazy self-heal 로 만든다** — 근거: `hermes_init()` 호출부가 없어
  install-time 마이그레이션 경로가 실재하지 않는다. 기존 8개 스크립트가 이미 이 방식이다.
- 2026-08-12: **상태 파일 계약을 Phase 2 로 미룬다** — 근거: 원장만으로 §1 의 두 실측
  결함(절단·135회 방치)이 해소된다. 리플레이는 그다음 문제다.

---

## 7. 발견·예외

### 발견 1 — 관측 장치는 있었는데 행동이 없었다

`history-reindex` 훅은 export 실패를 **매번 정확히 지목했다.** 세션 ID 까지 찍고 복구 명령까지
안내했다. 그런데 135회 동안 아무 일도 일어나지 않았다.

→ **룰 후보**: *탐지의 산출물이 사람이 읽어야 하는 문장이면, 그것은 탐지가 아니라 로그다.
기록에 질의를 걸어 자동 행동이 나가는 형태여야 관측이다.*

### 발견 2 — 무언의 절단은 성공으로 읽힌다

`head -2` 는 오류를 내지 않는다. 3줄 중 2줄을 처리하고 **정상 종료**한다. 로그에도
"2건 처리"라고만 남아 원래 3건이었다는 사실이 어디에도 없다.

→ **룰 후보 (core-beliefs 승격 검토)**: *상한을 두는 코드는 상한에 걸렸다는 사실을 같은
자리에서 기록해야 한다. 기록 없는 절단은 "전부 처리함"과 구별되지 않는다.*

### 발견 3 — 죽은 설치 함수

`lib/hermes_memory.sh:20` 의 `hermes_init()` 은 정의만 있고 **호출부가 저장소 어디에도 없다.**
`hermes-init.py` 도 `tests/` 에서만 실행된다. 그럼에도 소비 프로젝트의 DB 가 정상인 이유는
**8개 스크립트가 각자 런타임에 자기 스키마를 만들기 때문**이다.

이 계획은 그 사실에 맞춰 lazy self-heal 을 택했다. 다만 남는 위험이 있다:

> 다음 사람이 `hermes-init.py` 에만 테이블을 추가하고 "왜 안 퍼지지?" 하게 된다.

→ **후속 과제**(이 계획의 비목표): `hermes_init()` 을 설치 경로에 배선하거나, 죽었다는
사실을 `hermes-init.py` 상단 주석에 명시한다.

### 예외 — 일시적 경합 14건은 이 계획이 고치지 않는다

`lagging` 139건 중 1회만 지목된 14건은 **세션 종료 직후 재개**로 인한 경합이다
(export 완료 전에 SessionStart reindex 가 판정). 원장은 이것을 `fail` 로 잘못 기록할 수 있다.

→ 완화: 원장은 **노드 자체의 종료코드**만 본다. reindex 의 발산 판정은 원장에 넣지 않는다.
경합의 근본 해결(완료 마커)은 Phase 2 로 미룬다.
