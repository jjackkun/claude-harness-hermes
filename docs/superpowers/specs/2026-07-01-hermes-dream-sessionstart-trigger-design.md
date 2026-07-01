# 드림 세션 시작 트리거 (cron 대체) 설계 (2026-07-01)

> 작성일: 2026-07-01
> 목적: 드리밍을 cron 대신 **SessionStart 훅**으로 자동 구동한다. 세션을 여는 자연스러운 시점에
> 하루 1회만(throttle) 백그라운드로 드림을 돌려, 별도 스케줄러(cron) 없이 자동 드리밍을 달성한다.

## 1. 동기 (Why)

드리밍은 지금까지 두 경로로만 돌았다: cron `dream` 액션(사용자가 crontab에 직접 등록해야 함) 또는
`/hermes-dream` 수동 호출. 실측 결과 사용자 crontab은 비어 있어 **자동 드림이 한 번도 실행된 적
없다**(`no crontab for jjackkun`). cron은 등록 부담·PATH 이슈·WSL 환경 편차가 커서 실효성이 낮다.

앞선 작업(별건)에서 cron `dream` 액션은 이미 제거됐다(`hermes-cron-run.sh`는 자율 매니저
start/check/end 전용). 이제 그 대체재로, Claude Code가 이미 제공하는 **SessionStart 훅**에 드림을
얹는다. 러닝 루프가 Stop 훅으로 자동 배선되어 있듯, 드림도 세션 경계 훅으로 자동화한다.

**세션 시작이 드림의 최적 시점인 이유**: 직전 세션들의 5슬롯 요약이 모두 쌓인 뒤라 통합 재료가
최대이고, Stop 훅(저장·요약)과 시점이 겹치지 않아 DB 경합이 없다.

## 2. 목표 (What — 검증 가능)

- [ ] **G1 세션 시작 자동 구동** — SessionStart 훅이 등록되어, 세션 시작 시 드림 경로가 평가된다.
  검증: `hermes` 프리셋 설치 후 생성된 `settings.json`(또는 `settings.local.json`)의
  `hooks.SessionStart`에 드림 훅 커맨드가 존재.
- [ ] **G2 source 게이트** — `source`가 `startup` 또는 `resume`일 때만 드림을 시도하고,
  `clear`·`compact`에서는 아무것도 하지 않고 즉시 종료한다. 검증: 4개 source 각각을 stdin으로
  주입 → startup/resume은 드림 실행 경로 진입, clear/compact는 미진입(마커·로그로 확인).
- [ ] **G3 throttle(하루 1회)** — 마지막 드림 이후 `HERMES_DREAM_THROTTLE_HOURS`(기본 20) 이내면
  드림을 실행하지 않고 즉시 종료한다. 검증: 마커를 방금 시각으로 두고 훅 발화 → 미실행;
  마커를 21시간 전으로 두고 발화 → 실행.
- [ ] **G4 비차단** — 훅은 세션 시작을 블로킹하지 않는다. 드림은 `setsid` 백그라운드로 분리되고
  훅은 즉시 exit 0. 검증: 훅 본체 실행 시간이 상수 시간(수십 ms)이며, 드림 완료를 기다리지 않음.
- [ ] **G5 자동 실행은 dry-run** — 세션 훅 자동 드림은 삭제를 실행하지 않는다(`--apply` 없음).
  검증: junk 스킬이 있어도 훅 경유 드림 후 파일이 남아 있고, 리포트엔 제안만.
- [ ] **G6 source 가시화(실측)** — 발화한 source 값과 결정(실행/게이트)을 `hooks.log`에 한 줄
  남긴다. 검증: 각 source 주입 시 로그에 `source=<값>` 라인이 남음. (문서에 명시 안 된 picker
  진입의 실제 source를 사용자가 눈으로 확인하는 근거.)
- [ ] **G7 안전 종료** — DB 부재·python3 부재·stdin 파싱 실패 등 어떤 경우에도 비차단 exit 0.
  검증: 각 결핍 상황에서 훅이 오류 없이 0 종료.
- [ ] **G8 옵트아웃** — `HERMES_DISABLED=1`(전체) 또는 `HERMES_DREAM_ON_SESSION_START=0`(이 트리거만)
  으로 끌 수 있다. 검증: 각 env 설정 시 미실행.

