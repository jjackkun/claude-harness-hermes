# 변이 테스트 첫 전수 실행

> 작성일: 2026-08-25
> 목적: 테스트가 실제로 회귀를 잡는지 실측하고, 테스트를 추가할 지점 목록을 만든다.

## 개요

`scripts/mutation-probe.py` 로 이름 규칙이 매핑되는 8개 모듈에 변이 193개를 주입했다.
**193개 전부에서 원본이 복원됐다** (`git diff --exit-code` 로 매 모듈 확인).

## 결과

| 모듈 | 변이 | 잡힘 | 생존 | 변이 점수 |
|---|---|---|---|---|
| `scripts/hermes_loop.py` | 22 | 13 | 9 | **59.1%** |
| `scripts/hermes-dream.py` | 36 | 24 | 12 | **66.7%** |
| `scripts/hermes_redact.py` | 3 | 2 | 1 | **66.7%** |
| `scripts/hermes-loop.py` | 35 | 25 | 10 | **71.4%** |
| `assets/hooks/coverage_probe.py` | 29 | 22 | 7 | **75.9%** |
| `scripts/hermes-lifecycle.py` | 41 | 33 | 8 | **80.5%** |
| `scripts/hermes_mesh_gate.py` | 7 | 6 | 1 | **85.7%** |
| `assets/hooks/plan_state.py` | 20 | 18 | 2 | **90.0%** |
| **합계** | **193** | **143** | **50** | **74.1%** |

## 파일럿 결론을 정정한다

파일럿(2026-08-24)은 13개 변이로 **92%** 를 얻고
*"기존 테스트의 품질은 예상보다 높다"* 고 적었다. 표본이 2개 모듈뿐이었다.
193개로 넓히니 **74.1%** 다 — 변이 4개 중 1개가 살아남는다.

**작은 표본에서 나온 낙관은 결론이 아니라 가설이었다.**

## 커버리지와 겹치지 않는다

`R-cov` 실측에서 이 8개 모듈은 전부 **70% 이상** 커버리지였고, 여러 개가 90% 를 넘었다.
그런데도 변이의 26% 가 살아남는다. 두 지표가 다른 것을 잰다는 뜻이다 —
커버리지는 *줄이 실행됐는가*, 변이 점수는 *그 줄이 틀렸을 때 누가 우는가* 를 본다.

## 생존 변이가 드러낸 실제 공백 세 가지

### 1. 죽은 코드 (`coverage_probe.py:112` — 조치 완료)

`_in_scope()` 는 정의만 있고 호출처가 없었다. 어떤 변이를 넣어도 테스트가 통과한다.
**변이 테스트가 도입 당일 작성된 코드에서 이것을 잡았다.** 제거 후 75.9% → **81.5%**.

### 2. 문서가 약속한 동작에 테스트가 없다 (`hermes_redact.py:121`)

```python
if not text or not isinstance(text, str):
    return text
```

docstring 은 *"str 이 아니면(예: None) 입력을 그대로 돌려준다"* 고 약속한다.
`or` → `and` 로 바꾸면 `""`·`5`·`["a"]` 에서 조기 반환이 사라지는데 테스트는 통과한다.
**테스트가 `None` 하나만 보기 때문이다** — 하필 변이와 결과가 같아지는 유일한 값이다.
동등 변이가 아니라 진짜 공백이다.

### 3. 프롬프트 본문이 통째로 사라져도 통과한다 (`hermes_mesh_gate.py:80`)

```python
prompt = _PROMPT_TMPL.format(body=(text or "")[:_MAX_PROMPT_BODY])
```

파일럿이 찾은 것과 같은 지점이며 이번 실행이 재현했다.
`hermes-mesh-gate-test.sh` 가 프롬프트 **본문의 내용**을 단언하지 않는다.

## 생존 변이 전체 목록

