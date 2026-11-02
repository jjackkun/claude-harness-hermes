#!/usr/bin/env bash
# 계획 2026-11-02-new-pc-restore G3 — 프리셋 인자 없이 `project-claude.sh <경로>` 를 부르면
# 그 프로젝트의 커밋된 .claude/presets.lock 을 읽어 설치한다. 목록이 없거나 틀리면 아무것도 깔지 않는다.
#
# 새 PC 는 .installed-projects 가 비어 update-all 이 프로젝트를 모른다 — clone 한 저장소의 lock 만 남는다.
# 추측해서 깔지 않는다: 틀린 프리셋은 매니페스트의 추적된 설치물을 지운다(R-lock 2026-09-22 사고).
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다(preset-lock-tracked-test 와 같은 방식).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"

newproj() { P="$TMP/$1"; mkdir -p "$P/.claude"; git -C "$P" init -q; }
restore() { bash "$SANDBOX/project-claude.sh" "$@" >"$TMP/restore.log" 2>&1; echo $?; }
installed() { [[ -f "$P/CLAUDE.md" ]] && echo 1 || echo 0; }

echo "== lock 이 있으면 그 목록으로 설치한다 =="
newproj has-lock; printf 'harness\nhermes\nmcp\n' > "$P/.claude/presets.lock"
assert "rc 0" 0 "$(restore "$P")"
assert "어느 목록으로 까는지 한 줄" 1 "$(grep -c '커밋된 목록으로 설치' "$TMP/restore.log")"
assert "설치됐다(CLAUDE.md)" 1 "$(installed)"
assert "mcp 스킬이 깔렸다" 1 "$([[ -e "$P/.claude/skills/mcp-builder" ]] && echo 1 || echo 0)"
assert "lock 은 같은 집합" $'harness\nhermes\nmcp' "$(sort "$P/.claude/presets.lock")"

echo "== 빈 줄이 섞여도 이름만 읽는다 =="
newproj blank-lines; printf '\nharness\n\n  \nhermes\n' > "$P/.claude/presets.lock"
assert "rc 0" 0 "$(restore "$P")"
assert "lock 에 빈 줄이 남지 않는다" 0 "$(grep -c '^[[:space:]]*$' "$P/.claude/presets.lock")"

echo "== --dry-run 도 lock 을 읽고, 아무것도 쓰지 않는다 =="
newproj dry; printf 'harness\n' > "$P/.claude/presets.lock"
assert "rc 0" 0 "$(restore --dry-run "$P")"
assert "어느 목록인지 보인다" 1 "$(grep -c '커밋된 목록으로 설치' "$TMP/restore.log")"
assert "설치 안 됨" 0 "$(installed)"

echo "== lock 이 없으면 사용법, rc 1, 설치 0 =="
newproj no-lock
assert "rc 1" 1 "$(restore "$P")"
assert "사용법이 보인다" 1 "$([[ $(grep -c 'Usage' "$TMP/restore.log") -ge 1 ]] && echo 1 || echo 0)"
assert "설치 안 됨" 0 "$(installed)"

echo "== 빈 lock(빈 줄뿐)도 없는 것과 같다 =="
newproj empty-lock; printf '\n  \n' > "$P/.claude/presets.lock"
assert "rc 1" 1 "$(restore "$P")"
assert "설치 안 됨" 0 "$(installed)"

echo "== 모르는 이름이 섞이면 아무것도 깔지 않는다 =="
newproj unknown; printf 'harness\nno-such-preset\n' > "$P/.claude/presets.lock"
assert "rc 1" 1 "$(restore "$P")"
assert "모르는 이름을 말한다" 1 "$(grep -c "Unknown preset: 'no-such-preset'" "$TMP/restore.log")"
assert "설치 안 됨" 0 "$(installed)"
assert "lock 을 덮어쓰지 않는다" $'harness\nno-such-preset' "$(cat "$P/.claude/presets.lock")"

echo "== 인자 0개 · -h 는 지금 그대로 =="
assert "-h rc 0" 0 "$(restore -h)"
assert "인자 0개 rc 0" 0 "$(restore)"

echo; echo "project-claude-restore: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
