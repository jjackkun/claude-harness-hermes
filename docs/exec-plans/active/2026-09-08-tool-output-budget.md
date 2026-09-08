# 2026-09-08-tool-output-budget — 도구 출력이 컨텍스트를 태우는 양을 실측한다 (R-out)

> 작성일: 2026-09-08
> 목적: 도구 출력의 컨텍스트 비용을 **추측 없이** 측정해, 절감 조치의 근거를 만든다.

## 1. 동기 (Why)

외부 도구(`context-mode`, ELv2) 검토에서 출발했다. 그 도구의 진단은 옳다 —
컨텍스트를 태우는 주범은 모델의 답변이 아니라 **도구 출력**이다.

이 저장소에서 실측한 값(2026-09-08):

| 대상 | 크기 | 유효 신호 |
|---|---|---|
| `tests/run-all.sh` | **80,013 B** | `47 실행 / 47 통과 / 0 실패` ≈ 30 B |
| `gate_report.py` | 1,021 B | 거의 전부 |
| 훅 매 턴 주입 | 1,045 B | 전부 |

`run-all.sh` 한 번의 낭비율이 **99.96%** 다. 다만 이 파일은 프리셋 배포 대상이 아니다
(`HARNESS_HOOK_SOURCES` 에 없음). 즉 이 숫자는 **이 저장소만의** 비용이다.

**정작 모르는 것은 설치된 12곳의 비용이다.** 그쪽 프로젝트의 `pytest`·`npm test`·빌드가
얼마나 시끄러운지 잰 적이 없다. 근거 없이 절감 장치를 12곳에 뿌리면 소음만 12배가 된다.

그리고 이 저장소는 **개입 지점을 이미 소유하고 있다** — `PRE_TOOL_USE_HOOKS` 의
`Bash::claude-pretooluse-bash-guard.sh`. `context-mode` 가 MCP 서버로 확보하려는 그 자리다.
외부 도구를 설치할 이유가 없고, MIT 저장소가 ELv2 자산을 12곳에 재배포하는 문제도 피한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — Bash 도구 호출 1건의 **실제 출력 바이트**가 `.harness/gate-events.jsonl` 에
      남는다. 검증: 임의 명령 1회 실행 후 `grep R-out .harness/gate-events.jsonl` 에
      해당 레코드와 바이트 수가 있다.
- [x] 목표 2 — **오탐이 구조적으로 불가능하다.** 검증: 훅 소스에 명령 패턴 매칭이
      한 줄도 없다(`grep -c 'pytest\|npm test\|build' 훅` == 0). 판정은 실측 바이트로만 한다.
- [x] 목표 3 — 판정 불가를 통과로 세지 않는다. 검증: 출력 크기를 못 읽은 경우
      `skipped` 로 기록된다(시험으로 단언). 근거: `gate_emit.sh` 주석, 2026-09-08 감사.
- [x] 목표 4 — 12곳 전파 후 **조용하다.** 검증: `update-all.sh` 12/12 후 배포처 1곳에서
      임계 미만 명령이 `additionalContext` 를 내지 않는다(빈 stdout).
- [ ] 목표 5 — 3주 뒤(2026-09-29) 판단 근거가 존재한다. 검증: `gate_report.py` 에
      `R-out` 행이 나오고, 명령별 바이트 분포를 낼 수 있다.

> ⚠️ **이번 계획의 산출물은 토큰 절감이 아니라 근거다.** PostToolUse 는 이미 컨텍스트에
> 들어온 출력을 되돌리지 못한다. 절감은 다음 계획의 몫이다. 3주 뒤 "토큰이 안 줄었다" 는
> 실패가 아니다 — 목표 5가 실패여야 실패다.

## 3. 비목표 (Out of Scope)

- **PreToolUse 차단** — 실행 전에는 출력 크기를 모른다. 추측하면 R5 `-n` 사고를 반복한다.
- **명령 패턴 목록** — 위와 같은 이유. 3주치 실측 뒤에 근거를 갖고 만든다.
- **외부 도구 도입** — `context-mode` 는 채택하지 않는다(라이선스·관측 부재).
- **`run-all.sh` 출력 개선** — 배포 대상이 아니므로 별건. 하고 싶으면 별도 계획.
- **매 턴 주입(1,045 B) 다이어트** — 별건. Reminders 의 반복은 의도된 설계일 수 있어
  지운 뒤 규율 위반이 느는지 관측할 근거가 먼저 필요하다.
