#!/usr/bin/env bash
# 사본 동기화 판정 (계획 2026-09-27-dashboard-sync-before-verdict 목표 1~4).
# 망을 타지 않는다 — 로컬 bare 원격과 이미 받아 둔 ref 만으로 앞/뒤를 만든다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
st() { PYTHONPATH="$S" python3 -c "import sys; from hermes_repo_sync import repo_sync; r=repo_sync(sys.argv[1]); print(r['state'], r['behind'], r['ahead'])" "$1"; }

# 원격 1개 + 사본 2개(A 는 뒤처지게, B 는 원격을 앞서 나가게)
g init -q --bare "$TMP/remote.git"
g clone -q "$TMP/remote.git" "$TMP/a" 2>/dev/null; echo 1 > "$TMP/a/f"; g -C "$TMP/a" add f; g -C "$TMP/a" commit -qm c1; g -C "$TMP/a" push -q origin HEAD 2>/dev/null
g clone -q "$TMP/remote.git" "$TMP/b" 2>/dev/null

echo "== 1. 판정 =="
assert "원격과 같음 → synced" "synced 0 0" "$(st "$TMP/a")"
echo 2 > "$TMP/b/f"; g -C "$TMP/b" commit -qam c2; g -C "$TMP/b" push -q origin HEAD 2>/dev/null
g -C "$TMP/a" fetch -q
assert "받아만 두고 안 합침 → behind 1" "behind 1 0" "$(st "$TMP/a")"
echo 3 > "$TMP/b/f"; g -C "$TMP/b" commit -qam c3
assert "안 올린 커밋 → ahead" "ahead 0 1" "$(st "$TMP/b")"
echo 4 > "$TMP/a/g"; g -C "$TMP/a" add g; g -C "$TMP/a" commit -qm c4
assert "양쪽 다 새 커밋 → diverged" "diverged 1 1" "$(st "$TMP/a")"
mkdir -p "$TMP/plain"
assert "git 저장소 아님 → no_git" "no_git 0 0" "$(st "$TMP/plain")"
g init -q "$TMP/local"; echo x > "$TMP/local/x"; g -C "$TMP/local" add x; g -C "$TMP/local" commit -qm x
assert "원격 추적 없음 → no_upstream (최신으로 보지 않는다)" "no_upstream 0 0" "$(st "$TMP/local")"
mkdir -p "$TMP/local/sub"
assert "상위가 저장소인 하위 폴더도 no_git (남의 저장소로 판정하지 않는다)" "no_git 0 0" "$(st "$TMP/local/sub")"
FA="$(PYTHONPATH="$S" python3 -c "import sys; from hermes_repo_sync import repo_sync; print(repo_sync(sys.argv[1])['fetched_at'] is not None)" "$TMP/a")"
assert "fetch 한 사본은 마지막 fetch 시각이 있다" True "$FA"

echo "== 2. 우주 표 문구 =="
R() { PYTHONPATH="$S" python3 - "$@" <<'PY'
import sys
from hermes_dashboard_html import render_universe
base = {"installed": True, "agents": 1, "skills": 2, "helpful_rate": None, "demote_candidates": 0, "last_dream": None}
rows = [dict(base, project="copy-behind", factory_match=False, sync={"state": "behind", "behind": 3, "ahead": 0, "fetched_at": None}),
        dict(base, project="install-old", factory_match=False, sync={"state": "synced", "behind": 0, "ahead": 0, "fetched_at": None}),
        dict(base, project="plain", factory_match=True, sync={"state": "no_git", "behind": 0, "ahead": 0, "fetched_at": None})]
fs = {"state": sys.argv[1], "behind": int(sys.argv[2]), "ahead": 0, "fetched_at": None}
print(render_universe(rows, "factory", "now", factory_sync=fs))
PY
}
H="$(R behind 2)"
row() { echo "$H" | grep -o "<tr><td>$1</td>.*" | sed 's#</tr>.*##'; }
assert "사본이 옛것 → 사본 칸 '3 뒤'" 1 "$(row copy-behind | grep -c '3 뒤')"
assert "사본이 옛것 → factory 칸 '사본부터'(설치 판정 보류)" 1 "$(row copy-behind | grep -c '사본부터')"
assert "사본 최신·설치 옛것 → '설치 뒤처짐'" 1 "$(row install-old | grep -c '설치 뒤처짐')"
assert "git 아님 → 사본 칸 '해당 없음'" 1 "$(row plain | grep -c '해당 없음')"
assert "공장 사본이 뒤 → 머리 경고" 1 "$(echo "$H" | grep -c '공장 사본이 원격보다 2 커밋 뒤')"
assert "공장 사본 최신 → 머리 경고 없음" 0 "$(R synced 0 | grep -c '공장 사본이 원격보다')"

echo; echo "PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