## 3. 비목표 (Out of Scope)

- **드림 엔진 내부 로직** — `hermes-dream.py`의 propose/청킹/워터마크/이월은 불변. 훅은 이를 호출만 한다.
- **자율 매니저(cron start/check/end)** — 별개 기능. cron 유지. 본 spec 무관.
- **cron `dream` 액션 제거** — 앞선 별건에서 이미 완료. 본 spec은 대체 트리거 신설만 다룬다.
- **드림 결과의 세션 주입** — SessionStart는 stdout으로 `additionalContext` 주입이 가능하나, 드림은
  백그라운드로 돌아 시점상 결과를 즉시 못 준다. "직전 드림 리포트 요약 주입"은 후속 과제(§11).
- **throttle를 dream_log 기반으로** — 본 spec은 마커 파일 기반(아래 §6.3 근거). dream_log 결합은 대안으로만 기록.

## 4. 아키텍처

### 4.1 배선 (기존 인프라 재사용 — 신규 인프라 0)

`SESSION_START_HOOKS` 배열은 이미 설치 파이프라인 전체가 지원한다:
`lib/preset.sh`(선언) → `lib/settings_gen.sh`(기록) → `lib/generate_settings_json.py:147`
(`hooks.SessionStart` 생성) → `lib/windows.sh`(경로 래핑). `serena.conf`가 동일 패턴의 선례다.

따라서 배선은 `hermes.conf`에 두 줄 추가뿐이다:

```bash
HARNESS_HOOK_SOURCES+=(claude-sessionstart-dream.sh)
SESSION_START_HOOKS+=('${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-sessionstart-dream.sh')
```

### 4.2 데이터 흐름 (훅 본체)

```
SessionStart 발화 → stdin JSON { source, cwd, session_id, ... }
  │
  ├─ [게이트 0] HERMES_DISABLED=1 or HERMES_DREAM_ON_SESSION_START=0 → exit 0
  ├─ [게이트 1] python3 없음 → exit 0
  ├─ stdin에서 source·cwd 추출 (jq 우선, python3 폴백 — Stop 훅 C2 패턴 재사용)
  ├─ [로그] hooks.log 에 source=<값> 한 줄 (G6)
  ├─ [게이트 2] source ∉ {startup, resume} → exit 0            (G2)
  ├─ project_dir 해석 (워크트리 경로 → 메인 루트로 정규화, serena 선례)
  ├─ [게이트 3] .hermes/state.db 없음 → exit 0                 (G7)
  ├─ [게이트 4] 마커 mtime 이 throttle_hours 이내 → exit 0     (G3 throttle)
  │
  ├─ 마커 touch (백그라운드 기동 前 — 동시 세션 이중 기동 방지)
  └─ setsid 백그라운드:                                          (G4 비차단)
       python3 hermes-dream.py --db <db> --project-dir <dir>    (--apply 없음 = dry-run, G5)
       </dev/null >/dev/null 2>&1 &   (stderr는 hooks.log)
     exit 0
```

### 4.3 구성 단위

| 단위 | 대상 | 단일 책임 |
|------|------|----------|
| U1 훅 스크립트 | `assets/hooks/claude-sessionstart-dream.sh` (신규) | source·throttle 게이트 + 비차단 백그라운드 드림 기동 |
| U2 배선 | `presets/workflow/hermes.conf` (수정, 2줄) | `HARNESS_HOOK_SOURCES` 등록 + `SESSION_START_HOOKS` 배열 추가 |

> 별도 복사목록 편집 불필요: `HARNESS_HOOK_SOURCES` 등록만으로 `project-claude.sh` 가
> `assets/hooks/` 에서 대상 프로젝트 `scripts/hooks/` 로 복사한다(serena.conf 선례, 그 파일 주석
> "hook 소스 파일 등록 (project-claude.sh 가 assets/hooks/ 에서 복사)" 참조). hermes.conf 의 python
> 스크립트 복사목록은 `.py`/러너용이며 훅과 별개다.

## 5. 훅 로직 상세 (`claude-sessionstart-dream.sh`)

- **stdin 파싱**: Stop 훅과 동일하게 `input="$(cat)"` 후 jq(`.source`, `.cwd`) 우선, 부재 시
  python3 `json.load` 폴백. 파싱 실패 시 값 공백 → 게이트에서 걸러져 안전 종료.
