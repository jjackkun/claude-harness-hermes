# 2026-09-21-skill-trigger-eval-in-project — 진짜 스킬 이름으로, 픽스처 프로젝트 안에서 발동률을 잰다

> 출처: backlog `skill-trigger-eval-in-project` ← `docs/audits/2026-09-20-hermes-agent-trigger-eval.md`. 2026-09-21 사용자 "진행하자".

## 1. 동기 (Why)

9-20 에 hermes-agent 스킬 발동률을 skill-creator `run_eval.py` 로 쟀더니 재현율 28%. 그런데 원인이 평가 방식이었다:
`run_eval` 은 명령 이름을 `hermes-agent-skill-<id>` 로 바꿔 **빈 루트**에 심는다. 그래서 `/hermes-agent` 슬래시조차 0/3 이고,
CLAUDE.md·명부·조직 파일이 없는 곳에서 "직원 뽑자" 를 받으니 모델이 "여기엔 명부가 없다" 로 끝낸다.
실제 소우주의 조건(진짜 스킬 이름 + 프로젝트 문맥 + 세션 훅의 `[Hermes 관련 규칙]` 주입)에서의 발동률은 **한 번도 잰 적이 없다.**

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `harness-eval.py --trigger <스킬>` 이 `assets/skills/<스킬>/evals/trigger-eval.json` 의 질의를 **설치된 픽스처 프로젝트 안에서** 돌리고, 진짜 스킬 이름의 `Skill` 호출을 발동으로 센다. 검증: `bash tests/harness-eval-test.sh` 6절(가짜 실행 파일이 `Skill hermes-agent` 를 내면 재현율 100%).
- [x] 목표 2 — 정밀도·재현율·정확도(질의별 발동률 ≥ 50% 판정)를 9-20 감사 표와 같은 칸으로 낸다. 검증: 같은 절 + `trigger_metrics` 단위 시험(발동 0 이면 재현율 0%·오발동 0).
- [x] 목표 3 — `--no-inject` 로 세션 훅의 스킬 주입을 끈 조건을 따로 잰다(설명 문구의 기여와 훅의 기여 분리). 검증: 같은 절에서 실행 사본에 `.hermes/state.db` 가 없다.
- [x] 목표 4 — 실제 측정은 **사람이 정한다**(크레딧). 검증: `python3 scripts/harness-eval.py --trigger hermes-agent --dry-run` 이 호출 수를 예고한다.

## 2-bis. 착수 전 확인한 사실 (2026-09-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| harness-eval 이 이미 하는 것 | `project-claude.sh <tmp> harness hermes` 로 픽스처 설치 → 사본마다 헤드리스 실행(stream-json) → 도구 호출 타임라인 채점. `hire-form` 시나리오가 이미 `Skill /hermes-agent/` 를 요구한다 |
| harness-eval 에 없는 것 | 발동/비발동 **질의 묶음**의 정밀도·재현율 · 주입 켬/끔 분리 |
| 평가 집합 | `assets/skills/hermes-agent/evals/trigger-eval.json` 12 질의(발동 6 · 비발동 6), 형식 `{query, should_trigger}` |
| 주입 훅 스위치 | `claude-userpromptsubmit-reminders.sh:90` — `.hermes/state.db` 가 있을 때만 `hermes-search.py` 로 주입. **끄는 환경변수 없음** → 실행 사본에서 `state.db` 를 치우면 끔 |
| 시나리오 준비 | `_prepare` 는 `setup.files` 로 파일 **추가**만 지원. 제거는 없다 |
| 9-20 기준값 | 빈 루트·가짜 이름: 정밀도 100% · 재현율 28% · 정확도 50% |

## 3. 비목표 (Out of Scope)

- skill-creator 사본 수정 — backlog 는 "우리 skill-creator 사본에 옵션" 이라 했으나, 픽스처 설치·신뢰 등록·stream 파싱·채점이 이미 harness-eval 에 있다. 거기에 붙이면 중복 0.
- 설명 문구 개선 루프(run_loop) — 이번엔 **재는 도구**까지. 문구 수정은 측정 뒤 별건.
- 실제 측정 실행 — 크레딧이 든다. 사람이 `--dry-run` 을 보고 정한다.