- **게이트·훅 자신의 출력** — 영구 제외. 강제 메시지의 컨텍스트 도달이 하네스의 작동 원리다.

## 4. 영향 영역

- 코드: `presets/workflow/harness.conf` (배선 2줄), `.deprc` (tier 등재)
- **신규 파일 목록**:
  - `assets/hooks/claude-posttooluse-output-budget.sh` — Bash 도구 호출의 실제 출력
    바이트를 재어 R-out 판정 1건을 기록하고, 임계 초과 시에만 절감 지침을 주입한다.
  - `tests/output-budget-test.sh` — 임계 미만 침묵 · 임계 초과 발화 · 출력을 못 읽을 때
    `skipped` 를 가짜 페이로드로 단언한다.
- 룰: **R-out** (신규, Provisional). `docs/design-docs/core-beliefs.md` 에 절 추가.
- 데이터: `.harness/gate-events.jsonl` 에 새 rule 값 하나. 스키마 변경 없음.
- 외부 의존: 없음.

## 5. 단계 (Steps)

### Step 1. PostToolUse(Bash) 페이로드에 출력이 실제로 오는가 [단순 — 선행 확인]

- 입력: 임시 PostToolUse 훅으로 stdin 페이로드를 파일에 덤프
- 산출: `tool_response` 의 실제 구조(필드명·출력 포함 여부)
- 검증: 덤프에 명령 출력이 들어 있다
- **이것이 아니면 계획 전체가 성립하지 않는다.** 기존 훅 중 `tool_response` 를 읽는 것이
  하나도 없어 확인된 바 없다. 실패 시 §7 에 기록하고 중단한다.

### Step 2. 훅 구현 [Impl]

- 입력: Step 1 의 실제 필드 구조
- 산출: `assets/hooks/claude-posttooluse-output-budget.sh`
- 동작:
  - 출력 바이트를 잰다. **명령 문자열은 판정에 쓰지 않는다** (기록에만 남긴다)
  - 임계 미만 → `gate_add R-out pass posttooluse "" "<n>B"`, stdout 없음(침묵)
  - 임계 이상 → `gate_add R-out warn ...` + 지침 주입
  - 출력을 못 읽음 → `gate_add R-out skipped ...`
- 임계: **8,192 B**. 근거 — 컨텍스트 예산에서 약 2k 토큰. 이 값이 옳다는 근거는 없으며,
  3주치 분포를 보고 고치기 위한 **출발점**이다. 이 사실을 훅 주석에 명시한다.
- 검증: Step 3

### Step 3. 시험 [Impl]

- 산출: `tests/output-budget-test.sh`
- 검증: 가짜 페이로드 3종으로 침묵·발화·`skipped` 를 단언. `tests/run-all.sh` 통과
- **통과만 보는 시험 금지** — 임계 초과 페이로드로 실제 발화를 확인한다
  (`harness-hooks-smoke.sh` 가 조용히 꺼져 있던 선례)

### Step 4. 배선·문서 [단순]

- `harness.conf`: `HARNESS_HOOK_SOURCES` 에 파일 추가 + `POST_TOOL_USE_HOOKS+=('Bash::...')`
- `core-beliefs.md`: R-out 절 (Provisional, 3주 뒤 재판정 명시)
- `.deprc` tier 등재 (R-dep-4 경고 예방)
- CLAUDE.md 주입 절·README 수치: `sync-doc-counts.sh` 로 갱신 (R-doc 이 강제한다)

### Step 5. 전파·검증 [Review]

- `bash update-all.sh` → 12/12
- 배포처 1곳에서 작은 명령·큰 명령을 각각 실행해 침묵/발화 확인
- `gate_report.py` 에 R-out 행이 나오는지 확인
- code-reviewer 검토 (신규 훅 = 12곳 배포 = 공유 경계 변경)

### Step 6. 3주 뒤 재판정 (2026-09-29) — 이 계획은 그때까지 `active/` 에 남는다

- `gate_report.py` + 명령별 바이트 분포
- 결정: 임계 조정 / PreToolUse 절감으로 승격 / 이득 없음으로 제거
- 결과를 `docs/audits/` 에 기록하고 이 계획을 `completed/` 로 이동

## 6. 의사결정 로그

- 2026-09-08: **`context-mode` 를 채택하지 않는다** — 근거: (1) 줄인 것을 기록하지 않아
  "관측 없는 장치" 가 된다(이 저장소가 이번 주 세 번 만난 실패 유형), (2) 게이트 차단
  메시지의 컨텍스트 도달을 전제로 한 훅 3종과 충돌, (3) MIT 저장소가 ELv2 자산을 12곳에
  재배포하게 된다. 아이디어 한 줄("개입 지점에서 출력을 줄인다")만 가져온다.
