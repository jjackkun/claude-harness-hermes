# 드림 propose 무손실 map-reduce + 신뢰성 강화 (2026-06-25)

> 작성일: 2026-06-25
> 목적: `hermes-dream.py`의 propose 단계가 누적 증거를 절대 잘라먹지 않고(map-reduce),
> 호출 실패에 견디며(타임아웃+재시도+부분실패 이월), 후보 키도 잃지 않도록(이월 큐) 재구성한다.

## 1. 동기 (Why)

zeroday 실측(2026-06-25)에서 드러난 두 결함:

1. **증거 44% 폐기 (상시·결정적).** `propose_keys`가 12개 요약의 decisions+facts 총
   **10,806자**를 `evidence[:6000]`으로 잘라 약 4,800자를 버린다. `collect_summaries`가
   `ORDER BY updated_at`(오름차순)이므로 **최신 요약부터** 누락된다 — "최근 작업 지식을
   결정화"라는 목적과 정면 충돌. 데이터가 쌓일수록 악화.
2. **타임아웃 마진 부족 (간헐적·무신호).** propose의 단발 `claude -p`(haiku)가 타임아웃
   60초인데 실측 소요가 20.8~34.5초로 편차가 크고 본실행에선 60초+로 튀어 **빈 드림**이
   났다. 재시도 없음 + 실패가 비차단·무신호(exit 0)라 빈 드림이 성공처럼 `dream_log`에 박힌다.

추가로, 성공 후보 키는 `keys[:10]`으로 상위 10개만 결정화하고 **나머지를 영구 폐기**한다.
결정화는 키당 `claude -p` 1회(`hermes-crystallize.py:236`)라 비용이 키 수에 비례하므로,
한 번에 다 처리(폭주) 대신 **하루 10개씩 이월**이 무손실+비용상한을 동시에 만족한다.

## 2. 목표 (What — 검증 가능)

- [ ] **G1 증거 무손실** — 모든 요약이 잘리지 않고 어느 청크엔가 통째로 포함된다. 검증:
  4,000자를 초과하는 합성 증거가 여러 청크로 나뉘고, 입력 요약 집합 = 청크들의 합집합.
- [ ] **G2 단일 거대 요약 보존** — 청크 예산을 초과하는 단일 요약 1개는 **통째로 한 청크**가
  되며 절대 잘리지 않는다. 검증: 5,000자짜리 요약 1개 → 그 요약 전체가 한 청크.
- [ ] **G3 호출 견고화** — 청크 호출은 타임아웃 90초 + 1회 재시도. 검증: 1회차 실패(스텁)
  후 2회차 성공 시 키가 반환됨.
- [ ] **G4 부분 실패 이월** — 첫 실패 청크에서 멈추고, 워터마크는 **마지막으로 연속 성공한
  청크의 마지막 요약 시각**까지만 전진. 실패 지점 이후 요약은 다음 드림이 재처리. 검증:
  중간 청크 실패 스텁 → 워터마크가 실패 전까지만, `dream_log.failed_chunks ≥ 1`.
- [ ] **G5 후보 키 무손실 (옵션 C)** — 결정화 상한(10) 초과 후보 키는 폐기하지 않고
  `dream_pending_keys`에 이월, 다음 드림이 먼저 소진. 검증: 후보 13개 → 이번 10개 결정화 +
  3개 pending 적재 → 다음 드림이 그 3개를 먼저 처리.
- [ ] **G6 실패 가시화** — 부분 실패는 `hooks.log` 경고 + `dream_log.failed_chunks`로
  기록되어 "빈 성공"과 구분된다. 검증: 실패 스텁 시 두 곳 모두 반영.
- [ ] **G7 독(毒) 청크 탈출** — 같은 워터마크 경계에서 `STALL_SKIP`회 진척 없으면 그
  청크를 **건너뛰고**(`hooks.log` 경고 + `dream_log.skipped_chunks++`) 워터마크를 넘겨 나머지를
  살린다. 검증: 결정적으로 실패하는 청크 스텁을 N회 반복 → N회째에 skip되고 워터마크가 그 뒤로
  전진, `skipped_chunks ≥ 1`.
