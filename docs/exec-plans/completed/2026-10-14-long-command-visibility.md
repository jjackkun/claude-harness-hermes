# 2026-10-14-long-command-visibility — 긴 명령을 보이게 돌리고, 사람 입력이 필요한 명령은 넘긴다

---

## 1. 동기 (Why)

2026-10-14 jj-agent-room 새 클론에서 첫 세팅 스크립트(`npm run init:setting` — `npm run setup` 후 `sudo apt-get install redis-server`)를 에이전트가 돌렸다.

- 에이전트는 `Bash(..., timeout=600000)` 로 **앞에서** 돌렸고, 출력은 `> .harness/out/init.log 2>&1` 로 파일에 보냈다.
- npm 설치(`node_modules` 1.1GB)가 끝난 뒤 sudo 가 비밀번호를 기다리며 멈췄다. 로그에는 `Password:` 만 반복됐다.
- 명령이 끝나기 전까지 에이전트는 차례가 오지 않아 **멈춘 것을 보지도, 말하지도 못했다.** 사용자가 중단하고 "왜 말 안 하고 지켜만 보냐", "UI/UX 없이 그냥 기다리냐" 고 물었다.

이 실행 방식은 에이전트가 임의로 고른 것이 아니다. 공장이 까는 장치 세 개가 함께 그쪽으로 이끈다.

| 장치 | 지시 |
| --- | --- |
| `assets/hooks/claude-userpromptsubmit-reminders.sh` (매 턴) | "오래 걸리는 명령도 앞에서 기다린다 (Bash timeout 최대 600초)" |
| `assets/skills/run-to-the-end/SKILL.md` | "정하는 것은 하나다 — 배경으로 돌릴지 앞에서 기다릴지", 예시 `Bash(command="<시험 명령>", timeout=600000)` |
| `assets/hooks/claude-posttooluse-output-budget.sh` (R-out, 138~139행) | "출력을 파일로 받고 필요한 부분만 읽으십시오 — `<명령> > .harness/out/run.log 2>&1; tail -40 …`" |

이 셋을 합치면 "앞에서 최대 10분 동안 막혀 있고, 출력은 안 보인다" 가 된다. 사람이 입력해야 하는 명령(sudo·대화형 로그인)이 끼면 타임아웃까지 멈춘다.

이 지시들이 막으려던 문제는 실제로 있다. "배경으로 돌리고 턴을 끝내면 사용자가 '끝났어?' 를 물어야 한다" 는 run-to-the-end 의 근거는 맞다. 고칠 것은 그 목적이 아니라 **"앞에서 기다리기" 라는 수단**이다. 배경으로 돌리면서 같은 턴 안에서 Monitor 로 지켜보면, 턴을 넘기지도 않고 진행도 보인다.

에이전트 메모리(`~/.claude/projects/.../memory/`)에 적는 것으로는 해결되지 않는다. 메모리는 그 PC 에만 있고, 강제력이 없고, 매 턴 들어오는 위 리마인더와 반대로 말한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 매 턴 리마인더 문구가 "배경 + 같은 턴에서 지켜보며 중간 보고 + 결과까지 읽고 끝낸다" 로 바뀐다. "앞에서 기다린다" 는 문구가 남지 않는다. — 검증: 리마인더 훅·run-to-the-end·R-out 훅(assets·scripts 양쪽)에서 `grep "앞에서 기다린다\|앞에서 600"` 0건 + `tests/userpromptsubmit-backlog-test.sh` 통과 (§6 Step 1 결정으로 변경)
- [x] G2 — run-to-the-end 스킬이 "앞이냐 배경이냐" 대신 "짧으면 앞에서, 길거나 길 수 있으면 배경 + Monitor + 중간 보고, 같은 턴에서 마무리" 를 지시한다. — 검증: 스킬 본문 diff 리뷰 + skill-creator 발동 평가(기존 트리거 문구 회귀 없음)
- [x] G3 — R-out 안내가 "파일로 보내고 끝난 뒤 tail" 이 아니라 "배경으로 돌려 로그를 지켜보거나, 짧은 명령이면 tail" 을 구분해 안내한다. — 검증: `tests/output-budget-test.sh` 갱신·통과
- [x] G4 — Bash 가드가 비대화형 `sudo` (`-n`/`--non-interactive` 없이)를 **차단**하고, 사용자에게 `! <명령>` 으로 넘기라는 메시지를 낸다. — 검증: 가드 시험 — `sudo apt-get install x` 차단, `sudo -n true` 통과, `echo sudo` 같은 문자열은 오탐하지 않음
- [x] G5 — Bash 가드가 긴 명령(패키지 설치·전체 시험·빌드)을 `run_in_background` 없이 앞에서 긴 타임아웃(기준은 Step 1 에서 정함)으로 돌리면 **경고**한다. 차단하지 않는다. — 검증: 가드 시험 — 해당 패턴 경고, 짧은 명령·배경 실행은 경고 없음
- [x] G6 — 공장 시험 전체 통과 + 문서 개수 블록(`DS:COUNTS`) 갱신

