---
name: harness-boundary-check
description: 실행 모드(once/scheduled/realtime) 간 경계 위반과 LLM SDK 직접 호출을 감지한다. Use when writing or reviewing code that touches execution modules, LLM calls, or import statements across mode directories.
---

# Harness Boundary Check

## R1: 실행 모드 격리 검사

### 금지 패턴

`once/`, `scheduled/`, `realtime/` 디렉터리는 서로 import 금지.
공통 코드는 반드시 `shared/` 에 위치해야 한다.

```python
# BAD — once 에서 scheduled import
from app.execution.scheduled.runner import run_schedule  # ❌

# GOOD — shared 경유
from app.execution.shared.execution_repo import create_running  # ✓
```

### 검사 방법 (AST 기반)

```bash
# Python: once → scheduled/realtime cross-import 검사
python3 - <<'PY'
import ast, sys
from pathlib import Path

modes = ["once", "scheduled", "realtime"]
violations = []

for mode in modes:
    others = [m for m in modes if m != mode]
    for f in Path(f"backend/app/execution/{mode}").rglob("*.py"):
        tree = ast.parse(f.read_text())
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                src = getattr(node, "module", "") or ""
                for other in others:
                    if f"execution.{other}" in src:
                        violations.append(f"{f}: imports {src}")

if violations:
    print("❌ R1 위반:")
    for v in violations: print(f"  {v}")
    sys.exit(1)
else:
    print("✓ R1 경계 clean")
PY
```

```bash
# TypeScript/Svelte: 프론트엔드 경계 검사
npx eslint --rulesdir .eslint-rules src/lib/features/kanban/ 2>&1 | grep "boundary"
```

### 발견 시 행동 규칙

1. **즉시 중단** — 현재 작업을 멈춘다
2. **보고** — "R1 경계 위반 발견: [파일]:[라인]" 을 사용자에게 알린다
3. **수정 제안** — 위반 import를 `shared/` 로 이동하는 방법을 제시한다
4. **우회 금지** — `eslint-disable`, `# noqa`, `--no-verify` 로 숨기지 않는다

---

## R3: LLM SDK 직접 호출 금지 검사

### 금지 패턴

```python
# BAD
import anthropic                          # ❌
from anthropic import Anthropic           # ❌
client = anthropic.Anthropic()            # ❌

# GOOD
from app.llm.subscription.client import invoke  # ✓
```

### 검사 방법 (3중 검증)

```bash
# 1) AST import 스캔
python3 -c "
import ast, pathlib, sys
hits = []
for f in pathlib.Path('backend').rglob('*.py'):
    try:
        tree = ast.parse(f.read_text())
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                names = [a.name for a in node.names]
                mod = getattr(node, 'module', '') or ''
                if 'anthropic' in mod or any('anthropic' in n for n in names):
                    hits.append(str(f))
    except: pass
if hits:
    print('❌ anthropic SDK import 발견:', hits); sys.exit(1)
else:
    print('✓ SDK import 없음')
"

# 2) requirements.txt 검사
grep -i "^anthropic" backend/requirements.txt && echo "❌ requirements에 SDK 존재" || echo "✓ requirements clean"

# 3) find_spec 런타임 검사
python3 -c "import importlib.util; s=importlib.util.find_spec('anthropic'); print('❌ SDK 설치됨' if s else '✓ SDK 미설치')"
```

### 올바른 LLM 호출 패턴

```python
from app.llm.subscription.client import invoke
from app.llm.subscription.models import LLMRequest

resp = await invoke(LLMRequest(prompt="질문"))
print(resp.text)
```

---

## 빠른 전체 검사 명령

```bash
# 프로젝트 루트에서 실행
cd backend && python -m pytest tests/test_r1_boundary.py tests/test_llm_path.py -v
```

두 테스트가 모두 green이면 R1·R3 경계 clean.
