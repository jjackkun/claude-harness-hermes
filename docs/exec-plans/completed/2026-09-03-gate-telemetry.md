# 2026-09-03-gate-telemetry — 게이트 발화 기록과 R-mut 주간 트리거

## 1. 동기 (Why)

`docs/design-docs/core-beliefs.md` 의 R 룰 19개 중 **10개가 Provisional** 이다 —
`검증 상태` 헤더로 표기된 9개(R-iface:63, R-declare:68, R-struct-4:102, R-cx:148,
R-dep:178, R-cov:209, R-acc:299, R-plan-stale:342, R-retro:357) + 본문 인라인 1개
(R-pipe:276). 이 중 4개는 승격 조건으로 **발화율 관측을 명시**한다
(R-iface "발화율을 관측해 과발화하면 임계를 재산정", R-declare·R-cov·R-acc "발화율 관측 중").
R-plan-stale 은 "오탐 데이터를 `docs/audits/` 에 쌓은 뒤 차단 승격을 검토" 로 같은 것을 요구한다.
(R-mut:240 은 Provisional 이 아니라 **진단 도구** 이며, 별도로 Step 5 에서 다룬다.)

그러나 **발화를 기록하는 코드가 한 곳도 없다.** `scripts/hooks/*.sh` 와
`assets/hooks/*.sh` 전체에서 로그 append 패턴(`tee -a`, `>> *.log`, `HARNESS_LOG`)
매치 0건(2026-09-03 실측). 즉 승격·강등 판단의 입력이 존재하지 않으며,
Provisional 은 상태가 아니라 영구 라벨이 되어 있다.

이는 이 저장소가 이미 두 번 겪은 결함과 같은 종류다:

- `core-beliefs.md:280` (2026-08-24 정정) — pre-commit 이 `.review-dirty` 를
  **한 번도 읽지 않았는데** 문서는 "안 지우면 차단" 이라고 주장했다.
- 같은 문단이 지적하는 `R-test` — 테스트 0개라서 늘 통과하고 있었다.

문서가 주장하는 절차에 기계가 없는 상태가 세 번째로 반복됐다.

부수적으로, `scripts/mutation-probe.py`(R-mut)는 **진단 도구로 도입됐으나 실행 트리거가
없다.** 수동 실행뿐이라 생존 변이 목록("테스트를 추가할 지점")이 갱신되지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 게이트가 판정할 때마다 이벤트 1줄이 `.harness/gate-events.jsonl` 에 남는다.
      (런타임 7개 + pre-commit 7개 계장 완료, 2026-09-03)
      검증: 일부러 위반 파일을 만들어 `iface-guard` 차단 → 해당 파일에 `verdict":"block"` 레코드 1건 확인.
- [x] 목표 2 — 통과(pass)·우회(waived)도 같은 파일에 기록된다. 발화율의 **분모** 확보.
      (런타임 훅 축 Step 2a 완료, 2026-09-03. pre-commit 축은 Step 2b.)
      검증: 정상 파일 Write → `verdict":"pass"` 레코드, waiver 주석 파일 → `verdict":"waived"` 레코드.
- [x] 목표 3 — `gate_report.py` 가 룰별 (기회, 차단, 경고, 우회, 발화율)을 표로 출력한다.
      (Step 3 완료, 2026-09-03. `건너뜀` 열 추가 — 죽은 게이트 탐지.)
      검증: 위 3건을 넣은 상태에서 실행 → iface 행의 기회 3 / 차단 1 / 우회 1 확인.
- [x] 목표 4 — **R-plan-missing 이 실제로 발화하는지 답한다** (2026-09-08 완료).
      답: 둘 다 아니다. **계장이 없어 판정 자체가 불가능했다** — `R-plan-missing`·
      `R-plan-stale` 이 `gate_add` 를 부르지 않아 176건의 이벤트에 한 줄도 없었다.
      화면에는 경고를 찍으면서(이 세션 커밋 4건 전부) 기록은 0건이었다.
      부수 발견: `active/` 에 계획서가 하나라도 있으면 `R-plan-missing` 분기에
      도달하지 않는다 — 이 계획서 자신이 자기를 검사하는 게이트를 가리고 있었다.
      기록: `docs/audits/2026-09-08-plan-gate-firing.md`. 두 게이트는 계장 완료.
      남은 미계장 6종은 `docs/exec-plans/backlog/instrument-remaining-gates.md`.