- [ ] **G8 조용한 날 pending 소진** — 새 요약이 없어도 `dream_pending_keys`가 비어있지
  않으면 드림이 돌아 이월 키를 소진한다. 검증: 요약 0개 + pending 5개 → 드림이 pending 처리.

## 3. 비목표 (Out of Scope)

- **결정화 상한 자체(10/드림)** — 비용 정책으로 유지(`HERMES_DREAM_CRYSTALLIZE_MAX`로
  오버라이드만). 늘리지 않는다 — 이월(G5)로 무손실을 달성하므로 상한을 키울 이유가 없다.
- **진화 단계** — `run_evolve`는 hint를 건별 독립 처리(`hermes-dream.py:194-209`)라 동일
  truncation 없음. 미변경.
- **`hermes-evolve-skill.py:122`의 `content[:3000]`** — 개별 스킬 진화 시 내용 컷. 별개
  기능, 본 spec 범위 밖(발견·예외에 메모만).
- **crystallize/cleanup 내부 로직** — 불변. 드림은 이들을 호출만 한다.
- **드림 트리거(cron vs Stop 훅)** — 별건. 엔진 신뢰성이 먼저(이 spec). 트리거는 후속.

## 4. 아키텍처

### 4.1 데이터 흐름 (propose 재구성)

```
since = 요약 워터마크(마지막 성공 처리 요약 시각)        ← 변경점(아래 4.3)
summaries = collect_summaries(con, since)               (updated_at ASC)
pending   = peek_pending_keys(con)
if not summaries and not pending: return                 ← 조용한 날도 pending 있으면 진행 (G8)

propose 단계:
  1) pending = drain_pending_keys(con)                   ← 이월 큐 먼저 (G5)
  2) chunks = _chunk_summaries(summaries, CHUNK_CHARS)   ← 요약 단위 패킹, 무손실 (G1·G2)
  3) stalls = stall_count(con, since)                    ← 워터마크 불변 연속 횟수 (G7)
  4) for chunk in chunks (순서대로):
        keys = _propose_chunk(chunk)  [90s + 1 retry]    ← (G3)
        실패면:
          stalls+1 >= STALL_SKIP → 이 청크 skip(영구 포기, 로그+skipped_chunks++), 다음 청크로 (G7)
          아니면               → break (보류, failed_chunks=남은 청크 수)        (G4)
        성공면 → 후보 누적, watermark = 처리한 prefix 요약(빈 것 포함) 중 max(updated_at)
  5) candidates = dedup(pending + 누적 후보, 기존 crystallized 제외)
  6) to_crystallize = candidates[:MAX]                    ← 이번 결정화분
     overflow      = candidates[MAX:] → dream_pending_keys 적재 (G5)
return to_crystallize, watermark_ts, failed_chunks, skipped_chunks

main: run_crystallize(to_crystallize) → … →
      record_dream(..., watermark_at=watermark_ts,
                   failed_chunks=…, skipped_chunks=…)                 ← (G4·G6·G7)
```

### 4.2 구성 단위 (전부 `hermes-dream.py` 내부, propose 영역 + 스키마)

| 단위 | 함수/대상 | 단일 책임 |
|------|----------|----------|
| U1 스키마 | `_ensure_schema` (수정) | `dream_log.failed_chunks`·`dream_log.watermark_at` 컬럼 + `dream_pending_keys` 테이블 멱등 생성 |
| U2 청킹 | `_chunk_summaries(summaries, budget)` (신규) | 요약을 char 예산으로 greedy 패킹, 거대 요약은 단독 청크(무손실) |
| U3 청크 호출 | `_propose_chunk(evidence)` (신규) | 한 청크 → claude -p(haiku), 타임아웃 90s + 1 재시도 |
| U4 이월 큐 | `peek_pending_keys`·`drain_pending_keys`·`enqueue_pending_keys` (신규) | `dream_pending_keys` 조회·소진·적재(dedup) |
| U5 map-reduce | `propose_keys(summaries, con)` (재작성)·`stall_count` (신규) | U2~U4 조합 + 첫 실패 멈춤 + 독 청크 skip + 워터마크/실패수 산출 |
| U6 워터마크 | `get_dream_watermark`(신규, `get_last_dream_at` 대체)·`record_dream`(시그니처 확장)·`main`(배선·조기종료 조건 변경) | since 를 요약 워터마크로, dream_log 에 watermark_at·failed_chunks·skipped_chunks 기록, 조용한 날도 pending 있으면 진행(G8) |

