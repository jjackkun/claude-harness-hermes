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

## 착수 조건 (이 순서로)

1. `claude --version` 이 2.1.271 이상인지 확인한다.
2. 공장 리뷰어가 지금 CLAUDE.md 를 받는지 실측한다 — `architect-lite` 를 "받은 시스템 맥락에 CLAUDE.md 문구가 있는가" 과제로 1회 dispatch.
   - 받지 않으면 조각 2 는 할 일이 없다. 이 항목에서 지운다.
   - 받으면 `omitClaudeMd: true` 를 리뷰어 3종 머리말에 넣는 계획으로 승격.
3. 이해도 시험은 새 에이전트가 아니라 `architect-lite` 출력 맨 앞에 "한 문단 풀이" 칸을 더하는 안부터 본다(호출 수 0 증가).
   한 번 시험해 본 뒤 사람이 유용하다고 말해야 남긴다(`devil-advocate` 때와 같은 기준).

## 출처

- https://github.com/google/elephant-goldfish-model (README · `docs/claude.md` · `skills/egm-review/SKILL.md`)
- 계기: YouTube 소개 영상 "클로드 코드 구글 무료 플러그인 EGM, 코끼리·금붕어 모델로 설계 문서 리뷰" (본문·자막은 못 봄)