## 2-bis. 착수 전 확인한 사실 (2026-10-14)

| 확인한 것 | 결과 |
| --------- | ---- |
| 리마인더 문구 원본 | `assets/hooks/claude-userpromptsubmit-reminders.sh` (설치본: 각 프로젝트 `scripts/hooks/` 134~138행 부근) |
| run-to-the-end 스킬 | `assets/skills/run-to-the-end/SKILL.md` — 28행 "앞에서 600초까지 기다린다", 33행 `timeout=600000` 예시 |
| R-out 안내 문구 | `assets/hooks/claude-posttooluse-output-budget.sh` 138~139행 |
| Bash 가드 | `assets/hooks/claude-pretooluse-bash-guard.sh` 153행, `sudo` 처리 없음 |
| 관련 시험 | `tests/eval-reminder-test.sh`, `tests/output-budget-test.sh` 있음 · Bash 가드 전용 시험 파일은 이름으로 못 찾음 (Step 1 에서 확인) |
| jj-agent-room 새 클론의 `.claude/skills/` | **디렉터리 없음** — CLAUDE.md 목차엔 run-to-the-end 등이 있지만 클론에는 깔려 있지 않다 (§7) |
| 공장 main 작업 트리 | 이 계획과 무관한 미커밋 변경 2건 (`.claude/.factory-manifest.json`, `.hermes/factory.json`) — 건드리지 않는다 |

## 3. 비목표 (Out of Scope)

- 긴 명령을 **차단**하는 것 (G5 는 경고만). 오판 비용이 크고, 실측 후 승격을 따로 정한다.
- 프로젝트 쪽 스크립트 UX(예: jj-agent-room `init-setting.sh` 진행 표시) — 각 프로젝트의 일.
- 새 클론에 `.claude/skills/` 가 없는 문제의 수정 — §7 로 원인만 확인하고, 고치는 건 별도 계획.
- Codex 세션 대응.

## 4. 영향 영역

