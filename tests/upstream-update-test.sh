#!/usr/bin/env bash
# 공장 업데이트 명령 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G7
#
#   - 그대로(vendored): 원본으로 바꾸고, 한국어 설명 앞머리를 다시 붙이고, 뺄 파일은 빼고, 장부 sha 를 올린다
#   - 시험이 실패하면 파일과 장부를 되돌린다
#   - 고쳐 씀(adapted): 파일을 건드리지 않고 바뀐 원본 파일만 보인다. --mark-reviewed 로 장부를 맞춘다
#   - 이미 최신이면 아무것도 바꾸지 않는다 · 장부에 없는 이름은 rc 1
#   - 공장이 없으면 "공장이 있는 컴퓨터에서" 로 끝난다
#
# 가짜 공장(임시 git 저장소)과 UPSTREAM_FIXTURE_DIR 로 돈다. HOME 도 바꾼다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPD="$REPO_ROOT/scripts/upstream-update.py"
TMP=$(mktemp -d); export HOME="$TMP/home"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
export UPSTREAM_FIXTURE_DIR="$TMP/fix"; mkdir -p "$UPSTREAM_FIXTURE_DIR"
OLD=$(printf 'a%.0s' {1..40}); NEW=$(printf 'b%.0s' {1..40}); OLDA=$(printf 'c%.0s' {1..40}); NEWA=$(printf 'd%.0s' {1..40})

F="$TMP/factory"
setup() {
  rm -rf "$F"; mkdir -p "$F/assets/skills/demo" "$F/assets/agents" "$F/tests"
  printf -- '---\nname: demo\ndescription: "데모 한국어 설명. Old upstream text."\n---\nold body\n' > "$F/assets/skills/demo/SKILL.md"
  echo "keep me?" > "$F/assets/skills/demo/old-only.md"
  echo "# helper (ours)" > "$F/assets/agents/helper.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$F/tests/ok-test.sh"
  printf '#!/usr/bin/env bash\ngrep -q "new body" "$(dirname "$0")/../assets/skills/demo/SKILL.md" && exit 1 || exit 0\n' > "$F/tests/rejects-new-test.sh"
  python3 - "$F/assets/upstream.json" "$OLD" "$OLDA" <<'PY'
import json, sys
f, old, olda = sys.argv[1:]
json.dump({'version': 1, 'items': [
  {'name': 'demo', 'kind': 'skills', 'path': 'assets/skills/demo', 'mode': 'vendored',
   'sources': [{'repo': 'org/up', 'path': 'skills/demo', 'sha': old}],
   'local_patch': {'description_prefix': '데모 한국어 설명. '}, 'skip_files': ['big.js'], 'tests': ['tests/ok-test.sh']},
  {'name': 'helper', 'kind': 'agents', 'path': 'assets/agents/helper.md', 'mode': 'adapted',
   'sources': [{'repo': 'org/up', 'path': 'agents/helper.md', 'sha': olda}], 'tests': []}]}, open(f, 'w'), indent=2)
PY
  git -C "$F" init -q
}
upstream() {  # <demo sha> <helper sha>
  python3 - "$UPSTREAM_FIXTURE_DIR/org__up.json" "$1" "$2" "$OLDA" <<'PY'
import json, sys
f, demo, helper, olda = sys.argv[1:]
json.dump({'tree': [
    {'path': 'skills/demo', 'sha': demo, 'type': 'tree'},
    {'path': 'skills/demo/SKILL.md', 'sha': '1' * 40, 'type': 'blob'},
    {'path': 'skills/demo/ref/new.md', 'sha': '2' * 40, 'type': 'blob'},
    {'path': 'skills/demo/big.js', 'sha': '3' * 40, 'type': 'blob'},
    {'path': 'agents/helper.md', 'sha': helper, 'type': 'blob'}], 'truncated': False,
  '__raw': {'skills/demo/SKILL.md': '---\nname: demo\ndescription: "New upstream text."\n---\nnew body\n',
            'skills/demo/ref/new.md': 'ref\n', 'skills/demo/big.js': 'x\n'},
  '__trees': {}}, open(f, 'w'))
PY
}
sha_of() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print([s['sha'] for i in d['items'] if i['name']==sys.argv[2] for s in i['sources']][0])" "$F/assets/upstream.json" "$1"; }

