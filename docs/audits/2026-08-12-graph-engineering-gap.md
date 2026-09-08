# 그래프 엔지니어링 적용 여부 감사 — Hermes 러닝 루프

> 작성일: 2026-08-12
> 목적: [ai-engineering-paradigm-evolution.md](../ai-engineering-paradigm-evolution.md) 의 4단계(그래프 엔지니어링) 기준으로 본 저장소의 현재 위치를 판정하고, 적용 시 개선폭을 실측 근거로 산정한다.
> 대상: `assets/hooks/claude-stop-retrospective.sh` (러닝 루프 본체) · `scripts/hermes-*.py` · `scripts/hermes_loop.py`

## 결론 (한 줄)

**노드는 이미 다 있는데 그래프 실행기가 없다.** 현재는 *"노드로 잘 쪼개진 순차 bash 스크립트"* — 4단계 직전이다.
**단, 전면 도입은 권하지 않는다.** 이 시스템에서 실익이 있는 건 그래프의 4개 속성 중 **관측·재현 하나뿐**이고, 병렬 실행은 비차단 백그라운드라 이득이 사용자에게 도달하지 않는다 (4장·5장).

| 그래프 엔지니어링 속성 | 현재 | 근거 |
|---|---|---|
| 전문화된 노드 분업 | ✅ 있음 | `hermes-{save-session,summarize,crystallize,evolve-skill,correlate,prune,export-history}.py` — 파일 1개 = 책임 1개 |
| 피드백 엣지(학습 그래프) | ✅ 있음 | `correlate`(주입 원장↔편집경로 대조) → `prune`(측정 신호 기반 강등) → `skill_index` |
| 안전캡 있는 루프 | ✅ 있음 | `hermes_loop.py` — `max_iterations`·`no_progress_limit`·`verify` 객관신호·`loop/<id>` 브랜치 격리 |
| **병렬 실행** | ❌ 없음 | Stop 훅 7단계 전부 순차. `crystallize` 의 `for key in keys` 도 순차 |
| **조건 분기 · 승인 게이트** | ❌ 미배선 | `hermes_mesh_gate.py` 는 구현돼 있으나 **호출부가 없다** (Phase 3 미착수) |
| **단계별 관측 · 재현** | ❌ 없음 | 노드 실행 기록 테이블 부재. 자유텍스트 `hooks.log` 뿐 |
| **명시적 엣지 · 상태 계약** | ❌ 없음 | 단계 간 전달이 **stdout 문자열 grep** |

> 참고: **진입 게이팅**은 오히려 잘 돼 있다. `claude-sessionstart-dream.sh` 는 `[게이트 0]~[게이트 4]` 를 두고 탈락 사유를 로그에 남긴다(실측: `skip:throttle` 539건, `skip:source` 232건). 없는 것은 *파이프라인 내부*의 게이트·관측이다.

---

## 1. 현재 구조 — Stop 훅 러닝 루프

`assets/hooks/claude-stop-retrospective.sh` 가 세션 종료 시 `setsid` 백그라운드로 7단계를 **일렬로** 실행한다.

```
1.  save-session      →  stdout 에 CRYSTALLIZE:/EVOLVE: 출력
1.5 summarize         (LLM ×1)
2.  crystallize       ← grep "^\[hermes\] CRYSTALLIZE:" | head -1   (LLM ×키수)
3.  evolve-skill      ← grep "^\[hermes\] EVOLVE:"      | head -2   (LLM ×2)
4.  correlate
5.  prune
6.  export-history
```

각 단계는 예외 없이 `... || true` 로 끝난다 (파일 내 9회).

---

## 2. 실측 데이터

측정 대상: `zeroday-frontend` 프로젝트의 실제 운영 데이터(`.hermes/state.db` 59MB · `session_history` 27,343행 · `hooks.log` 39,841줄)를 작업용 복사본으로 떠서 실행. 트랜스크립트는 실제 세션(18,347줄 / 905 메시지).

### 2-1. 노드별 소요시간

| 노드 | 종류 | 실측 |
|---|---|---|
| `save-session` | 로컬 | **0.55s** |
| `summarize` | LLM ×1 (haiku) | **24.20s** |
| `correlate` | 로컬 | 0.03s |
| `prune` | 로컬 | 0.03s |
| `export-history` | 로컬 | 0.06s |

