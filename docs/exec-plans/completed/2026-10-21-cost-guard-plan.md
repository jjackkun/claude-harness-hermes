# 2026-10-21-cost-guard — 비싼 실행은 묻고, 서브에이전트는 맞는 모델로

> 출처 사고: 기획 사슬 계획(`docs/exec-plans/active/2026-10-21-planning-skill-chain-plan.md`) 중 묻지 않고 평가를 대량 실행 → 사용자 터미널 측정이 구독 한도("You've hit your session limit")에 걸려 무효.
> 사용자 요구 (2026-10-21): "앞으로 비싼 평가는 돌리기 전에 먼저 물어봐." · "앞으로 신 스킬이나 수정·개선들이 생길 수 있잖아 … 그것을 발생시키지 않게 우리 프로젝트를 개선해야겠어." · "개선 계획에 맞는 모델들을 지정하게 하는거 좋은 방식이네."

---

## 0. 다음 세션 시작점

**완료: G1~G9. 전파 11곳(커밋·푸시 10 + zeroday 설치만). §7·§8.**

| 단계 | 목표 | 상태 |
| --- | --- | --- |
| Step 0 계획 문서 | — | 완료 |
| Step 1 시험 골격·등록 + 훅 입력 실측 | G1~G3 빨강, §5 결정 닫기 | 완료 (빨강 18/37, §7) |
| Step 2 G1 비싼 실행 판정 | G1 | 완료 |
| Step 3 G2 에이전트 모델 판정 | G2 · G7 | 완료 |
| Step 4 G3 세션 누적 수 | G3 | 완료 |
| Step 5 규칙·양식 | G4 · G5 · G6 | 완료 |
| Step 6 수치·전체 시험 1회 | G8 | 완료 (146 중 143 → 실패 3 처리, §7) |
| Step 7 전파 (지시 시) | G9 | 완료 (2026-10-21) |

## 1. 동기 (Why)

사고에서 확인한 원인 셋 (사용자와 대화로 확인, 2026-10-21):

1. **멈출 이유에 비용이 없다.** `decision-ledger` §1 "멈추고 묻는 경우는 넷뿐" 에 사용자 자원(구독 사용량)이 없어, 대량 평가를 "계속할까요 금지" 쪽으로 분류했다.
2. **절차를 글자 그대로 따랐다.** `skill-dev.conf` 가 "평가/벤치마크 도구로 트리거 정확도 검증" 을 요구하고 skill-creator 는 시험마다 비교 실행을 띄우라 한다 → 필요 여부를 따지지 않고 전부 했다.
3. **모델을 지정하지 않은 서브에이전트가 부모 모델(Opus)을 물려받는다.** 평가용 내장 `general-purpose` 24개가 Opus 로 돌았고, 발동 측정 120회도 Opus 로 직접 지정했다. 리뷰용 lite 에이전트는 정의에 `model: sonnet` 이 있어 쌌다.

말로 된 규칙만으로는 같은 일이 또 생긴다 — 이번에도 규칙(skill-creator 필수)은 지켰지만 비용은 아무도 안 봤다. **기계가 멈춰 세운다. 단 훅은 안전망이고(우회 가능, §3), 재발 방지의 본체는 규칙(G4·G5)이다.**

## 2. 목표 (What — 검증 가능한 형태)

공통: 끔 스위치 `HARNESS_COST_GUARD=off`(`.harnessrc`), 모든 판정은 `gate_event.py` 로 `R-cost` 이벤트를 남겨 발화율을 잰다.

