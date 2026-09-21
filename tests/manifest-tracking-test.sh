#!/usr/bin/env bash
# 설치 목록이 git 에 안 들어가는 소우주를 보이게 한다 (계획 2026-09-21-manifest-tracking-warn, I-02).
#
#   (a) doctor — `.claude/*` 를 무시하는 저장소에서 "추적되지 않음" 을 내고, 추적되는 저장소에서는 안 낸다
#   (b) doctor — 그 항목이 ok 를 거짓으로 만들지 않는다(정보)
#   (c) git 저장소가 아니면 조용히 넘어간다
#   (d) 공장 무시 블록에 예외 줄이 있다 + 프로젝트 규칙이 뒤에서 덮어도 (a) 가 여전히 잡는다
#
# 실행: bash tests/manifest-tracking-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$ROOT/scripts/harness-doctor.py"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkproj() { # mkproj <경로> <gitignore 내용|-->
  local p="$1" ig="$2"
  mkdir -p "$p/.claude"
  printf '{"version": 1, "items": []}' > "$p/.claude/.factory-manifest.json"
  printf 'harness\n' > "$p/.claude/presets.lock"
  if [[ "$ig" != "--" ]]; then
    ( cd "$p" && git init -q && git config user.email t@t && git config user.name t )
    printf '%s\n' "$ig" > "$p/.gitignore"
  fi
}
doctor_json() { python3 "$DOCTOR" "$1" --json 2>/dev/null; }
# 사유까지 본다: ignored(무시 규칙에 덮임) · uncommitted(무시는 아닌데 아직 add 안 됨) · ""(문제 없음)
untracked_flag() { doctor_json "$1" | python3 -c "import json,sys;print(json.load(sys.stdin).get('manifest_untracked') or 'no')" 2>/dev/null || echo err; }

echo "[a] 무시되는 저장소 vs 추적되는 저장소"
mkproj "$T/ignored" '.claude/*'
mkproj "$T/tracked" 'node_modules/'
( cd "$T/tracked" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
assert "무시되는 곳 → 사유 ignored" "ignored" "$(untracked_flag "$T/ignored")"
assert "추적되는 곳 → 표시 없음" "no" "$(untracked_flag "$T/tracked")"
assert "사람이 읽는 보고에도 한 줄" "1" "$(python3 "$DOCTOR" "$T/ignored" 2>/dev/null | grep -c '추적되지 않음')"

echo "[b] 정보 항목 — ok 를 거짓으로 만들지 않는다"
assert "무시되는 곳도 ok 유지" "True" "$(doctor_json "$T/ignored" | python3 -c "import json,sys;print(json.load(sys.stdin).get('ok'))")"

echo "[c] git 저장소가 아니면 조용히"
mkproj "$T/nogit" '--'
assert "표시 없음" "no" "$(untracked_flag "$T/nogit")"
assert "보고에 그 줄 없음" "0" "$(python3 "$DOCTOR" "$T/nogit" 2>/dev/null | grep -c '추적되지 않음')"

echo "[d] 공장 예외 줄 + 덮이는 경우"
grep -q '!\.claude/\.factory-manifest\.json' "$ROOT/lib/harness_installers.sh"; assert "무시 블록에 예외 줄" "0" "$?"
# 프로젝트 규칙이 예외보다 **뒤**에 오면 예외가 덮인다 — 그때도 (a) 가 잡아야 한다
mkproj "$T/overridden" '!.claude/.factory-manifest.json'
printf '.claude/*\n' >> "$T/overridden/.gitignore"
assert "예외가 덮여도 잡는다" "ignored" "$(untracked_flag "$T/overridden")"
# 자기 검사 — 순서를 되돌리면(예외가 뒤) 추적되므로 표시가 사라져야 한다
printf '.claude/*\n!.claude/.factory-manifest.json\n' > "$T/overridden/.gitignore"
# 예외가 뒤에 오면 무시는 풀린다 — 그래도 아직 커밋되지 않았으므로 uncommitted 로 남는다(I-02 는 "커밋된다" 를 요구한다)
assert "예외가 뒤에 오면 무시는 풀리고 사유가 uncommitted(자기 검사)" "uncommitted" "$(untracked_flag "$T/overridden")"

echo "[e] 무시는 아닌데 커밋 안 된 경우 — 2026-09-21 전파 뒤 ai-create·kis-trading 이 정확히 이 상태가 됐다"
mkproj "$T/uncommitted" 'node_modules/'
assert "사유 uncommitted" "uncommitted" "$(untracked_flag "$T/uncommitted")"
assert "보고에 '커밋되지 않았다' 한 줄" "1" "$(python3 "$DOCTOR" "$T/uncommitted" 2>/dev/null | grep -c '아직 커밋되지 않았다')"

echo "[f] 설치기 경고"
grep -q '설치 목록이 git 에 추적되지 않습니다' "$ROOT/lib/harness_installers.sh"; assert "설치기에 경고 문구" "0" "$?"
grep -B2 '설치 목록이 git 에 추적되지 않습니다' "$ROOT/lib/harness_installers.sh" | grep -q 'log_warn'; assert "INFO 가 아니라 log_warn" "0" "$?"

echo; echo "manifest-tracking: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
