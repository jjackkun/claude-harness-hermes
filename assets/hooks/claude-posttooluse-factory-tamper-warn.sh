#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 편집한 파일이 공장 설치물(.claude/.factory-manifest.json 에
# 등재)이고 내용 해시가 기록과 달라졌으면 경고한다.
#
# 설계: docs/hermes-universe/design/world/copy-install.md §4 #5.
# 경고이지 차단이 아니다 — 막으면 우회(--no-verify 류)를 유도한다(계획 §6). 다음 update-all 이
# 이 파일을 덮어쓰므로, 고친 내용은 소우주 확장(.hermes/skills/)으로 옮기고 우주에 제안한다.
#
# 출력 형식: [factory-tamper WARN] <kind>/<name> …  (테스트가 이 접두어를 고정)

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
MANIFEST="$PROJECT_DIR/.claude/.factory-manifest.json"
[[ -f "$MANIFEST" ]] || exit 0

FILE_PATH=$(python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)
[[ -n "$FILE_PATH" ]] || exit 0
# 심링크·상대경로 입력을 정규화해 문자열 비교가 어긋나지 않게 한다 (리뷰 LOW)
FILE_PATH="$(readlink -f -- "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"
PROJECT_DIR="$(readlink -f -- "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")"

case "$FILE_PATH" in
  "$PROJECT_DIR"/.claude/skills/*|"$PROJECT_DIR"/.claude/agents/*|"$PROJECT_DIR"/.claude/rules/*) ;;
  *) exit 0 ;;
esac

# .claude/<kind>/<name>[/…] → kind, name(에이전트는 .md 제거)
REL="${FILE_PATH#"$PROJECT_DIR"/.claude/}"
KIND="${REL%%/*}"
NAME="${REL#*/}"; NAME="${NAME%%/*}"
[[ "$KIND" == "agents" ]] && NAME="${NAME%.md}"

INSTALLED="$PROJECT_DIR/.claude/$KIND/$NAME"
[[ "$KIND" == "agents" ]] && INSTALLED="$INSTALLED.md"

# 목록 조회·해시 대조 (lib/factory_manifest.sh 와 같은 규칙: 디렉터리는 파일 정렬 후 합산)
RECORDED=$(M_KIND="$KIND" M_NAME="$NAME" python3 - "$MANIFEST" <<'PYEOF'
import json, os, sys
for i in json.load(open(sys.argv[1], encoding="utf-8")).get("items", []):
    if i.get("kind") == os.environ["M_KIND"] and i.get("name") == os.environ["M_NAME"]:
        print(i.get("sha256", "")); break
PYEOF
)
[[ -n "$RECORDED" ]] || exit 0   # 목록에 없음 → 소우주 자체 자산, 경고 없음

if [[ -d "$INSTALLED" ]]; then
  CURRENT=$( (cd "$INSTALLED" && find . -type f | LC_ALL=C sort | xargs -r sha256sum) | sha256sum | awk '{print $1}')
else
  CURRENT=$(sha256sum "$INSTALLED" 2>/dev/null | awk '{print $1}')
fi
[[ "$CURRENT" != "$RECORDED" ]] || exit 0

cat >&2 <<EOF
[factory-tamper WARN] $KIND/$NAME 은(는) 공장 설치물(우주 공통)입니다. 방금 편집한 내용은 다음 update-all 에서 덮어써집니다.
  → 소우주 확장으로 옮기십시오: .hermes/skills/ 에 같은 이름의 확장 파일(머리말 extends: <skill_id>@<version>)
  → 공통 자체를 고치려면 우주에 제안하십시오 (hermes-propose.py, 사람이 --deliver 로 배달)
  근거: docs/hermes-universe/design/world/copy-install.md §4 #5
EOF
exit 0