- [x] G1 — **비싼 실행 묻기** (Bash): 명령을 단어로 나눠 **실제로 실행하는** 경우만 본다 — 첫 실행 단어가 `python`/`python3`/`bash`/`sh` 또는 스크립트 경로이고, 대상이 `-m scripts.run_eval`·`-m scripts.run_loop`·`…/run_eval.py`·`…/run_loop.py`·`harness-eval.py`(단 `--dry-run`·`--help` 제외). `bash -c "…"` 는 안쪽을 다시 본다. `grep`·`cat`·`git`·`sed` 등이 그 이름을 **다루기만** 하면 통과
      `bash tests/cost-guard-test.sh` — 잡을 명령 6종 → ask(`-p` 에서는 Claude Code 가 거부로 바꿈, §5) / 통과 명령 6종(dry-run·help·grep·cat·git diff·일반 python) → allow
- [x] G2 — **서브에이전트 모델 지정** (Task|Agent): `tool_input.model` 이 있으면 통과. 없으면 subagent_type 정의를 찾는다 — 프로젝트 `.claude/agents/<t>.md` → 전역 `~/.claude/agents/<t>.md` → 플러그인(`플러그인:이름`)의 agents 폴더. 정의에 `model:` 이 있으면 통과. **내장 타입(general-purpose·Explore·Plan·claude)·정의를 못 찾음 → deny**, 사유: "model 인자를 지정하십시오 — 기계적 작업 haiku · 일반 sonnet · 깊은 설계 opus". `fork` 는 부모 모델을 쓰는 것이 정의된 동작이라 통과. subagent_type 이 없으면 general-purpose 로 본다
      시험: general-purpose+model 없음 → deny · general-purpose+`model: sonnet` → allow · planner-lite(정의 sonnet) → allow · 없는 타입 → deny · fork → allow · deny 사유에 `model` 글자
- [x] G3 — **세션 누적 서브에이전트 수**: 같은 세션의 dispatch 를 세어 `HARNESS_AGENT_ASK_AT`(기본 8)의 **배수 번째**(8·16·24…)마다 ask. 값이 숫자가 아니면 기본 8. 저장은 `.harness/agent-count/<session>.json` 에 임시 파일 후 rename(원자적), 7일 지난 파일은 쓸 때 지운다. session_id 가 없으면 세지 않고 이벤트만 남긴다(fail-open)
      시험: 7번째 allow · 8번째 ask · 9번째 allow · 16번째 ask · `.harnessrc` 3 → 3번째 ask · 값 `abc` → 8 · session_id 없음 → allow
      기본 8 의 근거: 이번 사고 세션에서 사람이 시킨 정상 작업(조사 4 + 리뷰 2)이 6, 평가로 31 까지 늘었다 — 정상 최대치를 넘는 첫 지점
- [x] G4 — **규칙**: `assets/rules/harness/decision-ledger.md` §1 에 5번 "사용자 자원(구독 사용량·돈)을 크게 쓰는 일 (모델을 여러 번 부르는 평가·서브에이전트 여러 개)" + 물을 때 모양(호출 수 · 모델 · 더 싼 판 하나). 제목 "넷뿐" → "다섯뿐"
      `grep -c '사용자 자원(구독 사용량' assets/rules/harness/decision-ledger.md` → 1
- [x] G5 — **스킬 개발 평가 단계**: `skill-dev.conf:18` 을 "싼 것부터" 로 — ① 정적 시험(모델 0) ② 스킬 있음 1건(정의된 모델) ③ 비교 실행·발동 측정은 **사용자 승인 뒤**, 발동 측정은 haiku 기본
      변경 전 `grep -c 승인 presets/workflow/skill-dev.conf` → 0 (실측) / 변경 후 `grep -n '사용자 승인 뒤' presets/workflow/skill-dev.conf` → 1줄
- [x] G6 — **계획서 양식**: `assets/docs-templates/docs/exec-plans/template.md` §2 에 "모델을 부르는 검증 목표는 `비용: 호출 수 · 모델` 을 적고 실행 직전 사용자 승인" 한 줄
      `grep -n '비용: 호출 수' assets/docs-templates/docs/exec-plans/template.md` → 1줄