LLM 노드 단독 지연(haiku, 짧은 프롬프트) 3회 측정: **8.70s / 9.69s / 12.07s** (중앙값 9.69s).
`crystallize`·`evolve` 는 증거 5~10건을 실어 보내므로 `summarize` 급 프롬프트에 가깝다 → 노드당 **10~24s** 대역으로 본다.

> `crystallize`/`evolve` 는 `~/.hermes/global.db` 와 스킬 `.md` 에 실제로 쓰기 때문에 벤치마크에서 실행하지 않고, 측정된 LLM 노드 지연으로 산정했다.

### 2-2. 이 세션이 만든 실제 작업량

측정 세션의 `save-session` 산출:

```
[hermes] CRYSTALLIZE:zd-kos-004,hermes-dream        ← 키 2개
[hermes] EVOLVE:버전|...
[hermes] EVOLVE:eslint|...
[hermes] EVOLVE:prettier|...                        ← 3줄
```

→ LLM 노드 총 **5개**(summarize 1 + crystallize 2 + evolve 2). *evolve 3번째 줄은 `head -2` 에 잘려 사라진다 — 아래 3-3.*

### 2-3. 순차 vs 그래프 (임계경로)

**의존성 실측** (각 스크립트가 읽고 쓰는 테이블 기준):

- `summarize` 는 `session_summary` 만 읽고 쓴다. `save-session` 은 `session_history`·`pattern_count` 에 쓴다 → **완전 독립인데 순차 실행 중**
- `crystallize` 의 키들끼리, `evolve` 의 줄들끼리 서로 독립
- `crystallize`(INSERT `skill_index`) ∥ `evolve`(UPDATE `skill_index`) — 서로 다른 행, WAL + `busy_timeout=5000` (20개 스크립트에 적용됨)으로 안전
- **단, `correlate` → `prune` 순서는 유지 필수** — `prune` 이 `correlate` 가 갱신한 측정 신호를 소비한다

| | 계산 | LLM=10s | LLM=24s |
|---|---|---|---|
| 현재(순차 합) | `0.55 + 24.20 + 4×L + 0.12` | **≈ 65s** | **≈ 121s** |
| 그래프(임계경로) | `max(24.20, 0.55 + L + 0.06)` | **≈ 24.2s** | **≈ 24.6s** |
| **단축** | | **약 2.7×** | **약 4.9×** |

임계경로는 `summarize`(24.2s) 에 고정되므로, **결정화 키가 늘어날수록 격차가 선형으로 벌어진다.** `crystallize` 의 `for key in keys` 가 순차라서 키 5개면 현재는 +5L, 그래프는 +L 이다.

---

## 3. 속도보다 중요한 것 — 신뢰성 결함 (실측 근거 있음)

### 3-1. 모든 노드 실패가 삼켜진다

7단계 전부 `|| true`. 노드가 죽어도 파이프라인은 성공한 것처럼 끝난다.

**실제로 발생 중이다.** 라이브 로그에서 별도 탐지기가 뒤늦게 잡아낸 흔적:

```
[hermes-reindex-hook] action=skip:diverged:lagging ... reason=lagging
  — 파일이 DB 보다 뒤처졌다(Stop 훅 export 실패 가능)
```

| 사유 | 건수 |
|---|---|
| `reason=lagging` (6단계 export 실패 정황) | **139** |
| `reason=db` | 96 |
| `skip:diverged` 총계 | **235** |

**다만 139건을 실패 139회로 읽으면 안 된다.** 지목된 세션을 분해하면 성격이 갈린다:

| 같은 세션이 지목된 횟수 | 세션 수 | 해석 |
|---|---|---|
| 1회 | 14 | 다음 사이클에 자가 치유 — **일시적 경합** (세션 종료 직후 재개해 export 완료 전에 reindex 가 돌았다) |
| 2~3회 | 5 | 지연 회복 |
| 8회 | 1 | 회복 지연 |
| **135회** | **1** (`fcd65acc…`) | **영구 고착** — 135번의 세션 시작 동안 한 번도 복구되지 않음 |

즉 실제 문제는 *"139회 실패"* 가 아니라 **① 고착 1건이 135회 방치 + ② 순서 계약이 없어 생기는 일시적 경합 ~20건** 이다.