- **project_dir 정규화**: `cwd`(또는 `${CLAUDE_PROJECT_DIR:-$PWD}`)에서 `/.claude/worktrees/<name>$`
  를 제거해 **메인 프로젝트 루트의 `.hermes`** 를 대상으로 삼는다(백그라운드 워크트리 세션이
  워크트리 내부의 없는 DB를 보지 않도록 — serena 훅과 동일 처리).
- **source 게이트**: `case "$source" in startup|resume) ;; *) exit 0 ;; esac`.
- **throttle 마커**: `$project_dir/.hermes/dream-last-run`. `find` 로 mtime 을 검사하거나
  `stat` 기반 나이 계산. 마커가 없거나 throttle_hours 보다 오래됐으면 통과.
- **기동**: Stop 훅과 동일한 `setsid bash -c '... &' </dev/null >/dev/null 2>&1 &` 로 완전 분리.
  드림은 haiku 호출로 수 분이 걸릴 수 있으므로 **절대 포그라운드 실행 금지**.
- **로그**: `$project_dir/.hermes/hooks.log` 에 `[hermes-dream-hook] source=<x> action=<run|skip:reason>`.
- **stdout 함정 (필수)**: SessionStart 훅은 **stdout 출력이 그대로 세션 컨텍스트로 주입**된다
  (serena 훅이 이 방식으로 초기화 지시를 주입하는 것과 동일 메커니즘). 따라서 이 훅의 포그라운드
  본체는 **stdout으로 아무것도 출력하지 않는다** — 모든 진단은 `hooks.log`(파일)로만, 백그라운드
  드림은 `setsid ... >/dev/null 2>&1` 로 완전 분리. 실수로 로그를 stdout에 뱉으면 매 세션 시작마다
  대화에 잡음이 주입되므로 회귀 테스트로 stdout 무출력을 단언한다(§10에 항목 추가).

## 6. 임계값 (매직넘버 — 근거 + env 오버라이드)

| 상수 | 기본 | 근거 | env |
|------|------|------|-----|
| throttle 시간 | 20시간 | 24h로 잡으면 매일 세션 시작 시각이 조금씩 당겨질 때 "아직 24h 안 됨"으로 하루 걸러 실행되는 밀림 발생. 20h면 그 드리프트를 흡수하며 하루 1회 리듬 보장 | `HERMES_DREAM_THROTTLE_HOURS` |
| 트리거 source | startup, resume | "새 세션/이어가기"에서만. clear(맥락만 비움)·compact(대화 진행 중)는 작업 중간이라 제외 | — (코드 고정) |
| 자동 삭제 | 없음(dry-run) | 파괴적 동작은 자동 실행 안 함(드리밍 안전 모델). 삭제는 `/hermes-dream apply` 수동만 | — |

## 6.3 throttle 앵커를 마커 파일로 두는 이유

`dream_log.run_at` 대신 `.hermes/dream-last-run` 마커의 mtime 을 쓴다:

- **모든 시도를 억제**: 조용한 날(요약·pending 없음)의 드림은 `record_dream` 前에 조기 종료해
  `dream_log` 행을 남기지 않는다. dream_log 를 앵커로 쓰면 조용한 날 재시도가 억제되지 않는다.
  마커는 "시도했다"는 사실 자체를 기록하므로 하루 1회를 정확히 보장한다.
- **크래시 루프 방지**: 마커를 백그라운드 기동 **前**에 touch 하므로, 드림이 도중 실패해도 20h간
  재기동되지 않는다. 실패분은 다음 드림이 워터마크로 재처리(드림 엔진의 이월 불변식)하므로 손실 없음.
- **DB 비결합·단순**: SQL 없이 mtime 비교 한 번. serena 훅의 `/tmp` 플래그 파일 선례와 일관.

> 대안(기록만): dream_log 기반 throttle. "실제 작업이 있었던 실행만" 카운트하려면 유효하나,
> 조용한 날 억제 실패·실패 재시도 폭주 위험이 있어 채택하지 않는다.

## 7. 신규/수정 파일

