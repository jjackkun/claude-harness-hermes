#!/usr/bin/env bash
# 원본 확인 시작 훅 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G5
#
#   - startup/resume 에서만 돈다. HERMES_DISABLED·HERMES_UPSTREAM_CHECK=0 이면 조용하다
#   - 뒤처진 항목이 있으면 JSON 한 줄을 내고, 같은 날 두 번째 세션에서는 내지 않는다
#   - 확인은 뒤에서 돌아 상태 파일을 쓴다
#   - 장부가 다른 두 프로젝트를 동시에 열어도 같은 원본은 한 번만 묻는다
#   - 장부가 없거나 ~/.hermes 를 못 쓰면 조용히 끝난다
#
# HOME 을 바꾸고 네트워크 대신 UPSTREAM_FIXTURE_DIR 를 쓴다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-upstream.sh"
TMP=$(mktemp -d); export HOME="$TMP/home"; mkdir -p "$HOME"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
unset HERMES_DISABLED HERMES_UPSTREAM_CHECK

export UPSTREAM_FIXTURE_DIR="$TMP/fix"; mkdir -p "$UPSTREAM_FIXTURE_DIR"
export UPSTREAM_FETCH_LOG="$TMP/fetch.log"; : > "$UPSTREAM_FETCH_LOG"
OLD=$(printf 'a%.0s' {1..40}); NEW=$(printf 'b%.0s' {1..40})

mkproj() {  # <dir> <repo> <name>
  mkdir -p "$1/.claude" "$1/scripts" "$1/.hermes"
  cp "$REPO_ROOT/scripts/upstream-check.py" "$1/scripts/"
  python3 - "$1/.claude/.upstream.json" "$2" "$3" <<'PY'
import json, sys
f, repo, name = sys.argv[1:]
json.dump({'version': 1, 'items': [{'name': name, 'kind': 'skills', 'path': f'assets/skills/{name}', 'mode': 'vendored',
          'sources': [{'repo': repo, 'path': f'skills/{name}', 'sha': 'a' * 40}], 'tests': []}]}, open(f, 'w'))
PY
}
tree() {  # <repo> <name> <sha>
  python3 -c "import json,sys; json.dump({'tree':[{'path':'skills/'+sys.argv[2],'sha':sys.argv[3]}],'truncated':False}, open(sys.argv[4],'w'))" \
    "$1" "$2" "$3" "$UPSTREAM_FIXTURE_DIR/${1//\//__}.json"
}
hook() {  # <project> <source>
  printf '{"source":"%s"}' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK"
}
wait_state() {  # 뒤에서 도는 확인이 상태를 쓸 때까지 (최대 10초)
  for _ in $(seq 1 50); do
    [[ -f "$HOME/.hermes/upstream-status.json" ]] && ! [[ -d "$HOME/.hermes/upstream-check.lock" ]] && return 0
    sleep 0.2
  done
  return 1
}

P1="$TMP/p1"; mkproj "$P1" org/one alpha
P2="$TMP/p2"; mkproj "$P2" org/two beta
tree org/one alpha "$NEW"; tree org/two beta "$NEW"

echo "== 끄기·source 거르기 =="
assert "HERMES_DISABLED=1 → 출력 없음" "" "$(printf '{"source":"startup"}' | HERMES_DISABLED=1 CLAUDE_PROJECT_DIR="$P1" bash "$HOOK")"
assert "HERMES_UPSTREAM_CHECK=0 → 출력 없음" "" "$(printf '{"source":"startup"}' | HERMES_UPSTREAM_CHECK=0 CLAUDE_PROJECT_DIR="$P1" bash "$HOOK")"
assert "source=clear → 출력 없음" "" "$(hook "$P1" clear)"
sleep 0.5
assert "꺼진 동안 확인 요청 0회" 0 "$(wc -l < "$UPSTREAM_FETCH_LOG")"

echo "== 첫 세션: 상태가 없으니 알림 없음, 뒤에서 확인 =="
assert "첫 startup 출력 없음" "" "$(hook "$P1" startup)"
wait_state; assert "뒤에서 상태를 썼다" 1 "$([[ -f "$HOME/.hermes/upstream-status.json" ]] && echo 1 || echo 0)"

echo "== 다음 세션: 알림 한 번 =="
out="$(hook "$P1" resume)"
assert "JSON 한 줄 알림" 1 "$([[ "$out" == *systemMessage* && "$out" == *alpha* ]] && echo 1 || echo 0)"
assert "출력은 한 줄" 1 "$(printf '%s\n' "$out" | grep -c .)"
assert "같은 날 다음 세션은 조용" "" "$(hook "$P1" startup)"

echo "== 장부가 다른 두 프로젝트를 동시에 =="
rm -rf "$HOME/.hermes"; : > "$UPSTREAM_FETCH_LOG"
UPSTREAM_FIXTURE_DELAY=1 hook "$P1" startup >/dev/null &
UPSTREAM_FIXTURE_DELAY=1 hook "$P2" startup >/dev/null &
UPSTREAM_FIXTURE_DELAY=1 hook "$P1" startup >/dev/null &
wait
for _ in $(seq 1 60); do [[ $(sort -u "$UPSTREAM_FETCH_LOG" | wc -l) -ge 2 ]] && ! [[ -d "$HOME/.hermes/upstream-check.lock" ]] && break; sleep 0.2; done
sleep 0.5
assert "org/one 1회" 1 "$(grep -c '^org/one$' "$UPSTREAM_FETCH_LOG")"
assert "org/two 1회" 1 "$(grep -c '^org/two$' "$UPSTREAM_FETCH_LOG")"

echo "== 장부 없음·~/.hermes 쓰기 불가 =="
P3="$TMP/p3"; mkdir -p "$P3/.hermes"
assert "장부 없음 → 출력 없음" "" "$(hook "$P3" startup)"
assert "장부 없음 → rc 0" 0 "$(hook "$P3" startup >/dev/null; echo $?)"
RO="$TMP/ro"; mkdir -p "$RO"; chmod 555 "$RO"
assert "~/.hermes 못 만듦 → 출력 없음" "" "$(printf '{"source":"startup"}' | HOME="$RO" CLAUDE_PROJECT_DIR="$P1" bash "$HOOK")"
assert "~/.hermes 못 만듦 → rc 0" 0 "$(printf '{"source":"startup"}' | HOME="$RO" CLAUDE_PROJECT_DIR="$P1" bash "$HOOK" >/dev/null; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
