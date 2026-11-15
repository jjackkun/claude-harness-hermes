#!/usr/bin/env bash
# 원본 확인 프로그램 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G4·G5(알림·잠금)
#
# 네트워크 대신 UPSTREAM_FIXTURE_DIR 의 가짜 응답을 쓴다. 상태 폴더는 임시 폴더다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHK="$REPO_ROOT/scripts/upstream-check.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SHA_OLD=$(printf 'a%.0s' {1..40}); SHA_NEW=$(printf 'b%.0s' {1..40})
FIX="$TMP/fix"; mkdir -p "$FIX"; export UPSTREAM_FIXTURE_DIR="$FIX"
# 장부 두 개: A 는 org/one, B 는 org/two (장부가 다른 두 프로젝트)
ledger() {  # <file> <repo> <name> [version]
  python3 - "$@" <<'PY'
import json, sys
f, repo, name = sys.argv[1:4]
it = {'name': name, 'kind': 'skills', 'path': f'assets/skills/{name}', 'mode': 'vendored',
      'sources': [{'repo': repo, 'path': f'skills/{name}', 'sha': 'a' * 40}], 'tests': []}
if len(sys.argv) > 4:
    it['version_from'] = {'file': 'SKILL.md', 'frontmatter': 'version'}
json.dump({'version': 1, 'items': [it]}, open(f, 'w'))
PY
}
tree() {  # <repo> <name> <sha> [version]
  python3 - "$FIX" "$@" <<'PY'
import json, sys
fix, repo, name, sha = sys.argv[1:5]
d = {'tree': [{'path': f'skills/{name}', 'sha': sha, 'type': 'tree'}], 'truncated': False}
if len(sys.argv) > 5:
    d['__raw'] = {f'skills/{name}/SKILL.md': f'---\nname: {name}\nversion: {sys.argv[5]}\n---\n'}
json.dump(d, open(f"{fix}/{repo.replace('/', '__')}.json", 'w'))
PY
}
run() { python3 "$CHK" "$@" --state-dir "$STATE"; }
fresh() { STATE="$TMP/state-$1"; rm -rf "$STATE"; }
A="$TMP/a.json"; B="$TMP/b.json"
ledger "$A" org/one alpha with-version
ledger "$B" org/two beta

echo "== 새 버전: 상태에 쓰고 알림 한 번 =="
fresh 1; tree org/one alpha "$SHA_NEW" 5.0.0
run --check --ledger "$A"; assert "check rc 0" 0 "$?"
assert "상태에 새 sha" "$SHA_NEW" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['sources']['org/one:skills/alpha']['sha'])" "$STATE/upstream-status.json")"
out=$(run --notice --ledger "$A")
assert "알림 JSON 에 이름과 버전" 1 "$([[ "$out" == *'alpha 5.0.0'* && "$out" == *systemMessage* && "$out" == *additionalContext* ]] && echo 1 || echo 0)"
assert "공장 없으면 '공장이 있는 컴퓨터에서'" 1 "$([[ "$out" == *'공장이 있는 컴퓨터에서'* ]] && echo 1 || echo 0)"
assert "같은 날 두 번째 알림은 없다" "" "$(run --notice --ledger "$A")"

echo "== 같음: 알림 없음 =="
fresh 2; tree org/one alpha "$SHA_OLD"
run --check --ledger "$A"; assert "check rc 0" 0 "$?"
assert "알림 없음" "" "$(run --notice --ledger "$A")"

echo "== 20시간 안 재확인은 묻지 않는다 =="
export UPSTREAM_FETCH_LOG="$TMP/fetch.log"; : > "$UPSTREAM_FETCH_LOG"
run --check --ledger "$A"
assert "두 번째 check 는 요청 0회" 0 "$(wc -l < "$UPSTREAM_FETCH_LOG")"

