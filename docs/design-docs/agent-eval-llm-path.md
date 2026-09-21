# 하네스 행동 평가(agent eval)의 LLM 호출 경로

> 작성일: 2026-09-18
> 목적: `backlog/agent-eval-regression.md` 착수 조건 ②("R3 와 CI 내 LLM 호출의 관계를 설계로 정리")에 답한다.
> 결론 한 줄: **행동 평가는 로컬·수동·구독 CLI(`claude -p`) 경로로만 한다. CI 와 API 키 경로는 쓰지 않는다.**

## 개요

"agent eval" 은 코드가 아니라 **에이전트의 행동**이 규칙을 지키는지 재는 검사다(예: 룰 문구를 순화한 뒤에도 금지된
import 요청을 거부하는가). 정적 검사(`tests/run-all.sh`)로는 잴 수 없고 모델을 실제로 불러야 한다. 그래서 "어느 경로로
부르는가" 가 먼저 정해져야 한다.

## 사실 (2026-09-18 실측)

| 항목 | 실측 |
|---|---|
| R3 의 정체 | `assets/rules/harness/rules.md` 의 **소우주 도메인 룰** — "anthropic SDK 설치·import·호출 금지, 모든 LLM 호출은 구독 CLI 어댑터 경유". 애플리케이션 코드를 겨냥한다. 공장 `core-beliefs.md` 에는 R3 절이 없다 |
| 공장이 이미 쓰는 경로 | `hermes-summarize.py`·`hermes-dream.py`·`hermes-crystallize.py`·`hermes_search_fallback.py`·`assets/skills/skill-creator/scripts/run_eval.py` 전부 `["claude","-p",…,"--model","claude-haiku-4-5-20251001"]`. API 키·SDK 사용 0 |
| 비용 체계 | `docs/design-docs/claude-p-policy-change-2026-06.md`: 2026-06-15 부터 `claude -p` 는 **월간 프로그래매틱 크레딧**(Max 20x 기준 ≈ 2,200회/월). 대화형 세션은 제외 |
| CI | `.github/workflows/ci.yml` 은 `bash tests/run-all.sh` 만 — 결정론적·무료. 구독 CLI 는 CI 러너에 없다 |
| 이미 있는 평가 러너 | `skill-creator/scripts/run_eval.py` — 스킬 description 트리거 정확도를 `claude -p` 로 재는 로컬 도구. 행동 평가의 골격으로 재사용 가능 |

## 판단

1. **R3 와 모순되지 않는다.** R3 는 "SDK/API 키 경로 금지, 구독 CLI 경유" 다. 하네스 자체 평가가 `claude -p` 를 쓰는 것은
   R3 가 요구하는 바로 그 경로다. 모순은 영상 예시처럼 **CI 에서 `ANTHROPIC_API_KEY` 로 직접 호출**할 때만 생긴다.
2. **CI 에서는 하지 않는다.** CI 에 구독 CLI 가 없고, API 키를 넣는 순간 이 프로젝트가 소우주에 강제하는 R3 를 공장이 스스로
   어긴다. CI 는 지금처럼 결정론적 검사만 둔다.
3. **야간 자동 실행도 하지 않는다.** 과제 20~50개 × 매일 = 월 600~1,500회로 크레딧의 27~68% 다. 요약·드림이 쓰는 몫(소우주
   8곳, 세션당 1회 + 하루 1회)과 경쟁한다. 실행은 **룰/스킬을 바꾼 직후 사람이 로컬에서 수동**으로만.
   > **실측 갱신 (2026-09-21)**: 위 20~50개는 설계 당시 가정이다. 실제 러너 기본값(시나리오 7 × 단계 3 × `--k 3`)은
   > **1회 63 호출** → 매일 돌리면 월 1,890회 = 크레딧의 **약 86%**. 결정(야간 금지)은 더 강해진다.
   > `--k 2` 는 42 호출, `--only` 로 바뀐 규칙의 시나리오만 돌리면 6~18 호출이다.
   >
   > "수동으로만" 은 사람의 기억에 기대는 모양이라 그대로 두면 이 도구를 만든 이유("잰 적이 없어 두 달 몰랐다")를 상속한다
   > (2026-09-21 반대 심문 지적). 그래서 **돌리는 것은 사람, 돌릴 때라고 알리는 것은 기계** 로 나눴다 —
   > pre-commit `R-eval` 경고가 규칙·강제 파일 변경 커밋에서 마지막 실행 경과일을 알린다(모델 호출 0, R3 유지).
4. **모델은 haiku 고정, 과제는 어휘 판정 가능한 형태로.** 채점은 모델이 아니라 출력의 어휘·행동 로그(거부 문구·도구 호출 유무)로
   한다 — 채점에 또 모델을 쓰면 비용이 두 배가 되고 판정이 흔들린다.

## 착수 판단에 미치는 영향

조건 ②는 이 문서로 충족된다. 그러나 조건 ①(실제 행동 퇴행 관측)·③(다른 프로젝트의 요청)은 2026-09-18 현재 미충족이고,
잡으려는 퇴행이 한 번도 관측되지 않은 상태에서 과제 파일 수십 개의 유지보수 비용을 지는 것은 이르다. **①·③ 중 하나가
생기면** 이 문서의 경로(로컬·수동·haiku·어휘 채점)로 `run_eval.py` 를 본떠 만든다.

## 관련

- `docs/exec-plans/backlog/agent-eval-regression.md`
- `docs/design-docs/claude-p-policy-change-2026-06.md`
- `assets/skills/skill-creator/scripts/run_eval.py`
