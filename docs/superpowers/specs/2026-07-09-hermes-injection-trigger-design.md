# 헤르메스 주입 트리거 확장 설계 (C1)

> 작성일: 2026-07-09
> 목적: 스킬 주입이 "사용자 프롬프트 텍스트"에만 반응하는 구조를 고쳐, 에이전트가 **작업 도중**
> 필요로 하는 스킬이 전달되게 한다.
> 근거 감사: `docs/audits/2026-07-08-hermes-skill-utilization-gap.md` (C1)
> 선행 작업: C2 효용 판정 신호 복구 (`2026-07-08-hermes-correlate-signal-design.md`, 머지 완료)

## 1. 동기 (Why)

감사 실측: `skill_index` 292개, **주입 원장 `skill_injection` 총 3행**, `helpful_count` 합계 0.

주입은 `claude-userpromptsubmit-reminders.sh` → `hermes-search.py --query "$prompt"` 단 한 곳에서만
일어난다. 즉 **사용자가 입력한 문장에 스킬 키워드가 들어 있을 때만** 스킬이 전달된다.

그러나 스킬의 필요성은 사용자가 말하는 시점이 아니라 **에이전트가 작업 중 벽에 부딪히는 시점**에
발생한다. UserPromptSubmit 1회 주입으로는 그 시점을 관측할 수 없다. 원장이 3행뿐인 것은 버그가
아니라 **트리거 위치의 구조적 한계**다.

C2로 효용 판정 로직은 고쳤으나, 판정할 주입 자체가 거의 발생하지 않아 신호가 쌓이지 않는다.
본 설계는 그 주입을 발생시켜 **C2가 신호를 쌓고, 그 신호가 C3(파편 정리)와 승격의 근거가 되는**
순서를 성립시킨다.

## 2. 목표 (What — 검증 가능)

- [ ] **G1 도중 주입 경로 신설** — Bash 도구의 PostToolUse 에서 터미널 실패 신호를 감지하면 관련 스킬을
  검색해 에이전트 컨텍스트에 주입한다. 검증: 신호가 든 가짜 훅 페이로드로 훅 실행 시 stdout 에 스킬
  스니펫이 나온다.
- [ ] **G2 신호 없으면 무동작** — 터미널 실패 신호가 없는 도구 출력에는 아무것도 출력하지 않고 python 도
  기동하지 않는다. 검증: 정상 출력 페이로드 → stdout 공백, exit 0.
- [ ] **G3 `claude -p` 폴백 차단** — assist 경로는 FTS 미스 시 조용히 종료한다. 검증: `--no-fallback` 지정
  시 `claude` 실행 파일이 PATH 에 있어도 호출되지 않는다(모킹으로 확인).
- [ ] **G4 중복 주입 차단** — 같은 세션에서 이미 주입된 스킬은 다시 주입하지 않는다. 검증: 동일 신호를 두 번
  넣으면 두 번째는 stdout 공백, 원장 행 증가 없음.
- [ ] **G5 세션 상한** — assist 주입은 세션당 최대 3건. 검증: 서로 다른 스킬을 유발하는 신호를 4회 넣으면
  4번째는 주입되지 않는다.
- [ ] **G6 출처 구분·측정 가능** — 원장에 `source` 컬럼을 두어 `prompt` / `assist` 를 구분한다. 기존 DB 는
  가산 마이그레이션으로 승격한다. 검증: 기존 스키마 DB 에 `hermes-init.py` 재실행 → 컬럼 추가, 기존 행은
  `prompt`.
- [ ] **G7 비차단** — 훅은 어떤 입력에도 exit 0. 검증: 깨진 JSON·DB 부재·스크립트 부재에도 exit 0.

## 3. 비목표 (Out of Scope)

- **질의 확장(직전 대화·에이전트 의도 텍스트를 `--query` 에 합치기)** — 기각. `search_db` 는
  `kw in hay` 부분문자열 매칭에 매칭 수 상위 N 을 취한다. 질의 텍스트를 늘리면 키워드가 늘어 **거짓양성이
  함께 증가**한다. 또한 "프롬프트가 짧아 원장이 3행"이라는 증거가 감사에 없다. 근거 없이 노이즈를 사는 거래다.