- 2026-09-08: **PreToolUse(추측) 가 아니라 PostToolUse(실측)** — 근거: 실행 전에는 출력
  크기를 알 수 없어 명령 패턴으로 추측해야 하는데, 그 추측이 틀린 것이 오탐이다.
  R5 가 `-n` 을 단어로 잡아 20/20 오탐을 낸 선례가 같은 파일에 주석으로 남아 있다
  (`docs/audits/2026-09-03-gate-firing-first-observation.md`). 훅은 12곳에 복사본으로
  깔리므로 잘못된 패턴 한 줄이 12배로 증폭되고, 복사본이라 `update-all.sh` 를 다시
  돌릴 때까지 시차 동안 계속 오탐한다. **실측은 이 위험 자체가 없다.**
- 2026-09-08: **`bash-guard` 에 얹지 않고 별도 훅 파일로 만든다** — 근거: (1) 훅 하나 =
  관심사 하나가 이 저장소의 기존 패턴(PostToolUse Edit 매처에 훅 3개가 따로 등록돼 있다),
  (2) `bash-guard` 는 R5 하드 경로라 회귀 위험을 만들면 안 된다, (3) PreToolUse 훅은
  `hookSpecificOutput` 을 하나만 낼 수 있어 얹으면 R5 와 R-out 이 서로의 메시지를 가린다.
- 2026-09-08: **차단이 아니라 경고로 시작한다** — 근거: Provisional 룰은 발화율을 보고
  승격한다(`core-beliefs.md`). 실측 없이 12곳을 차단하면 오탐 여부를 판단할 데이터가
  생기기 전에 마찰이 먼저 퍼진다.
- 2026-09-08: **임계 8,192 B 에는 근거가 없다** — 출발점일 뿐이며 Step 6 에서 분포를 보고
  정한다. 근거 없는 고정값을 남기지 않기 위해 이 사실을 훅 주석과 여기에 함께 적는다.

- 2026-09-08: **페이로드를 임시 파일로 받는다** — 근거: `python3 - <<'PY'` 는 히어독이
  stdin 을 차지해 페이로드를 읽을 수 없다(실측: 전 판정이 `skipped` 로 샜고 시험이 잡았다).
  환경변수로 넘기면 출력이 큰 명령에서 E2BIG 로 실패하는데, 하필 가장 재고 싶은 경우다.
- 2026-09-08: **EXIT trap 을 쓰지 않고 임시 파일을 명시적으로 지운다** — 근거: `gate_emit.sh`
  가 EXIT trap 이 비어 있을 때만 자기 trap 을 건다. 훅이 뒤에 trap 을 걸면 그쪽 flush 가
  조용히 사라진다.
- 2026-09-08: **`.deprc` 등재는 하지 않는다** — 근거: scope 가 `scripts/*.py lib/*.py
  assets/hooks/*.py` 로 `.py` 한정이다. `.sh` 훅은 R-dep-4 대상이 아니다. 계획 §4 의
  ".deprc tier 등재" 항목은 실측으로 불필요함이 확인돼 취소한다.

## 7. 발견·예외

### Step 1 결과 (2026-09-08) — 성립한다

임시 PostToolUse 훅으로 페이로드를 덤프해 실측했다. 문서(code.claude.com/docs/en/hooks)에는
PostToolUse 스키마 예시가 없어 문서로는 확인할 수 없었다.

최상위 키:

```
session_id transcript_path cwd scratchpad_dir prompt_id permission_mode
agent_type effort hook_event_name tool_name tool_input tool_response tool_use_id duration_ms
```

`tool_response` (Bash):

```json
{"stdout": "...", "stderr": "", "interrupted": false, "isImage": false, "noOutputExpected": false}
```

**출력 전문이 들어온다.** 따라서 바이트를 추측이 아니라 실측할 수 있다.

부수 발견:
- `duration_ms` 가 함께 온다 — 출력 크기와 소요 시간을 같은 레코드에 남길 수 있다.
  비용이 0이므로 기록한다. 판정에는 쓰지 않는다.
- `interrupted` 가 true 면 출력이 잘린 것이므로 크기 판정의 근거가 못 된다 → `skipped`.
- `stderr` 도 컨텍스트에 들어가므로 `stdout + stderr` 를 합산한다.
- `scratchpad_dir` 는 이 저장소 훅들이 아직 쓰지 않는 필드다. 기록만 해 둔다.

