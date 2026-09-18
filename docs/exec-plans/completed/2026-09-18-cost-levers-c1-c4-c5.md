# 2026-09-18-cost-levers-c1-c4-c5 — 비용·성능 레버 중 지금 할 수 있는 셋 (C1·C5·C4)

> 출처: `docs/exec-plans/backlog/platform-cost-performance-levers.md` (C1·C4·C5 만 승격, C2·C3 은 backlog 에 남김)
> 설계 결정 인용: 없음 — 헤드리스 호출 인자·문구 감사. 원장 결정과 무관.

## 1. 동기 (Why)

실측(2026-09-18):
- C1: `scripts/hermes_search_fallback.py:76` 이 `["claude","-p",prompt]` 로 **모델 없이** 부른다 → 세션 기본 모델(Opus)로 돈다.
  같은 저장소의 다른 6곳(crystallize·evolve-skill·dream·summarize·lifecycle·mesh_gate)은 `--model claude-haiku-4-5-20251001`.
  함수 이름부터 `haiku_fallback` 이다. 훅 경로는 `--no-fallback` 이라 안 타지만 수동 `hermes-search` 는 탄다.
- C5: CLI 에 `--exclude-dynamic-system-prompt-sections` 가 있다(cwd·환경·git status 를 첫 사용자 메시지로 옮겨 접두부 캐시 재사용).
  같은 프로젝트를 반복 호출하는 `hermes-cron-run.sh:71` 이 가장 이득. 측정 수단: 헤드리스 세션 transcript 의
  `cache_read_input_tokens`(session-report 가 읽음) — 확인됨. cron 은 현재 미등록(0건)이라 효과는 등록 뒤 잰다.
- C4: `prompt-audit` 스킬 미설치(플러그인 캐시·마켓플레이스 어디에도 없음) → 글의 안티패턴 목록으로 **수동 감사**만.
  자동 수정 금지(공통 자산은 사용자 승인 후).

## 2. 목표 (What — 검증 가능한 형태)

- [x] C1 — `hermes_search_fallback.py` 호출 인자에 `--model claude-haiku-4-5-20251001` — 검증: `tests/hermes-keywords-test.sh` 단언 1개
- [x] C5 — `hermes-cron-run.sh` 의 헤드리스 호출에 `--exclude-dynamic-system-prompt-sections` — 검증: 같은 테스트 단언 1개 +
  측정 절차(§7)를 backlog 에 기록
- [x] C4 — `docs/audits/2026-09-18-prompt-antipattern-audit.md`: `assets/rules`·`assets/skills`·UserPromptSubmit 주입의 안티패턴
  건수·파일·출처 표. 자산 수정 0 — 검증: `git diff --stat assets/` 가 비어 있음

## 3. 비목표 (Out of Scope)

- C2(`--effort`)·C3(에이전트 effort 배분) — 평가 세트(`agent-eval-regression`)·관측(`agent-model-routing-blindspot`) 이후.
- 감사에서 나온 문구를 고치는 것 — 사용자 승인 뒤 별도 커밋.
- hermes-loop·manager 프롬프트 경로에 플래그 붙이기 — cron 이 아닌 대화형 성격, 효과 불명.

## 4. 영향 영역

- 코드: `scripts/hermes_search_fallback.py`(인자 1개), `scripts/hermes-cron-run.sh`(플래그 1개), `tests/hermes-keywords-test.sh`(단언 2개)
- **신규 파일 목록**: 없음 (감사 문서는 docs/)
- 룰: 없음. 소우주 전파 대상: 두 스크립트(hermes.conf 복사 목록에 이미 있음)

## 5. 단계 (Steps)

### Step 1. C1·C5 — 테스트 단언 먼저(RED) → 인자 추가(GREEN) [단순]
### Step 2. C4 — 어휘 감사 스크립트 1회 실행 → 감사 문서 [단순]
### Step 3. 전체 스위트·backlog 갱신(C2·C3 잔류) [단순]

## 6. 의사결정 로그

- 2026-09-18: C5 는 cron 래퍼에만 — 근거: 반복 호출 경로가 거기뿐이고, 측정(transcript 캐시 필드)은 cron 등록 뒤에야 가능.
  cron 미등록 상태에서 붙이는 것은 "쓰일 때 이득" 이지 지금 이득이 아님을 §7 에 적는다.
- 2026-09-18: C4 는 건수·위치·출처만 — 근거: 강조 문구 일부는 실패 사례에서 나온 것(run-to-the-end 등). 지우기는 사람 판단.

## 7. 발견·예외

- C4 실측: 매 턴 주입 텍스트(2,990 B)는 안티패턴 0. 강조 46건은 세션 시작 로드 자산에 있고 상당수가 실패 사례 출처.
  즉시 고칠 가치는 `rules/common/performance.md` 의 옛 모델 표(Sonnet 4.6·Opus 4.5) 하나 — 사용자 승인 대상으로 감사 문서에.
- C5: cron 미등록(crontab 0건)이라 지금은 효과 0. 등록되면 transcript `cache_read_input_tokens` 로 전후 비교.
  `hermes-cron-run.sh` 는 hermes.conf 복사 목록에 있어 전파 대상.
- C1 의 첫 단언이 `grep -c '--exclude…'` 로 2(주석+호출)를 세어 한 번 빨갛게 됨 → 호출 줄 자체를 패턴으로.

## 8. 회고 (완료 시 작성)

- 잘된 것: 셋 다 실측으로 시작해 "고칠 것 하나(옛 모델 표)" 와 "고치면 안 되는 것(출처 있는 강조)" 를 갈랐다.
- 잘못된 것: 없음 특기.
- 다음 룰 후보: "헤드리스 `claude -p` 호출은 `--model` 을 반드시 넘긴다" — 이번 C1 이 7곳 중 유일한 누락이었고, 새 호출이
  생길 때 같은 누락이 반복되면 테스트(호출 인자 grep)로 승격.
