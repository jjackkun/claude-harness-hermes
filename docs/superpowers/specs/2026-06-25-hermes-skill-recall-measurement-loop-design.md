# 헤르메스 스킬 재활용 측정·자기개선 루프 (2026-06-25)

> 작성일: 2026-06-25
> 목적: 동작 중인 스킬 recall(검색·주입)에 **측정 → 랭킹 → 정리**의 자기개선 계층을 붙여,
> 유용한 스킬은 상위 노출되고 안 쓰이는 junk 스킬은 강등·톰브스톤되게 한다. setup.sh /
> update-all.sh 설치 경로로 이미 설치된 프로젝트까지 자동 반영한다.

## 1. 동기 (Why)

my-app 실측(2026-06-25):

- `.hermes/skills/` 에 자동 생성 스킬 **217개**, 그중 `skill_index` 등록은 **38개(18%)**.
- `skill_index.used_count` 가 **전 행 0** — 검색이 평면 `.md` 를 찾는 경로(`hermes-search.py`
  의 `search_skills_dir`)는 `used_count` 를 증가시키지 않기 때문. (증가는 `search_db`
  경로 = 인덱스 매칭에만 존재, `hermes-search.py:288-300`)
- 결정화·주입 자체는 정상 동작 확인됨(라이브 검색 시 관련 스킬 3개 주입). **죽은 것은
  recall 이 아니라 "어떤 스킬이 실제로 유용한지"를 재는 측정 계층**이다.

결과: 어떤 스킬도 사용 신호를 남기지 않으므로 (1) 랭킹이 불가능하고 (2) junk 스킬을
정리할 근거가 없다. 스킬은 무한히 쌓이기만 한다(217개, 파일명이 패턴키라 `있으면.md`·
랜덤해시 포함). 측정 신호가 들어갈 "집"이 없는 것이 근본 원인이다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] **G1 인덱싱 통일** — `.hermes/skills/` 의 평면 `.md` 와 `.claude/skills/` 의 폴더형
  `SKILL.md` 가 **모두** `skill_index` 행을 갖는다. 검증: zeroday 재인덱싱 후
  `SELECT COUNT(*) FROM skill_index` ≥ 디스크 스킬 파일 수.
- [ ] **G2 주입 원장** — 검색이 주입한 모든 스킬(평면 포함)이 `skill_injection` 에 1행씩
  기록된다. 검증: 한 번 검색 실행 후 주입된 스킬 수 = 신규 원장 행 수.
- [ ] **G3 결과 상관** — Stop 훅에서 원장 + transcript 편집 이벤트를 대조해
  `helpful_count`/`noop_count` 를 갱신한다. 검증: 편집이 키워드와 겹치는 주입 →
  `helpful_count` 증가, 안 겹치면 `noop_count` 증가 (단위 테스트, transcript 픽스처).
- [ ] **G4 랭킹** — 검색이 `state='tombstoned'` 를 제외하고 score(helpful·최근성)로 정렬
  한다. 검증: 톰브스톤 스킬은 주입 후보에서 빠지고, helpful 높은 스킬이 먼저 나온다.
- [ ] **G5 정리** — `noop_count ≥ NOOP_DEMOTE AND helpful_count = 0` 인 스킬을 `demoted`,
  강등 후 무용 기간이 `TOMBSTONE_DAYS` 초과면 `tombstoned` 로 강등한다. 파일은 보존.
  검증: 임계값을 넘긴 픽스처 스킬이 강등→톰브스톤되고 `.md` 파일은 디스크에 남는다.
- [ ] **G6 설치 전파** — 신규 스크립트·스키마·훅 변경이 setup.sh / update-all.sh 로
  설치되고 기존 DB가 멱등 마이그레이션된다. 검증: zeroday 에 update-all 재실행 후
  신규 컬럼/테이블 존재 + Stop 훅에 correlate·prune 호출 포함.

## 3. 비목표 (Out of Scope)

- **검색 매칭 알고리즘 전면 교체** — 부분문자열 매칭은 유지. 랭킹(정렬)만 score 기반으로
  바꾼다. 정밀도는 helpful 신호가 쌓이며 부수적으로 개선된다(YAGNI).
- **하드 삭제** — 정리는 강등·톰브스톤(되돌림 가능)까지. 물리 삭제는 기존
  `hermes-cleanup.py --apply` 경로 유지.