echo "== 일부 실패: 되는 것만 쓰고 실패는 error 로 =="
fresh 3; rm -f "$FIX"/*.json; tree org/one alpha "$SHA_NEW"
python3 -c "import json;d=json.load(open('$A'));d['items'].append(json.load(open('$B'))['items'][0]);json.dump(d,open('$TMP/ab.json','w'))"
run --check --ledger "$TMP/ab.json"; assert "check rc 0" 0 "$?"
assert "실패한 저장소에 error" 1 "$(python3 -c "import json,sys;print(1 if json.load(open(sys.argv[1]))['repos']['org/two'].get('error') else 0)" "$STATE/upstream-status.json")"

echo "== 전부 실패: 상태 무변경, rc 3, 1시간 안 재시도 안 함 =="
fresh 4; rm -f "$FIX"/*.json
run --check --ledger "$A"; assert "rc 3" 3 "$?"
assert "상태 파일 없음" 0 "$([[ -f "$STATE/upstream-status.json" ]] && echo 1 || echo 0)"
assert "실패 표시 생김" 1 "$([[ -f "$STATE/upstream-last-attempt" ]] && echo 1 || echo 0)"
tree org/one alpha "$SHA_NEW"; : > "$UPSTREAM_FETCH_LOG"
run --check --ledger "$A"; assert "1시간 안: rc 0" 0 "$?"
assert "1시간 안: 요청 0회" 0 "$(wc -l < "$UPSTREAM_FETCH_LOG")"
touch -d '2 hours ago' "$STATE/upstream-last-attempt"
run --check --ledger "$A"
assert "1시간 뒤: 다시 묻는다" 1 "$(wc -l < "$UPSTREAM_FETCH_LOG")"

echo "== 한도 초과·응답 모양 바뀜 =="
fresh 5; echo '{"__status": 403}' > "$FIX/org__one.json"
run --check --ledger "$A"; assert "403 → rc 3" 3 "$?"
fresh 6; echo '{"message": "changed"}' > "$FIX/org__one.json"
run --check --ledger "$A"; assert "트리 없음 → rc 3" 3 "$?"
fresh 7; echo '{"tree": [], "truncated": true}' > "$FIX/org__one.json"
run --check --ledger "$A"; assert "잘린 트리 → rc 3" 3 "$?"

echo "== 장부 깨짐 =="
echo 'not json' > "$TMP/broken.json"
python3 "$CHK" --check --ledger "$TMP/broken.json" --state-dir "$TMP/s8" 2>/dev/null; assert "rc 2" 2 "$?"

echo "== 낡은 잠금은 깬다 =="
fresh 9; tree org/one alpha "$SHA_NEW"; mkdir -p "$STATE/upstream-check.lock"; touch -d '20 minutes ago' "$STATE/upstream-check.lock"
run --check --ledger "$A"; assert "rc 0" 0 "$?"
assert "상태가 써졌다" 1 "$([[ -f "$STATE/upstream-status.json" ]] && echo 1 || echo 0)"
assert "잠금이 남지 않았다" 0 "$([[ -d "$STATE/upstream-check.lock" ]] && echo 1 || echo 0)"

echo "== 장부가 다른 두 프로젝트가 동시에: 합집합을 다 묻고 중복은 없다 =="
fresh 10; tree org/one alpha "$SHA_NEW"; tree org/two beta "$SHA_NEW"; : > "$UPSTREAM_FETCH_LOG"
UPSTREAM_FIXTURE_DELAY=1 run --check --ledger "$A" & p1=$!
UPSTREAM_FIXTURE_DELAY=1 run --check --ledger "$B" & p2=$!
UPSTREAM_FIXTURE_DELAY=1 run --check --ledger "$A" & p3=$!
wait $p1 $p2 $p3
assert "org/one 1회" 1 "$(grep -c '^org/one$' "$UPSTREAM_FETCH_LOG")"
assert "org/two 1회" 1 "$(grep -c '^org/two$' "$UPSTREAM_FETCH_LOG")"
assert "상태에 둘 다" 2 "$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['repos']))" "$STATE/upstream-status.json")"

echo "== 알림 문구: 공장 있음 =="
fresh 11; tree org/one alpha "$SHA_NEW"; run --check --ledger "$A"
F="$TMP/factory"; mkdir -p "$F/assets"; cp "$A" "$F/assets/upstream.json"; echo "$F" > "$STATE/factory-path"
assert "공장도 낡음 → 공장에서 올려" 1 "$([[ "$(run --notice --ledger "$A")" == *'공장에서 올려'* ]] && echo 1 || echo 0)"
python3 -c "import json;d=json.load(open('$F/assets/upstream.json'));d['items'][0]['sources'][0]['sha']='$SHA_NEW';json.dump(d,open('$F/assets/upstream.json','w'))"
rm -f "$STATE/upstream-last-notice"
assert "공장은 최신 → 전파 필요" 1 "$([[ "$(run --notice --ledger "$A")" == *'전파가 필요'* ]] && echo 1 || echo 0)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