그리고 더 나쁜 쪽은 ①이다. 시스템은 135회 동안 **똑같은 안내 문구를 로그에 반복 출력했을 뿐**, 재시도도 에스컬레이션도 하지 않았다. 관측 자체가 없는 게 아니라 **관측 결과가 아무 행동으로도 이어지지 않는다.**

### 3-2. 엣지가 stdout 문자열이다

```bash
crystallize_keys=$(printf "%s" "$save_output" | grep "^\[hermes\] CRYSTALLIZE:" | ...)
```

`save-session` 의 출력 포맷이 한 글자만 바뀌어도 이 엣지는 **조용히 끊긴다**. 타입도, 스키마도, 실패 시그널도 없다.

### 3-3. 무언의 절단 (`head -1` / `head -2`)

- `crystallize`: `head -1` — CRYSTALLIZE 줄이 2개 이상이면 나머지 버림
- `evolve`: `head -2` — 측정 세션에서 **3줄 중 1줄(`prettier`)이 로그 한 줄 없이 사라졌다**

영상의 원칙 *"no silent caps — 잘라냈으면 로그로 남겨라"* 위반이다.

### 3-4. 노드 실행 기록 테이블이 없다

`state.db` 의 선언 테이블 13개(`hermes-init.py` 11개 + `hermes_loop.py` 2개 — `session_history`·`pattern_count`·`skill_index`·`dream_log`·`loops`·`loop_steps` …) 중 **파이프라인 노드의 상태·소요시간·입출력을 기록하는 테이블이 없다.** 결과:

- 어느 노드가 실패했는지 질의 불가
- 실패한 노드만 골라 재실행(리플레이) 불가 — 전체를 다시 돌려야 함
- 노드별 SLA·지연 추세 관측 불가

> 아이러니: **루프 레이어는 이미 이걸 갖고 있다.** `loop_steps` 테이블이 `iteration`·`verdict`·`objective_signal`·`progressed` 를 반복마다 남긴다. 러닝 루프 파이프라인에만 없다.

### 3-5. 발행 전 게이트가 미배선

`scripts/hermes_mesh_gate.py` 는 2단계 fail-closed 게이트(정규식 신원 필터 → LLM 일반성 분류 → `redact()` 스크럽)로 **완성돼 있다**. 그런데 저장소 전체에서 **운영 호출부가 없다** — 참조는 설계·계획 문서와 단위 테스트(`tests/hermes-mesh-gate-test.sh`)뿐이고, `docs/superpowers/plans/2026-07-24-hermes-mesh-part-c-phase2-gate.md` 가 *"배선은 Phase 3"* 이라 명시한 채 멈춰 있다.

현재 `crystallize` 는 스킬 `.md` 를 쓰고 `~/.hermes/global.db` 에 바로 기록한다. **판단 → 발행 사이에 검증 게이트가 없다.**

---

## 4. 적용하면 얼마나 좋아지는가 — 항목별 실익 판정

**전면 도입은 권하지 않는다.** 항목마다 실익이 크게 다르다.

| 항목 | 현재 | 적용 후 | 실익 판정 |
|---|---|---|---|
| 노드 실패 → 행동 | 로그에 안내문 반복 (고착 1건 × 135회) | **재시도 큐 + N회 초과 시 에스컬레이션** | 🟢 **큼** |
| 실패 복구 | 전체 재실행 | 실패 노드만 리플레이 | 🟢 **큼** |
| 산출물 누락 | 무언의 절단 (실측 1건) | 로그 + 큐 이월 | 🟢 **큼** |
| 파이프라인 ↔ 다음 세션 순서 | 계약 없음 → 경합 ~20건 | **완료 마커로 순서 보장** | 🟡 중간 |
| 전역 그물망 승격 | 게이트 없이 발행 | fail-closed 게이트 통과분만 | 🟡 중간 (그래프와 무관, 원래 계획된 Phase 3) |
| 러닝 루프 지연 | 65~121s | 24~25s (2.7~4.9×) | 🔴 **거의 없음** — 아래 참조 |

### 속도 이득이 무가치한 이유

Stop 훅은 `setsid` 로 분리된 **백그라운드 비차단** 실행이다. 세션은 이미 끝났고 **아무도 이 파이프라인을 기다리지 않는다.** 65초가 24초가 돼도 사용자 체감은 0이다.

