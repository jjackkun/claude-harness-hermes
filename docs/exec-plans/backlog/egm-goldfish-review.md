# EGM 에서 두 조각만 가져오기 — 이해도 시험 · 리뷰어 CLAUDE.md 격리

## 무엇

구글의 Claude Code 플러그인 EGM(`google/elephant-goldfish-model`, Apache-2.0, 2026-11-12 기준 ★17.7k)은
"맥락을 가진 에이전트(코끼리)가 설계 문서를 쓰고, 대화 기록 없는 새 서브에이전트(금붕어)가 문서만 읽고 리뷰한다" 는 방법론이다.

2026-11-12 README·`skills/egm-review/SKILL.md`·`docs/claude.md` 를 읽고 공장과 대조했다.
**7개 스킬 중 5개는 공장에 이미 있다:**

| EGM | 공장 |
|---|---|
| egm-brainstorm | `idea-check` |
| egm-draft | `prd-writer` · 실행 계획서 템플릿 |
| egm-review | `architect-lite` · `planner-lite` · `devil-advocate` (모두 `Read/Grep/Glob` 전용) |
| egm-resolve | 리뷰 지적을 코드로 가려 반영하는 관행 |
| egm-drift-report | `intended-vs-implemented` |

**공장에 없는 두 조각만 후보로 둔다.**

1. **이해도 시험(EGM Stage 6)** — 리뷰어 한 명이 문서만 읽고 "이 문서가 무엇을 하자는지" 를 다시 풀어 쓴다.
   풀이가 작성자 의도와 어긋나면 문서가 모호하다는 신호다. 공장 리뷰어는 "빠진 것"(lite)·"반론"(devil-advocate)만 본다.
2. **리뷰어 CLAUDE.md 격리** — EGM 리뷰어 어댑터는 `omitClaudeMd: true` 를 쓴다.
   공장 리뷰어 3종의 머리말에는 이 키가 없다(2026-11-12 저장소 grep 0건). 즉 공장 리뷰어는 CLAUDE.md·규칙을
   받은 채로 리뷰할 수 있고, 그만큼 "금붕어" 가 아니다.

## 가져오지 않는 것

- **5단계 리뷰어 약 10회 + `model: inherit`** — 리뷰 한 번에 부모 모델이 10회 이상 돈다(단계표에서 센 값, 저장소에 총합 없음).
  decision-ledger 5번·R-cost 훅과 충돌한다. 공장은 sonnet 한 명으로 쓸 만한 반론을 이미 얻었다
  (`docs/audits/2026-09-21-devil-advocate-trial.md`).
- **플러그인 통째 설치** — 같은 역할 스킬이 두 벌 생겨 발동이 엇갈린다.

## 왜 지금 하지 않는가

- active 계획서가 5개 진행 중이다.
- 착수 조건 실측이 안 됐다: `omitClaudeMd` 는 Claude Code 2.1.271 이상이 필요하다(`docs/claude.md`).
  2026-11-12 이 PC 에는 `claude` 명령이 PATH 에 없어 버전을 재지 못했다.

## 범위

"리뷰어 3종" = `architect-lite` · `planner-lite` · `devil-advocate` 만이다.
`code-reviewer` · 언어별 리뷰어 · `architect` · `planner` 는 코드나 프로젝트 맥락을 봐야 하므로 대상이 아니다.

## 열린 결정 — 격리가 이득인가 손해인가

`architect-lite` 는 "The design matches existing project patterns."(`assets/agents/architect-lite.md:18`)를 본다.
CLAUDE.md 를 끄면 리뷰어가 `core-beliefs.md` 의 R 룰과 프로젝트 관례를 못 볼 수 있다. 그러면 금붕어가 되는 대신 R 룰 위반을 놓친다.
승격 전에 둘 중 하나를 정한다.

- 격리하고, 리뷰어가 읽을 규칙 경로(`docs/design-docs/core-beliefs.md` 등)를 dispatch 프롬프트로 명시해 `Read` 하게 한다. (EGM 의 GoldfishContext 방식)
- 격리하지 않고 조각 2 를 버린다.

판단 기준: 같은 문서 1건을 격리 전·후로 리뷰시켜, 격리 후에만 나온 지적 수와 격리 후에 사라진 R 룰 지적 수를 센다.

## 착수 조건 (이 순서로)

1. 공장 리뷰어가 지금 CLAUDE.md 를 받는지 실측한다. 버전과 상관없이 먼저 할 수 있다.
   - 방법: 루트 `CLAUDE.md` 에만 있는 고유 문구 하나를 고른다(다른 파일에 같은 문구가 없음을 grep 으로 확인).
     `architect-lite` 를 1회 dispatch 해 "그 문구 다음 줄을 그대로 인용하라, 파일을 Read 하지 말고 받은 맥락에서만" 이라고 시킨다.
     자기 보고("있다/없다")가 아니라 **인용이 맞는가** 로 판정한다. 맞으면 받음, 틀리거나 못 하면 받지 않음.
   - 받지 않으면 조각 2 는 할 일이 없다. 이 항목에서 조각 2 를 지운다.
   - 받으면 2번으로 간다.
2. 조각 2 를 승격할 때만 `claude --version` 이 2.1.271 이상인지 확인한다. 미만이면 업데이트 전까지 보류한다.
3. 이해도 시험은 새 에이전트가 아니라 `architect-lite` 출력 맨 앞에 "한 문단 풀이" 칸을 더하는 안부터 본다(호출 수 0 증가).
   - `architect-lite` 는 `*-design.md` · `*-spec.md` 담당이다(`architect-lite.md:3`). 계획서는 `planner-lite` 담당이므로 이 시험이 닿지 않는다.
   - 출력 형식이 바뀐다. 2026-11-12 grep 기준 `tests/` · `scripts/` 에 `architect-lite`·`Design Review` 를 참조하는 곳은 없다. 깨질 시험은 없다.
   - 남길지 판정: 설계 문서 2건에 붙여 보고, 풀이가 작성 의도와 어긋난 것을 사람이 1건 이상 "쓸모 있었다" 고 하면 남긴다. 0건이면 빼고 이 항목을 지운다.

## 출처

- https://github.com/google/elephant-goldfish-model (README · `docs/claude.md` · `skills/egm-review/SKILL.md`)
- 계기: YouTube 소개 영상 "클로드 코드 구글 무료 플러그인 EGM, 코끼리·금붕어 모델로 설계 문서 리뷰" (본문·자막은 못 봄)