- [x] G7 — **앞으로 들어올 에이전트 정의도 모델을 갖는다**: `cost-guard-test.sh` 가 `assets/agents/*.md` 전부에 `^model:` 이 있는지 단언 (지금 16/16 — §2-bis)
- [x] G8 — 등록·수치·전체 시험: `harness.conf` 설치 목록(75행 근처)에 훅·판정 모듈, `PRE_TOOL_USE_HOOKS`(141·142행 근처)에 `Bash::` · `Task|Agent::` 두 줄. 설치한 임시 프로젝트의 `.claude/settings.json` 에 두 matcher 가 있다. 생성 CLAUDE.md ≤ 100줄(새 안내 문구는 CLAUDE.md 가 아니라 규칙 파일에만, 수치 줄은 값만 바뀜)
      `bash tests/cost-guard-test.sh && bash tests/run-all.sh --check-orphans && bash tests/run-all.sh` · `wc -l <설치본>/CLAUDE.md`
- [x] G9 — (사용자 지시가 있을 때만) 전파 — 2026-10-21 "전파하자"

## 2-bis. 착수 전 확인한 사실 (2026-10-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| summon-guard 의 판정 방식 | 명령 **글자**에 `claude -p` 가 있는지만 본다 → `python3 -m scripts.run_eval` 안의 subprocess 120회는 통과 (이번 사고), 반대로 그 글자를 grep 하는 명령은 막힘 |
| agent-guard | `assets/hooks/claude-pretooluse-agent-guard.sh` 133줄, `Task|Agent`, general-purpose + 도메인 키워드면 **안내만** — cost-guard 와 책임이 달라 따로 둔다 |
| 막는 방식 선례 | `claude-pretooluse-iface-guard.sh:225` `permissionDecision: deny`, 구버전은 컨텍스트 주입으로 강등 |
| 스위치 읽기 선례 | `claude-pretooluse-iface-guard.sh:25` `[[ -f .harnessrc ]] && source .harnessrc` (값 검증 없음 → G3 에서 검증) |
| 판정 모듈 위치 관례 | `assets/hooks/` 에 평평하게(`complexity.py`·`gate_event.py` 등), `harness.conf:75~113` 설치 목록에 이름 나열. `lib/` 폴더 없음 |
| 훅 등록 | `harness.conf:141` `PRE_TOOL_USE_HOOKS+=('Bash::…bash-guard.sh')`, `:142` `('Task|Agent::…agent-guard.sh')` |
| 에이전트 정의 모델 | `assets/agents/*.md` 16/16 에 `model:` (`grep -L` 0개). planner-lite·architect-lite `sonnet/low`, devil-advocate·code-reviewer `sonnet/medium`, planner·architect `opus/high`. 사고의 원인은 내장 `general-purpose`(정의 없음) |
| skill-dev.conf "승인" | 0회 |
| 사용량 화면 (사용자 제공, 새 계정) | 이 세션 $41.50 중 Opus $41.13, 캐시 읽기 7,150만 — 긴 대화를 턴마다 다시 읽는 비용이 큼. 도구 제시 원인: 단순 서브에이전트에 싼 모델(90%) · 작업 바뀌면 `/clear`(87%) · 동시 세션 줄이기(최대 33개 동시, 82%) |
| 생성 CLAUDE.md | 99줄 — 여유 1줄 |

## 3. 비목표 (Out of Scope)·한계

- **훅의 한계**: 사용자가 만든 래퍼 스크립트 안에서 모델을 부르면 못 잡는다(글자로 안 보임). 이 훅은 아는 도구에 대한 안전망이다.
- 사용량(토큰·%)을 실시간으로 읽어 막는 것 — 훅 입력에 그 값이 없다(Step 1 에서 입력 필드로 확인).
- 동시 세션 수 제한·`/clear` 자동화 — 사람 습관 영역. 규칙 파일에 "긴 작업이 끝나면 새 세션" 한 줄만(CLAUDE.md 아님).
- 기존 평가 도구(run_eval·harness-eval) 자체 수정. `hermes-loop-run.sh` 는 잡지 않는다 — 사람이 터미널·cron 에서 여는 자율 루프이고, 그 안의 세션이 비싼 실행을 하면 G1 이 그 자리에서 잡는다.
- 백로그의 산술 비교 주입 결함(`marker-block-sync-data-loss.md`) — 따로.

