# 하네스 도메인 룰 예시집

> **⚠️ 이것은 복사할 *정답*이 아니라 복사할 *출발점*이다.**
>
> PDF 11쪽 인용:
> > "리포지토리는 특정 구조에 따라 다르다. LLM이 지름길을 택하거나 규칙을 어기는 방법은
> > 리포지토리마다 다르므로, 일반적인 가정을 하지 않는 것이 가장 좋다."
>
> 즉, 아래 예시들은 rim-kanban 프로젝트의 *특정* 도메인(칸반 실행 모드 3개 격리, 구독 기반
> LLM 호출)을 위한 것이며, 다른 프로젝트에 그대로 복사하면 "내 프로젝트와 상관없는 테스트가
> 강제되는" 상황이 된다. **반드시 자기 도메인에 맞게 고쳐라.**

---

## 무엇이 들어있는가

| 경로 | 패턴 | 원본 출처 |
|---|---|---|
| `python/test_mode_isolation.py` | AST 기반 디렉토리 상호 import 금지 (R1) | rim-kanban `backend/tests/test_r1_boundary.py` |
| `python/test_module_boundaries.py` | R1 다층 방어 — parametrize 패턴 | rim-kanban `backend/tests/test_module_boundaries.py` |
| `python/test_sdk_ban.py` | 특정 패키지 import·설치·가용성 3중 차단 (R3) | rim-kanban `backend/tests/test_llm_path.py` |
| `typescript/eslint-no-restricted-imports.config.js` | ESLint 레벨 동일 경계 강제 | rim-kanban `eslint.config.js` |
| `llm-subscription-template.py` | subprocess + cwd=/tmp + env 화이트리스트 | rim-kanban `backend/app/llm/subscription/client.py` |

## 이 예시들이 공통으로 보여주는 *패턴*

1. **정적 검사 우선** — 런타임에 잡지 말고 AST/린터로 커밋 전에 잡는다. PDF 9쪽 "구현을
   세세하게 관리하지 않고 불변 조건을 강제 적용한다".
2. **다층 방어** — 같은 R1을 pytest(AST) + ESLint(import-regex) 두 곳에서 강제. 한 레이어만
   있으면 에이전트가 우회한다.
3. **에러 메시지에 *수정 지침*을 박는다** — "R1 위반: once/ 는 scheduled/ 를 import 할 수
   없다. shared/ 를 경유하라." → 에이전트 컨텍스트에 들어갈 때 다음 행동을 바로 유도.
   PDF 9쪽 "오류 메시지를 작성하여 에이전트 컨텍스트에 수정 지침을 주입한다".
4. **봉쇄(격리) > 탐지** — LLM subprocess 예시는 cwd/env 화이트리스트로 *물리적으로*
   오염을 차단. "anthropic SDK 금지"를 코드 리뷰로 지키는 게 아니라 `ANTHROPIC_API_KEY`
   환경변수를 제거해서 설치돼 있어도 API 모드로 폴백 불가능하게 만듦.

## 복사해서 쓰는 순서

1. **먼저 자기 도메인의 R 룰을 `docs/design-docs/core-beliefs.md`에 문장으로 정의하라.**
   "X와 Y는 서로 import 할 수 없다" "패키지 Z는 설치 금지" 같은 *측정 가능한* 형태로.
   룰이 없으면 예시를 복사해도 무엇을 강제하는 건지 모른다.
2. **가장 가까운 예시를 고른다** — 위 표에서 패턴이 비슷한 것 하나만.
3. **고정된 이름을 *모두* 치환한다** — `execution`, `once/scheduled/realtime`, `anthropic`,
   `app.execution.shared` 같은 식별자는 rim-kanban 전용이다. 자기 프로젝트의 디렉토리/
   패키지 이름으로 바꿔라. grep 으로 찾아서 전부 바꾸는 걸 권한다.
4. **가짜 위반을 일부러 만들어 테스트가 *실제로* 차단하는지 확인한다.**
   통과만 보는 검증은 `tests/harness-hooks-smoke.sh` 사례처럼 silent-skip을 못 잡는다.
5. **통과를 확인한 뒤 원래 코드로 되돌리고 커밋.**

## 무엇을 복사하지 말아야 하는가

- **파일 경로** (`backend/app/execution/`) — 모든 프로젝트가 이런 구조를 쓰지 않는다.
- **R 번호** (`R1`, `R3`) — 자기 프로젝트의 `core-beliefs.md` 에 붙인 번호와 일치시켜라.
- **에러 메시지의 도메인 언급** ("kanban/once/...") — 자기 도메인으로 바꿔라.
- **테스트가 강제하는 금지 대상** (`anthropic`) — 자기 프로젝트에 실제로 금지할 것이
  없다면 그 테스트 자체를 복사하지 마라. "남들이 쓰니까" 복사하는 건 PDF 11쪽 위반.

## 원칙 재확인

> 강제는 도메인 지식이다. ai-dev-setting 의 `harness` preset 은 *강제 장치*(hook, lint,
> 테스트 러너)만 제공하고 *무엇을 강제할지*는 각 프로젝트가 결정한다. 이 예시는 그
> "무엇을"을 만들 때 참고하는 샘플 갤러리일 뿐이다.
