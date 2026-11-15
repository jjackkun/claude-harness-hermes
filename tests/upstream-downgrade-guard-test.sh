#!/usr/bin/env bash
# 거꾸로 덮어쓰기 막기 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G8
#
# 공장 장부가 버전 위치를 정한 에셋(impeccable: SKILL.md 의 version)으로 본다.
#   - 소우주 사본이 공장보다 높은 버전 → 바꾸지 않고, 백업도 만들지 않고, 경고를 남긴다
#   - 같음·낮음 → 지금처럼 백업 후 공장 판으로
#   - 버전 줄이 없음 → 지금처럼
#   - 목록에 없는 사용자 로컬 항목(rc=2) → 버전이 높아도 지금처럼
#
# 격리: 저장소 임시 사본 + HOME 변경.
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"
FACTORY_VER="$(grep -m1 '^version:' "$SANDBOX/assets/skills/impeccable/SKILL.md" | awk '{print $2}')"

P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q
S="$P/.claude/skills/impeccable/SKILL.md"
install() { bash "$SANDBOX/project-claude.sh" "$P" harness svelte >"$TMP/install.log" 2>&1; }
setver() { sed -i "s/^version: .*/version: $1/" "$S"; }
ver() { grep -m1 '^version:' "$S" | awk '{print $2}'; }
backups() { find "$P/.claude/skills" -maxdepth 1 -name 'impeccable.backup-*' | wc -l; }

install; assert "첫 설치 rc 0" 0 "$?"
assert "impeccable 이 공장 버전으로 깔렸다" "$FACTORY_VER" "$(ver)"

echo "== 소우주가 더 새 버전 → 건너뜀 =="
setver 99.0.0; install; assert "재설치 rc 0" 0 "$?"
assert "99.0.0 이 그대로" "99.0.0" "$(ver)"
assert "백업을 만들지 않았다" 0 "$(backups)"
assert "경고 줄" 1 "$(grep -c "'impeccable' 는 공장보다 새 버전이라 건너뜀" "$TMP/install.log")"
install
assert "다음 전파에서도 그대로" "99.0.0" "$(ver)"

echo "== 소우주가 낮은 버전 → 공장 판으로 =="
setver 1.0.0; install
assert "공장 버전으로 바뀌었다" "$FACTORY_VER" "$(ver)"
assert "백업 1개" 1 "$(backups)"

echo "== 버전 줄이 없음 → 지금 동작 =="
find "$P/.claude/skills" -maxdepth 1 -name 'impeccable.backup-*' -exec rm -rf {} +
sed -i '/^version:/d' "$S"; install
assert "공장 버전으로 바뀌었다" "$FACTORY_VER" "$(ver)"
assert "백업 1개" 1 "$(backups)"

echo "== 목록에 없는 사용자 로컬 항목(rc=2) → 지금 동작 =="
find "$P/.claude/skills" -maxdepth 1 -name 'impeccable.backup-*' -exec rm -rf {} +
python3 - "$P/.claude/.factory-manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d['items'] = [i for i in d['items'] if not (i['kind'] == 'skills' and i['name'] == 'impeccable')]
json.dump(d, open(p, 'w'))
PY
setver 99.0.0; install
assert "공장 버전으로 바뀌었다" "$FACTORY_VER" "$(ver)"
assert "백업 1개" 1 "$(backups)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