## 4. 영향 영역

- **신규 파일 목록 (파일별 책임 1줄)**:
  - `assets/hooks/claude-pretooluse-cost-guard.sh` — 진입: 스위치 확인 → 도구 이름에 따라 판정 모듈 호출 → 결정 JSON 출력 → `gate_event.py` 기록. Bash 는 `case` 로 먼저 걸러 후보일 때만 python 을 부른다
  - `assets/hooks/cost_command.py` — G1: 명령이 비싼 실행인지 (공개: `classify(command) -> str`)
  - `assets/hooks/cost_agent_model.py` — G2: 에이전트 호출의 모델을 정할 수 있는지 (공개: `resolve(tool_input, project_dir, home) -> str|None`)
  - `assets/hooks/agent_count.py` — G3: 세션별 dispatch 수 더하기·읽기·오래된 파일 정리 (공개: `bump(session_id, root) -> int`)
  - `tests/cost-guard-test.sh` — G1·G2·G3·G7 (가짜 페이로드, 모델 호출 0)
- **수정**: `assets/rules/harness/decision-ledger.md`, `presets/workflow/skill-dev.conf`, `assets/docs-templates/docs/exec-plans/template.md`, `presets/workflow/harness.conf`(설치 목록·등록 두 줄), `tests/run-all.sh`(Step 1 에 목록 추가), README(훅 설명·스위치)
- 룰: R-size · R-struct · R-declare · R-iface(공개 심볼 파일당 1개)
- 외부 의존: python3 표준 라이브러리

## 5. 설계 결정

- **ask 가 안 되는 세션 (닫음, Step 1)**: 늘 `ask`. 헤드리스 판별을 하지 않는다 — 공식 문서: "When Claude Code denies the call in a `-p` run where no one can answer that prompt, Claude reads the reason in the tool result instead." 즉 `-p` 에서 ask 는 Claude Code 가 거부로 바꾸고 사유를 돌려준다. 그래서 ask 사유에도 "호출 수·모델을 보이고 승인받은 뒤 다시" 를 넣는다. 시험 기대값은 하나(ask).
- **훅 하나, 진입 둘**: 같은 스크립트를 `Bash::` 와 `Task|Agent::` 로 등록. agent-guard 는 안내용이라 그대로 둔다. 결정 병합(닫음): 공식 문서 "precedence is `deny` > `defer` > `ask` > `allow`" — agent-guard 는 결정을 내지 않으므로 cost-guard 의 deny 가 그대로 선다.
- **G2 에서 막힌 호출은 G3 수에 넣지 않는다**: 실행되지 않은 dispatch 다. 판정 순서 G2 → G3.
- **알려진 한계 — `-p` 에서 G3 은 한 번만 멈춘다 (리뷰 MEDIUM, 고치지 않음)**: ask 를 낸 호출도 수에 들어가므로, `-p` 에서 거부된 뒤 재시도하면 다음 번호가 되어 통과한다. 수를 되돌리면 대화형에서 사람이 승인한 호출도 세지 않아 같은 번호에서 계속 묻는다. 헤드리스 판별을 하지 않기로 한 결정과 같은 이유로 대화형 동작을 택했다. 헤드리스의 비싼 실행은 G1(묻기)·G2(모델 지정)가 계속 잡는다.
- **session_id 는 파일 이름으로 쓰기 전에 `[A-Za-z0-9_-]` 만 남긴다**: 입력값으로 경로를 만드는 자리라 `../` 를 막는다. 남는 글자가 없으면 "session_id 없음" 과 같게 다룬다.
- **G2 는 deny**: 안내만 하면 이번처럼 무시될 수 있다. 사유에 고칠 방법(`model` 인자)을 박는다 — 수정 지침이 든 오류 문구 원칙.
- **G3 은 배수마다 ask**: 한 번 승인한 뒤 매번 묻지 않게, 같은 단위(기준값)만큼 더 쓸 때 다시 묻는다.
- **기각한 대안**: 규칙만 강화 — 이번 사고에서 규칙은 지켰는데 비용은 안 봤다. 사용량 % 로 막기 — 훅이 그 값을 못 받는다.

