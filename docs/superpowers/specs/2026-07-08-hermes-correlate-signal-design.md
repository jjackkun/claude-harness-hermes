# 헤르메스 효용 판정 신호 복구 설계 (C2)

> 작성일: 2026-07-08
> 목적: 결정화된 스킬이 "만들기만 하고 안 쓰는" 상태의 근본원인 중 **C2(효용 판정이 파일
> 편집에만 걸림)**를 고쳐, 읽기·조회·테스트·검증형 스킬도 helpful 신호를 받을 수 있게 한다.
> 근거 감사: `docs/audits/2026-07-08-hermes-skill-utilization-gap.md`
> 소스(고칠 위치): `claude-harness-hermes/scripts/hermes-correlate.py`

## 1. 동기 (Why)

감사(`docs/audits/2026-07-08-hermes-skill-utilization-gap.md`)의 실측: `skill_index` 292개 중
`helpful_count` 합계가 **0**. 원인은 상관 로직 버그가 아니라, `hermes-correlate.py`가 helpful을
**Edit/Write/MultiEdit 대상 파일 경로 토큰과 스킬 키워드의 겹침**으로만 판정하기 때문이다.
`api-token`·`swagger-curl-lookup` 같은 **읽기·조회·테스트·검증형 스킬은 파일을 편집하지 않으므로**
설령 주입되어 실제로 도움이 됐어도 helpful로 카운트될 경로가 원천 봉쇄된다(효용 판정의 영구 사각지대).

효용 신호가 죽어 있으면 드리밍(`hermes-dream.py`)이 승격·강등·정리 근거를 잃는다(감사 C3). 이 설계는
그 사각지대를 없애 신호를 되살리는 것에 한정한다.

## 2. 목표 (What — 검증 가능)

- [ ] **G1 도구 활동 전반으로 토큰 확대** — `hermes-correlate.py`가 helpful 판정에 쓰는 세션 토큰을
  Edit/Write/MultiEdit 뿐 아니라 Read·Bash·Grep·Glob 도구의 대상에서도 수집한다. 검증: Bash `command`에
  스킬 키워드가 든 가짜 transcript로 상관 실행 시 그 스킬이 helpful 후보로 잡힌다.
- [ ] **G2 겹침 키워드 ≥2 가드** — helpful은 `스킬키워드 ∩ 세션토큰`의 **서로 다른 원소가 2개 이상**일
  때만 인정한다. 검증: 1개만 겹치면 noop, 2개 겹치면 helpful.
- [ ] **G3 단어 파편 배제** — 키워드가 1개뿐인 스킬(파편)은 아무리 겹쳐도 helpful을 못 받는다(구조상 ≥2
  불가). 검증: 키워드 1개 스킬은 주입·활동 겹침이 있어도 helpful_count=0 유지.
- [ ] **G4 편집 경로 회귀 방어** — 기존 편집 스킬 판정도 동일하게 ≥2 규칙으로 동작한다. 검증: 편집 경로
  토큰과 스킬 키워드가 2개 겹치면 helpful.
- [ ] **G5 비차단·되돌림 가능** — 상관은 항상 exit 0이고, 결과는 helpful/noop 카운터 증가(되돌릴 수 있는
  강등으로만 이어짐)뿐이다. 스키마·데이터 흐름 불변. 검증: 잘못된 transcript·DB에도 예외 없이 exit 0.

## 3. 비목표 (Out of Scope)

- **C1 (주입 트리거 확장·push→pull 승격)** — 다음 사이클. 본 설계는 "주입이 일어났을 때 효용을 제대로
  판정"하는 것만 다룬다. 주입 빈도 자체는 C1의 몫.
- **C3 (258개 파편 정리 배치)** — C2 신호가 쌓인 뒤 별건. 단, ≥2 가드가 파편의 helpful 획득을 구조적으로
  막아 C3의 사전 효과를 낸다.
- **점수 등급제(fractional/weighted)** — binary(helpful_count/noop_count) 모델을 유지. 스키마 변경 없음.
- **자동 강등·삭제** — 드리밍이 신호를 근거로 제안만 하고 사람이 승인하는 기존 정책 유지.

## 4. 아키텍처

### 4.1 변경 범위 (1파일)

```
scripts/hermes-correlate.py   # 토큰 수집 확대 + ≥2 가드 (유일한 로직 변경)
tests/hermes-pipeline-test.sh # 상관 시나리오 테스트 추가
```

기존 데이터 흐름·트리거(Stop 훅 등록)·스키마는 그대로. `hermes-correlate.py` 내부 두 지점만 바뀐다.

### 4.2 토큰 수집 확대 — `edited_path_tokens` → `session_tool_tokens`

