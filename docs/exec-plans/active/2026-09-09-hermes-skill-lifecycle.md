# 2026-09-09-hermes-skill-lifecycle — 헤르메스 스킬의 되먹임과 정리를 살린다

> 작성일: 2026-09-09
> 목적: 자동 생성된 스킬이 쌓기만 하고 낡지도 사라지지도 않는 상태를 고친다.

## 1. 동기 (Why)

2026-09-08~09 실측이다. 의견이 아니라 숫자다.

### 생성은 도는데 정리는 한 번도 안 돌았다

`zeroday-frontend/.hermes/state.db` 의 `dream_log` 48회 누적:

| 항목 | 48회 누적 |
|---|---|
| 요약 소비 | 407 |
| **결정화(생성)** | **119** |
| **진화(낡은 것 갱신)** | **0** |
| **삭제 제안** | **0** |

결과물은 `.hermes/skills/` 에 **1,028개 / 4.2 MB**. 그중 이름이 단어 조각인 것이
217개다(`bash.md` `props.md` `title.md` `v-if.md`). 내용이 쓰레기는 아니다 —
`bash.md` 는 "WSL 내부 서버는 WebFetch 말고 curl" 이라는 실제 지식이다. 이름이
`bash.md` 라 스킬 검색에 영원히 안 걸릴 뿐이다.

### 되먹임 카운터가 전부 0이다

```
used_count     min=0 max=5  합=43   (1,078행)
noop_count     min=0 max=0  합=0
helpful_count  min=0 max=0  합=0
```

`hermes-prune.py` 의 강등 조건은 `noop_count >= 5 AND helpful_count = 0` 이다.
입력이 0이므로 **조건에 영원히 도달하지 못한다.** 강등 0건, 묘비 0건, 전부 `active`.

체인: `주입 원장(3건) → correlate(입력 없음) → helpful/noop(0) → prune(강등 0)`

### 도메인 어휘가 프리셋에 하드코딩돼 있다

`hermes-dream.py` 의 진화 힌트 추출은 교정어와 아래 키워드를 **동시에** 요구한다.

```python
_SKILL_KW_RE = re.compile(
    r"(pnpm|npm|yarn|poetry|pip|docker|fastapi|svelte|postgres|mysql|redis"
    r"|pytest|vitest|eslint|prettier|ruff|mypy|버전|version)", re.IGNORECASE)
```

이 그물에 걸리는 자동 생성 스킬 비율:

| 프로젝트 | 스킬 수 | 매칭 | 비율 |
|---|---|---|---|
| zeroday-frontend | 1,028 | 27 | 2% |
| terminal-shipping | 133 | 9 | 6% |
| **novel-bc** | 95 | 0 | **0%** |

`novel-bc` 는 소설 집필 프로젝트다(`canon-check-before-scene-draft`,
`anchor-prologue-before-drafting`). `pnpm` 도 `docker` 도 나올 리 없다.
**그 프로젝트에서 진화는 구조적으로 영원히 0건이다.**

이것은 `assets/rules/harness/examples/README.md` 가 경고한 바로 그 경우다 —
강제 장치는 도메인 지식인데 도메인 지식을 프리셋에 고정값으로 박았다.

### 수동 정리 경로마저 비어 있다

`hermes-cleanup.py` dry-run 실측 (2026-09-09, `--apply` 없이):

```
== (a) junk 패턴: 0개
== (b) junk 스킬 파일: 0개
```

1,028개 중 **0개**를 잡았다. 판정 기준이 "불용어 · 2글자 이하 한글 · 서술형 어미"
라서 `bash.md` `props.md` 같은 영문 단어 조각은 대상이 아니다. 게다가 이 스크립트는
사람이 `/hermes-dream apply` 를 입력해야만 도는 수동 장치다.

### 왜 지금인가

프리셋 소속이다. 원본이 이 저장소 `scripts/` 에 있고 `presets/workflow/hermes.conf`
가 배포한다. 세 프로젝트의 `hermes-prune.py` md5 가 전부 같다(`010f9e5219df`).
**활발히 쓰는 프로젝트일수록 빨리 쌓인다.** 0개인 4곳은 안전한 게 아니라 아직
안 쌓인 것이다. zeroday 의 오늘이 나머지의 내일이다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — **주입이 실사용 세션에서 원장에 남는 이유·안 남는 이유를 확정한다.**
      검증: `docs/audits/2026-09-09-hermes-injection-gap.md` 에 원인과 재현 절차가
      적혀 있고, 그 원인을 제거한 뒤 zeroday 에서 1일 사용 후
      `select count(*) from skill_injection where injected_at > '<수정일>'` > 0.