- **B 드리밍 엔진(③망각·④그래프)** — 별도 백로그
  (`docs/exec-plans/backlog/2026-06-19-hermes-memory-aging-graph.md`). 본 spec과 무관.
- **전역 DB(`~/.hermes/global.db`) 측정 공유** — 프로젝트 로컬 측정 먼저. 전역 병합은 후속.
- **파일명 정규화** — `있으면.md` 같은 junk 파일명 개명은 별건. 본 spec은 파일명이 아니라
  내용·사용 신호로 측정한다.

## 4. 아키텍처

### 4.1 데이터 흐름

```
[매 턴] UserPromptSubmit → claude-userpromptsubmit-reminders.sh → hermes-search.py
        ├─ 스킬 주입 (기존)
        └─ 주입 원장 기록: skill_injection(session_id, skill_path, injected_at)   ← G2

[세션 종료] Stop 훅 → claude-stop-retrospective.sh (setsid 블록)
        ├─ (기존) save-session → crystallize
        ├─ hermes-correlate.py: 원장 + transcript Edit/Write 대조                ← G3
        │     상관 O → helpful_count↑, last_helpful_at=now
        │     상관 X → noop_count↑
        └─ hermes-prune.py: 임계값 판정 → state demoted/tombstoned                ← G5

[다음 턴] hermes-search.py: state!='tombstoned' 만, score=f(helpful,최근성) 정렬   ← G4
```

### 4.2 구성 단위 (1파일 = 1책임)

| 단위 | 파일 | 단일 책임 |
|------|------|----------|
| U0 공유 헬퍼 | `scripts/hermes_skills.py` (신규) | 평면+폴더 스킬 순회(`iter_skill_files`)·키워드 추출. index/search 중복 제거(DRY) |
| U1 주입 원장 | `scripts/hermes-search.py` (수정) | 주입한 모든 스킬을 `skill_injection` 에 기록 + 랭킹 정렬 적용 |
| U2 결과 상관 | `scripts/hermes-correlate.py` (신규) | 원장 + transcript 편집경로를 스킬 키워드와 대조 → helpful/noop 갱신 |
| U3 정리 | `scripts/hermes-prune.py` (신규) | 임계값 판정 → state 강등(active→demoted→tombstoned). 파일 보존 |
| U4 인덱싱 통일 | `scripts/hermes-index-skills.py` (수정) | U0 헬퍼로 평면 `.md` 포함 인덱싱 |
| U5 스키마 | `scripts/hermes-init.py` (수정) | 신규 테이블/컬럼 멱등 생성·마이그레이션 |
| U6 배선 | `presets/workflow/hermes.conf`, `assets/hooks/claude-stop-retrospective.sh` (수정) | 복사목록·허용목록 등록, Stop 훅에 correlate→prune 추가 |

각 단위는 독립 실행·테스트 가능: U2/U3/U4 는 `--db` 인자를 받는 CLI 스크립트, U0 는 import 모듈.

### 4.3 U0 공유 헬퍼 인터페이스

```python
# scripts/hermes_skills.py
def iter_skill_files(skills_dir: str):
    """(name, skill_md_path) 순회. <name>/SKILL.md 와 평면 <name>.md 둘 다."""
    # 현재 hermes-search.py:_iter_skill_files 와 동일 로직을 단일화

def extract_keywords(skill_path: str) -> set[str]:
    """SKILL.md/평면 .md 에서 키워드 집합 추출 (제목·트리거·인라인코드)."""
    # 현재 hermes-index-skills.py:extract_keywords_from_skill 로직을 set 반환으로
```

`hermes-index-skills.py` 와 `hermes-search.py` 는 위 두 함수를 import 해 중복을 제거한다.

## 5. 스키마 변경 (멱등 마이그레이션)

`hermes-init.py` 의 기존 패턴(`CREATE TABLE IF NOT EXISTS` + `PRAGMA table_info` 가드 후
`ALTER TABLE ADD COLUMN`, 현재 `:91-93`)을 그대로 따른다.

### 5.1 신규 테이블 `skill_injection`

```sql
CREATE TABLE IF NOT EXISTS skill_injection (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT    NOT NULL,
    skill_path  TEXT    NOT NULL,
    injected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    correlated  INTEGER DEFAULT 0    -- 0=미처리, 1=correlate 가 처리함 (중복 집계 방지)
)
```