## 5-bis. 단계 (Steps)

1. **시험 골격·등록·실측** — `cost-guard-test.sh` 를 쓰고 `run-all.sh` 목록에 넣는다(빨강 확인, 실패 수 §7). 훅 입력 실측: `session_id`·`tool_input.model`·`subagent_type` 필드 이름, 대화형/헤드리스 표지, Agent 에 훅 둘일 때 결정 병합 → §6 에 기록하고 §5 첫 항목을 닫는다
2. **G1** — `cost_command.py` + 진입 훅 Bash 분기 → G1 시험 통과 → `harness.conf` Bash 등록
3. **G2·G7** — `cost_agent_model.py` + Agent 분기 → 시험 통과 → `Task|Agent` 등록
4. **G3** — `agent_count.py` → 시험 통과
5. **G4·G5·G6** — 문구
6. **G8** — 수치 동기화, 설치본 확인, 전체 시험 1회
7. **G9** — 지시 시

**완료 조건**: G1~G8 체크 → §8 회고 → `completed/`.
**되돌리기**: `.harnessrc` 에 `HARNESS_COST_GUARD=off`(즉시) → 필요하면 `harness.conf` 의 등록 두 줄·설치 목록에서 제거하고 재전파.
**비용**: 검증은 전부 모델 호출 0 (가짜 페이로드). 계획서 lite 리뷰 2개(Sonnet)만 — 사용자 승인(2026-10-21 "다음 행동도 진행하자").

## 6. 의사결정 로그

- 2026-10-21: 말 규칙 + 기계 강제 둘 다 — 근거: 이번 사고에서 말 규칙(skill-creator 필수)은 지켰는데 비용은 안 봤다
- 2026-10-21: 서브에이전트 모델은 "지정 강제" — 사용자 승인("맞는 모델들을 지정하게 하는거 좋은 방식")
- 2026-10-21: `hermes-loop-run.sh` 는 G1 대상에서 뺌 — 근거: 사람이 여는 자율 루프이고 그 안의 비싼 실행은 G1 이 잡는다(리뷰 지적)
- 2026-10-21: 내장 에이전트 타입의 기본 모델은 가정하지 않는다 — 근거: 확인 못 한 주장("Explore 는 haiku")에 기대지 않는다. model 인자 한 줄로 풀리는 마찰이라 감수

## 7. 발견·예외

- 2026-10-21 Step 1 훅 입력 실측 (출처: code.claude.com/docs/en/hooks, 기존 훅 코드):
  | 항목 | 결과 |
  | --- | --- |
  | `session_id` | 모든 훅 공통 최상위 필드. 이 저장소 훅 6곳이 이미 `d.get("session_id")` 로 읽음 |
  | Agent 입력 | `tool_input.subagent_type`·`tool_input.model`(선택, "Optional model alias to override the default")·`prompt`·`description` |
  | 대화형/헤드리스 표지 | 전용 필드·환경변수 없음(`permission_mode` 는 default/plan/acceptEdits/auto/dontAsk/bypassPermissions). 필요 없어짐 — §5 |
  | `ask` | "prompts the user to confirm", auto 모드에서도 분류기가 조용히 승인 못 함. `-p` 에서는 거부 + 사유가 도구 결과로 감 |
  | 결정 병합 | `deny > defer > ask > allow` |
  | 플러그인 에이전트 | `~/.claude/plugins/installed_plugins.json` 의 키 `<플러그인>@<마켓>` → `installPath/agents/<이름>.md`. subagent_type `플러그인:이름` 의 앞부분이 플러그인 이름 |
  | 평가 도구 실제 경로 | skill-creator `…/skill-creator/scripts/run_eval.py`(전역 스킬·플러그인 캐시 셋), 공장 `scripts/harness-eval.py` |