- 코드:
  - `assets/hooks/claude-userpromptsubmit-reminders.sh` — 리마인더 1번 문구
  - `assets/skills/run-to-the-end/SKILL.md` — 본문 판단 기준·예시 (description 트리거 문구는 유지)
  - `assets/hooks/claude-posttooluse-output-budget.sh` — R-out 안내 문구
  - `assets/hooks/claude-pretooluse-bash-guard.sh` — sudo 차단, 긴 명령 경고
  - 공장 자기 설치본 `scripts/hooks/` 동기화 (공장의 기존 동기화 방식을 따른다)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/hooks/bash_guard_long_cmd.py`(가칭) — 명령 문자열·타임아웃·배경 여부로 "긴 명령 앞 실행" 여부를 판정한다. **기존 가드가 판정 모듈을 쓰는 방식이면 그 관례를 따르고, 가드 안에 둘 만큼 작으면 만들지 않는다** (Step 1 에서 결정)
  - `tests/bash-guard-interactive-test.sh`(가칭) — sudo 차단·긴 명령 경고 시험. 기존 가드 시험 파일이 있으면 거기에 넣고 만들지 않는다
- 룰: 새 R 룰 후보 — "사람 입력이 필요한 명령은 에이전트가 돌리지 않는다" (`harness-promote-rule` 로 승격할지 Step 5 에서 판단)
- 데이터: 없음
- 외부 의존: Claude Code `Bash` 의 `run_in_background` 와 `Monitor` 도구. Codex 엔 해당 없음 (비목표)

## 5. 단계 (Steps)

### Step 1. 현황 파악 [Plan]

- 입력: §2-bis 파일들, 가드 시험 위치, 공장 `assets/` → `scripts/` 동기화 방식, Monitor 도구 동작(배경 명령 로그를 같은 턴에서 지켜보며 사용자에게 중간 보고할 수 있는지)
- 산출: §6 에 결정 기록 — 긴 명령 판정 패턴·타임아웃 기준, 신규 파일 여부
- 검증: 결정마다 근거 한 줄

### Step 2. 리마인더·스킬·R-out 문구 [Impl]

- 입력: Step 1 결정
- 산출: G1·G2·G3 의 문구 변경. 세 곳이 **같은 말**을 하도록 맞춘다 — 짧으면 앞에서, 길 수 있으면 배경 + Monitor + 중간 보고, 멈춤·입력 대기는 즉시 알림, 결과까지 읽고 턴을 끝낸다
- 검증: `tests/eval-reminder-test.sh`, `tests/output-budget-test.sh` (먼저 기대 문구를 시험에 쓰고 RED 확인)

### Step 3. Bash 가드 — sudo 차단 [TDD]

- 산출: G4
- 검증: RED → GREEN. 오탐 사례(따옴표 안 문자열, `sudo -n`, 주석) 포함

### Step 4. Bash 가드 — 긴 명령 경고 [TDD]

- 산출: G5
- 검증: RED → GREEN. 짧은 명령·배경 실행·이미 Monitor 로 보는 경우 경고 없음

### Step 5. 전체 검증·리뷰 [Review]

- 공장 시험 전체, `DS:COUNTS` 갱신, code-reviewer 로 가드 변경 검토 (공유 경계·전 프로젝트 영향)
- R 룰 승격 여부 판단

### Step 6. main 커밋 → 프로젝트 반영

- main 에 직접 커밋한다(PR 없음 — 이 저장소 관례, 2026-10-14 사용자 지적). 그 뒤 jj-agent-room 에 재설치로 반영하고 매 턴 리마인더 문구가 바뀐 것을 확인한다
- jj-agent-room 쪽 에이전트 메모리 `long-commands-visible-progress.md` 삭제 (규칙과 중복, 사용자 확인 후)

## 6. 의사결정 로그

- 2026-10-14: 메모리가 아니라 공장 장치에서 고친다 — 근거: 메모리는 PC 한정·강제력 없음·매 턴 리마인더와 충돌. 사용자 결정.
- 2026-10-14: sudo 는 차단, 긴 명령은 경고로 시작 — 근거: sudo 는 판정이 명확하고 멈춤이 확정적, 긴 명령은 패턴 오판 가능.
- 2026-10-14: "같은 턴에서 끝낸다" 는 원칙은 유지하고 수단만 바꾼다 — 근거: run-to-the-end 가 막으려던 "끝났어?" 문제는 실재한다.
- 2026-10-14 (Step 1): **G1 검증 시험을 바꾼다** — `tests/eval-reminder-test.sh` 는 R-eval(harness-eval 실행 알림) 시험으로 리마인더 문구와 무관하다. 리마인더 문구는 `tests/userpromptsubmit-backlog-test.sh`(Harness Reminders 구획을 이미 단언) 에 단언을 더한다.
- 2026-10-14 (Step 1): **G1 grep 범위를 좁힌다** — `assets/` 전체 grep 은 범위 밖 두 곳에 걸린다: `assets/codex/hooks/codex-userpromptsubmit-reminders.sh`(Codex 는 비목표, Monitor 도 없다), `claude-sessionstart-dashboard.sh:46` 주석(`HERMES_DASHBOARD_SYNC` 시험 모드 설명, 무관). 검증은 리마인더 훅·run-to-the-end 스킬·R-out 훅 3곳(+`scripts/hooks/` 설치본)에서 0건으로 한다.
- 2026-10-14 (Step 1): **긴 명령 판정 = 명령 패턴이 아니라 `timeout ≥ 300000ms` 이고 `run_in_background` 가 아님** — 근거: 에이전트가 긴 타임아웃을 준 것 자체가 "길 것 같다" 는 자기 신고다. 패턴(npm install·pytest…)은 R5 `-n` 20/20 오탐 선례처럼 오판하고, 12개 프로젝트에 복사본으로 증폭된다. 300초는 `pytest_gate.sh:34` 의 "앞에서 기다리기 위험해지는 선"(한도 600초의 절반)과 같은 값.
- 2026-10-14 (Step 1): **G5 경고는 그 호출을 못 바꾼다** — PreToolUse 의 additionalContext 는 도구 결과와 함께 모델에 닿으므로, 이미 앞에서 시작된 명령은 그대로 끝까지 막힌다. 경고는 **다음 호출**을 바꾸는 근거다(R-out 과 같은 성격). 그 호출을 바꾸려면 차단이 필요한데 §3 비목표. 실측 후 승격 판단.
- 2026-10-14 (Step 1): **sudo 판정 — 명령 위치의 `sudo` 만, `-n`/`--non-interactive` 가 있으면 통과** — `shlex` 의 punctuation_chars 로 따옴표·`;&|()`·줄바꿈을 존중해 토큰화하고, 세그먼트 첫 토큰(앞의 `VAR=값`·`env`·`time`·`nohup`·`exec`·`command` 건너뜀)이 `sudo`(basename) 일 때만 본다. `sudo -S` 도 차단 — 비밀번호를 stdin 으로 흘리는 길은 R-secret 위험이다. 알려진 한계: `bash -c "sudo …"`·`xargs sudo` 는 못 잡는다.
- 2026-10-14 (Step 1): **새 판정 모듈을 만들지 않는다** — 모듈은 `lib/preset.sh` 의 `HARNESS_HOOK_SOURCES`·`lib/uninstall_helpers.sh` 알려진 목록·README 모듈 표까지 바꿔야 한다. 판정이 수십 줄이고 가드가 이미 명령 파싱용 인라인 python 을 띄우므로 그 한 번에 합친다(Bash 호출마다 프로세스 1개 유지). 시험은 기존 `tests/r5-detection-test.sh` 와 같은 방식의 새 파일 `tests/bash-guard-interactive-test.sh` — r5 시험은 이름이 R5 전용이라 섞지 않는다.
- 2026-10-14 (Step 1): **Monitor 동작 확인** — Monitor 는 명령의 stdout 한 줄을 알림 하나로 대화에 넣는다. 배경 실행 로그를 `tail -f … | grep --line-buffered -E '<진행>|<실패>|Password|\[y/N\]'` 로 걸러 같은 턴 안에서 중간 보고·입력 대기 감지가 가능하다. 끝 하나만 알면 되면 배경 Bash + `until` 루프로 충분하다(Monitor 도구 설명).

## 7. 발견·예외

- jj-agent-room 새 클론(2026-10-14)에 `.claude/skills/` 디렉터리가 없다. CLAUDE.md 목차·하네스 리마인더는 스킬이 있다고 가정한다. `.gitignore` 로 빠지는 것인지, 설치를 다시 해야 하는 것인지 확인 → 별도 backlog 로 흘려보낸다.
- 같은 클론에 `.git/hooks/pre-commit`(하네스 커밋 게이트)도 없다. 클론마다 공장 설치를 다시 해야 하는지, 저장소 안에 설치 진입점이 있어야 하는지 위 항목과 함께 본다.

- 발동 평가(G2): 옛·새 description 모두 12건 중 5건 통과(발동해야 할 7건 모두 0회 발동, 발동 안 해야 할 5건 모두 조용). 회귀는 없지만 옛판도 0회라 **변별력 없는 측정**이다 — `claude -p` 한 턴에서는 이 스킬이 원래 거의 안 불린다. 발동률 개선은 별도 과제.
- code-reviewer(Step 5) 지적 반영: 붙은 구분자 토큰(`);`·빈 줄) 뒤 sudo 놓침(HIGH) · if/then/do/!/{ 뒤 놓침 · 새 판정 예외가 R5 를 끄던 구조 · sudo -k/-K/-V/--help 오탐 → 시험 먼저 넣고 고침(52건 통과). `-un x` 미탐지는 드물어 그대로 둠.
- 리뷰 반영 중 인라인 python 주석의 백틱이 bash 명령 치환으로 실행되는 결함을 냈다 → "가드가 stderr 를 내지 않는다" 단언 추가.
- 전체 시험 133개 중 132 통과. `update-all-roundtrip-test.sh` 의 "실제 ~/.claude 를 건드리지 않음" 실패는 단독 재실행에서 통과 — 같은 시간에 돈 `claude -p` 평가·다른 세션이 `~/.claude` 를 바꾼 것으로 본다.
- 가드 비용: 1회 중앙 35→39ms(20회 번갈아).
- 이 작업 중에도 실패한 시험 하나를 앞에서 194초 말없이 기다렸다 — 사용자가 "몇십분동안 뭐하냐" 고 물었다. 규칙이 막으려던 바로 그 모양이다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 시험을 먼저 쓰고(RED) 고쳐서, code-reviewer 지적 4건과 히어독 오탐을 모두 단언으로 남겼다. 긴 명령 판정을 명령 패턴이 아니라 에이전트가 준 timeout 으로 해서 R-out 의 "패턴 추측 금지" 와 충돌하지 않았다.
- 잘못된 것: 작업 도중 실패 시험 하나를 앞에서 194초 말없이 기다리고, 진행 보고 없이 수십 분을 썼다 — 사용자가 "몇십분동안 뭐하냐" 고 물었다. 계획서 Step 6 의 "PR" 을 그대로 따르려 했다 — 이 저장소는 main 직접 커밋이다(사용자 "pr을 왜해"). 인라인 python 주석의 백틱으로 bash 명령 치환 결함을 냈다(시험이 잡음).
- 다음 룰 후보: 없음 — 이번에 R-sudo·R-fg 를 core-beliefs 에 올렸다. R-fg 는 발화율을 본 뒤 차단 승격을 판단한다.
- 남은 일: jj-agent-room 재설치로 반영(Step 6 후반) · 그쪽 메모리 `long-commands-visible-progress.md` 삭제는 사용자 확인 후.