- **`.hermes/skills/` → `.claude/skills/` 승격** — 이번 사이클 제외. 세 가지 이유:
  (1) 승격된 스킬 description 은 **모든 세션 컨텍스트에 영구 상주**한다 — 저빈도 스킬에 매 세션 토큰을 낸다.
  (2) 무엇을 승격할지 고르려면 효용 신호가 필요한데 현재 0이다(닭-달걀). 본 설계가 그 신호를 생산한 뒤에
  근거 있는 게이트를 세울 수 있다.
  (3) `.claude/skills/` 는 `project-claude.sh` 가 `assets/skills/` 에서 복사·관리하는 디렉토리다. 프로젝트가
  학습한 파일을 섞으면 소유 경계가 무너진다.
- **의도 신호 트리거** (명령어에 `curl`·`login`·`migrate` 등이 보이면 발동) — 기각. 매 Bash 호출마다 발동해
  노이즈 대비 이득이 없다. **실패만** 신호로 삼는다.
- **기존 UserPromptSubmit 경로의 `claude -p` 30초 지연** — 사전 존재 동작. 본 설계 범위 밖이며 건드리지 않는다.
- **C3 파편 정리** — 신호가 쌓인 뒤 별건.

## 4. 아키텍처

### 4.1 근거 — 이미 선언된 원칙

`assets/hooks/claude-settings-hooks.json` 에 기록되어 있다:

> `"_pdf_reference": "PDF 9·11쪽 — 에이전트 컨텍스트에 수정 지침 주입 + 어려움을 신호로 간주"`

새 개념 도입이 아니라, 이미 선언한 원칙을 헤르메스 스킬 전달에 적용하는 것이다. PostToolUse 훅이
stdout 으로 낸 텍스트가 에이전트 컨텍스트에 들어가는 것도 기존 `claude-posttooluse-size-warn.sh` 가
검증된 선례다.

### 4.2 변경 범위

```
assets/hooks/claude-posttooluse-hermes-assist.sh  # 신규 — 신호 게이트 + 검색 호출
scripts/hermes-search.py                          # --no-fallback / --once-per-session / --source
scripts/hermes-init.py                            # skill_injection.source 가산 마이그레이션
presets/workflow/hermes.conf                      # 훅 등록 + 훅 소스 배포
tests/hermes-pipeline-test.sh                     # 시나리오 추가
```

`uninstall.sh` 는 `assets/hooks/` 를 스캔해 제거 대상을 정하므로(`_known_hooks`) 추가 수정 불필요.

### 4.3 터미널 실패 신호

**판정 기준: 에이전트가 접근 방식을 바꿔야만 넘어갈 수 있는 실패인가.** 경고·진행 로그는 제외한다.

**매칭은 대소문자 구분**한다. `-i` 를 쓰면 `FAILED` 가 로그에 상시 등장하는 `failed` 까지 잡아 정밀도가
무너진다. 대소문자 변형이 실재하는 항목만 명시적으로 열거한다.

| 부류 | 정규식(대소문자 구분) | 채택 근거 |
|---|---|---|
| 인증·인가 | `\b401\b`, `\b403\b`, `[Uu]nauthorized`, `[Ff]orbidden` | 해법이 코드가 아니라 지식(토큰 발급 절차)이다 — 스킬이 정확히 담는 종류 |
| 권한 | `[Pp]ermission denied` | 위와 동일 |
| 명령 부재 | `command not found` | 환경 설정 지식 |
| 실행 실패 | `Traceback \(most recent call last\)` | 프로젝트 고유 함정이 결정화되어 있을 여지 |
| 테스트 실패 | `\bFAILED\b`, `AssertionError` | 위와 동일 |

**기각한 패턴:**
- `error:` / `Error` — 빌드 로그에 상시 등장하고 대개 비종결적. 채택 시 훅이 사실상 상시 발동한다.
- `No such file or directory` — 빈도는 높으나 에이전트가 즉시 자기 수정한다. 스킬이 개입할 여지가 없다.

