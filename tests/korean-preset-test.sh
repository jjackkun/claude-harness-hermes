#!/usr/bin/env bash
# korean 프리셋 설치 시험 (G5) — 켠 프로젝트에만 규칙·훅이 깔리고, 끄면 깔리지 않는다.
#
#   [a] harness korean  → 규칙·훅 3개·Stop 등록·presets.lock·.gitignore 표시 파일
#   [b] harness         → 위 어느 것도 없다
#   [c] 깔린 훅이 그 자리에서 동작한다 — 영어 보고 페이로드를 막는다
#   [d] Codex 설치에는 Stop 검사를 등록하지 않는다(transcript 형식이 다름)
#
# 실행: bash tests/korean-preset-test.sh
# 계획: docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md G5
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vF "$TMP" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
has() { [[ -e "$1" ]] && echo 1 || echo 0; }

install_into() {  # <디렉터리> <설치기> <프리셋...>
  local dir="$1" installer="$2"; shift 2
  mkdir -p "$dir" && git -C "$dir" init -q
  bash "$REPO_ROOT/$installer" "$dir" "$@" > "$dir.install.log" 2>&1 \
    || { echo "  ✗ 설치 실패: $installer $* (로그 끝)"; tail -5 "$dir.install.log"; FAIL=$((FAIL+1)); }
}

ON="$TMP/on"; OFF="$TMP/off"
install_into "$ON" project-claude.sh harness korean
install_into "$OFF" project-claude.sh harness

echo "[a] korean 을 켠 프로젝트"
assert "규칙 korean-reply.md" 1 "$(has "$ON/.claude/rules/korean/korean-reply.md")"
assert "Stop 훅" 1 "$(has "$ON/scripts/hooks/claude-stop-korean-guard.sh")"
assert "판정 모듈" 1 "$(has "$ON/scripts/hooks/korean_reply_check.py")"
assert "매 턴 훅" 1 "$(has "$ON/scripts/hooks/claude-userpromptsubmit-korean.sh")"
assert "settings.json Stop 에 등록" 1 "$(grep -c 'claude-stop-korean-guard.sh' "$ON/.claude/settings.json")"
assert "매 턴 훅은 개별 등록하지 않는다(디스패처 경유)" 0 "$(grep -c 'claude-userpromptsubmit-korean.sh' "$ON/.claude/settings.json")"
assert "presets.lock 에 korean" 1 "$(grep -cx 'korean' "$ON/.claude/presets.lock")"
assert ".gitignore 에 표시 파일" 1 "$(grep -cxF '.hermes/korean-guard.last' "$ON/.gitignore")"

echo "[b] korean 을 끈 프로젝트"
assert "규칙 없음" 0 "$(has "$OFF/.claude/rules/korean")"
assert "Stop 훅 없음" 0 "$(has "$OFF/scripts/hooks/claude-stop-korean-guard.sh")"
assert "매 턴 훅 없음" 0 "$(has "$OFF/scripts/hooks/claude-userpromptsubmit-korean.sh")"
assert "settings.json 에 없음" 0 "$(grep -c 'korean' "$OFF/.claude/settings.json")"
assert "presets.lock 에 없음" 0 "$(grep -cx 'korean' "$OFF/.claude/presets.lock")"

echo "[c] 깔린 훅이 그 자리에서 동작한다"
ENG='All done. I updated the plan, moved the finished items to the completed section, and committed the change. The tests pass and the gate reported no warnings.'
P="$(python3 -c 'import json,sys; print(json.dumps({"transcript_path":"","last_assistant_message":sys.argv[1]}))' "$ENG")"
OUT="$(printf '%s' "$P" | CLAUDE_PROJECT_DIR="$ON" CLAUDE_CONFIG_DIR="$TMP/cfg" bash "$ON/scripts/hooks/claude-stop-korean-guard.sh" 2>/dev/null)"
assert "영어 보고를 막는다" 1 "$(grep -c '"decision": "block"' <<<"$OUT")"
OUT="$(printf '%s' '{"prompt":"x"}' | CLAUDE_PROJECT_DIR="$ON" bash "$ON/scripts/hooks/claude-userpromptsubmit-dispatch.sh" 2>/dev/null)"
assert "디스패처가 한국어 한 줄을 붙인다" 1 "$(grep -c '\[한국어\]' <<<"$OUT")"

echo "[d] Codex 설치"
CX="$TMP/codex"
install_into "$CX" project-codex.sh harness korean
assert "hooks.json 이 만들어졌다" 1 "$(has "$CX/.codex/hooks.json")"
assert "Codex 에는 Stop 검사 미등록" 0 "$(grep -c 'korean-guard' "$CX/.codex/hooks.json" 2>/dev/null)"

echo
echo "결과: 통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]]