- 2026-10-21 Step 1 빨강: `cost-guard-test.sh` 37개 중 18 실패(통과 19 = 훅이 없어 출력이 비는 allow 경우 + G7). 구현 후 37/37.
- 2026-10-21 시험 밖 경계 9개 직접 확인: 줄바꿈 구분·`timeout 600`·`FOO=1`·`env X=1`·`./scripts/harness-eval.py` → ask / `echo "…run_eval"`·`sed … run_eval.py`·`python3 -c "import scripts.run_eval"`·안 닫힌 따옴표 → allow. 빠른 길(일반 Bash) 21ms.
- 2026-10-21 G8 설치 확인: 임시 프로젝트에 공장 프리셋 5개 설치 → 모듈 4개 복사, `settings.json` 에 `Bash`·`Task|Agent` 두 matcher, 설치본 훅이 general-purpose(모델 없음) deny. harness 단독 설치 CLAUDE.md **99줄**(변화 없음). 수치 훅 16→17 · 판정 모듈 15→18 · 시험 141→142 (README·CLAUDE.md·harness.conf).
- 2026-10-21 전체 시험 146개 중 143 통과, 실패 3:
  - `doc-counts-gate-test.sh` — `harness.conf` 의 수치 블록을 빠뜨림 → `sync-doc-counts.sh` 로 맞춤.
  - `gate-instrumentation-test.sh` — 설치 목록을 `grep -A 40`(줄 수 창)으로 읽어, 모듈 4줄을 넣자 `gate_emit.sh` 가 창 밖으로 밀림 → 배열 끝 `)` 까지 읽게 고침. `gate_emit.sh` 를 일부러 지우면 여전히 빨강임을 확인.
  - `eval-reminder-test.sh` "3일 전" — 단독 실행 8/8 통과, 이번 변경과 닿는 파일 없음 → 묶음 실행 중 흔들림으로 보고 고치지 않음.
  고친 둘과 cost-guard 는 단독 재실행 통과. 전체 묶음 재실행은 하지 않음(기억: 전체 시험은 마지막 한 번).

- 2026-10-21 실제 에이전트 13개로 G2 확인: 정의에 `model:` 있는 프로젝트·플러그인 에이전트 전부 통과, `hookify:conversation-analyzer` 는 `inherit` 로 통과. 막히는 것: 내장(general-purpose·Explore·claude-code-guide·statusline-setup)과 **명부 에이전트 `backlog-manager`** — 생성기 `scripts/hermes_mention_file.py:39` 가 역할 템플릿에 모델이 없으면 칸을 비운다(= 부모 상속). G2 가 막으려는 바로 그 경우다. → 사용자 결정(2026-10-21 "기본 sonnet 으로 해"): 생성기가 템플릿에 모델이 없거나 모르는 값이면 `model: sonnet` 을 쓴다(`_DEFAULT_MODEL`). `hermes-agent-mention-test.sh` 빨강 2 → 87/87, 머리말 주입 단언은 줄 수 대신 키 목록(`name description model`)으로. 공장 `sync-mention-files` 로 `backlog-manager.md` 에 `model: sonnet` → 훅 통과 확인. 다른 소우주의 명부 파일은 전파(G9) 때 다시 만들어진다.
- 2026-10-21 리뷰 반영 후 R-cx: `_wrapper_width` 12 → 함수 분리로 최대 11.

