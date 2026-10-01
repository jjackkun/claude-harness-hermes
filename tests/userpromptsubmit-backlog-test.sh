#!/usr/bin/env bash
# 매 턴 주입의 백로그 구획 — 파일 경로 목록 대신 건수 한 줄
# (계획 docs/exec-plans/completed/2026-10-01-per-turn-injection-trim.md 목표 1 · 2).
#
# 이 구획은 매 사용자 입력마다 프롬프트 앞에 붙는다. 18건이면 경로 18줄(1,073B ≈ 500 토큰)이 매번 똑같이 실렸다.
# 경로가 필요하면 모델이 ls 로 열 수 있으므로 존재·건수만 알린다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

run_hook() { printf '{"prompt":"x","session_id":"s"}' | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null; }
section() { sed -n '/^--- \[Backlog\] ---$/,/^---$/p'; }

echo "1. 18건 백로그"
P="$TMP/many"; mkdir -p "$P/docs/exec-plans/backlog"
for i in $(seq 1 18); do : > "$P/docs/exec-plans/backlog/some-long-backlog-item-name-$i.md"; done
OUT="$(run_hook "$P")"; SEC="$(printf '%s\n' "$OUT" | section)"
assert "구획 머리가 있다" 1 "$(printf '%s\n' "$SEC" | grep -c '^--- \[Backlog\] ---$')"
assert "건수 줄이 18건을 말한다" 1 "$(printf '%s\n' "$SEC" | grep -c '18건')"
assert "파일 경로 줄이 없다" 0 "$(printf '%s\n' "$SEC" | grep -c 'some-long-backlog-item-name')"
assert "목록 위치를 알려 준다" 1 "$(printf '%s\n' "$SEC" | grep -c 'docs/exec-plans/backlog/')"
BYTES="$(printf '%s\n' "$SEC" | wc -c)"
assert "구획이 120B 안이다(경로 18줄이면 1,000B 넘는다)" 1 "$(( BYTES <= 120 ? 1 : 0 ))"

echo "2. 건수가 많아도 크기가 늘지 않는다"
for i in $(seq 19 60); do : > "$P/docs/exec-plans/backlog/some-long-backlog-item-name-$i.md"; done
BYTES60="$(run_hook "$P" | section | wc -c)"
assert "60건에서도 120B 안" 1 "$(( BYTES60 <= 120 ? 1 : 0 ))"

echo "3. 비면 구획이 없다"
Q="$TMP/none"; mkdir -p "$Q/docs/exec-plans/backlog"
assert "0건이면 [Backlog] 없음" 0 "$(run_hook "$Q" | grep -c '\[Backlog\]')"
R="$TMP/nodir"; mkdir -p "$R"
assert "백로그 폴더가 없어도 [Backlog] 없음" 0 "$(run_hook "$R" | grep -c '\[Backlog\]')"

echo "4. 다른 구획은 그대로다"
mkdir -p "$P/docs/exec-plans/active"; : > "$P/docs/exec-plans/active/2026-01-01-x.md"
OUT="$(run_hook "$P")"
assert "Active Plans 구획 유지" 1 "$(printf '%s\n' "$OUT" | grep -c '\[Active Plans\]')"
assert "Harness Reminders 구획 유지" 1 "$(printf '%s\n' "$OUT" | grep -c '\[Harness Reminders\]')"

echo "통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]]
