# 2026-09-17-summon-soul-injection — 소환된 에이전트가 정체성 폴더를 읽고 출근한다

> 작성일: 2026-09-17
> 목적: 설계 `design/agent/creation-and-organization.md:20`("소환될 때마다 그 폴더를 읽고 출근하는 존재")이 구현 계획 `2026-09-15-agent-identity.md` 목표에서 빠진 것을 채운다.
> 선행: 계획 4(agent-identity — 명부·SOUL·소환 러너·nonce 검증 훅).

## 1. 동기 (Why)

- **설계에는 있고 코드에는 없다.** 소환 러너(`scripts/hermes-summon.py`)는 `[소환] 당신은 <이름> (agent:<id>) 입니다.` 한 줄과 환경변수 `HERMES_AGENT_ID` 만 넘긴다. `HERMES_AGENT_ID` 를 읽는 파일 7개 중 `SOUL.md`·`MEMORY.md` 를 세션에 넣는 훅은 0개(2026-09-17 실측).
- **사람이 쓴 정체성이 읽히지 않는다.** 입사 출력은 "SOUL.md 를 채우십시오" 라고 안내하지만, 채워도 소환된 세션은 그 파일을 열지 않는 한 자기 역할을 모른다. 이력서를 쓰라 해 놓고 아무도 안 읽는 상태.
- 계획 4 는 소환을 **보안(사칭·토큰)** 측면으로만 목표화했고 **출근(정체성 읽기)** 측면이 목표에서 빠진 채 완료로 닫혔다(§8 에도 미완 기록 없음).

## 2. 목표 (What — 검증 가능한 형태)

> 검증 명령: `bash tests/hermes-soul-inject-test.sh`(목표 1~5) · `bash tests/run-all.sh`(회귀).

- [x] 목표 1 — `HERMES_AGENT_ID` 가 있고 `.hermes/agents/<id>/` 가 있으면 세션 시작 훅이 **SOUL.md 전문 + MEMORY.md** 를 stdout 으로 주입한다(SessionStart stdout = 세션 문맥). 머리에 `[헤르메스 출근] <이름> (agent:<id>)` 한 줄. 검증: 테스트가 훅을 stdin JSON 과 함께 실행해 stdout 에 SOUL 본문 문장과 MEMORY 본문이 있음을 단언.
- [x] 목표 2 — 보통 세션(환경변수 없음)·폴더 없는 id(`main` 포함)·retired 에이전트는 **무출력 exit 0**. retired 는 설계 `skill-layers.md`("은퇴한 에이전트는 주입에서 빠진다")와 일치. 검증: 세 케이스 stdout 빈 문자열, rc 0.
- [x] 목표 3 — 크기 상한: SOUL 4,096 B · MEMORY 4,096 B, 합 8,192 B — 이 프로젝트가 R-out 으로 "한 번에 너무 많은 문맥" 이라 재는 임계(`claude-posttooluse-output-budget.sh` `R_OUT_THRESHOLD=8192`)와 같은 값. 넘치면 자르고 `[…잘림 N B — 원문 <경로>]` 한 줄. 검증: 10 KB SOUL → 주입 ≤ 4,096 B + 잘림 줄, 경로 포함.
- [x] 목표 4 — 훅은 절대 세션을 세우지 않는다: 명부 손상·파이썬 부재·파일 권한 오류 → stderr 한 줄 + exit 0. 검증: `bash tests/hermes-soul-inject-test.sh` §4 — `agents.json` 을 깨뜨린 픽스처에서 rc 0·stdout 빈 문자열·stderr 에 이유, `chmod 000 SOUL.md` 에서도 rc 0 이고 MEMORY 는 주입.
- [x] 목표 5 — 프리셋 등록·전파: `presets/workflow/hermes.conf` 에 `HARNESS_HOOK_SOURCES`·`SESSION_START_HOOKS` 등록, `.deprc` 필요 시 등록, `run-all.sh` 등록. 검증: `preset-integrity-test` 통과, 소우주 사본 설치 뒤 `.claude/settings.json` 에 훅 경로 존재.
- [x] 목표 6 — 문서 동기: `design/agent/creation-and-organization.md` 소환 절에 "읽는 주체 = 세션 시작 훅" 한 줄, 안내서 2장(`docs/hermes-universe/guide/`)의 "알려진 구멍" 에서 SOUL 항목 제거. 검증: `grep -c 'SOUL' docs/hermes-universe/guide/agent-eli5.html` 의 "안 되는 것" 상자 0건.

## 3. 비목표 (Out of Scope)

- MEMORY.md 의 내용 생성·요약 방식(`hermes_memory_view.py` 몫) — 있는 파일을 읽어 넣기만 한다.
- 러너의 `--append-system-prompt` 경로 — 훅으로 통일한다(§6).
- 개인 스킬 주입(`.hermes/agents/<id>/skills/`) — 이미 `hermes-search.py` 가 `HERMES_AGENT_ID` 로 처리한다.

## 4. 영향 영역

