# R-dep — 모듈 의존 계약

> 작성일: 2026-08-24
> 목적: 지금 지켜지고 있는 의존 방향을 **문서가 아니라 검사로** 고정한다.

## 개요

`scripts/` 에 파이썬 파일이 30개 이상 있으나 **이들 사이의 의존 방향을 규정한 스펙 파일이 없다.**
`lib/` ↔ `scripts/` ↔ `assets/hooks/` 경계도 문서로만 존재한다.

영상이 지적한 지점이다 — 의존 규칙을 스펙 파일로 정의하고 에이전트가 위반하지 못하게 막아야 한다.

## 실측 (2026-08-24)

### 측정 방법 정정

첫 측정은 `^(from|import)` 정규식을 썼고 **들여쓴 import 를 전부 놓쳤다.**
`ast` 모듈로 재측정하니 간선 9개가 빠져 있었다 — 전체 28개 중 3분의 1이다.

파이썬의 조건부·지연 import 는 함수 안이나 `try` 블록 안에 들어가므로 들여쓰기가 기본이다.
**의존 계약 검사는 정규식이 아니라 AST 로 구현해야 한다.** 이 스펙의 구현 요건이다.

### 그래프 (AST 기준)

계층은 아래에서 위로, 각 계층은 자기보다 아래만 import 한다.

```text
tier0 (내부 의존 0)  hermes_secret_values  hermes_skills  hermes_reuse  hermes_lifecycle_apply
tier1                hermes_redact                    → tier0
tier2                hermes_loop  hermes_mesh_gate  hermes_save_session_storage   → tier1
tier3                hermes_loop_prompt  hermes_loop_report                        → tier2
                     hermes_save_session_patterns  hermes_save_session_signals     → tier1, tier2
entrypoint           scripts/hermes-*.py                                           → tier0~3
```

**순환 0건, 계층 역전 0건.** 이 부분은 재측정 후에도 유지된다.

### 구조적으로 이미 강제되는 것

CLI 진입점은 파일명에 하이픈이 있어 **파이썬이 import 할 수 없다.**
"라이브러리가 CLI 를 부르는" 방향은 파일명 규칙만으로 이미 불가능하다.
이 관례가 우연이 아니라 계약이었음을 문서화한다.

### 디렉터리 경계 — 위반 1건이 있고, 그것은 의도된 설계다

재측정에서 드러난 간선:

```python
# assets/hooks/check-secrets.py:36
try:
    from hermes_secret_values import load_secret_values
except ImportError:
    load_secret_values = None
```

훅이 `scripts/` 의 모듈을 import 한다. 바로 위에 근거가 적혀 있다:

```text
정답지 모듈은 훅 디렉터리(.git/hooks/) 또는 프로젝트 scripts/ 에 있다.
없으면 형태 규칙만으로 동작한다 — 차단기가 죽는 것보다 낫다.
```

`try/except ImportError` 로 우아하게 강등되는 **선택적 의존**이다.
모듈이 없어도 훅은 동작하므로, 훅의 자립성이라는 원칙을 실제로는 지키고 있다.

**본 스펙의 초안은 이것을 위반으로 판정했다.** 하드 의존과 선택적 의존을 구분하지 않은 탓이다.
설계에 구분을 넣는다.

## 설계

### 도구 — 자체 구현

`import-linter` 는 미설치이며, 설치해도 **이 저장소에는 쓸 수 없다.**
`scripts/` 는 파이썬 패키지가 아니다 — `__init__.py` 가 없고, 대신 10곳 이상에서
`sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))` 로 경로를 조작한다.
`import-linter` 는 패키지 경로 기반 계약을 요구하므로 이 구조에 맞지 않는다.

표준 `ast` 모듈로 import 를 수집하고 계약 파일과 대조한다. 외부 의존이 없다.

### 계약 파일 — `.deprc`

`.harnessrc` 옆에 둔다. 계층은 위 실측 그래프에서 그대로 뽑았다 — **새 규칙을 발명하지 않는다.**

```text
# 아래 tier 는 위 tier 를 import 할 수 없다. 같은 tier 안의 상호 참조는 허용한다.
tier: 0  scripts/hermes_secret_values.py scripts/hermes_skills.py
         scripts/hermes_reuse.py scripts/hermes_lifecycle_apply.py
tier: 1  scripts/hermes_redact.py
tier: 2  scripts/hermes_loop.py scripts/hermes_mesh_gate.py
         scripts/hermes_save_session_storage.py
tier: 3  scripts/hermes_loop_prompt.py scripts/hermes_loop_report.py
         scripts/hermes_save_session_patterns.py scripts/hermes_save_session_signals.py
tier: 4  scripts/hermes-*.py

# 디렉터리 경계 — 훅은 자립해야 한다.
# 설치본에서 scripts/ 가 함께 있다는 보장이 없다.
forbid: assets/hooks/*.py -> scripts/*.py

# 위 forbid 의 예외. try/except ImportError 로 감싸 없어도 동작하는 것만 등록한다.
optional: assets/hooks/check-secrets.py -> hermes_secret_values
```

