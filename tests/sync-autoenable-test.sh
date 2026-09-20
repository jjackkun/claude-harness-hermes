#!/usr/bin/env bash
# 설치기의 기억 운반 자동 켜기 (T-19·T-21, 계획 2026-09-20-transport-plain 목표 5). gh 는 스텁(네트워크 0).
#   1. PRIVATE → sync.json {push:true, mode:plain} + 첫 push 로 refs/hermes/sync 생성
#   2. PUBLIC  → {push:false} · 3. gh 실패 → unknown, push:false · 4. 이미 있는 sync.json 보존 · 5. CLAUDECODE 있으면 아무것도 안 함
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
STUB="$TMP/stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\n[[ -n "${GH_STUB_FAIL:-}" ]] && exit 1\necho "${GH_STUB_VIS:-PRIVATE}"\n' > "$STUB/gh"; chmod +x "$STUB/gh"
BARE="$TMP/bare"; git init -q --bare "$BARE"
mk() { # <dir> — 설치본 최소 흉내: scripts + .hermes + origin
  mkdir -p "$1/scripts/data" "$1/.hermes"
  cp "$S"/*.py "$S/hermes-sync.py" "$1/scripts/"; cp "$REPO_ROOT/assets/data/bip39-english.txt" "$1/scripts/data/"
  git init -q "$1"; git -C "$1" config user.name t; git -C "$1" config user.email t@t; git -C "$1" commit -q --allow-empty -m init
  git -C "$1" remote add origin "$BARE"
  python3 "$S/hermes-init.py" --project "$1" >/dev/null 2>&1
  PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$1')"
}
run() { # run <dir> [env...] → 로그를 $OUT 에
  local d="$1"; shift
  OUT="$(env -u CLAUDECODE "$@" PATH="$STUB:$PATH" bash -c "source '$REPO_ROOT/lib/logging.sh'; source '$REPO_ROOT/lib/sync_autoenable.sh'; sync_autoenable '$d'" 2>&1)"
}
pol() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('push'), d.get('mode'), d.get('visibility'))" "$1/.hermes/sync.json" 2>/dev/null || echo none; }

echo "[1] PRIVATE → 평문 운반 켬 + 첫 push"
A="$TMP/A"; mk "$A"
python3 "$A/scripts/hermes-journal.py" --project "$A" emit --json '{"kind":"task.started","task_id":"t1","intent":"첫 push 재료","actor":"agent:main"}' >/dev/null 2>&1   # 올릴 것이 있어야 ref 가 생긴다
run "$A" GH_STUB_VIS=PRIVATE
assert "sync.json = push true · plain · PRIVATE" "True plain PRIVATE" "$(pol "$A")"
assert "첫 push 로 refs/hermes/sync 생성" 1 "$(git ls-remote "$BARE" refs/hermes/sync | grep -c .)"
assert "로그에 켬 안내" 1 "$(grep -c '평문 운반 켬' <<<"$OUT")"

echo "[2] PUBLIC → 끔"
B="$TMP/B"; mk "$B"; run "$B" GH_STUB_VIS=PUBLIC
assert "sync.json = push false · PUBLIC" "False None PUBLIC" "$(pol "$B")"

echo "[3] gh 실패 → 미상, 끔"
C="$TMP/C"; mk "$C"; run "$C" GH_STUB_FAIL=1
assert "sync.json = push false · unknown" "False None unknown" "$(pol "$C")"

echo "[4] 이미 있는 sync.json 은 보존"
D="$TMP/D"; mk "$D"; echo '{"push": true, "mode": "locked", "history": true}' > "$D/.hermes/sync.json"; run "$D" GH_STUB_VIS=PRIVATE
assert "사람이 정한 값 그대로" "True locked None" "$(pol "$D")"
assert "로그에 '그대로 둔다'" 1 "$(grep -c '그대로 둔다' <<<"$OUT")"

echo "[5] AI 세션 안(CLAUDECODE)이면 건너뜀"
E="$TMP/E"; mk "$E"
OUT="$(CLAUDECODE=1 PATH="$STUB:$PATH" bash -c "source '$REPO_ROOT/lib/logging.sh'; source '$REPO_ROOT/lib/sync_autoenable.sh'; sync_autoenable '$E'" 2>&1)"
assert "sync.json 안 만듦" none "$(pol "$E")"
assert "로그에 세션 안 안내" 1 "$(grep -c 'AI 세션 안' <<<"$OUT")"

echo "[6] origin 없으면 gh 를 부르지 않고 미상"
F="$TMP/F"; mk "$F"; git -C "$F" remote remove origin; run "$F" GH_STUB_VIS=PRIVATE
assert "origin 없음 → unknown" "False None unknown" "$(pol "$F")"

echo; echo "sync-autoenable: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