### 5.2 `skill_index` 컬럼 보강 (PRAGMA 가드 후 ADD COLUMN)

| 컬럼 | 타입/기본 | 의미 |
|------|-----------|------|
| `helpful_count` | INTEGER DEFAULT 0 | 주입 후 관련 작업이 실제 일어난 횟수 (G3) |
| `noop_count` | INTEGER DEFAULT 0 | 주입됐으나 상관 없던 횟수 (G3) |
| `last_helpful_at` | TEXT | 마지막으로 도움된 시각 (정리 판정용) |
| `state` | TEXT DEFAULT 'active' | active / demoted / tombstoned (G4·G5) |
| `demoted_at` | TEXT | demoted 로 강등된 시각 (톰브스톤 경과 판정용, §6.3) |

`used_count`(기존)는 "주입 총 횟수"로 의미 유지(하위호환), 랭킹 1차 키는 `helpful_count`.

## 6. 핵심 로직 상세

### 6.1 U1 주입 원장 + 랭킹 (`hermes-search.py`)

- **원장 기록**: `db_results` + `dir_results` + `haiku_results` 로 실제 주입된 모든 스킬에
  대해 `INSERT INTO skill_injection(session_id, skill_path)`. `session_id` 는 새 인자
  `--session-id` 로 받는다(호출 훅이 이미 보유). 미전달 시 원장 기록만 생략(검색은 정상).
- **랭킹**: `search_db` 의 `ORDER BY used_count DESC` → `ORDER BY helpful_count DESC,
  last_helpful_at DESC`. `WHERE` 에 `state != 'tombstoned'` 추가. `search_skills_dir`
  결과는 `skill_index` 와 join 해 동일 정렬·톰브스톤 제외 적용.

### 6.2 U2 결과 상관 (`hermes-correlate.py`)

입력: `--db`, `--transcript`, `--session-id`.

1. transcript(JSONL)에서 이 세션의 `Edit`/`Write`/`MultiEdit` tool_use 의 `file_path` 들을
   수집 → 소문자 토큰 집합 `edited_tokens` (경로·파일명 분해).
2. `skill_injection WHERE session_id=? AND correlated=0` 의 각 스킬에 대해:
   - 해당 스킬의 키워드 집합(`skill_index.keywords` 또는 U0 추출)과 `edited_tokens` 교집합 ≥ 1
     → **상관 O**: `helpful_count += 1`, `last_helpful_at = now`.
   - 교집합 0 → **상관 X**: `noop_count += 1`.
   - 처리한 원장 행은 `correlated = 1` (중복 집계 방지).
3. 비차단: 오류는 stderr/hooks.log 로만, exit 0.

**한계(명시)**: 키워드↔편집경로 겹침은 휴리스틱이라 오탐·미탐이 있다. 그러나 결과가
되돌릴 수 있는 강등으로만 이어지므로 복구 가능하다(§3 하드삭제 비목표와 정합).

### 6.3 U3 정리 (`hermes-prune.py`)

입력: `--db` (+ 선택 `--config`).

- `state='active' AND noop_count >= NOOP_DEMOTE AND helpful_count = 0` → `state='demoted'`.
- `state='demoted' AND (last_helpful_at IS NULL) AND (now - 강등시각) > TOMBSTONE_DAYS`
  → `state='tombstoned'`. **파일은 삭제하지 않는다.**
- 멱등: 같은 DB에 반복 실행해도 추가 부작용 없음.
- 강등 시각 추적을 위해 `skill_index` 에 `demoted_at TEXT` 컬럼을 5.2 에 포함(누락 방지).

### 6.4 임계값 (매직넘버 금지 — 근거 + 오버라이드)

데이터 미축적 상태이므로 **보수적 기본값 + 근거**로 시작하고, 상관 데이터가 쌓이면
재튜닝한다. `.hermes/config.json` 또는 환경변수로 오버라이드:

| 상수 | 기본 | 근거 |
|------|------|------|
| `NOOP_DEMOTE` | 5 | 일회성 노이즈와 지속 무용을 가르는 최소 표본 수 |
| `TOMBSTONE_DAYS` | 14 | 한 스프린트(2주) 동안 한 번도 도움 안 됐으면 휴면 간주 |