### 선택적 의존의 취급

`optional:` 에 등록된 간선은 `forbid`·tier 검사에서 제외한다.
다만 등록만으로는 부족하고, **실제로 선택적인지 검사한다**:

| 검사 | 내용 |
|---|---|
| `try` 블록 안의 import 인가 | AST 로 부모 노드 확인 |
| `except ImportError` 핸들러가 있는가 | 핸들러 타입 확인 |
| fallback 이 할당되는가 | 핸들러 본문이 비어 있지 않은가 |

셋을 모두 만족하지 않으면 `optional:` 등록이 있어도 위반으로 판정한다.
**등록이 곧 면제가 되면 `optional:` 줄을 추가하는 것이 우회 경로가 된다.**

### 검사 규칙

| 규칙 | 내용 | 행동 |
|---|---|---|
| `R-dep-1` | 하위 계층이 상위 계층을 import | 차단 |
| `R-dep-2` | 순환 의존 | 차단 |
| `R-dep-3` | `forbid:` 에 명시된 경계 위반 | 차단 |
| `R-dep-4` | 계약 파일에 없는 새 파일 | **경고** — 계층을 정하라고 요구 |

**차단이 성립하는 이유**: 이 규칙들은 이분 판정이다.
`R-iface` 처럼 분포에서 임계를 뽑는 문제가 아니므로 간극 논쟁이 없다.
현재 위반은 1건이며 그것은 `optional:` 로 등록될 의도된 설계다.
등록 후에는 위반 0건이 되므로 도입 즉시 켜도 정상 코드가 막히지 않는다.

`R-dep-4` 만 경고인 이유: 새 파일마다 계약 갱신을 강제하면 마찰이 크고,
계층 판단은 사람이 해야 한다. 경고로 계약 갱신을 유도한다.

### 발화 지점

`pre-commit` 의 신규 단계 `R-dep`. 대상은 스테이징된 `.py`.

**계약 파일 부재는 조용히 통과시킨다** (2026-08-24 구현 시 초안에서 변경).

초안은 `R-test` 사고를 이유로 여기서도 경고하기로 했으나, 두 상황이 다르다.
`R-test` 는 **켜져 있는데** 아무것도 안 막으면서 통과 표시를 냈다.
여기서는 사용자가 계약을 만든 적이 없다 — 고장이 아니라 **미설정**이다.
계약 없는 프로젝트에 매 커밋 경고를 내면 경고 피로로 훅 자체가 꺼진다
(`size-warn` 이 같은 이유로 겹치는 경고를 억제한다).

"죽은 줄 모르는" 위험은 **설치 시점 안내**로 옮긴다 —
`harness_installers.sh` 가 `.deprc` 부재 시 R-dep 이 비활성임을 한 번 알린다.

한편 **모듈(`depcheck.py`) 부재는 경고한다.** 그쪽은 미설정이 아니라 설치 손상이다.

## 검증

| 항목 | 방법 |
|---|---|
| 측정 방식 | 들여쓴 import 를 잡는지 (`check-secrets.py` 의 간선이 검출되는지) |
| 현재 상태 | 저장소 전체 검사 → `optional:` 등록 후 위반 0건 |
| 선택적 의존 | `try/except ImportError` 없이 `optional:` 만 등록 → 위반 판정 |
| `R-dep-1` | `hermes_redact.py` 에 `import hermes_loop` 추가 → 차단 |
| `R-dep-2` | 인위적 순환 생성 → 차단 |
| `R-dep-3` | `assets/hooks/plan_state.py` 에서 `scripts/` import → 차단 |
| `R-dep-4` | 계약에 없는 새 `.py` → 경고, 커밋은 성공 |
| 계약 부재 | `.deprc` 삭제 → 건너뛰되 사유 출력 |

`tests/dep-contract-test.sh` 를 추가한다.

## 미해결

1. **`optional:` 목록의 관리 주체.** 지금은 1건이지만 늘어나면 목록 자체가 계약의 구멍이 된다.
   상한을 둘지, 등록마다 `docs/audits/` 근거를 요구할지 결정이 필요하다.
2. **`sys.path.insert` 를 남길 것인가.** 계약 검사는 정적 분석이므로 경로 조작과 무관하게 동작한다.
   그러나 이 관용구가 10곳 이상 반복되는 것 자체가 구조 문제의 징후다.
   패키지화(`__init__.py` 도입)는 별개 사안으로 분리한다 —
   설치본의 파일 배치와 훅 실행 경로에 영향이 크다.
3. **`lib/*.py` 와 `assets/hooks/*.py` 의 계층.** 이번 계약은 `scripts/` 중심이다.
   `lib/generate_*.py` 3개는 내부 의존이 0이라 계층 판단이 유보돼 있다.
4. **glob 문법.** 위 예시의 `{patterns,signals}` 는 brace expansion 이다.
   계약 파일 파서가 이를 지원할지, 단순 나열로 갈지 구현 시 결정한다.