- [ ] 목표 2 — **correlate 가 카운터를 실제로 올린다.**
      검증: 목표 1 이후 `select sum(helpful_count)+sum(noop_count) from skill_index` > 0.
- [ ] 목표 3 — **도메인 어휘 하드코딩이 사라진다.**
      검증: `grep -c 'pnpm|npm|yarn' scripts/hermes-dream.py` == 0 이고,
      novel-bc 의 실제 요약에서 진화 힌트가 1건 이상 추출된다(드라이런 로그로 확인).
- [ ] 목표 4 — **junk 판정이 실제 junk 를 잡는다.**
      검증: `hermes-cleanup.py --db <사본>` dry-run 이 217개 단어조각 중 과반을
      제안한다(현재 0개). 정상 스킬은 제안 목록에 없다 — 표본 20개를 눈으로 확인.
- [ ] 목표 5 — **전파 후 조용하다.**
      검증: `update-all.sh` 후 hermes 설치 프로젝트에서 세션 1회 — 새 경고·오류 0건,
      `.hermes/hooks.log` 에 신규 ERROR 라인 0건.
- [ ] 목표 6 — **회귀가 고정된다.**
      검증: `bash tests/run-all.sh` 통과, 신규 시험이 각 수정에 대해 가짜 위반으로
      차단을 확인한다(통과만 보는 시험 금지).

## 3. 비목표 (Out of Scope)

- **자동 삭제** — 삭제 실행은 끝까지 사람 승인이다. 이번 계획은 *제안*까지만.
- **생성 억제** — 119개 결정화 자체를 줄이는 것은 별건. 되먹임이 살아나면 어느 것이
  쓸모없는지 데이터가 생기고, 그때 근거를 갖고 정한다. 지금 줄이면 또 추측이다.
- **메모리 → 스킬 분류기** — 이 논의의 발단이었으나, 고장난 기계에 입력을 더하는
  일이다. 목표 1~2 가 끝난 뒤 별도 계획으로 판단한다.
- **`R-out` 판단(2026-09-29)** — 섞지 않는다. 계장 변경과 이 작업이 겹치면 발화율
  변화의 원인을 구분할 수 없다.
- **`.hermes/skills` 이름 재작명** — 1,028개 개명은 별건이자 위험하다. 이번엔
  junk 판정으로 *걸러내는* 것까지.

## 4. 영향 영역

- 코드 (수정):
  - `scripts/hermes-dream.py` — `_SKILL_KW_RE` 하드코딩 제거
  - `scripts/hermes-cleanup.py` — junk 판정 확장
  - `assets/hooks/claude-userpromptsubmit-reminders.sh` — 목표 1 원인에 따라 조건부
  - `scripts/hooks/` 의 대응 사본 (배포본 동기화)
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `docs/audits/2026-09-09-hermes-injection-gap.md` — 주입 원장이 실사용에서
    비는 원인의 조사 기록. 이 파일의 유일한 책임은 *원인 확정*이며 수정 방법은 담지 않는다.
  - `tests/hermes-lifecycle-test.sh` — 되먹임 체인(주입→correlate→prune)이 끊기면
    차단한다. 가짜 위반으로 각 고리의 실효를 확인하는 것이 유일한 책임.
  - `scripts/hermes-vocab.py` — **조건부**. 목표 3 을 "프로젝트 어휘 추출"로 풀 때만
    만든다. 책임: 해당 프로젝트의 축적 데이터에서 빈출 어휘를 산출한다(판정 없음).
    Step 3 의 측정 결과가 "교정어만으로 충분"으로 나오면 만들지 않는다.
- 룰: 신규 R 룰 후보 — "프리셋 코드에 도메인 어휘를 하드코딩하지 않는다".
  Step 3 완료 후 `harness-promote-rule` 로 승격 판단.
- 데이터: `.hermes/state.db` 스키마 변경 없음. **기존 행 삭제 없음.**
- 외부 의존: 없음. 표준 라이브러리만.

## 5. 단계 (Steps)

### Step 1. 주입 원장이 비는 원인 확정 [Plan]

- 입력: zeroday `.hermes/state.db` 사본, `reminders.sh`, `hermes-search.py`
- 산출: `docs/audits/2026-09-09-hermes-injection-gap.md`
- 검증: 원인 가설을 **재현**으로 확인한다. 정적 읽기로 단정하지 않는다.

**이미 반증된 가설 (2026-09-09, 되풀이 금지)**

1. ~~`--session-id` 를 안 넘긴다~~ → 호출부 둘 다 넘긴다(`reminders.sh:105`,
   `hermes-assist.sh:82`).