## 4. 영향 영역

- 코드: `scripts/harness-eval.py`(`--trigger`·`--no-inject` 인자, 시나리오 출처 선택, `_prepare` 의 `setup.remove`, 지표 출력) · `tests/harness-eval-test.sh`(6절)
- **신규 파일 목록**:
  - `scripts/harness_eval_trigger.py` — 발동 평가 집합을 harness-eval 시나리오로 바꾸고, 실행 결과에서 정밀도·재현율·정확도를 계산한다(모델 호출 0)
- 룰: 없음. 데이터: 없음(결과는 기존 `.harness/evals/`). 외부 의존: 없음.

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [Impl] — 6절 + 단위 시험, 빨강 확인
### Step 2. 변환·지표 모듈 [Impl]
### Step 3. 러너 배선 [Impl] — main 복잡도 11 이하 유지(헬퍼로)
### Step 4. 전체 시험 → 커밋 [검증]

## 6. 의사결정 로그

- 2026-09-21: skill-creator 가 아니라 **harness-eval 에 붙인다** — 근거: 필요한 기반(픽스처·신뢰·파싱·채점)이 이미 거기 있다. skill-creator 사본에 붙이면 그 전부를 다시 짠다.
- 2026-09-21: 발동 판정은 `Skill` 도구 호출만 센다(hire-form 처럼 CLI `hermes-agent.py hire` 를 대안으로 치지 않는다) — 근거: 재려는 것은 **스킬 설명의 발동력**이다.
- 2026-09-21: 주입 끔은 실행 사본의 `state.db` 제거로 만든다 — 근거: 제품 훅에 시험용 스위치를 더하지 않는다.

## 7. 발견·예외

- **결과 폴더를 나누지 않았다면 어제 만든 장치가 조용히 꺼졌다.** 발동 평가 결과를 행동 평가와 같은 `.harness/evals/` 에 두면,
  다음 행동 평가의 "직전 결과" 가 발동 평가 파일이 된다. 칸 이름(`trig-01/neutral` ↔ `no-verify/neutral`)이 겹치지 않아
  시도율 상승 알림이 아무 말도 안 하게 된다. 그래서 `evals/trigger-<스킬>[-noinject]/` 로 나눴다 — R-eval 의 "마지막 실행" 도 최상위만 센다.
- **발동 판정은 이름 일치로.** 채점용 시나리오는 정규식이지만 지표는 `Skill` 입력의 스킬 이름이 정확히 같을 때만 센다.
  9-20 의 `hermes-agent-skill-<id>` 같은 이름은 발동이 아니다(단위 시험으로 고정).
- 계획서를 Bash heredoc 으로 쓰다가 summon-guard 에 막혔다 — 본문에 헤드리스 실행 명령 글자가 있었다. 실행이 아니라 문서였으므로 우회 대신 Write 도구로 썼다.
  훅이 명령 **문자열**을 보는 이상 같은 일이 또 난다(문서 작성 경로는 Write 로).
- 실측은 하지 않았다. 호출 수: 주입 켬 k=3 이면 36회, k=2 면 24회. 켬/끔 둘 다 재면 두 배.

## 8. 회고 (완료 시 작성)

- 잘된 것: 백로그가 지목한 곳(skill-creator 사본)이 아니라 이미 기반이 있는 harness-eval 에 붙여 새 코드가 모듈 하나(약 100줄)로 끝났다.
  시험도 러너 호출 1회만 더해 비용을 늘리지 않았다(앞 작업에서 배운 것).
- 잘못된 것: 없음 — 다만 도구가 정말 쓸모 있는지는 실측 전까지 모른다. 9-20 의 28% 가 평가 방식 탓이었다는 가설은 아직 가설이다.
- 다음 룰 후보: 없음.