echo "== 그대로: 원본으로 교체 =="
setup; upstream "$NEW" "$OLDA"
python3 "$UPD" demo --factory "$F" >"$TMP/out" 2>&1; assert "rc 0" 0 "$?"
assert "본문이 원본으로" 1 "$(grep -c 'new body' "$F/assets/skills/demo/SKILL.md")"
assert "한국어 앞머리를 다시 붙였다" 1 "$(grep -c '^description: "데모 한국어 설명. New upstream text."' "$F/assets/skills/demo/SKILL.md")"
assert "원본에 새로 생긴 파일" 1 "$([[ -f "$F/assets/skills/demo/ref/new.md" ]] && echo 1 || echo 0)"
assert "원본에 없는 옛 파일은 사라짐" 0 "$([[ -f "$F/assets/skills/demo/old-only.md" ]] && echo 1 || echo 0)"
assert "skip_files 는 빼고 깐다" 0 "$([[ -f "$F/assets/skills/demo/big.js" ]] && echo 1 || echo 0)"
assert "장부 sha 를 올렸다" "$NEW" "$(sha_of demo)"
assert "커밋·전파 안 했다고 말한다" 1 "$(grep -c '커밋·전파는 하지 않았습니다' "$TMP/out")"

echo "== 이미 최신 =="
python3 "$UPD" demo --factory "$F" >"$TMP/out" 2>&1; assert "rc 0" 0 "$?"
assert "이미 최신이라고 말한다" 1 "$(grep -c '이미 최신' "$TMP/out")"

echo "== 시험 실패면 되돌린다 =="
setup; upstream "$NEW" "$OLDA"
python3 -c "import json;p='$F/assets/upstream.json';d=json.load(open(p));d['items'][0]['tests']=['tests/rejects-new-test.sh'];json.dump(d,open(p,'w'))"
python3 "$UPD" demo --factory "$F" >"$TMP/out" 2>&1; assert "rc 1" 1 "$?"
assert "본문이 옛것 그대로" 1 "$(grep -c 'old body' "$F/assets/skills/demo/SKILL.md")"
assert "옛 파일도 그대로" 1 "$([[ -f "$F/assets/skills/demo/old-only.md" ]] && echo 1 || echo 0)"
assert "장부 sha 그대로" "$OLD" "$(sha_of demo)"
assert "되돌렸다고 말한다" 1 "$(grep -c '되돌렸습니다' "$TMP/out")"

echo "== 고쳐 씀: 파일은 그대로, 바뀐 것만 보인다 =="
setup; upstream "$OLD" "$NEWA"
before=$(sha256sum "$F/assets/agents/helper.md")
python3 "$UPD" helper --factory "$F" >"$TMP/out" 2>&1; assert "rc 0" 0 "$?"
assert "파일 무변경" "$before" "$(sha256sum "$F/assets/agents/helper.md")"
assert "바뀐 원본 경로를 보인다" 1 "$(grep -q 'agents/helper.md' "$TMP/out" && echo 1 || echo 0)"
assert "장부 sha 그대로" "$OLDA" "$(sha_of helper)"
python3 "$UPD" helper --mark-reviewed --factory "$F" >/dev/null 2>&1; assert "--mark-reviewed rc 0" 0 "$?"
assert "장부 sha 가 최신" "$NEWA" "$(sha_of helper)"
python3 "$UPD" helper --factory "$F" >"$TMP/out" 2>&1
assert "그 뒤엔 이미 최신" 1 "$(grep -c '이미 최신' "$TMP/out")"

echo "== 없는 이름·공장 없음 =="
python3 "$UPD" nothing --factory "$F" >/dev/null 2>&1; assert "없는 이름 rc 1" 1 "$?"
mkdir -p "$TMP/nofactory"; cp "$UPD" "$TMP/nofactory/"
python3 "$TMP/nofactory/upstream-update.py" demo >"$TMP/out" 2>&1; assert "공장 없음 rc 1" 1 "$?"
assert "공장이 있는 컴퓨터에서 라고 말한다" 1 "$(grep -c '공장이 있는 컴퓨터에서' "$TMP/out")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