### Step 2~5 결과 (2026-09-08)

- 시험 `tests/output-budget-test.sh` — 14/14 통과. 최초 실행에서 stdin 버그를 잡았다
  (전 판정이 `skipped`). **통과만 보는 시험이었으면 못 잡았다.**
- 전체 시험 `tests/run-all.sh` — 48 실행 / 48 통과 / 0 실패.
- 전파 `update-all.sh` — 성공 12 / 실패 0.
- 배포처(zeroday-frontend) 기능 확인 — 임계 미만 침묵(빈 stdout), 임계 초과 발화,
  그 프로젝트의 `.harness/gate-events.jsonl` 에 기록:
  `{"rule": "R-out", "verdict": "warn", "stage": "posttooluse", "detail": "30000B 5ms (임계 8192B 초과)"}`
### 경계 조건 실측 (2026-09-08)

| 입력 | 결과 |
|---|---|
| 5 MB 출력 | `warn` · `5000000B` 정상 기록 (임시 파일 방식이라 E2BIG 없음) |
| 개행·따옴표 섞인 출력 | 주입 JSON 유효, `18000B` 정상 |
| 깨진 UTF-8 / 깨진 JSON | `skipped` (통과로 새지 않음) |
| 연속 실행 3회 | 임시 파일 누수 0 |
| 1회 소요 | **61 ms** (python3 2회 — 파싱 1, `gate_flush` 1) |

61 ms 는 Bash 호출마다 붙는다. `gate_emit.sh` 실측 기준(기동 1회 21 ms, size-warn 훅 자체
32 ms)과 같은 수준이며, Bash 호출이 보통 초 단위인 것을 감안해 수용한다. 줄이려면 파싱
스크립트가 `gate_event.py` 를 직접 부르면 되지만, **호출 규약의 주인이 `gate_emit.sh` 라는
계약을 깨는 값이 61 ms 보다 크다**고 판단했다.

**잠재 위험(기록만)**: 훅이 `cd` 한 뒤 `$(dirname "$0")/gate_emit.sh` 를 source 한다.
상대 경로로 호출되면 계장이 조용히 사라진다. 배선은 `${CLAUDE_PROJECT_DIR}/...` 절대
경로이므로 실사용에서는 발생하지 않고, 기존 훅 전부가 같은 형태다. 다만 2026-04-17 에
같은 원인으로 훅 4개가 silent-fail 한 이력이 있어 여기 남긴다.

- **부수 확인**: 이번 작업 중 `update-all.sh`(95,424 B)와 `run-all.sh`(80,810 B) 출력을
  파일로 돌려 받았다. R-out 이 권하려는 바로 그 형태이며, 두 호출만으로 176 KB 를 아꼈다.

## 7-1. 검토에서 잡힌 것 (2026-09-08, code-reviewer)

판정: WARNING — CRITICAL 0 / HIGH 0 / MEDIUM 3. 세 건 모두 재현 후 수정했다.

**[1] 유효한 JSON 인데 최상위가 dict 가 아니면 판정이 통째로 사라졌다.** `json.loads` 는
try 로 감쌌지만 바로 다음 `d.get("tool_response")` 가 무방비였다. `[]` `123` `"str"` 이
오면 AttributeError 로 스크립트가 죽고, `2>/dev/null || true` 가 그 실패를 삼켜
`PARSED` 가 비고, bash 가 조용히 `exit 0` 한다 — **`skipped` 조차 남지 않는다.**

재현(2026-09-08): `echo '[]' | CLAUDE_PROJECT_DIR=$T bash 훅` → exit 0,
`.harness/gate-events.jsonl` 자체가 생성되지 않음.

이 훅이 스스로 내건 규칙("판정 불가는 통과가 아니라 `skipped`")을 어기는 상태였다.
더 나쁜 것은 `pass` 로 세는 것보다 **아무것도 안 남기는 것**이었다 — 발화율에서 이 경로가
존재조차 하지 않게 된다. `isinstance(d, dict)` 가드를 추가했다.

> 아래쪽 `isinstance(tr, dict)` 방어가 이미 "dict 가 아닐 수 있다" 를 상정하고 있었는데
> 정작 그 앞이 무방비였다. **방어를 한 곳에 두고 안심한 것**이 실수의 형태다.

