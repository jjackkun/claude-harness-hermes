# 비용·성능 레버(캐시·프롬프트 감사·effort)를 이 저장소에 적용한다

> 작성일: 2026-09-15
> 목적: Claude Platform 비용 절감 글의 레버 중 **구독 CLI 경로(R3)에서 실제로 쓸 수 있는 것**만 골라 적용 후보로 남긴다.

## 출처

- 글: <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform> (2026-09-08 게시)
- 핵심 레버 셋: ① 프롬프트 캐시 ② 프롬프트 안티패턴 감사 ③ effort 조정.
- 글이 제시한 수치(글 기준, 이 저장소에서 잰 값 아님):
  - `/claude-api prompt-audit` — Opus 4.8→5 이전 시 비용 14.6% 감소, 정확도 5.3% 증가(고객지원 벤치 평균)
  - `/claude-api hillclimb` — Opus 4.8 기준 78.6% → Sonnet 5 low effort 90.5%, 비용 약 1/5
  - `/claude-api cost-optimize` — LegalBench 약 58%, tau2-bench retail 약 73%, SWE-bench Verified 약 55% 절감
  - 캐시 재작성 비용은 입력가의 1.25배. 기본 TTL 5분, 1시간 선택 가능.

## 무엇을 적용하고 무엇을 버리는가

### 적용 불가 — R3 와 충돌 (API 직접 호출이 전제)

| 글의 기법 | 버리는 이유 |
|---|---|
| 명시적 cache breakpoint · `max_tokens: 0` 선예열 | Messages API 파라미터. 구독 CLI 는 캐시를 내부에서 관리한다 |
| 도구 `defer_loading` | API 도구 정의 필드. CLI 는 이미 deferred tool 방식으로 동작한다 |
| Batch API | 종량제 API 전용. 구독 청구 경로가 아니다 |
| cache diagnostics API · usage/cost API | API 키 필요 |

### 적용 후보 — CLI·자산 수준에서 가능

2026-09-15 실측으로 확인한 현재 상태와 함께 적는다.

#### C1. `hermes_search_fallback.py` 가 모델을 지정하지 않는다 (가장 먼저)

- 현재: `scripts/hermes_search_fallback.py:76` 이 `["claude", "-p", prompt]` 로 부른다. 함수 이름은 `haiku_fallback` 인데 `--model` 이 없어 **세션 기본 모델(현재 Opus)** 로 돈다.
- 비교: `hermes-crystallize.py:280` · `hermes-evolve-skill.py:148` · `hermes-dream.py:216` 은 `--model claude-haiku-4-5-20251001` 을 넘긴다.
- 할 일: 같은 `--model` 을 넘긴다. 스킬 설명 중 하나를 고르는 분류 작업이라 haiku 로 충분하다는 것이 다른 세 호출과 같은 판단이다.
- 검증: 호출 인자에 `--model` 이 들어갔는지 확인하는 테스트 1개.

#### C2. 헤드리스 호출에 `--effort` 가 하나도 없다

- 현재: `claude --help` 에 `--effort <level>` (low·medium·high·xhigh·max) 가 있다. 저장소의 `claude -p` 호출 7곳(crystallize·evolve-skill·dream·search_fallback·hermes-loop.py:118·cron-run.sh:56·manager 프롬프트) 어디에도 없다.
- 할 일: 작업 성격별로 정한다.
  - 짧은 생성·분류(crystallize·evolve·dream·search_fallback) → `low` 후보. 단 haiku 모델이 `--effort` 를 받는지 **먼저 확인**한다(글은 effort 지원 모델을 Opus 5 · Fable 5.1 · Fable 5 로 적었다).
  - 자율 루프(hermes-loop.py:118) → 기본값 유지, `--effort` 를 루프 옵션으로 노출만 한다.
- 검증: 같은 입력으로 effort 별 결과를 비교할 평가 세트가 없으면 값을 정하지 않는다(글의 핵심 주장이 "과제별 곡선을 재고 정하라" 다).

#### C3. 에이전트 effort 배분이 측정 없이 선언돼 있다

- 현재(15종): `high` 9 · `medium` 4 · `low` 2. 리뷰어 대부분(python·typescript·database·silent-failure·tdd)이 `sonnet` + `high`.
- 글 근거: 최신 모델은 낮은 effort 에서도 이전 세대 high 를 따라잡는 경우가 있다(Fable 5.1 low ≈ Fable 5 high, 비용 1/3).
- 할 일: `backlog/agent-model-routing-blindspot.md`(어느 에이전트가 어느 모델로 불렸는지 기록이 없다)와 **합쳐서** 진행한다. 관측 없이 effort 를 내리면 같은 문제를 반복한다.
- 검증: `backlog/agent-eval-regression.md` 의 평가 세트가 생긴 뒤, 리뷰어 1종을 `high`/`medium` 으로 돌려 놓친 결함 수를 비교한다.