신호 집합은 훅 스크립트의 단일 상수(`_SIGNAL_RE`)로 두고, bash `grep -E` 게이트와 python 정밀 재검사가
**같은 문자열을 공유**한다(환경변수 전달). ERE 와 python `re` 문법이 이 패턴 집합에서 동일하게 해석된다.

### 4.4 상한 (매직넘버 금지 — 유도 근거)

| 상한 | 값 | 유도 |
|---|---|---|
| 이벤트당 주입 스킬 수 | 1 | 한 번의 실패에 한 개의 처방. 다중 주입은 어느 것이 도움됐는지 상관을 흐린다 |
| 세션당 assist 주입 | 3 | UserPromptSubmit 경로가 **턴당** 최대 3개(`--max 3`)를 주입한다. assist 경로 **전체**가 프롬프트 경로의 한 턴 분량을 넘지 못하게 맞춘다. `HERMES_ASSIST_MAX_PER_SESSION` 으로 조정 |
| 동일 스킬 재주입 | 금지 | 같은 실패가 반복되면 같은 스킬이 반복 주입되어 원장이 부풀고 helpful 통계가 왜곡된다 |

질의 길이는 별도 절단하지 않는다 — `search_db` 가 이미 `keywords[:5]` 로 자른다.

### 4.5 훅 동작

```
PostToolUse(Bash)
  → stdin JSON: {session_id, tool_name, tool_input.command, tool_response.{stdout,stderr}}
  → [1단계 게이트] 원문 payload 에 grep -E _SIGNAL_RE 미매칭 → exit 0 (python 미기동)
  → [2단계 정밀] python 파싱: tool_name==Bash 인가, tool_response 안에서 매칭되는가
       (1단계는 tool_input.command 의 우연 매칭도 통과시키므로 여기서 걸러낸다)
  → 질의 = "<매칭된 줄> <command>"  ← 순서 고정
  → hermes-search.py --db --query --session-id --source assist
                     --max 1 --no-fallback --once-per-session
  → stdout 있으면 그대로 출력 (에이전트 컨텍스트로 들어감)
  → exit 0 (항상)
```

**질의 순서는 필수 제약이다.** `search_db` 는 `keywords[:5]` 로 자른다. 명령어를 앞에 두면
`curl -s https://api.example/orders` 만으로 5칸이 차서 정작 신호 단어(`401`, `Unauthorized`)가 잘려나간다.
매칭된 줄을 먼저 둔다.

**두 단계 게이트가 필요한 이유.** 1단계는 JSON 원문을 통째로 `grep` 하므로 빠르지만
`grep 401 access.log` 같은 명령어 문자열에도 반응한다. 2단계에서 `tool_response` 로 범위를 좁혀 재검사한다.
정상 경로에서는 1단계가 막아 python 이 아예 뜨지 않는다.

세션 상한은 `hermes-search.py` 가 원장을 세어 강제한다(`source='assist'` 행 수 ≥ 상한이면 무동작).
훅 쪽에서 세면 DB 접근이 이중화되므로 검색 스크립트에 일임한다.

### 4.6 `hermes-search.py` 변경 (3개 플래그, 기존 경로 무변경)

| 플래그 | 기본 | 동작 |
|---|---|---|
| `--no-fallback` | off | `haiku_fallback()` 호출 자체를 건너뛴다 |
| `--once-per-session` | off | `skill_injection` 에서 해당 `session_id` 로 이미 주입된 `skill_path` 를 결과에서 제외. **출처 무관** — 프롬프트 경로로 이미 주입된 스킬도 제외한다(같은 세션 컨텍스트에 이미 들어가 있으므로) |
| `--source` | `prompt` | 원장 INSERT 시 기록할 출처. `assist` 지정 시 세션 상한 검사도 함께 적용 |

기본값이 전부 기존 동작이므로 **UserPromptSubmit 경로는 한 줄도 바뀌지 않는다.**

### 4.7 스키마 (가산 마이그레이션)

```sql
ALTER TABLE skill_injection ADD COLUMN source TEXT DEFAULT 'prompt';
```