- `scripts/hermes_loop.py:182:23  == → !=`
- `scripts/hermes_loop.py:184:25  == → !=`
- `scripts/hermes_loop.py:187:50  == → !=`
- `scripts/hermes_loop.py:188:25  == → !=`
- `scripts/hermes_loop.py:190:36  != → ==`
- `scripts/hermes_loop.py:192:25  == → !=`
- `scripts/hermes_loop.py:192:34  and → or`
- `scripts/hermes_loop.py:327:15  or → and`
- `scripts/hermes_loop.py:343:54  == → !=`
- `scripts/hermes-dream.py:81:25  and → or`
- `scripts/hermes-dream.py:185:15  or → and`
- `scripts/hermes-dream.py:190:13  and → or`
- `scripts/hermes-dream.py:268:43  or → and`
- `scripts/hermes-dream.py:313:20  not → (삭제)`
- `scripts/hermes-dream.py:322:38  == → !=`
- `scripts/hermes-dream.py:339:7  not → (삭제)`
- `scripts/hermes-dream.py:380:43  or → and`
- `scripts/hermes-dream.py:381:47  and → or`
- `scripts/hermes-dream.py:384:27  not → (삭제)`
- `scripts/hermes-dream.py:419:37  or → and`
- `scripts/hermes-dream.py:442:7  not → (삭제)`
- `scripts/hermes_redact.py:121:16  or → and`
- `scripts/hermes-loop.py:95:26  or → and`
- `scripts/hermes-loop.py:135:29  == → !=`
- `scripts/hermes-loop.py:143:12  or → and`
- `scripts/hermes-loop.py:144:12  or → and`
- `scripts/hermes-loop.py:144:23  == → !=`
- `scripts/hermes-loop.py:144:33  and → or`
- `scripts/hermes-loop.py:144:49  == → !=`
- `scripts/hermes-loop.py:169:61  not → (삭제)`
- `scripts/hermes-loop.py:170:25  == → !=`
- `scripts/hermes-loop.py:211:11  not → (삭제)`
- `assets/hooks/coverage_probe.py:112:11  not → (삭제)`
- `assets/hooks/coverage_probe.py:112:36  and → or`
- `assets/hooks/coverage_probe.py:125:46  not → (삭제)`
- `assets/hooks/coverage_probe.py:187:55  and → or`
- `assets/hooks/coverage_probe.py:188:35  or → and`
- `assets/hooks/coverage_probe.py:195:36  or → and`
- `assets/hooks/coverage_probe.py:214:35  or → and`
- `scripts/hermes-lifecycle.py:68:32  or → and`
- `scripts/hermes-lifecycle.py:155:21  or → and`
- `scripts/hermes-lifecycle.py:228:7  not → (삭제)`
- `scripts/hermes-lifecycle.py:249:31  or → and`
- `scripts/hermes-lifecycle.py:287:36  or → and`
- `scripts/hermes-lifecycle.py:299:47  or → and`
- `scripts/hermes-lifecycle.py:353:31  or → and`
- `scripts/hermes-lifecycle.py:354:7  not → (삭제)`
- `scripts/hermes_mesh_gate.py:80:44  or → and`
- `assets/hooks/plan_state.py:160:19  and → or`
- `assets/hooks/plan_state.py:160:36  and → or`

### 4. 도구가 자기 테스트의 공백도 잡았다 (dogfood)

`mutation-probe.py` 자신에 돌리자 **92.3%** 가 나왔다. 생존 변이는 `not` 삭제 시
뒤 공백을 지우는 분기였고 — 테스트 픽스처에 `not` 이 없어 그 경로가 한 번도 안 돌았다.
픽스처에 `not` 을 넣었더니 **여전히 생존했다.**

확인해 보니 **진짜 동등 변이**였다. `if not x` 에서 `not` 만 지우면 `if  x` 로 공백이
둘이 되는데 파이썬 의미는 같다. 즉 그 분기는 **어떤 테스트로도 검증할 수 없는 코드**였다.
분기를 없애자 코드가 단순해지고 변이 점수는 **100%** 가 됐다.

동등 변이는 "테스트를 더 쓰라" 가 아니라 **"그 분기가 필요 없다"** 는 신호일 수 있다.

## 동등 변이 — 관측된 것과 관측하지 않은 것

스펙 미해결 1번(동등 변이 발생률)에 대해 말할 수 있는 것은 제한적이다.
**개별 확인한 것은 3건뿐이다** — `hermes_redact.py:121`(동등 아님, 진짜 공백),
`hermes_mesh_gate.py:80`(동등 아님), `mutation-probe.py:89`(동등, 조치 완료).
나머지 47건의 생존 변이는 하나씩 검토하지 않았으므로 **전체 동등 변이 비율은 모른다.**
표본에서 비율을 추정하지 않는다 — 3건은 비율을 말할 표본이 아니다.

## 한계 — 자동 매핑이 8/37 이다

이름 규칙(`scripts/hermes_loop.py` → `tests/hermes-loop-test.sh`)으로 매핑되는 모듈은
운영 파이썬 37개 중 **8개(22%)** 다. 나머지 29개는 `--test` 로 직접 지정해야 한다.

이름이 안 맞는 것이 아니라 **모듈과 테스트가 1:1 이 아니기 때문이다** —
한 테스트가 여러 모듈을 지나가고, 한 모듈이 여러 테스트에 걸린다.
테스트별 커버리지를 따로 수집하면 자동으로 알아낼 수 있으나
(`coverage_probe.py` 를 테스트마다 돌리면 된다) 비용이 커서 별도 판단이 필요하다.

## 임계를 정하지 않는다

`R-mut` 은 게이트가 아니라 진단이다. 전체 실행이 수십 분이라 커밋 경로에 맞지 않고,
분포(59.1~90.0%)에 자를 만한 절벽이 없다. 생존 변이 목록을 **테스트를 추가할 지점**
목록으로 쓰는 것이 이 도구의 용도다.
