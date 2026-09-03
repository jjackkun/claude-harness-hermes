#!/usr/bin/env bash
# Step 2b 계장 검증 — pre-commit 게이트가 판정마다 이벤트를 남기는지 단언한다.
#
# 특히 `skipped` 를 확인한다. 판정 모듈이 없어 검사를 건너뛴 상태가 `pass` 로 기록되면
# **게이트가 죽었는데 통과 표시가 나는** 상태가 관측에서도 재현된다 —
# 이 저장소가 R-test 와 .review-dirty 에서 이미 두 번 겪은 실패 형태다.
#
# 실행: bash tests/gate-precommit-instrumentation-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO_ROOT/assets/hooks"
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

EVENTS=".harness/gate-events.jsonl"

verdicts() {
  python3 - "$1/$EVENTS" "$2" <<'PY'
import json, sys
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    print(""); raise SystemExit
out = []
for ln in lines:
    try:
        r = json.loads(ln)
    except ValueError:
        continue
    if r.get("rule") == sys.argv[2]:
        out.append(r.get("verdict", "?"))
print(" ".join(out))
PY
}

# newrepo <name> [모듈...] — git 저장소 + .git/hooks 에 지정 모듈만 배치
newrepo() {
  local name="$1"; shift
  local d="$TMP/$name"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  cp "$HOOKS/pre-commit.sh" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
  cp "$HOOKS/gate_event.py" "$HOOKS/gate_emit.sh" "$d/.git/hooks/"
  local m
  for m in "$@"; do cp "$HOOKS/$m" "$d/.git/hooks/"; done
  echo "$d"
}

run_hook() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash .git/hooks/pre-commit >/dev/null 2>&1); }

echo "== R-size (precommit) =="

P=$(newrepo size plan_state.py complexity.py depcheck.py check-secrets.py)
printf 'x = 1\n%.0s' {1..10} > "$P/small.py"
git -C "$P" add small.py
run_hook "$P"
assert "한도 이내면 pass" "pass" "$(verdicts "$P" R-size)"

P=$(newrepo size_block plan_state.py complexity.py depcheck.py check-secrets.py)
printf 'x = 1\n%.0s' {1..600} > "$P/big.py"
git -C "$P" add big.py
run_hook "$P"
assert "한도 초과면 block" "block" "$(verdicts "$P" R-size)"

echo "== R-cx / R-dep skipped (모듈 부재) =="

# complexity.py / depcheck.py 를 일부러 빼서 "게이트가 죽은" 상태를 만든다.
P=$(newrepo nomod plan_state.py check-secrets.py)
printf 'def a():\n    pass\n' > "$P/mod.py"
git -C "$P" add mod.py
run_hook "$P"
assert "complexity.py 부재는 skipped (pass 아님)" "skipped" "$(verdicts "$P" R-cx)"
assert "depcheck.py 부재는 skipped (pass 아님)" "skipped" "$(verdicts "$P" R-dep)"

echo "== R-secret =="

P=$(newrepo nosecret plan_state.py complexity.py depcheck.py)
printf 'x = 1\n' > "$P/a.py"
git -C "$P" add a.py
run_hook "$P"
assert "check-secrets.py 부재는 skipped — 마지막 방어선이 꺼진 상태" "skipped" \
  "$(verdicts "$P" R-secret)"

P=$(newrepo secret plan_state.py complexity.py depcheck.py check-secrets.py)
printf 'x = 1\n' > "$P/a.py"
git -C "$P" add a.py
run_hook "$P"
assert "검사가 돌면 pass" "pass" "$(verdicts "$P" R-secret)"

echo "== R-plan (스테이징된 계획서가 있을 때만 평가) =="

P=$(newrepo plan_none plan_state.py complexity.py depcheck.py check-secrets.py)
printf 'x = 1\n' > "$P/a.py"
git -C "$P" add a.py
run_hook "$P"
assert "계획서가 없으면 분모에 넣지 않음" "" "$(verdicts "$P" R-plan)"

P=$(newrepo plan_done plan_state.py complexity.py depcheck.py check-secrets.py)
mkdir -p "$P/docs/exec-plans/active"
cat > "$P/docs/exec-plans/active/2026-01-01-x.md" <<'EOF'
# 계획
- [x] 항목1
- [x] 항목2
EOF
git -C "$P" add docs/exec-plans/active/2026-01-01-x.md
run_hook "$P"
assert "전부 완료된 계획이 active/ 에 남으면 block" "block" "$(verdicts "$P" R-plan)"

P=$(newrepo plan_open plan_state.py complexity.py depcheck.py check-secrets.py)
mkdir -p "$P/docs/exec-plans/active"
cat > "$P/docs/exec-plans/active/2026-01-01-y.md" <<'EOF'
# 계획
- [x] 항목1
- [ ] 항목2
EOF
git -C "$P" add docs/exec-plans/active/2026-01-01-y.md
run_hook "$P"
assert "미완료가 남아 있으면 pass" "pass" "$(verdicts "$P" R-plan)"

echo "== flush (종료 시 기록이 유실되지 않는가) =="

P=$(newrepo flush plan_state.py complexity.py depcheck.py check-secrets.py)
printf 'x = 1\n%.0s' {1..600} > "$P/big.py"
git -C "$P" add big.py
run_hook "$P"   # FAIL=1 로 exit 1 하는 경로
assert "차단(exit 1) 경로에서도 이벤트가 남는다" "1" \
  "$([[ -s "$P/$EVENTS" ]] && echo 1 || echo 0)"

echo "== 설치 경로 (다운스트림에서 조용히 꺼지지 않는가) =="

# pre-commit 은 `$(dirname $0)` = `.git/hooks/` 에서 형제 파일을 찾는다.
# `HARNESS_HOOK_SOURCES` 는 `scripts/hooks/` 로만 배치하므로, 설치기가 `.git/hooks/` 에도
# 넣어주지 않으면 source 가 실패해 gate_add 가 no-op 이 되고 **관측만 조용히 꺼진다.**
INST="$REPO_ROOT/lib/harness_installers.sh"
for m in gate_event.py gate_emit.sh; do
  assert "설치기가 .git/hooks/$m 를 배치한다" "1" \
    "$(grep -q "gate_event.py gate_emit.sh" "$INST" && echo 1 || echo 0)"
done

# emitter 가 없어도 pre-commit 자체는 정상 동작해야 한다 (관측이 게이트를 죽이지 않는다).
P=$(newrepo noemit plan_state.py complexity.py depcheck.py check-secrets.py)
rm -f "$P/.git/hooks/gate_event.py" "$P/.git/hooks/gate_emit.sh"
printf 'x = 1\n%.0s' {1..600} > "$P/big.py"
git -C "$P" add big.py
rc=0; run_hook "$P" || rc=$?
assert "emitter 가 없어도 R-size 차단은 그대로 동작 (exit 1)" "1" "$rc"
assert "emitter 가 없으면 기록만 없다" "0" \
  "$([[ -e "$P/$EVENTS" ]] && echo 1 || echo 0)"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