- [x] 목표 5 — R-mut 이 주 1회 자동 실행되어 생존 변이를 알린다. (Step 5 완료, 2026-09-03)
      검증: 상태 파일 `.harness/mutation-last-run` 의 값을 8일 전으로 조작 → SessionStart 에서
      실행됨. 1일 전 → 침묵.
- [x] 목표 6 — 이벤트 파일이 무한히 자라지 않는다. (Step 1 완료, 2026-09-03)
      검증: 상한(`GATE_EVENTS_MAX_LINES`, 기본 5000) 초과 레코드를 넣고 emitter 실행 →
      가장 오래된 줄부터 잘려 상한 이하 유지됨을 단언.

## 3. 비목표 (Out of Scope)

- **새 차단 게이트 추가 금지.** 이번 작업은 기존 게이트를 *관측*만 한다.
  Provisional 10개를 정리하기 전에 11번째를 만들지 않는다.
- **기존 파일 통째 Write 덮어쓰기 경고**(검토 후 기각). `core-beliefs.md:84` 의
  R-declare 침묵 조건이 "기존 파일 덮어쓰기도 대상이 아니다"로 이미 제외를 결정했고,
  `docs/audits/` 에 유실 사고 기록이 없다. 같은 훅 지점에서 같은 행위를 하나는 무시하고
  하나는 경고하게 된다. 되살리려면 실제 사고 기록이 먼저다.
- **임계값 변경 금지.** 이번 계획은 데이터를 만들 뿐, R-iface 8 이나 R-cx 12 를 건드리지 않는다.
- 발화율 기반 자동 승격·강등. 판정은 사람이 한다.

## 4. 영향 영역