| 파일 | 책임 | 신규/수정 |
|------|------|----------|
| `assets/hooks/claude-sessionstart-dream.sh` | source·throttle 게이트 + 비차단 드림 기동 | 신규 |
| `presets/workflow/hermes.conf` | HARNESS_HOOK_SOURCES + SESSION_START_HOOKS 등록, 안내 문구 | 수정 |
| `tests/hermes-pipeline-test.sh` | 훅 게이트 회귀(source 4종·throttle·비차단·dry-run) | 수정 |
| `README.md` | 드림 트리거를 "세션 시작 자동(하루 1회) + 수동" 으로 갱신 | 수정 |
| `docs/superpowers/specs/2026-06-18-...`·`2026-06-25-...` | 드림 트리거 확정 반영(§11 후속) | 수정(선택) |

신규 인프라 없음 — 기존 `SESSION_START_HOOKS` 파이프라인 재사용.

## 8. 배포·전파

`hermes.conf` 복사목록에 새 훅을 넣으면 `setup`/`update-all` 이 대상 프로젝트의
`scripts/hooks/` 로 복사하고, `settings.json` 의 `SessionStart` 에 등록한다. 기존 hermes
프리셋 설치 프로젝트들은 `update-all` 로 전파 후 `settings.json` 에 훅이 실렸는지
검증한다(전파 검증 관례).

## 9. 에러 처리

- 전 경로 비차단: 결핍·오류는 로그 후 `exit 0`. 세션 시작을 절대 막지 않는다.
- 드림 자체 오류는 백그라운드에서 발생하고 `hooks.log` 로만 흘러 세션과 격리.
- 동시 세션(빠른 연속 startup): 마커 선(先)-touch 로 이중 기동을 억제. 완벽한 원자성은 아니나
  드림 자체가 `busy_timeout`+`WAL` 로 DB 경합을 흡수하고, 중복 실행돼도 additive 라 무해.

## 10. 테스트 (`tests/hermes-pipeline-test.sh` 확장, mock claude 재사용)

1. **G2 source 게이트**: startup/resume stdin → 드림 기동(마커 생성); clear/compact → 미기동.
2. **G3 throttle**: 마커를 현재 시각 → 미기동; 마커 mtime 을 21h 전으로 → 기동.
3. **G5 dry-run**: junk 스킬 존재 + 훅 경유 드림 → 파일 잔존(삭제 안 함).
4. **G6 로그**: 각 source 주입 시 `hooks.log` 에 `source=<값>` 라인.
5. **G7 안전 종료**: DB 없음/파싱 실패 → exit 0, 부작용 없음.
6. **G8 옵트아웃**: `HERMES_DREAM_ON_SESSION_START=0` → 미기동.
7. 비차단: 훅 반환이 드림 완료를 기다리지 않음(백그라운드 PID 분리 확인).
8. **stdout 무출력**: startup·resume·clear·compact 어떤 source에서도 훅 포그라운드 stdout이
   비어 있음(세션 컨텍스트 오염 방지). 진단은 `hooks.log`에만.
9. `tests/run-all.sh` 통합 실행.

mock claude 는 PATH stub(기존 방식) 사용. setsid 백그라운드는 테스트에서 완료 대기 마커로 동기화.

## 11. 후속 과제

- **드림 리포트 요약 세션 주입**: SessionStart `additionalContext` 로 "직전 드림에서 결정화 N건"
  한 줄을 세션 시작에 띄우기. 백그라운드 드림과 시점이 어긋나므로 "직전 리포트"를 읽어 주입하는 별도 설계 필요.
- **설계 spec 트리거 확정 반영**: `2026-06-18-hermes-dreaming-core-design.md`(cron 트리거 서술)와
  `2026-06-25-...`(트리거 후속으로 유보)에 "세션 시작 훅으로 확정"을 반영.
- **자율 매니저도 세션 훅화 검토**: 매니저는 시각 기반이라 부적합하나, "세션 시작 시 미읽은 매니저
  메시지 요약 주입" 같은 경량 연동은 별도 검토 여지.

## 12. 단계 개요 (상세는 구현계획에서)

1. U1 훅 스크립트 작성(게이트+비차단 기동) → 2. U2/U3 hermes.conf 배선·복사목록 →
3. 테스트 확장 → 4. `update-all` 전파 + settings.json 검증 → 5. README 갱신.

훅 스크립트가 먼저 있어야 배선·테스트가 물린다(순서 의미 있음).
