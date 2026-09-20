# 2026-09-19 — 에이전트 MEMORY.md 다섯 쟁점: cumora · ECC 는 어떻게 풀었나

> 출처: 사용자 "위의 5개 의견을 cumora 와 ECC 는 해결해 뒀잖아. 그걸 찾아." 조사는 탐색 에이전트 2개(cumora 로컬 v0.11.1 · ECC GitHub v2.2.1).
> 우리 현황: `memory_events`(C-14) 스키마·운반 코드는 있으나 쓰는 주체 0, MEMORY.md 재생성 호출 0, `about` 형식 미정(설계 6절), 주입은 4,096 B 캡 단순 절단.

## 요약표

| 쟁점 | cumora | ECC | 우리에게 맞는 답 |
|---|---|---|---|
| 1. 누가 언제 쓰나 | 훅 없음. 시스템 프롬프트가 모델에게 `memory note '<lesson>' --about <subject>` 를 스스로 부르라고 지시. 지적 전용 경로 없음 | PreToolUse/PostToolUse 가 모든 도구 호출을 `observations.jsonl` 로 적재(입출력 5,000자 절단) → 별도 백그라운드 observer(haiku, 5분·20건 이상, 기본 off)가 "같은 패턴 3회 이상" 일 때 instinct 생성. 지적 전용 경로 없음, 사용자 발화는 관찰 안 함 | **둘의 합**: 소환 러너가 `task.finished` 에 에이전트에게 `hermes-agent.py note "<한 줄>" --about <키>` 를 부르게 프롬프트로 지시(cumora 식, 모델 추가 호출 0). 사람 지적은 teach·리뷰(C-21·C-22) 전용 경로 — 두 곳 다 없는 것을 우리는 이미 설계함. ECC 식 도구 로그 관찰은 R3·비용 때문에 안 함 |
| 2. 주입 예산·선별 | 핀 전체 + 의미검색 20 + 최근 10 = 40 UNION, 핀>의미>최근 순 중복 제거. 다이제스트 4,000자, 초과 시 "…truncated — cat the file" 꼬리표 | confidence ≥ 0.7 필터 → 프로젝트 범위 +0.25, 스택 관련 +0.2 가산 → 상위 **6개**. 전체 주입 8,000자 캡 + 잘림 마커 | 파일(MEMORY.md)은 전체, **주입은 선별**: 핀(사람이 `pin`) 전체 + 이번 봉투 `about`/키워드 일치 상위 N + 최근 M. 초기값 N=6·M=4(ECC 6 · cumora 10 사이), 캡은 기존 4,096 B 유지하되 잘림 시 ECC 식 마커 필수. 의미검색은 R3 로 불가 → `hermes_search_fallback` 의 키워드 매칭 재사용 |
| 3. 주제 키 형식 | `--about` 자유 문자열(검증 없음). `--kind` 5종 화이트리스트(observation·preference·fact·decision·note), 모르는 값은 observation 으로 강등. 민감정보 필터 없음 | `id` kebab-case 정규식 `^[A-Za-z0-9][A-Za-z0-9._-]*$` ≤128자, `domain` 고정 집합, `trigger: "when …"`. 군집은 trigger 토큰 overlap ≥ 0.5 & 공유 ≥ 2. 저장 전 `(api[_-]?key|token|secret|password|authorization|credentials?|auth)` 값 `[REDACTED]`, "코드 조각 금지" | `about` = `<domain>/<slug>`: domain 은 고정 집합(ECC 6종을 우리 말로: gate·test·git·debug·workflow·file + sync·agent), slug 는 위 정규식. `kind` 는 cumora 5종 채택. 같은 주제 = `about` 문자열 일치 우선, 보조로 ECC overlap 규칙. 원격 평문인 `about` 에는 ECC 정규식 + 봉투 누출 게이트(이름·경로·티켓) 적용 |
| 4. 승격 뒤 원 기억 | 승격 경로 없음. 등급은 `pin` 하나. 만료·감쇠 없음, 정리는 수동 delete | `/evolve` 가 군집을 스킬로 **복사 생성**(`evolved_from` 기록), 원 instinct 는 그대로. `/promote`(2개 이상 프로젝트, 평균 ≥ 0.8) 만 원본 제거. `/prune` 은 pending 30일. confidence 감쇠는 문서만, 미구현 | ECC 처럼 **원 기억은 남긴다**(INSERT 전용과도 맞음). 결정화 시 `memory.revised` 한 건으로 "스킬 X 로 승격" 을 표시하고 MEMORY.md 는 그 about 을 한 줄로 접는다(내 4번 의견 유지). 감쇠는 두 곳 다 안 했으니 우리도 안 함 — 대신 기존 도움률 강등을 그대로 |
| 5. 이름·위치 | `agent_workspace` 테이블, 경로 `memory/[projects/<pid>/]<kind>/<id>.md`, 로컬 BYOA 는 `~/.cumora/agents/<id>/memory/MEMORY.md`. 동기화 명령 없음(Postgres 가 원본) | `~/.local/share/ecc-homunculus/projects/<12자 해시>/instincts/{personal,inherited}` — `~/.claude` 밖(민감 경로 가드 회피). memory vault 는 별개 시스템, Claude auto-memory 와 통합 없음 | 이름 충돌은 둘 다 안 풀었다(cumora 도 `MEMORY.md`). 우리는 `state.db` + `refs/hermes/sync`(C-14) 가 이미 답이고 운반 계획(agent-memory-roundtrip)이 있다. 파일 이름은 그대로 두고 세션 시작 훅 머리말에 "에이전트 기억" 이라고 써서 구분 |

## 그대로 가져올 값

- ECC: 생성 문턱 3회, 주입 상위 6, 잘림 마커 문구 형식, `id` 정규식, redact 정규식, `evolved_from`.
- cumora: `kind` 5종, 핀 > 관련 > 최근 우선순위, "…truncated — cat the file" 안내.

## 미해결

- 사람 지적(correction) 전용 경로는 **두 곳 다 없다**. 우리 C-21·C-22 가 앞서 있다 — 그대로 간다.
- confidence 감쇠는 ECC 도 문서만. 채택하지 않는다.

## 다음

쟁점 1·2·3 은 `agent-teaching` 계획 §4·§6 에 결정으로 옮긴다(teach/note 명령 · 주입 선별 · about 형식). 4 는 같은 계획 목표 3 에 한 줄. 5 는 roundtrip 계획이 이미 담당.