- 신규: `assets/hooks/claude-sessionstart-agent-soul.sh` — 정체성 주입 훅(단일 책임).
- 신규: `tests/hermes-soul-inject-test.sh` — 목표 1~4.
- 수정: `presets/workflow/hermes.conf`(훅 등록), `tests/run-all.sh`, `docs/hermes-universe/design/agent/creation-and-organization.md`, `docs/hermes-universe/guide/agent-guide.html`, `docs/hermes-universe/guide/agent-eli5.html`.
- 전파: 훅은 `assets/` 자산 → `update-all` 필요(hermes 소우주 8곳).

## 5. 단계 (Steps)

### Step 1. 훅 + 테스트 [Impl]
- 산출: 위 신규 2파일. 테스트는 임시 프로젝트(명부·정체성 폴더 픽스처)에서 훅을 직접 실행.
- 검증: 테스트 초록 + "훅을 빈 파일로 바꾸면 빨강"(통과만 보는 검증 금지).

### Step 2. 등록·문서 [단순]
- 산출: hermes.conf · run-all · 설계 문서 한 줄 · 안내서 2장.
- 검증: `preset-integrity-test`, 전체 스위트 0 실패.

### Step 3. 전파·실측 [단순]
- 산출: 사용자 승인 뒤 `update-all`; 소우주 사본에서 입사 → 소환 없이 훅만 `HERMES_AGENT_ID` 로 실행해 주입 확인(실제 `claude -p` 는 세션 비용이라 생략).
- 검증: hermes 소우주 8곳 `settings.json` 에 훅 등록, `.factory-new` 0.

## 6. 의사결정 로그

- 2026-09-17: **러너가 아니라 세션 시작 훅이 읽는다.** 근거: 러너는 소환 한 경로지만 훅은 `HERMES_AGENT_ID` 가 있는 모든 세션(향후 루프·크론 소환 포함)에 같은 방식으로 붙는다. 기존 `summons-verify` 훅이 같은 조건으로 이미 도는 자리다. 틀렸을 때 손해: 훅이 안 깔린 소우주(hermes 프리셋 미사용 4곳)에서는 주입이 없다 — 그곳엔 명부 자체가 없어 소환도 없다.
- 2026-09-17: **상한 8,192 B 는 R-out 임계와 같은 값을 쓴다.** 근거: 이 프로젝트가 "한 번에 문맥에 넣기엔 많다" 고 실측으로 정한 유일한 수치. 새 숫자를 만들지 않는다. 손해: 긴 SOUL 은 잘린다 — 잘림 줄이 원문 경로를 가리켜 세션이 직접 읽을 수 있다.
- 2026-09-17: **retired 는 주입하지 않는다.** 근거: `skill-layers.md` 의 기존 결정과 일치. 소환 러너도 은퇴자를 거부하므로 이중 방어.

## 7. 발견·예외

- 2026-09-17 Step 1: 첫 판은 파이썬 경고를 `hooks.log` 로만 보내 훅 stderr 가 비었다(목표 4 단언 1건 빨강). 다른 훅 관례대로 stderr + 로그 양쪽으로 고침. 테스트 25/25.
- 2026-09-17 Step 2: 전체 스위트 71개 중 `doc-counts-gate` 1건 빨강 — 훅 1종·테스트 1개 증가로 문서 수치가 낡음. `sync-doc-counts.sh` 뒤 초록. 사본 설치(`HERMES_NO_REGISTER=1`)로 `settings.json` 훅 등록·755 확인, 레지스트리 오염 0.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 러너가 아니라 세션 시작 훅에 붙여 `HERMES_AGENT_ID` 가 있는 모든 세션에 한 방식으로 닿게 했다. 소우주 사본에서 실제 id 로 실행해 SOUL·MEMORY 전문 주입을 눈으로 확인했다.
  - 상한을 새로 정하지 않고 R-out 임계(8,192 B)를 빌렸다 — 근거 없는 숫자를 안 만들었다.
  - 이 한 건을 고치고 멈추지 않고 "같은 유형이 더 있나" 를 전수 대조해 15+1건을 찾았다(→ 계획 design-coverage-gaps).
- 잘못된 것:
  - 첫 판이 파이썬 경고를 로그로만 보내 훅 stderr 가 비었다(목표 4 단언 1건 빨강) — 기존 훅 관례(stderr+로그)를 먼저 읽었어야 했다.
  - 설계 문장 한 줄이 계획 4 목표에서 빠진 것을 이틀 뒤에야 발견했다 — 계획 완료 시 "설계 확정 문장이 다 옮겨졌나" 를 보는 절차가 없었다.
- 다음 룰 후보: `R-design-cover`(설계 "(확정)" 문장 ↔ 계획 §2 인용 대조 게이트) — 계획 design-coverage-gaps §8 과 동일 후보, 한 번만 승격.
- 전파: 2026-09-17 `update-all` 12/12 — hermes 소우주 8곳 `settings.json` 에 훅 등록·755, `.factory-new` 0.