병렬화의 유일한 실익은 "세션 종료 직후 재개" 시 경합(위 ②, ~20건)을 줄이는 것인데, 이건 **병렬화가 아니라 완료 마커·순서 계약으로 푸는 문제**다. 오히려 병렬화하면 `skill_index` 를 4개 노드가 동시에 건드리게 되어 디버깅 난도만 올라간다.

> 영상 자체가 그래프 엔지니어링의 한계로 **"설계 비용 증가 · 단순 작업엔 과함"** 을 든다. 비차단 7단계 bash 파이프라인에 DAG 실행기를 얹는 것이 정확히 그 사례다.

---

## 5. 권장 적용 순서

비용 대비 효과 순. 각 단계는 독립적으로 배포 가능하다.

### 1순위 — 노드 실행 원장 (비용 최소 · 효과 최대)

`state.db` 에 테이블 하나 추가하고, Stop 훅의 각 단계를 감싸 기록한다.

```sql
CREATE TABLE IF NOT EXISTS pipeline_run (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id      TEXT NOT NULL,       -- 세션 1회 실행 = run 1개
  node        TEXT NOT NULL,       -- save-session | summarize | ...
  status      TEXT NOT NULL,       -- ok | fail | skip | truncated
  reason      TEXT,                -- 실패·절단 사유 (무언의 절단 제거)
  duration_ms INTEGER,
  created_at  TEXT NOT NULL
);
```

`|| true` 를 `|| record_fail <node> "$?"` 로 바꾸는 것만으로 3-1·3-3 이 동시에 해결된다.
기존 `loop_steps` 와 같은 설계라 새 개념이 아니다.

### 2순위 — 엣지를 파일 계약으로

stdout grep 대신 `save-session` 이 `$RUN_DIR/state.json` 을 쓰고, 후속 노드가 읽는다. 입출력이 파일로 남으면 **리플레이가 공짜로 따라온다** (3-2·3-4 해결).

### 3순위 — 완료 마커 (병렬화 아님)

Stop 파이프라인이 끝날 때 `.hermes/pipeline-done-<session>` 를 남기고, SessionStart 의 reindex 훅이 **직전 세션 마커가 없으면 발산 판정을 유예**한다. 위 ② 경합 ~20건이 사라진다. 병렬화 없이 순서 계약만으로 해결된다.

### 4순위 — 승인 게이트 배선

`hermes_mesh_gate.mesh_gate()` 를 `crystallize` 의 발행 직전에 삽입. 이미 만들어져 있고 순수 함수라 호출만 하면 된다 (Phase 3 원안).

### 하지 말 것 — 병렬 실행 · DAG 실행기 도입

비차단 백그라운드라 속도 이득이 사용자에게 도달하지 않는다(4장). `skill_index` 를 4개 노드가 동시에 쓰게 되어 디버깅 비용만 늘어난다. **1·2순위를 마친 뒤에도 여전히 느리다고 느껴질 때** 재검토한다.

### 보류 — 사람 승인 노드

영상의 `사람 승인(이상 징후 시)` 노드는 러닝 루프가 **백그라운드 비차단**이라는 설계 전제와 충돌한다. 대신 `pipeline_run` 에 `status=blocked` 를 남기고 다음 세션 시작 시 회상으로 알리는 비동기 승인이 이 시스템에 맞다.

---

## 6. 측정 재현 방법

```bash
# 노드별 로컬 실행시간
W=<작업복사본>/proj; DB=$W/.hermes/state.db
time python3 scripts/hermes-prune.py --db $DB
time python3 scripts/hermes-export-history.py --db $DB --project $W --session <SID>

# LLM 노드 지연
time claude -p "<게이트 프롬프트>" --model claude-haiku-4-5-20251001

# 조용한 실패 건수
grep -c "skip:diverged" <프로젝트>/.hermes/hooks.log
grep -oE "reason=[a-z]+" <프로젝트>/.hermes/hooks.log | sort | uniq -c
```

> 주의: `crystallize`/`evolve` 는 `~/.hermes/global.db` 와 스킬 디렉터리에 **실제로 쓴다.** 벤치마크에 포함하지 말 것.