- 2026-10-21 전파(G9): 사용자 결정 "cost-guard 만" — 미커밋 기획 사슬 작업 중 설치에 닿는 경로(assets 스킬·에이전트·양식, harness.conf)만 `git stash push -u -- <경로>` 로 빼고 update-all, 끝나고 pop. 공장 푸시(af007ba·7f972b2 + 이전 세션 2건).
  - 등록부에 시험 잔재 경로 `…/jobs/71400f1a/tmp/cmd` 한 줄 → 뺌(12곳).
  - update-all 11 성공 · zeroday-frontend 실패 → 원인: `_pytest_venv_of` 가 못 찾으면 rc 1, `set -euo pipefail` 설치기가 조용히 종료(4b6b261 결함). 시험 [8b] 빨강 확인 후 `return 0` 으로 고침(4d3c13b), zeroday 는 끊긴 도구 단계만 마저(pytest → .venv).
  - stash 대상에서 CLAUDE.md 를 빠뜨려 설치가 공장 CLAUDE.md 를 HEAD 기준으로 다시 씀 → 기획 사슬이 가졌던 차이는 수치 두 개뿐이라 `sync-doc-counts.sh CLAUDE.md` 로 복원. 덤으로 af007ba 에서 빠뜨린 skill-dev 생성 줄이 채워져 공장 자기 설치 커밋(8065f04)에 넣음.
  - 소우주 10곳: 영수증 + 설치 목록 경로만 커밋·푸시 — novel-ab 7596625 · novel-bc 51cb454 · rim-kanban 2aabc8c · jjackkun_bot f3321e7 · upbit-ai-trading 8831553 · terminal-shipping 0bdc2b27(Node v22.23.3) · kis-trading 281774d · jj-agent-room 104887b · drh-cloth-shop 9f19e29 · Nbbang-Run fff17bf. 확인: 10곳 HEAD 에 훅 1 · settings 등록 2 · 기획 스킬 0 · 미푸시 0. zeroday-frontend 는 설치만(기억된 예외).

## 8. 회고 (완료 시 작성)

- **전파**: 작업 폴더에서 설치하는 구조라, 미커밋 작업이 있으면 "무엇이 퍼지나" 를 먼저 물어야 한다 — 이번엔 물었고 stash 로 갈랐다. 다만 stash 경로를 고를 때 **설치가 다시 쓰는 생성물(CLAUDE.md)** 을 빠뜨렸다. 다음엔 생성물도 대상에 넣는다.
- **시험이 결함을 숨긴 두 번**: 설치기 시험 [8] 은 실제 설치기와 달리 `set -e` 없이 돌았고, 새로 쓴 [8b] 첫 판은 `|| true` 가 안쪽 `set -e` 를 꺼서 초록이었다. 둘 다 "실제와 같은 모드에서 빨강을 먼저 본다" 로 잡았다.

- **잘된 것**: Step 1 실측을 공식 문서로 닫아 설계가 줄었다 — `-p` 에서 ask 가 자동 거부되고 결정이 `deny > ask` 로 합쳐진다는 두 문장으로 헤드리스 판별·훅 병합 걱정이 모두 사라졌다. 빨강(18/37) → 초록 순서를 지켰고, 고친 시험(`gate-instrumentation`)은 일부러 깨 봐서 여전히 잡는지 확인했다.
- **놓친 것**: 분류기 첫 판은 제어 구문·`$()`·`-lc`·`uv run` 등 12가지를 놓쳤고, 에이전트 탐색은 파일 이름만 봐서 하위 폴더·`name:` 불일치 정의를 잘못 막았다. 둘 다 리뷰어 1회(Sonnet, 약 6만 토큰)가 실제 입력으로 잡았다 — **모든 소우주의 Agent 호출을 막을 수 있는 훅은 리뷰가 값을 한다.**
- **줄 수 창 시험**: `grep -A 40` 처럼 줄 수에 기대는 단언은 목록이 자라면 조용히 틀린다. 배열 끝까지 읽도록 바꿨다.
- **비용**: 모델 호출은 계획 리뷰 2 + 코드 리뷰 1 = 서브에이전트 3개(전부 Sonnet). 평가 실행 0.