기존 `edited_path_tokens(transcript_path)`는 `tool_use` 블록 중 이름이 `edit/write/multiedit`인 것의
`input.file_path`만 토큰화했다. 이를 **모든 `tool_use` 블록**을 훑어 아래 필드를 토큰화하도록 일반화한다:

| 도구 이름(소문자) | 토큰화 대상 필드 |
|---|---|
| `edit`, `write`, `multiedit` | `file_path` |
| `read` | `file_path` |
| `bash` | `command` |
| `grep`, `glob` | `pattern`, `path` |

- 토큰화 규칙은 기존 그대로 재사용: 정규식 `[a-z0-9가-힣_\-]+`, 길이 ≥ 2, 소문자화, `set`에 수집.
- 알 수 없는 도구·필드 부재는 조용히 건너뛴다(방어적). 함수는 여전히 예외를 삼키고 빈 `set`을 반환할 수
  있다(비차단).
- 함수명을 `session_tool_tokens(transcript_path)`로 바꾸고, 의미가 "편집 경로"에서 "세션 도구 활동
  토큰"으로 넓어졌음을 docstring에 명시한다.

### 4.3 helpful 판정 — 겹침 ≥2

`correlate()`의 판정을 다음으로 바꾼다:

```python
overlap = kws & tokens
helped = len(overlap) >= MIN_KEYWORD_OVERLAP
```

- `MIN_KEYWORD_OVERLAP = 2` — 모듈 상수. 근거: **단어 하나짜리 파편 키워드로는 도달 불가**(≥2 필요)
  하여 파편을 배제하고, 진짜 스킬(토큰·인증·login 등 복수 도메인 키워드)만 통과시킨다. 최소한의 교차
  근거를 요구해 단일 우연 겹침의 거짓양성을 막는다.
- 환경변수로 조정 가능: `MIN_KEYWORD_OVERLAP = int(os.environ.get("HERMES_CORRELATE_MIN_OVERLAP", "2"))`.
- 나머지(주입 원장 조회, `correlated=1` 마킹, helpful/noop 갱신, 커밋)는 불변.

## 5. 데이터 흐름 (완성도 검증)

```
Stop 훅 → hermes-correlate.py --db --transcript --session-id
  → skill_injection 에서 (session_id, correlated=0) 주입 행 조회
  → session_tool_tokens(transcript): 모든 도구 활동 토큰 수집 (확대)
  → 각 주입 스킬: skill_index.keywords 와 토큰 교집합
       len(교집합) >= 2 → helpful_count++, last_helpful_at 갱신
       그 외              → noop_count++
  → skill_injection.correlated=1 마킹 (중복 집계 방지)
  → commit, exit 0
```

`skill_index`/`skill_injection` 스키마 불변. `hermes-dream.py`가 소비하는 helpful/noop 컬럼 의미도 불변
(값이 살아날 뿐).

## 6. 테스트 (`tests/hermes-pipeline-test.sh`)

HOME 격리 + 가짜 transcript(도구 tool_use 블록) 패턴으로 상관 섹션을 추가한다:

- 조회형 스킬(키워드 ≥2, 예: `token,인증,login`) 주입 → Bash `command`에 그 중 2개 등장하는 transcript
  → 상관 실행 → 해당 스킬 `helpful_count=1` (G1·G2: 편집 없이도 인정)
- 같은 스킬, Bash에 키워드 **1개만** 등장 → `noop_count++`, helpful 불변 (G2 가드)
- 키워드 1개짜리 파편 스킬 → 활동 겹침이 있어도 `helpful_count=0` (G3)
- 편집 경로 토큰과 키워드 2개 겹침 → `helpful_count=1` (G4 회귀 방어)
- 존재하지 않는 transcript/DB → 예외 없이 exit 0 (G5)

`run-all.sh`의 `py_compile` 글롭에 이미 포함되므로 정적 검사는 자동.

## 7. 위험 · 한계

- **가시적 효과는 C1에 의존**: helpful이 실제로 쌓이려면 주입이 자주 일어나야 하는데, 주입 빈도는 C1의
  몫이다. C2 단독으로는 "주입이 일어났을 때 조회형도 인정된다"까지만 보장한다(테스트로 검증). 이는 의도된
  범위 분할이며 감사 결론과 일치한다.
- **≥2 가드의 잔여 구멍**: 일반적 키워드 2개(예: `test`+`api`)가 함께 걸리는 경우는 여전히 거짓양성일 수
  있다. 완전 해소는 C3(파편·일반 키워드 식별)의 몫으로 넘긴다. 본 설계는 단일 우연 겹침만 막는다.
- 되돌림 가능성: 모든 판정은 카운터 증가일 뿐이고 파괴적 작업이 아니므로, 오탐이 있어도 드리밍 제안
  단계에서 사람이 거른다.