> 재튜닝 트리거: `skill_injection` 가 충분히 쌓이면(예: 프로젝트당 correlate 처리 200건+)
> helpful/noop 분포를 실측해 임계값을 데이터 기반으로 조정한다. 이때까지는 위 기본값.

## 7. 영향 영역

- 코드(수정): `scripts/hermes-search.py`, `scripts/hermes-index-skills.py`,
  `scripts/hermes-init.py`, `assets/hooks/claude-stop-retrospective.sh`,
  `presets/workflow/hermes.conf`
- **신규 파일 (책임 1줄)**:
  - `scripts/hermes_skills.py` — 평면+폴더 스킬 순회·키워드 추출 공유 헬퍼
  - `scripts/hermes-correlate.py` — 주입 원장 ↔ transcript 편집 대조로 helpful/noop 갱신
  - `scripts/hermes-prune.py` — 임계값 기반 state 강등(active→demoted→tombstoned)
  - `tests/hermes-recall-measurement-test.sh` — 본 기능 회귀 테스트
- 룰: 없음(R 룰 변경 아님)
- 데이터: `skill_injection` 신규 + `skill_index` 컬럼 5개 추가, 멱등 마이그레이션
- 외부 의존: transcript JSONL 포맷(기존 save-session 이 이미 파싱). 신규 의존 없음

## 8. 설치 배선 (setup.sh / update-all.sh)

- `presets/workflow/hermes.conf` 의 `hermes_scripts` 복사목록에 3종 추가:
  `hermes_skills.py`, `hermes-correlate.py`, `hermes-prune.py`.
- 동일 conf 의 Stop 훅 호출 스크립트 집합(허용목록)과 메모리 규칙
  [[hermes-asset-registration]] 에 따라 두 허용목록 모두 등록.
- `claude-stop-retrospective.sh` 의 setsid 블록에 save→crystallize 다음으로
  `hermes-correlate.py`(--transcript/--session-id) → `hermes-prune.py` 호출 추가. 비차단.
- 스키마 마이그레이션은 `hermes-init.py --both` 가 설치 시 실행되므로 자동.
- 재인덱싱: conf 의 인덱싱 단계가 U4 수정본으로 평면 스킬까지 등록.
- `setup.sh` / `update-all.sh` 는 `project-claude.sh` → `hermes.conf` 재실행이므로
  기존 설치 프로젝트(zeroday 등)에 전파. **하네스 프리셋 사용 프로젝트 한정.**

## 9. 에러 처리

- 모든 신규 스크립트는 **비차단**: transcript 누락·DB 잠금·파싱 실패 시 stderr + hooks.log
  기록 후 exit 0 (기존 헤르메스 규약 M2 준수).
- DB 접근은 공통 헬퍼(`busy_timeout`+WAL, M1) 재사용.
- `--session-id` 미전달 시 원장/상관은 스킵하되 검색·주입은 정상 동작(점진적 degrade).

## 10. 테스트 (`tests/hermes-recall-measurement-test.sh`)

tmp DB + 픽스처로 AAA 패턴:

1. **U4 인덱싱**: 평면 `.md` 2개 + 폴더 `SKILL.md` 1개 → 인덱스 행 3개 단언.
2. **U1 원장**: 검색 1회 → `skill_injection` 행 수 = 주입 스킬 수.
3. **U2 상관**: 편집경로가 키워드와 겹치는 transcript 픽스처 → 해당 스킬 `helpful_count=1`,
   안 겹치는 스킬 `noop_count=1`.
4. **U3 정리**: `noop_count=5,helpful=0` 픽스처 → `demoted`; 14일 전 강등 픽스처 →
   `tombstoned`, 파일 디스크 잔존 단언.
5. **U4 랭킹**: 톰브스톤 스킬이 검색 결과에서 제외됨.
6. `tests/run-all.sh` 에 편입.

## 11. 단계 개요 (상세 태스크는 구현계획에서)

1. U5 스키마(마이그레이션) → 2. U0 공유 헬퍼 → 3. U4 인덱싱 통일 → 4. U1 원장+랭킹
→ 5. U2 상관 → 6. U3 정리 → 7. U6 배선 → 8. 테스트 → 9. zeroday 전파 검증.

스키마·헬퍼를 먼저 깔아야 이후 단위가 의존할 수 있다(순서 의미 있음).
