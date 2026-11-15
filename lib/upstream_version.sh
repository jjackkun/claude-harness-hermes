#!/usr/bin/env bash
# lib/upstream_version.sh
# Responsibility: 공장 장부가 버전 위치를 정한 에셋에 대해 "소우주 사본이 공장보다 새 버전인가" 만 판정한다.
# 계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G8
#
# 전파가 소우주에서 먼저 올린 새 버전을 공장의 옛 버전으로 덮어 내리는 일을 막는 데 쓴다.
# 버전을 못 읽으면(장부에 version_from 없음 · 파일 없음 · 숫자 마디가 아님) "모름" 이고 rc 1 — 지금 동작 그대로.
#
# 공개 함수 1개: upstream_project_is_newer

# upstream_project_is_newer <kind> <name> <project_copy> <factory_copy>
# rc 0 = 소우주 사본이 공장보다 높은 버전. 그 밖(같음·낮음·모름)은 rc 1.
upstream_project_is_newer() {
  local kind="$1" name="$2" ours="$3" theirs="$4"
  local ledger="${ASSETS_DIR:-}/upstream.json"
  [[ -f "$ledger" ]] || return 1
  python3 - "$ledger" "$kind" "${name%.md}" "$ours" "$theirs" <<'PY'
import json, os, re, sys
ledger, kind, name, ours, theirs = sys.argv[1:]
try:
    items = json.load(open(ledger, encoding='utf-8'))['items']
except (OSError, ValueError, KeyError):
    sys.exit(1)
item = next((i for i in items if i['kind'] == kind and i['name'] == name), None)
vf = (item or {}).get('version_from')
if not vf:
    sys.exit(1)

def version(root):
    path = os.path.join(root, vf['file']) if os.path.isdir(root) else root
    try:
        text = open(path, encoding='utf-8').read(65536)
    except OSError:
        return None
    m = re.search(rf"^{re.escape(vf['frontmatter'])}:\s*['\"]?(\d+(?:\.\d+)*)['\"]?\s*$", text, re.M)
    return tuple(int(x) for x in m.group(1).split('.')) if m else None

a, b = version(ours), version(theirs)
sys.exit(0 if a is not None and b is not None and a > b else 1)
PY
}
