#!/usr/bin/env bash
# 편집 전 사실 확인 준수율 계측기 (계획 2026-09-21-gateguard-fact-force).
#
#   (a) Read 뒤 편집은 준수, 맨눈 편집은 위반
#   (b) Bash 로 읽은 것도 준수로 친다 — Read 도구만 세면 준수율이 과소 집계된다(실측 18.4% vs 95.7%)
#   (c) 같은 세션에서 Write 로 만든 파일 수정은 분모에서 빠진다
#   (d) grep 계열만 importer 조회로 친다 — cat 은 아니다
#   (e) --json · 실 저장소 · 모델 호출 0
#
# 실행: bash tests/edit-factcheck-rate-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/scripts/edit_factcheck_rate.py"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# 트랜스크립트 한 줄 = assistant 메시지 하나. 도구 호출 블록만 있으면 계측기가 읽는다.
emit() { # emit <파일> <도구> <JSON 입력>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, name, raw = sys.argv[1], sys.argv[2], sys.argv[3]
rec = {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": name, "input": json.loads(raw)}]}}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
}
field() { python3 "$TOOL" --root "$1" --json 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['$2'])"; }

mkdir -p "$T/p/proj"

echo "[a] Read 뒤 편집 vs 맨눈 편집"
S="$T/p/proj/a.jsonl"
emit "$S" Read '{"file_path": "/x/seen.py"}'
emit "$S" Edit '{"file_path": "/x/seen.py"}'
emit "$S" Edit '{"file_path": "/x/unseen.py"}'
assert "편집 2건" "2" "$(field "$T/p" edits)"
assert "내용 본 것 1건" "1" "$(field "$T/p" saw_content)"
assert "맨눈 1건" "1" "$(field "$T/p" blind)"

echo "[b] Bash 로 읽은 것도 준수"
rm -f "$T"/p/proj/*.jsonl; S="$T/p/proj/b.jsonl"
emit "$S" Bash '{"command": "sed -n 1,40p /x/viacat.py"}'
emit "$S" Edit '{"file_path": "/x/viacat.py"}'
assert "Bash 읽기 뒤 편집은 맨눈 아님" "0" "$(field "$T/p" blind)"

echo "[c] 자기가 만든 파일은 분모에서 제외"
rm -f "$T"/p/proj/*.jsonl; S="$T/p/proj/c.jsonl"
emit "$S" Write '{"file_path": "/x/new.py"}'
emit "$S" Edit  '{"file_path": "/x/new.py"}'
assert "분모 0" "0" "$(field "$T/p" edits)"
assert "self_made 1" "1" "$(field "$T/p" self_made)"

echo "[d] importer 조회는 grep 계열만"
rm -f "$T"/p/proj/*.jsonl; S="$T/p/proj/d.jsonl"
emit "$S" Bash '{"command": "cat /x/target.py"}'
emit "$S" Edit '{"file_path": "/x/target.py"}'
assert "cat 은 importer 조회 아님" "0" "$(field "$T/p" saw_importer)"
rm -f "$T"/p/proj/*.jsonl; S="$T/p/proj/d2.jsonl"
emit "$S" Bash '{"command": "grep -rn target /x"}'
emit "$S" Edit '{"file_path": "/x/target.py"}'
assert "grep 은 importer 조회" "1" "$(field "$T/p" saw_importer)"

echo "[e] --json · 실 저장소 · 모델 호출 0"
assert "JSON 키" "blind,edits,rates,saw_content,saw_importer,self_made,transcripts" \
  "$(python3 "$TOOL" --root "$T/p" --json 2>/dev/null | python3 -c "import json,sys;print(','.join(sorted(json.load(sys.stdin))))")"
assert "빈 디렉터리도 rc 0" "0" "$(mkdir -p "$T/empty"; python3 "$TOOL" --root "$T/empty" >/dev/null 2>&1; echo $?)"
assert "모델 호출 없음" "0" "$(grep -cE 'subprocess|"claude"' "$TOOL")"

echo; echo "edit-factcheck-rate: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