2. ~~원장 기록 코드가 고장~~ → 사본 DB 에 직접 실행하니 정상 기록(3→6행).
3. ~~짧은 한글 프롬프트라 매칭이 안 된다~~ → "커밋 푸시하자" "지금 하자" 등
   5개 중 4개가 3건씩 주입, 원장 12행 생성.

**남은 가설 (우선순위 순)**

- **`$PWD` vs `${CLAUDE_PROJECT_DIR}`** — `reminders.sh:87` 은 DB 경로를
  `$PWD/.hermes/state.db` 로 잡는데, 같은 파일의 스크립트 경로는 `$0` 기준이고
  다른 훅들은 `${CLAUDE_PROJECT_DIR}` 를 쓴다(`assets/hooks/*.sh` 24개 중 **20개**). 워크트리·하위 디렉터리에서 세션을
  열면 `if [[ -f ... ]]` 가 조용히 거짓이 되어 **블록 전체가 건너뛰어진다.**
  zeroday 는 워크트리를 쓴다(포트 7003 분리 관행).
- 훅이 등록됐으나 실행 중 조기 종료 — 앞 훅의 stdin 소비 등.

### Step 2. 원인 제거 + 실사용 1일 측정 [Impl]

- 입력: Step 1 의 원인
- 산출: 수정 + `update-all.sh` 전파
- 검증: 목표 1·2. **1일 뒤 카운터가 0이면 원인 확정이 틀린 것이다** — Step 1 로 돌아간다.
  카운터가 붙기 전에 Step 3 으로 넘어가지 않는다.

### Step 3. 도메인 어휘 하드코딩 제거 [Plan → Impl]

- 입력: `_SKILL_KW_RE` 없이 교정어만으로 힌트를 뽑았을 때의 **오탐 규모 실측**.
  세 프로젝트의 기존 요약에 대해 드라이런한다.
- 산출: 오탐이 감당 가능하면 키워드 조건 제거. 아니면 `hermes-vocab.py` 로
  프로젝트별 어휘 산출.
- 검증: 목표 3. novel-bc 에서 힌트가 1건 이상 나오는 것이 성공 기준이다 —
  zeroday 만 좋아지는 수정은 같은 실수의 반복이다.

> ⚠️ **키워드를 추가하는 방식은 금지한다.** 18개를 21개로 늘려도 novel-bc 는 0%다.

### Step 4. junk 판정 확장 [Impl]

- 입력: 217개 단어조각 표본, 정상 스킬 표본
- 산출: `hermes-cleanup.py` 판정 확장
- 검증: 목표 4. **정상 스킬을 하나라도 제안하면 실패다** — 되돌릴 수 없는 삭제로
  이어지는 판정이므로 미탐(놓침)보다 오탐(잘못 지목)이 훨씬 비싸다.

### Step 5. 시험 고정 + 전파 [Impl → Review]

- 산출: `tests/hermes-lifecycle-test.sh`, `run-all.sh` 등록, 전파
- 검증: 목표 5·6. 큰 변경이자 12곳 공유 경계이므로 `code-reviewer` 로 승격한다.

## 6. 의사결정 로그

- 2026-09-09: 진화 그물을 **넓히지** 않고 **없애는** 방향으로 정함 — 근거: 키워드
  추가는 zeroday 어휘를 늘릴 뿐이고 novel-bc 는 여전히 0%. 세션 중 "jira·swagger·
  figma 를 추가하자"고 제안했다가 같은 실수임을 확인하고 철회.
- 2026-09-09: 삭제는 사람 승인 유지 — 근거: 되돌릴 수 없다. 자동 삭제가 오탐을
  내면 12곳에서 동시에 지식이 사라진다.
- 2026-09-09: Step 2 의 카운터 확인 전에는 Step 3 으로 넘어가지 않음 — 근거:
  되먹임이 죽은 채로 진화를 고치면 무엇이 좋아졌는지 잴 수 없다.

## 7. 발견·예외

- **`hermes-crystallize` 는 정상 작동 중이다.** 이번 계획은 생성이 아니라 *되먹임*을
  고친다. 생성을 끄자는 판단이 아님을 명시해 둔다.
- **`used_count`(43) 와 원장(3건) 의 불일치**는 아직 설명되지 않았다. Step 1 에서
  같이 본다. 두 값이 같은 지점에서 기록되는데 다르다는 것은 한쪽이 더 오래된
  코드거나 경로가 둘이라는 뜻이다.
- **R 룰 후보**: "프리셋 코드에 도메인 어휘를 하드코딩하지 않는다." 지금 승격하면
  근거가 사례 1건뿐이다. Step 3 에서 실제로 고친 뒤 판단한다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