- 코드: `assets/hooks/` (원본) → `scripts/hooks/` (설치기 사본).
  기존 훅 계장은 각 파일에 emitter 호출 1~2줄 추가.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/hooks/gate_event.py` — 게이트 판정 1건을 `.harness/gate-events.jsonl` 에 append 한다.
  - `assets/hooks/gate_emit.sh` — 셸 훅이 판정 1건을 기록할 때 쓰는 호출 규약(모듈 탐색 + 인자 조립)을 한 곳에 둔다.
  - `assets/hooks/gate_report.py` — 누적된 gate-events 를 룰별 발화율 표로 집계한다.
  - `assets/hooks/claude-sessionstart-mutation-probe.sh` — 주 1회 R-mut 대상 1개를 실행하고 생존 변이를 알린다.
  - `tests/gate-event-test.sh` — emitter 의 레코드 형식·append·실패 무해성을 단언한다.
  - `tests/gate-report-test.sh` — 집계기의 룰별 카운트·발화율 계산을 단언한다.
  - `tests/mutation-trigger-test.sh` — 주기 판정(8일 경과 실행 / 1일 침묵)을 단언한다.
- 룰: R-iface, R-declare, R-cx, R-dep, R-size, R-plan-missing, R-mut (관측 대상)
- 데이터: 마이그레이션 없음. `.harness/` 는 로컬 전용 — `.gitignore` 에 추가.
  - `.harness/gate-events.jsonl` — 게이트 판정 이벤트 (상한 초과 시 앞에서부터 절삭)
  - `.harness/mutation-last-run` — R-mut 마지막 실행 시각 (epoch 초 1줄)
- 외부 의존: 없음. python3 표준 라이브러리만.

### 4-1. 이벤트 스키마 (emitter 와 집계기가 공유하는 계약)

필드명이 두 파일에서 갈라지면 집계가 조용히 0을 낸다. **정의의 주인은 `gate_event.py` 하나**이고,
`gate_report.py` 는 그 상수를 import 한다 — `iface_width.py` 를 생성·편집 두 시점이 공유하는 것과 같은 판단이다.

| 필드 | 타입 | 의미 |
|---|---|---|
| `ts` | int | epoch 초 |
| `rule` | str | R 룰 ID (`R-iface`, `R-cx` …) |
| `verdict` | str | `pass` \| `warn` \| `block` \| `waived` |
| `stage` | str | `pretooluse` \| `posttooluse` \| `precommit` \| `sessionstart` |
| `path` | str \| null | 판정 대상 파일 (없으면 null) |
| `detail` | str \| null | 임계 초과값 등 한 줄 (없으면 null) |

`session` 은 넣지 않는다 — pre-commit 에는 세션 개념이 없어 절반이 null 이 되고,
발화율 계산에 쓰이지 않는다.

## 5. 단계 (Steps)

### Step 1. emitter 작성 [Impl]

- 입력: 없음 (신규)
- 산출: `assets/hooks/gate_event.py`, `tests/gate-event-test.sh`, `.gitignore` 항목
- **적재 위치 결정**: `${CLAUDE_PROJECT_DIR}` → 없으면 `git rev-parse --show-toplevel`
  → 그것도 실패하면 **기록하지 않고 조용히 성공한다**(훅을 죽이지 않는다).
  이 저장소의 훅 10개가 이미 쓰는 관행이며(`grep -l CLAUDE_PROJECT_DIR scripts/hooks/*.sh`),
  프로젝트마다 자기 루트 아래 `.harness/` 에 쌓이므로 설치처가 늘어도 섞이지 않는다.
  cwd 기준은 쓰지 않는다 — pre-commit 과 훅의 cwd 가 다르다.
- **로테이션**: append 후 줄 수가 `GATE_EVENTS_MAX_LINES`(기본 5000) 를 넘으면
  가장 오래된 줄부터 잘라 상한을 유지한다. 시간 기반이 아니라 줄 수 기반인 이유는
  발화 빈도가 프로젝트마다 다르고, 디스크 상한은 시간이 아니라 부피의 함수이기 때문이다.
- 검증: `bash tests/gate-event-test.sh` 통과. 다음 셋을 단언한다 —
  (a) 레코드 형식이 §4-1 스키마와 일치, (b) 디스크 쓰기 실패 시 exit 0 (훅 무해),
  (c) 상한 초과 시 절삭.

### Step 2a. 런타임 훅 계장 [Impl]

- 입력: Step 1 emitter
- 산출: PreToolUse `iface-guard`·`plan-declare`·`agent-guard`·`bash-guard`,
  PostToolUse `size-warn`·`dead-file-warn`·`review-reminder` 가 판정 시 이벤트를 남긴다.
- **프로세스 기동 정책 (2026-09-03 실측 후 개정)**: 당초 "별도 프로세스 금지" 였으나,
  대부분의 판정 지점이 python 블록이 아니라 **셸 쪽**에 있어 그대로 지키려면 훅 7개를
  구조 개편해야 한다. 관측을 붙이자고 게이트를 재작성하는 것은 위험 대비 이득이 없다.
  - 실측: emit 1회 **21ms**, size-warn 훅 1회 **27ms**(조기 반환 경로).
  - 개정된 규칙: **판정이 실제로 일어난 지점에서만** 호출한다. 대상 아님으로 조기 반환하는
    경로(확장자 불일치, 기존 파일, 계획 부재 등)에서는 부르지 않는다. 그래서 도구 호출마다
    비용이 붙지 않고, 게이트가 실제로 룰을 평가한 횟수만큼만 붙는다.
  - 예외: `iface-guard` 는 판정이 python 블록 안에 있으므로 그 안에서 기록한다(프로세스 0 추가).
  - `dead-file-warn` 은 이미 ripgrep 전체 스캔을 돌아 21ms 가 무의미하다.
  - python3 를 안 쓰는 훅(`stop-perm-prompt-fatigue`)은 이번 대상이 아니다.
- 검증: 게이트마다 위반 1건을 인위로 만들어 레코드 발생 확인 **+ 정상 입력으로 pass 레코드 확인**.
  **통과만 보는 검증 금지** — `tests/harness-hooks-smoke.sh` 의 silent-skip 사례 재발 방지.
  지연 기준은 **훅 1회당 emitter 프로세스 1회 이하**다 (실측 21ms).
  당초 "기존 소요의 20% 이내" 로 잡았으나 그 기준은 성립하지 않는다 —
  size-warn 자체가 32ms 라 프로세스 하나만 띄워도 이미 75% 다. 싼 훅에서는
  파이썬 기동 1회가 훅 전체와 같은 자릿수이므로, 비율이 아니라 **기동 횟수**가
  통제해야 할 양이다. 축을 둘 이상 판정하는 훅은 배치(`+` 구분)로 묶어 1회를 지킨다.

### Step 2b. pre-commit 계장 [Impl]

- 입력: Step 2a
- 산출: `assets/hooks/pre-commit.sh` 의 R-size / R-cx / R-dep / R-secret / R-plan /
  R-retro / R-pipe 가 판정 시 이벤트를 남긴다.
- 검증: 각 게이트를 실제로 위반하는 스테이징을 만들어 레코드 확인 후 원복.
- **왜 2a 와 나누는가**: 런타임 훅과 커밋 훅은 실행 시점·입력 형식·실패 영향이 모두 다르다.
  한 단계로 묶으면 14개 지점 중 하나만 틀려도 단계 전체가 실패로 보이고, diff 도 리뷰 불가능해진다.

### Step 3. 집계기 작성 [Impl]

- 입력: Step 2a·2b 가 만든 이벤트
- 산출: `assets/hooks/gate_report.py`, `tests/gate-report-test.sh`
- 검증: `bash tests/gate-report-test.sh` 통과. 필드명은 §4-1 상수를 import 해 쓰며,
  하드코딩된 문자열 키가 없음을 테스트가 단언한다.
- **`.deprc` 등록 필수**: 신규 파이썬 2개(`gate_event.py`, `gate_report.py`)가 의존 계약에
  등록되지 않으면 R-dep-4 경고가 매 커밋 발생한다 — 2026-08-25 자기 설치 첫 커밋에서
  실제로 겪은 사고이며 `pre-commit.sh:55-60` 주석에 남아 있다.
  (Step 2a·2b 가 편집하는 대상은 전부 셸이라 R-cx 대상이 아니다 — `complexity.py` 는 `ast` 기반 파이썬 전용.)

### Step 4. 첫 관측과 판정 [Review]

- 입력: 1주일치 실사용 이벤트
- 산출: `docs/audits/2026-09-XX-gate-firing-baseline.md`
- 검증: Provisional 10개 각각에 대해 (과발화 / 정상 / 무발화) 판정 기재.
  목표 4(R-plan-missing)의 답을 여기 포함.

### Step 5. R-mut 주간 트리거 [Impl]

- 입력: 기존 `scripts/mutation-probe.py`
- 산출: `assets/hooks/claude-sessionstart-mutation-probe.sh`,
  상태 파일 `.harness/mutation-last-run` ("<epoch> <다음 대상 인덱스>"),
  `.harness/mutation-report.txt` (다음 세션 1회 보고 후 삭제), `tests/mutation-trigger-test.sh`
- **인라인 실행 금지**: 변이 1회가 ~40초라 SessionStart 에서 기다리면 매주 한 번 세션이
  40초 멈춘다 — 사람이 훅을 끈다. 백그라운드(setsid)로 띄우고 결과는 다음 세션에 보고한다.
- **대상은 짝 테스트가 있는 파일만**: 짝이 없으면 전부 생존으로 나오는데 그건 테스트가
  약한 것이 아니라 없는 것이다 — R-cov 의 관할이지 R-mut 의 신호가 아니다.
- 검증: `bash tests/mutation-trigger-test.sh` 통과. 전수 실행이 수십 분이므로
  1회 1개 대상 상한을 단언.

## 6. 의사결정 로그

- 2026-09-03: **통과(pass)도 기록한다** — 근거: 발화율은 발화/기회이며, 차단만 기록하면
  분모가 없어 "율"이 나오지 않는다. 부피는 게이트 발동 자체가 드물어 문제되지 않는다.
- 2026-09-03: **우회(waived)를 별도 verdict 로 둔다** — 근거: R-iface 가 경계하는 것은
  차단 횟수가 아니라 "우회의 상시화"다. waiver 주석 통과를 pass 로 세면 그 신호가 사라진다.
- 2026-09-03: **`.harness/` 는 git 추적하지 않는다** — 근거: 발화 기록은 개발자 로컬 사건이고
  커밋하면 매 커밋마다 diff 노이즈가 된다. `docs/audits/` 생존 변이 목록이 로컬 전용인 것과 같은 취급.
- 2026-09-03: **emitter 를 독립 파일로 둔다(공용 lib 에 넣지 않음)** — 근거: 훅은 설치기가
  프로젝트로 **개별 복사**하며 서로를 source 하지 않는다(`plan_state.py`·`iface_width.py` 와 같은 패턴).
- 2026-09-03: **2번 항목(Write 덮어쓰기 경고)을 기각** — 근거: §3 비목표 참조.
- 2026-09-03: **적재 경로는 `CLAUDE_PROJECT_DIR` → git root → 무기록 순** — 근거: 이 저장소
  훅 10개가 이미 쓰는 관행이고, cwd 는 pre-commit 과 훅이 서로 달라 신뢰할 수 없다.
  루트를 못 찾을 때 기록을 포기하는 이유는 관측 장치가 게이트를 죽이면 안 되기 때문이다.
- 2026-09-03: **로테이션은 줄 수 기준(기본 5000)** — 근거: 발화 빈도가 프로젝트마다 달라
  시간 기준은 부피를 보장하지 못한다. 디스크 상한은 부피의 함수다.
- 2026-09-03: **emitter 를 별도 프로세스로 띄우지 않는다** — 근거: 대상 훅 7개가 이미 python3 를
  1~7회 기동 중이다. 프로세스를 더 늘리면 관측 비용이 게이트 비용을 넘는다.
- 2026-09-03: **스키마 정의의 주인은 `gate_event.py` 하나** — 근거: 같은 것을 두 곳에서 정의하면
  반드시 갈라진다. `iface_width.py` 통합과 같은 판단(`core-beliefs.md` R-iface 절).
- 2026-09-03: **Step 2 를 런타임(2a)/커밋(2b)으로 분리** — 근거: 14개 지점을 한 단계로 묶으면
  하나만 틀려도 단계 전체가 실패로 보이고 diff 리뷰가 불가능해진다. 리뷰 지적 반영.
- 2026-09-03: **`session` 필드를 넣지 않는다** — 근거: pre-commit 에는 세션 개념이 없어 절반이
  null 이 되고, 발화율 계산에 쓰이지 않는다.

## 7. 발견·예외

- 2026-09-03 `planner-lite` 리뷰 (판정 NEEDS_WORK, 지적 8건). 7건 반영, 1건은 방향 수정 후 반영.
  - 반영: 로테이션 부재(HIGH) → §2 목표 6 + Step 1 / 적재 경로 미정(HIGH) → Step 1 /
    스키마 필드 부재(MEDIUM) → §4-1 / 훅 지연 미검토(MEDIUM) → Step 2a /
    Step 2 범위 폭증(MEDIUM) → Step 2a·2b 분리 / 상태 파일 누락(LOW) → Step 5 /
    목표 4 산출 위치 불일치(LOW) → §2 정정.
  - **방향 수정**: "Step 2 대상 파일의 R-cx baseline 사전 점검" 지적은 전제가 어긋난다.
    `complexity.py` 는 `ast` 기반 **파이썬 전용**이고 Step 2a·2b 가 편집하는 대상은 전부 셸이라
    R-cx 대상이 아니다. 다만 지적이 가리킨 *자기 참조 위험 자체는 실재*하며, 실제 위치는
    R-cx 가 아니라 **R-dep** 다 — 신규 파이썬 2개가 `.deprc` 에 등록되지 않으면 매 커밋
    R-dep-4 경고가 뜬다(2026-08-25 실제 사고, `pre-commit.sh:55-60`). Step 3 에 반영.
- 훅 지연 임계를 절대값(ms)이 아니라 **기존 소요 대비 비율**로 잡았다. 훅마다 기존 python3
  기동 횟수가 1~7회로 달라 같은 ms 잣대가 서로 다른 것을 재게 된다.

### 커밋 전 리뷰에서 (2026-09-03)

- **설치기가 `.git/hooks/` 에 emitter 를 넣지 않아 다운스트림 pre-commit 계장이
  전부 조용히 꺼질 뻔했다.** `HARNESS_HOOK_SOURCES` 는 `scripts/hooks/` 로만 배치하는데
  `pre-commit` 은 `$(dirname $0)` = `.git/hooks/` 에서 형제 파일을 찾는다.
  `lib/harness_installers.sh` 의 `.git/hooks` 동반 파일 목록(check-secrets·plan_state·
  complexity·coverage_probe·depcheck)에 `gate_event.py`·`gate_emit.sh` 를 추가했고,
  설치 경로와 "emitter 없어도 게이트는 동작" 을 테스트가 단언한다.
  **등록 배열이 둘인데 하나만 보면 놓친다** — 리뷰어도 `HARNESS_HOOK_SOURCES` 만 확인했다.
- `scripts/hooks/pre-commit.sh` 사본을 잘못 만들어 두었다(설치기는 `.git/hooks/` 에만 둔다).
  제거했다.
- 이 저장소의 `.git/hooks/pre-commit` 이 구버전이라 갱신했다. 안 했으면 이번 커밋이
  계장되지 않은 옛 훅으로 검사돼 도그푸딩이 성립하지 않았다.

### 후속 (2026-09-03)

- **R5 오탐은 별도 계획으로 수정 완료** — `docs/exec-plans/completed/2026-09-03-r5-false-positive.md`.
  이 계획의 §3 비목표(기존 게이트 수정 금지)를 지켜, 관측은 보고까지만 하고
  수정은 승인 후 별도 계획·별도 테스트로 처리했다. 관측 → 보고 → 승인 → 수정의
  경로가 실제로 한 바퀴 돌았다.
- 그 과정에서 **신규 테스트 6개가 `run-all.sh` 에 미등록**이라 한 번도 CI 에서
  돌지 않았다는 것이 드러났다(등록 후 40 → 46개, 전부 통과).
  근본 대응은 `docs/exec-plans/backlog/run-all-orphan-test-guard.md`.

### Step 5 실행 중 발견 (2026-09-03)

- **`hermes-pipeline-test.sh` 가 간헐 실패한다(플레이키).** `run-all.sh` 3회 실행 중 1회
  실패로 집계됐고, 같은 테스트가 단독 실행과 이후 재실행에서는 통과했다(최종 40/40, exit 0).
  이번 변경과 무관한 기존 불안정성이며, 이 계획의 범위 밖이라 **보고만 한다.**
  게이트 관측이 자리 잡으면 이런 간헐 실패도 발화율로 드러난다.

### Step 2b~3 실행 중 발견 (2026-09-03)

- **첫 관측이 곧바로 R5 과발화를 드러냈다.** `bash-guard` 의 `-n` 탐지가 단어 단위라
  `grep -n`·`sort -n`·`head -n` 이 전부 발화한다. 관측된 14건이 **전부 오탐**이었고
  발화율 100% 다. 차단이 아니라 컨텍스트 주입이라 지금까지 배경 소음으로 묻혀 있었다.
  §3 비목표("기존 게이트 수정 금지")에 따라 **보고만 한다** —
  `docs/audits/2026-09-03-gate-firing-first-observation.md`.
- **테스트가 실제 관측 파일을 오염시켰다.** `mutation-probe` 가 경로 판정을 변이시키면
  폴백이 저장소로 향해 픽스처 룰 10건이 실제 `.harness/` 에 쌓였다. 모든 emit 호출을
  임시 디렉터리 cwd 에서 실행하도록 고쳤고(재오염 0건 확인), 기존 오염분은 제거했다.
- **`skipped` verdict 를 추가했다.** 판정 모듈이 없어 검사를 건너뛴 상태를 `pass` 로 세면
  "게이트가 죽었는데 통과 표시가 나는" 상태가 관측에서도 재현된다. 이 저장소가 R-test 와
  `.review-dirty` 에서 두 번 겪은 실패 형태라, 분모에서 빼고 별도 열로 경고한다.
- **R-cx 가 `gate_report.py` 초안을 잡았다** (main 17, format_table 14 > 한도 11).
  우회하지 않고 `_row`·`_rate_key`·`_render`·`_parse_args`·`_notes` 로 분리했다.

### Step 2a 실행 중 발견 (2026-09-03)

- **지연 기준을 잘못 잡았다.** "기존 소요의 20% 이내" 는 훅이 파이썬 기동보다 훨씬
  비싸다는 가정에 기대는데, 실측하니 size-warn 훅 전체가 32ms 이고 emitter 기동이 21ms 다.
  같은 자릿수라 어떤 계장도 이 기준을 통과할 수 없다. 통제해야 할 양은 비율이 아니라
  **훅당 프로세스 기동 횟수**였다. 기준을 그렇게 바꾸고, 축을 둘 판정하는 size-warn 은
  배치로 묶어 2회 → 1회로 줄였다(43ms → 24ms).
- **같은 룰 키에 분모가 다른 모집단이 섞일 뻔했다.** `review-reminder`(편집마다)와
  `bash-guard`(커밋마다)가 둘 다 `R-review` 로 기록하면 발화율이 아무것도 뜻하지 않는다.
  전자를 `R-review-debt` 로 분리했다. 같은 이유로 size-warn 의 두 축도
  `R-size`(줄 수)와 `R-size-resp`(책임 증가)로 나눴다 — 후자는 기준선이 있는 파일만
  평가되므로 분모가 다르다.
- **`gate_emit.sh` 를 새로 만들면서 R-declare 가 실제로 작동하는 것을 확인했다.**
  계획서 §4 에 없는 파일이라 먼저 §4 에 책임 한 줄을 적고 만들었다. 게이트가 의도대로
  "만들기 전에 책임을 적게" 만든 첫 사례다.

### Step 1 실행 중 발견 (2026-09-03)

- **[룰 후보] `mutation-probe.py` 가 stale `.pyc` 를 남겨 이후 import 를 오염시킨다.**
  변이 주입과 복원이 **같은 초 안에, 같은 파일 크기로** 일어나면 CPython 의 (mtime, size)
  기반 pyc 검증이 통과해 **변이본 바이트코드가 재사용된다.** 실제로 `gate-event-test.sh` 의
  스키마 단언이 이 때문에 조용히 깨졌고, 원인이 코드가 아니라 캐시라 진단에 시간이 걸렸다.
  당장의 대응은 테스트에서 `python3 -B` 를 쓰는 것(적용 완료)이지만, **근본 대응은
  `mutation-probe.py` 가 복원 시 대상의 `__pycache__` 항목을 지우는 것**이다.
  같은 함정을 밟을 다음 테스트가 반드시 나온다 → `harness-promote-rule` 대상.
  이 계획의 범위 밖이므로 `docs/exec-plans/backlog/mutation-probe-pyc-invalidation.md` 로 넘긴다.
- **의미 동등 변이 1건은 잡을 수 없다.** `gate_event.py:57` 의 `or → and` 는 도달 가능한
  모든 상태(`root` 가 빈 문자열이거나 실재 디렉터리)에서 결과가 같다. 변이 점수 95.5%
  (22개 중 21개 killed)가 이 파일의 상한이다. 억지로 100% 를 만들려 하지 않는다.
- **`.gitignore` 하네스 블록은 "Do not edit between markers" 인데 생성기에 없는 항목이
  손으로 들어가 있었다** (`.claude/harness-hooks.lock`, 2026-09-02). 이번에는 `.harness/` 를
  생성기(`lib/harness_installers.sh`)에 먼저 넣고 이 리포에도 같은 값을 반영해 어긋남을 늘리지 않았다.
  다만 **손 편집분이 생성기에 없는 상태 자체는 남아 있다** — 재설치하면 사라진다. 별도 정리 대상.

## 8. 회고

**계획대로 된 것**: 게이트 발화가 `.harness/gate-events.jsonl` 에 쌓이고
`gate_report.py` 가 룰별 발화율을 낸다. 176건이 모였고, R-doc 같은 새 게이트가
바로 이 표에 올라온다. 상한(5000줄) 절단과 R-mut 주간 트리거도 동작한다.

**계획이 놓친 것**: Step 2b 가 "pre-commit 축 계장" 을 완료로 선언했지만 실제로는
16종 중 8종만 계장했다. 목표 4 에 답하려는 순간 대상 게이트가 그 8종 밖이었다.
**"관측 장치가 있다" 와 "관측되고 있다" 는 다르다** — 계장 여부를 세는 검사가
없으면 이 상태는 다시 발생한다. backlog 에 그 검사를 남겼다.

**미완으로 오래 남은 대가**: 이 계획서가 목표 4 하나 때문에 5일간 active 에
머물렀고, 그 결과 `R-plan-stale` 이 커밋마다 발화해 4번 무시됐다. 무시되는 경고는
채널 전체를 무디게 만든다 — 미완 항목은 답을 내거나 backlog 로 내려야 한다.

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