**[2] 시험이 그 경로를 만들지 못했다 — "통과만 보는 시험" 의 변종.** 깨진 페이로드 케이스가
`not json at all`(파싱 실패)뿐이라 "파싱은 되는데 dict 가 아닌" 분기를 한 번도 만들지
않았다. 14/14 통과가 안전을 보장하지 못했다. `[]` `123` `"str"` 세 케이스를 추가했고,
**가드를 도로 빼서 실제로 3건이 실패하는 것까지 확인**했다(17 통과 → 14 통과 / 3 실패).

**[3] 매 Bash 호출마다 도는 훅의 빈도 곱셈.** 기존 훅은 Edit/Write/Task 매처라 세션당
호출이 드물지만 이 훅은 **모든 Bash 호출**에 걸린다. 프로세스 하나가 곧 세션 전체의
곱셈이다. `sed` 3 + `awk` 3 을 bash 내장 `read` 로 걷어냈다 — 실측 55~61ms → **47ms**.
남은 프로세스는 mktemp · cat · python3(파싱) · rm · python3(gate_flush) 다.
`gate_flush` 는 호출 규약의 주인이므로 합치지 않는다.

**Step 6 관측 대상에 추가**: 발화율·바이트 분포뿐 아니라 **세션 체감 지연**도 본다.
47ms × 세션당 Bash 호출 수가 실제로 거슬리는 수준인지가 존치 판단에 들어간다.

## 7-2. 전파·사이드이펙트 전수 검증 (2026-09-08)

앞선 확인은 12곳 중 2곳 표본이었다. 전수로 다시 했다.

**배포 (12/12)** — 파일 존재 · 원본과 바이트 동일 · `settings.json` 등록 · 실행 권한, 전부 통과.

**기능 (12/12)** — 배포 사본을 각 프로젝트에서 직접 실행. 임계 미만 침묵 · 임계 초과 발화 ·
최상위가 dict 아닌 JSON → `skipped`. 검증은 임시 `CLAUDE_PROJECT_DIR` 로 돌려 배포처의
실측 데이터를 오염시키지 않았다.

**사이드이펙트**

| 항목 | 결과 |
|---|---|
| 배포처 git 발자국 | 신규 파일 1 + `settings.json` 한 항목뿐. 나머지 `M` 은 이전 하네스 갱신이 각 프로젝트에 미커밋으로 남아 있던 기존 드리프트(이번 작업에서 손대지 않은 `bash-guard` 도 `M` 인 것으로 확인) |
| 기존 훅 회귀 | `size-warn`·`review-reminder`·`dead-file-warn` 정상 침묵, `bash-guard` 의 `git log -n 5` 오탐 재발 없음 |
| 같은 매처 공존 | 7곳에 `hermes-assist` 가, zeroday 에는 `kos-docs-sweep` 까지 같은 Bash 매처에 있다. 둘 다 rc=0·침묵으로 서로 방해하지 않는다 |
| `python3` 부재 환경 | rc=0 · 침묵. 세션을 깨지 않고 조용히 판정을 포기한다 |
| 세션 안정성 | zeroday-frontend 의 **살아 있는 세션**(약 5.5시간째)에서 재전파 직후부터 계속 기록 중. 재시작 없이 반영됐고 오류 없음 |

**정리한 오염**: 초기 확인 때 배포처(zeroday-frontend)에 합성 페이로드 3건을 남겼다.
실측 데이터에 섞이면 3주 뒤 판단이 흐려지므로 제거했다(백업 후, `ts` 로 특정).

## 7-3. 첫 실측 (2026-09-08, 몇 시간치)

실제 Bash 호출 **187건** (3개 프로젝트, 합성 제외):

```
중앙값 386B · 90분위 1,999B · 99분위 5,225B · 최대 6,046B
임계 8,192B 초과: 0건 (0.0%)
```

**소음은 0이다** — 사이드이펙트가 없다는 뜻이고, 동시에 **현 임계에서는 이득도 0**이라는 뜻이다.

다만 이 표본으로 임계를 낮추자고 결론 내면 안 된다:
- 몇 시간치이고, 세션 성격이 편향돼 있다(이번 세션은 `update-all`·`run-all` 출력을 이미
  파일로 돌려 받았다 — 돌리지 않았으면 각각 95 KB·81 KB 였다).
- 큰 출력은 드물게 오는 꼬리다. 중앙값이 아니라 꼬리를 봐야 하고, 꼬리는 시간이 걸린다.

Step 6(2026-09-29)에서 이 분포가 어떻게 바뀌는지가 판단 근거다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