### 4.3 워터마크 변경 (필수 — 안 하면 G4·G5 깨짐)

현재 워터마크는 `get_last_dream_at = MAX(run_at)` = **마지막 드림 실행 시각**이다. 드림이
한 번이라도 기록되면 워터마크가 "지금"으로 점프해, **실패 청크의 요약도 워터마크 뒤로 밀려
재처리 불가**. 따라서:

- 워터마크 원천을 **요약 시각**으로 변경: `get_dream_watermark(con) = MAX(watermark_at)
  WHERE watermark_at IS NOT NULL`, 없으면 `None`(=전체 처리).
- `record_dream`이 `watermark_at`(이번에 마지막으로 성공 처리한 요약의 `updated_at`)을 기록.
- **안전성**: 전부 성공하는 정상 케이스에선 watermark_at = 마지막 요약 시각 = 사실상 기존과
  동등. 차이는 부분 실패 시에만 발생(실패분 이월) — 정확히 원하는 개선.
- **마이그레이션**: 기존 `dream_log` 행은 `watermark_at IS NULL` → 워터마크 None → 다음 첫
  실행이 backlog 전체를 정상 처리(zeroday의 기존 빈 드림 1행은 무해, backlog 재처리가 바람직).

## 5. 스키마 변경 (멱등)

`_ensure_schema`에 `PRAGMA table_info` 가드 후 `ALTER TABLE` + `CREATE TABLE IF NOT EXISTS`:

```sql
-- dream_log 컬럼 보강
ALTER TABLE dream_log ADD COLUMN failed_chunks  INTEGER DEFAULT 0;  -- 이번에 보류(다음 드림 재처리)
ALTER TABLE dream_log ADD COLUMN skipped_chunks INTEGER DEFAULT 0;  -- 영구 포기(독 청크, 재처리 안 함)
ALTER TABLE dream_log ADD COLUMN watermark_at   TEXT;

-- 후보 키 이월 큐
CREATE TABLE IF NOT EXISTS dream_pending_keys (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    key        TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## 6. 핵심 로직 상세

### 6.1 U2 청킹 (`_chunk_summaries`)

- 입력: 요약 리스트(updated_at ASC), `budget`(기본 4,000자).
- 각 요약의 기여 텍스트 = decisions+facts 항목들을 `\n`으로 결합한 문자열.
- greedy: 현재 청크 누적 길이 + 다음 요약 길이 > budget 이면 새 청크 시작. **요약은 절대
  분할하지 않음** — 단일 요약이 budget 초과여도 그 요약 하나로 한 청크(통째 전송).
- 출력: 청크 리스트. 각 청크는 `{summaries: [...], last_updated_at: ..., evidence: "..."}`.
- 빈 기여(decisions·facts 모두 빈) 요약은 청크에서 제외하되 워터마크 전진엔 포함(처리 완료로 간주).

### 6.2 U3 청크 호출 (`_propose_chunk`)

- 입력: 청크의 evidence 문자열(잘리지 않음).
- `PROPOSE_PROMPT.format(evidence=evidence)` — **`[:6000]` 제거**.
- `claude -p ... --model haiku`, `timeout=HERMES_DREAM_TIMEOUT`(기본 90), `env HERMES_DISABLED=1`.
- 실패(타임아웃/rc≠0)면 **1회 재시도**. 둘 다 실패면 `None` 반환(호출자가 멈춤 처리).
- 성공이면 기존 파싱(라인→kebab-case, NONE 처리) 그대로 적용해 키 리스트 반환.

### 6.3 U5 map-reduce + 첫 실패 멈춤 (`propose_keys`)

- pending = `drain_pending_keys(con)` (FIFO, 최대 MAX개 우선 확보).
- `stalls = stall_count(con, since)` — **워터마크가 마지막으로 바뀐 이후의 연속 dream_log 행 수**
  (= `watermark_at = since` 인 최근 연속 행 수). 실패 여부에 결합하지 않는다 — "워터마크 불변
  = 진척 없음 = stall"이 곧 정의이며, 암묵적 불변식에 기대지 않는다(G7).
  - **NULL-안전 비교 필수**: 첫 캐치업 드림은 `since=NULL`이고 SQL `watermark_at = NULL`은 항상
    거짓이므로, `WHERE (watermark_at IS NULL AND :since IS NULL) OR watermark_at = :since`로
    비교해야 한다. 안 그러면 backlog 선두의 독 청크가 STALL_SKIP에 도달 못 해 영구 정체된다.
- 청크를 순서대로 호출:
  - 성공 → 키 누적, **워터마크 = 지금까지 성공 처리한 prefix 요약(기여 빈 요약 포함) 중
    `max(updated_at)`**. (후행 빈 요약이 매번 재수집되는 낭비 방지.)
  - **실패(None)** →
    - `stalls + 1 >= STALL_SKIP` 이면 **이 청크 skip(영구 포기)**: 해당 요약 session_id들을
      `hooks.log`에 경고로 남기고, `skipped_chunks += 1`, 워터마크를 이 청크의 max(updated_at)까지
      전진(포기), 다음 청크로 계속 (G7).
    - 아니면 **즉시 break** (첫 실패에서 멈춤, 뒤 청크 보류 → 이중 결정화 방지, 다음 드림이
      워터마크 이후로 재수집). 미처리 청크 수 = `failed_chunks`(=보류, 영구 손실 아님) (G4).
- 어떤 청크도 성공 못 하면 **워터마크 = `since`(불변)로 기록** — `record_dream`이 이 값을
  남겨야 다음 드림의 `stall_count`가 "같은 경계 연속 실패"를 인식한다(G7의 근거).
- candidates = dedup 순서보존(`pending` 먼저 + 누적 키), 이미 `pattern_count.crystallized=1`
  인 키 제외.
- `to_crystallize = candidates[:MAX]` (MAX=`HERMES_DREAM_CRYSTALLIZE_MAX`, 기본 10).
- `overflow = candidates[MAX:]` → `enqueue_pending_keys(con, overflow)` (UNIQUE로 중복 무시).
- 소진된 pending 키(= to_crystallize에 포함된 것)는 `dream_pending_keys`에서 삭제.
- 반환: `(to_crystallize, watermark, failed_chunks, skipped_chunks)`.

### 6.4 G6 가시화

- `_propose_chunk` 최종 실패 시 `_log`로 `hooks.log`에 경고(청크 인덱스·요약 수).
- `failed_chunks`(보류)와 `skipped_chunks`(영구 포기)를 **구분해** `record_dream`에 기록 →
  빈 성공(0/0/0/0)·일시 보류·영구 손실이 dream_log에서 각각 식별된다. 특히 `skipped_chunks > 0`은
  "어쩔 수 없이 버린 증거"이므로 `hooks.log`에도 포기한 session_id를 남긴다.

## 7. 임계값 (매직넘버 — 근거 + env 오버라이드)

| 상수 | 기본 | 근거 | env |
|------|------|------|-----|
| 청크 예산 | 4,000자 | 실측 6,000자→20~35초. 4,000자면 ~15~25초로 타임아웃 여유 + 호출 가벼움 | `HERMES_DREAM_CHUNK_CHARS` |
| 호출 타임아웃 | 90초 | 실측 변동이 60초+까지 튐 → 90초+재시도로 꼬리 흡수 | `HERMES_DREAM_TIMEOUT` |
| 재시도 | 1회 | 일시적 지연 1회 흡수(영구 실패와 구분). 최악 청크당 180초(백그라운드 일배치라 허용) | — |
| 결정화 상한/드림 | 10 | 기존값 유지(키당 claude 1회 = 비용 상한). 무손실은 이월로 달성 | `HERMES_DREAM_CRYSTALLIZE_MAX` |
| 독 청크 skip 임계 | 3 | 같은 경계 3드림 연속 실패면 일시적이 아니라 결정적 실패로 보고 1청크 포기·나머지 구제 | `HERMES_DREAM_STALL_SKIP` |

## 8. 영향 영역

- 코드(수정): `scripts/hermes-dream.py` — propose 영역(`propose_keys` 재작성) + `_ensure_schema`
  + `get_last_dream_at`→`get_dream_watermark` + `record_dream` 시그니처 + `main` 배선.
  신규 함수: `_chunk_summaries`, `_propose_chunk`, `drain_pending_keys`, `enqueue_pending_keys`.
- **신규 파일**: 없음(단일 파일 내부 함수 분해).
- 데이터: `dream_log` 컬럼 2개 + `dream_pending_keys` 테이블, 멱등 마이그레이션.
- 외부 의존: `claude -p`(haiku) 동작. 신규 의존 없음.
- 배포: `hermes-dream.py`는 이미 `hermes.conf` 복사목록에 있음 — `update-all.sh`로 전파.

## 9. 에러 처리

- 전 함수 비차단: 실패는 `_log`(stderr/hooks.log) 후 진행. `main`은 항상 정상 종료.
- DB는 기존 `connect_db`(busy_timeout+WAL).
- pending 큐 적재 실패·청크 호출 실패가 드림 전체를 멈추지 않음(부분 성공 보존).

## 10. 테스트 (`tests/hermes-pipeline-test.sh` 30번대 섹션 확장 또는 신규)

claude는 **PATH stub**(앞선 작업과 동일 방식 — 가짜 `claude`가 정해진 키 출력)으로 모킹.

1. **G1 무손실**: 4,000자 초과 합성 증거 → 청크 분할, 모든 요약이 어느 청크엔가 포함(합집합 일치).
2. **G2 거대 요약**: 5,000자 단일 요약 → 한 청크에 통째(잘림 없음).
3. **G3 재시도**: stub이 1회차 비정상·2회차 정상 → 키 반환.
4. **G4 부분실패 이월**: 중간 청크에서 stub 실패 → 워터마크가 실패 전까지만, `failed_chunks≥1`,
   다음 호출에서 실패 이후 요약 재수집.
5. **G5 후보 이월**: 후보 13개·MAX=3 → 3개 결정화 + 10개 pending, 다음 드림이 pending 먼저 소진.
6. **G6 가시화**: 실패 시 `failed_chunks>0` 기록.
7. **G7 독 청크 skip**: 결정적 실패 청크 stub + `STALL_SKIP=2` → 2드림 반복 시 2회째에 그 청크
   skip되고 워터마크가 그 뒤로 전진(나머지 요약 처리됨), `dream_log.skipped_chunks ≥ 1` + `hooks.log`
   에 skip 경고. (failed_chunks와 skipped_chunks가 별개로 기록됨도 단언.)
8. **G8 조용한 날 pending**: 요약 0개 + pending 3개 → 드림이 조기 종료 안 하고 pending 소진.
9. `tests/run-all.sh`로 통합 실행.

## 11. 단계 개요 (상세는 구현계획에서)

1. U1 스키마(마이그레이션) → 2. U2 청킹 → 3. U3 청크 호출(재시도) → 4. U4 이월 큐
→ 5. U5 map-reduce(첫 실패 멈춤) → 6. U6 워터마크/record_dream/main 배선 → 7. 테스트 → 8. 전파 검증.

스키마·청킹·호출이 먼저 깔려야 map-reduce가 조립된다(순서 의미 있음).