#### C4. 규칙·스킬 문구 안티패턴 감사

- 글이 꼽은 안티패턴: 검증 의식("두 번 확인하라"), 강조 대문자("CRITICAL: YOU MUST"), 고정 절차 스캐폴드, 옛 모델용 예시, 서로 모순되는 규칙.
- 현재: `assets/rules` · `assets/skills` 에 `반드시`·`절대`·`YOU MUST` 류가 7개 파일에 있다(가장 많은 곳: `harness-promote-rule/SKILL.md` 3, `rules/harness/rules.md` 3). 매 턴 주입되는 `UserPromptSubmit` 리마인더도 대상이다 — 주입량이 매 턴 입력 토큰이 된다.
- 할 일: `/claude-api prompt-audit` 를 `assets/rules/` · `assets/skills/` · `scripts/hooks/claude-userpromptsubmit-dispatch.sh` 출력에 돌려 지적 목록을 `docs/audits/` 에 남긴다. **자동 수정 금지** — 공통 자산은 사용자 승인 후 반영(헤르메스 원칙).
- 선행 확인: 설치된 `claude-api` 스킬에 `prompt-audit` 하위 명령이 실제로 있는지. 2026-09-15 확인 시 `~/.claude/skills`·`~/.claude/plugins` 의 스킬 본문에서는 못 찾았고 마켓플레이스 목록(`marketplace.json`)에만 이름이 있었다 — 설치·갱신이 필요할 수 있다. 없으면 글의 안티패턴 목록을 체크리스트로 수동 감사한다.
- 주의: 강조 문구 중 일부는 실패 사례에서 나온 것이다(예: `run-to-the-end`). 지우기 전 해당 문구의 출처 계획서·감사 기록을 확인한다.

#### C5. 캐시를 깨는 동적 내용 점검

- 글 근거: 캐시는 접두부가 바이트 단위로 같아야 맞는다. 시스템 프롬프트의 타임스탬프·ID 가 바뀌면 매 요청 재작성(1.25배).
- 현재 CLI 에 `--exclude-dynamic-system-prompt-sections` 가 있다(cwd·환경·git status 를 첫 사용자 메시지로 옮겨 캐시 재사용을 늘림, 기본 꺼짐).
- 할 일:
  1. cron·manager·loop 헤드리스 호출에 이 플래그를 붙일지 판단한다. 같은 프로젝트를 반복 호출하는 cron 경로가 이득이 가장 크다.
  2. `CLAUDE.md` 템플릿·`SessionStart` 훅 주입에 날짜·카운트처럼 매 세션 바뀌는 값이 **시스템 프롬프트 쪽**에 들어가는지 확인한다. 예: 이 저장소 `CLAUDE.md` 의 "게이트 16종 · 테스트 49개" 는 자산이 바뀔 때만 바뀌므로 문제없음. 매 세션 바뀌는 값이 있으면 사용자 메시지 쪽 주입으로 옮긴다.
- 검증: 측정 수단이 없다(구독 CLI 는 캐시 적중률을 노출하지 않는다). `session-report` 스킬의 캐시 지표로 전후 비교가 가능한지 먼저 확인한다.

## 진행 (2026-09-18)

C1·C5·C4 는 `completed/2026-09-18-cost-levers-c1-c4-c5.md` 로 완료(C1 haiku 고정 · C5 cron 래퍼 플래그 · C4 감사 문서
`docs/audits/2026-09-18-prompt-antipattern-audit.md`). **남은 것은 C2·C3** — 평가 세트(`agent-eval-regression`, 착수 조건
미충족)와 관측(`agent-model-routing-blindspot`, 09-29 판단) 이후. 이 항목은 그 둘을 기다린다.

## 우선순위 제안

1. **C1** — 한 줄 수정, 훅 경로(세션 시작마다)에서 기본 모델이 도는 것을 막는다.
2. **C4** — 측정 없이도 문구 감사 기록은 남길 수 있다.
3. **C5** — 플래그 판단은 싸다. 효과 측정 수단 확인이 선행.
4. **C2 · C3** — 평가 세트(`agent-eval-regression`)와 관측(`agent-model-routing-blindspot`) 이후.

## 착수 시

`docs/exec-plans/active/YYYY-MM-DD-<slug>.md` 로 옮기고 템플릿의 §2 목표·검증을 위 항목별 "검증" 줄로 채운다. C1 만 떼어 먼저 할 경우 별도 계획서로 분리한다.
