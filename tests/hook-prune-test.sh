#!/usr/bin/env bash
# hook 소유권 정리 테스트 — preset 에서 빠진 hook 이 실제로 회수되는지 검증.
#
# 왜 이 테스트가 필요한가:
#   2026-08-04 이전 generate_settings_json.py 의 hook 병합은 순수 additive 였다.
#   "preset 에서 빠진 hook"과 "사용자가 직접 등록한 hook"을 구분할 수단이 없어
#   둘 다 보존됐고, 그 결과 한번 등록된 hook 은 preset 을 제거해도 영구히 남았다
#   (serena 가드가 프로젝트마다 되살아난 원인). 소유권 기반 회수 로직의 회귀 방지.
#
# 실행: bash tests/hook-prune-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

HARNESS_HOOK="claude-pretooluse-serena-guard.sh"
HARNESS_CMD="\${CLAUDE_PROJECT_DIR}/scripts/hooks/$HARNESS_HOOK"
USER_CMD="\${CLAUDE_PROJECT_DIR}/scripts/custom/my-own-hook.sh"

# _run_generator <preset_pre_tool_use_entry|""> <output_json>
# DS_TMPDIR 프로토콜로 generate_settings_json.py 를 직접 구동한다.
_run_generator() {
  local preset_entry="$1" out="$2"
  local d; d=$(mktemp -d)
  : > "$d/harness_hook_inventory"
  printf '%s\n' "$HARNESS_HOOK" > "$d/harness_hook_inventory"
  [[ -n "$preset_entry" ]] && printf '%s\n' "$preset_entry" > "$d/pre_tool_use"
  DS_TMPDIR="$d" python3 "$REPO_ROOT/lib/generate_settings_json.py" "$out"
  local rc=$?
  rm -rf "$d"
  return $rc
}

# 기존 settings.json — 하네스 훅 1개 + 사용자 훅 1개가 같은 matcher 그룹에 공존
_seed_settings() {
  cat > "$1" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$HARNESS_CMD" },
          { "type": "command", "command": "$USER_CMD" }
        ]
      }
    ]
  }
}
EOF
}

_has_cmd() {
  python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
cmds=[h.get('command') for g in d.get('hooks',{}).get('PreToolUse',[]) for h in g.get('hooks',[])]
print('yes' if sys.argv[2] in cmds else 'no')
" "$1" "$2"
}

echo "== preset 에서 빠진 하네스 훅 회수 =="
OUT="$TMP/a.json"; _seed_settings "$OUT"
_run_generator "" "$OUT"
assert "하네스 훅은 제거된다"        "no"  "$(_has_cmd "$OUT" "$HARNESS_CMD")"
assert "사용자 훅은 보존된다"        "yes" "$(_has_cmd "$OUT" "$USER_CMD")"

echo "== preset 이 계속 제공하는 훅은 유지 =="
OUT="$TMP/b.json"; _seed_settings "$OUT"
_run_generator "Edit|Write|MultiEdit::$HARNESS_CMD" "$OUT"
assert "하네스 훅이 다시 등록된다"   "yes" "$(_has_cmd "$OUT" "$HARNESS_CMD")"
assert "사용자 훅도 그대로 남는다"   "yes" "$(_has_cmd "$OUT" "$USER_CMD")"

echo "== 그룹 전체가 하네스 소유면 matcher 껍데기까지 제거 =="
OUT="$TMP/c.json"
cat > "$OUT" <<EOF
{ "hooks": { "PreToolUse": [ { "matcher": "Edit", "hooks": [ { "type": "command", "command": "$HARNESS_CMD" } ] } ] } }
EOF
_run_generator "" "$OUT"
assert "빈 hooks 키는 남기지 않는다" "no" "$(python3 -c "
import json,sys; print('yes' if json.load(open(sys.argv[1])).get('hooks') else 'no')" "$OUT")"

echo "== _cleanup_stale_hooks: 프로젝트 잔여 스크립트 회수 =="
export DEV_SETTING_DIR="$REPO_ROOT"
export ASSETS_DIR="$REPO_ROOT/assets"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

PROJ="$TMP/proj"; mkdir -p "$PROJ/scripts/hooks"
touch "$PROJ/scripts/hooks/$HARNESS_HOOK"          # 하네스 소유, preset 에서 빠짐
touch "$PROJ/scripts/hooks/my-own-hook.sh"         # 사용자 소유 — 인벤토리에 없음
HARNESS_HOOK_SOURCES=()
_cleanup_stale_hooks "$PROJ/scripts/hooks" >/dev/null

assert "잔여 하네스 스크립트 삭제" "no"  "$([[ -f "$PROJ/scripts/hooks/$HARNESS_HOOK" ]] && echo yes || echo no)"
assert "사용자 스크립트 보존"      "yes" "$([[ -f "$PROJ/scripts/hooks/my-own-hook.sh" ]] && echo yes || echo no)"

echo "== 은퇴 훅이 인벤토리에 포함되는가 =="
assert "RETIRED_HOOK_SOURCES 반영" "yes" \
  "$(harness_hook_inventory | grep -qxF "$HARNESS_HOOK" && echo yes || echo no)"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