`hermes-init.py` 의 `ensure_schema` 에서 `PRAGMA table_info` 로 컬럼 부재를 확인한 뒤에만 실행한다.
기존 행은 기본값 `prompt` 를 갖는다. `hermes-correlate.py` 는 `source` 를 읽지 않으므로 무변경.

이 컬럼이 있어야 감사 §8 의 검증 항목("주입 원장 증가 + 읽기형 스킬 helpful 상승")을 **경로별로 실측**할 수
있다. 없으면 C1 의 효과를 측정할 방법이 없다.

## 5. 데이터 흐름

```
사용자 프롬프트 → UserPromptSubmit → hermes-search.py (source=prompt, max 3)
                                        └→ skill_injection(source='prompt')

에이전트 Bash 실행 → 터미널 실패 → PostToolUse(Bash) → 신호 게이트 통과
                                        → hermes-search.py (source=assist, max 1,
                                           no-fallback, once-per-session)
                                        └→ skill_injection(source='assist')
                                        └→ stdout → 에이전트 컨텍스트

세션 종료 → Stop → hermes-correlate.py
                     → 두 경로의 주입 행을 동일하게 판정 (도구 활동 겹침 ≥2, C2)
                     → helpful_count / noop_count 갱신
```

## 6. 오류 처리

- 훅은 **항상 exit 0**. 깨진 stdin JSON, DB 부재, 스크립트 부재, python3 부재 모두 조용히 통과한다.
- `hermes-search.py` 의 진단 로그는 stderr 전용(기존 `_log` 규약). PostToolUse stdout 은 컨텍스트로
  들어가므로 **오염 금지**.
- `HERMES_DISABLED=1` 이면 훅은 즉시 종료한다 — `hermes-search.py` 가 내부적으로 `claude -p` 를 띄울 때
  설정하는 변수로, 재귀 발동을 막는다.

## 7. 테스트 (`tests/hermes-pipeline-test.sh`)

HOME 격리 + 가짜 훅 페이로드(JSON) 패턴으로 assist 섹션을 추가한다.

1. 신호 있는 페이로드(`401 Unauthorized`) → 관련 스킬 스니펫이 stdout 에 나오고 원장에 `source='assist'` 1행 (G1·G6)
2. 정상 출력 페이로드 → stdout 공백, 원장 불변 (G2)
3. `--no-fallback` 지정 시, PATH 에 모킹된 `claude` 를 두어도 호출 흔적이 없음 (G3)
4. 동일 신호 2회 → 두 번째는 stdout 공백, 원장 1행 유지 (G4)
5. 서로 다른 스킬을 유발하는 신호 4회 → 원장 `assist` 행 3개에서 멈춤 (G5)
6. 깨진 JSON / DB 부재 → exit 0 (G7)
7. 구 스키마 DB 에 `hermes-init.py` 재실행 → `source` 컬럼 추가, 기존 행 `prompt` (G6)

## 8. 위험 · 한계

- **반응형이지 예방형이 아니다.** assist 는 실패가 *일어난 뒤* 발동한다. 실패 전에 스킬을 꺼내 쓰려면
  에이전트가 스스로 당길 수 있어야 하고(`.claude/skills/` 승격), 그건 본 설계의 비목표다. 다만 401 을 맞은
  직후 토큰 발급 절차가 주입되는 것만으로도 사용자가 매번 알려줘야 하는 상황은 해소된다.
- **거짓양성 잔존.** `FAILED`·`Traceback` 은 스킬과 무관한 실패에서도 나온다. 이때 무관한 스킬이 1개
  주입될 수 있다. 피해 상한은 이벤트당 1개·세션당 3개이며, C2 의 겹침 ≥2 판정이 무관 주입을 `noop` 으로
  기록해 오히려 강등 근거가 된다 — 오탐이 신호를 오염시키지 않고 신호가 된다.
- **효과 측정에 시간이 걸린다.** helpful 이 쌓이려면 실제 세션이 여러 번 돌아야 한다. 즉시 검증 가능한 것은
  "원장 `assist` 행이 증가한다"까지다.