## 9-bis. 코드 리뷰 반영 (2026-10-21, code-reviewer · Sonnet 1회)

| 지적 | 처리 |
|---|---|
| HIGH 정의를 파일 이름으로만 찾음(하위 폴더·`name:`·플러그인 하위·`CLAUDE_CODE_SUBAGENT_MODEL`) | 받음 — 폴더 재귀 + `name:` 일치, 환경변수 통과. 시험 3개 추가 |
| HIGH 분류기 놓침 12가지(`then`/`do`/`{`·`$()`·백틱·`-lc`·`uv run`·`sudo`·`nice`·`timeout -k`·`-W 값`·긴 모듈 경로) | 받음 — 괄호·백틱 구분자, 예약어·래퍼 옵션 벗기기, 합친 `-c`, 값 옵션 건너뛰기, 모듈 접미 일치. 시험 12개 + 따옴표 안 괄호 통과 1개 |
| MEDIUM `-p` 에서 G3 재시도 통과 | 고치지 않음 — §5 한계로 기록 |
| LOW `cd` 뒤 훅 폴더 계산 · `.harnessrc` 출력 · `.tmp` 잔재 | 받음 |
| LOW heredoc 본문 오탐 | 그대로 — 결과가 ask 뿐(해 없음) |

## 9. 리뷰 반영 (2026-10-21, Sonnet lite 2개)

architect-lite 8건 · planner-lite 13건 → 받아들임 20, 다르게 처리 1.

| 지적 | 처리 |
|---|---|
| A1 HIGH 글자 매칭 우회 | 단어 단위 판정 + `bash -c` 안쪽 + 다루기만 하는 명령 통과(G1), 한계를 §3 에 |
| A2 HIGH G2 대상·정의 탐색 경로 | 탐색 순서·내장 타입·fork·기본 subagent_type 을 G2 에 확정. **"Explore 는 원래 haiku" 는 확인 못 한 주장이라 기대지 않음** (다르게 처리) |
| A3 HIGH 헤드리스 ask | 기본안 + Step 1 실측 + 끔 스위치. `hermes-loop-run.sh` 제외 |
| A4·P5 MED 세션 id·경합·정리·반복 질문 | 원자적 갱신·7일 정리·fail-open·배수마다 ask (G3) |
| A5·P3 MED 훅 하나/둘·matcher | 하나의 스크립트, `Bash::`·`Task|Agent::` 두 등록, agent-guard 와 분리, case fast path |
| A6 MED 오탐 | G1 통과 명령 6종 시험 |
| A7·P7 LOW/MED 책임·심볼 | 모듈 셋으로 분리, 파일당 공개 1개, gate_event 기록 |
| A8 LOW 누락 | 롤백·deny 문구 시험·필드 실측을 Step 1·G2 에 |
| P1 HIGH G7 이미 충족 | §2-bis 사실로 옮기고 G7 을 "앞으로의 정의" 단언으로 |
| P2 HIGH 등록 경로 | harness.conf 75·141·142 행을 값으로, 설치본 settings 확인 (G8) |
| P4 MED ask 실측이 기대값을 바꿈 | Step 1 산출·§6 기록, 시험 기대값 분기 |
| P6 MED CLAUDE.md 여유 1줄 | 새 문구는 규칙 파일에만, `wc -l` 검증 (G8) |
| P8 MED run-all 등록 방식 | Step 1 에 목록 추가로 명시 |
| P9·P10·P11 LOW 검증 문구 | 고유 문구 grep, 변경 전 값(승인 0회) 기록, G6 명령 추가 |
| P12 LOW §0·롤백·끔 스위치 | 진행 표·되돌리기·`HARNESS_COST_GUARD=off` |
| P13 LOW 단계 독립성 | Step 2~4 를 G1→G2→G3 로 나누고 각자 시험·등록 |
