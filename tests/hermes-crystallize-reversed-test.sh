#!/usr/bin/env bash
# 결정화 철회 보류 — 철회된 결정을 규칙으로 굳히지 않는다 (계획 2026-09-18-crystallize-reversed-guard, L-06).
#
#   (a) 패턴 키와 겹치는 기억이 철회된 채  → HOLD, 스킬 파일 0, crystallized 0 유지
#   (b) 철회 뒤 같은 주제를 다시 추가       → 보류 해제, DONE
#   (c) 겹치지 않는 철회                    → 영향 없음, DONE
#   (d) memory_events 표 없음               → 기존 동작 그대로, DONE
#
# `claude` 는 PATH 가짜 실행파일. 실행: bash tests/hermes-crystallize-reversed-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/scripts"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'MOCK'
#!/usr/bin/env bash
printf '# %s\n<!-- hermes:auto-generated version:1 created:2026-09-18 -->\n\n## 규칙\n- [ ] 규칙\n' "${MOCK_TITLE:-reversed-test}"
MOCK
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"

new_db() { # new_db <dir> [with-memory] — 실제 초기화 도구로 프로젝트 DB 생성 (HOME 격리)
  local d="$1"; mkdir -p "$d"
  HOME="$T/home" python3 "$S/hermes-init.py" --project "$d" >/dev/null 2>&1
  [[ "${2:-}" == "with-memory" ]] && python3 - "$d/.hermes/state.db" "$S" <<'PY'
import sqlite3, sys, importlib.util
spec = importlib.util.spec_from_file_location("me", sys.argv[2] + "/hermes_memory_events.py")
me = importlib.util.module_from_spec(spec); spec.loader.exec_module(me)
con = sqlite3.connect(sys.argv[1]); me.ensure_memory_schema(con); con.commit()
PY
  return 0
}
mem() { # mem <db> <kind> <about> <body> [revises] → memory_id
  python3 - "$@" "$S" <<'PY'
import sqlite3, sys, importlib.util, datetime, uuid
db, kind, about, body = sys.argv[1:5]; revises = sys.argv[5] if len(sys.argv) > 6 else None
spec = importlib.util.spec_from_file_location("me", sys.argv[-1] + "/hermes_memory_events.py")
me = importlib.util.module_from_spec(spec); spec.loader.exec_module(me)
con = sqlite3.connect(db)
n = con.execute("SELECT COUNT(*) FROM memory_events").fetchone()[0]
ev = {"memory_id": uuid.uuid4().hex, "kind": kind, "agent_id": "a1", "universe_id": "u1",
      "ts": "2026-09-18T00:00:%02dZ" % n, "about": about, "body": body, "source_event": "e1"}
if revises: ev["revises"] = revises
print(me.record(con, ev)); con.commit()
PY
}
run() { MOCK_TITLE="$2" python3 "$S/hermes-crystallize.py" --db "$1/.hermes/state.db" --crystallize "$2" --project-dir "$1" 2>&1; }
skills() { ls "$1/.hermes/skills" 2>/dev/null | wc -l | tr -d ' '; }
cryst() { python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('SELECT crystallized FROM pattern_count WHERE pattern_key=?',(sys.argv[2],)).fetchone()[0])" "$1/.hermes/state.db" "$2"; }

echo "[a] 철회된 결정과 겹침 → HOLD"
new_db "$T/a" with-memory
m1=$(mem "$T/a/.hermes/state.db" memory.added "pnpm 고정" "pnpm 버전을 고정한다")
mem "$T/a/.hermes/state.db" memory.retracted "pnpm 고정" "고정하지 않기로 함" "$m1" >/dev/null
OUT=$(run "$T/a" "pnpm-고정")
assert "HOLD 출력" "1" "$(grep -c 'HOLD:pnpm-고정' <<<"$OUT")"
assert "보류 사유에 철회 기억 id" "1" "$(grep -c "$m1" <<<"$OUT")"
assert "스킬 파일 0" "0" "$(skills "$T/a")"
assert "crystallized 0 유지(재판정 가능)" "0" "$(cryst "$T/a" "pnpm-고정")"

echo "[b] 철회 뒤 재추가 → 보류 해제"
mem "$T/a/.hermes/state.db" memory.added "pnpm 고정" "역시 pnpm 버전을 고정한다" >/dev/null
OUT=$(run "$T/a" "pnpm-고정")
assert "DONE 출력" "1" "$(grep -c 'DONE:' <<<"$OUT")"
assert "스킬 파일 1" "1" "$(skills "$T/a")"

echo "[c] 무관한 철회 → 영향 없음"
new_db "$T/c" with-memory
m2=$(mem "$T/c/.hermes/state.db" memory.added "탭 정책" "탭 4칸")
mem "$T/c/.hermes/state.db" memory.retracted "탭 정책" "2칸으로" "$m2" >/dev/null
OUT=$(run "$T/c" "pnpm-고정")
assert "DONE 출력" "1" "$(grep -c 'DONE:' <<<"$OUT")"
assert "HOLD 없음" "0" "$(grep -c 'HOLD:' <<<"$OUT")"

echo "[d] memory_events 표 없음 → 기존 동작"
new_db "$T/d"
OUT=$(run "$T/d" "pnpm-고정")
assert "DONE 출력" "1" "$(grep -c 'DONE:' <<<"$OUT")"

echo "[e] 판정 모듈은 표준 라이브러리만 (R3)"
assert "hermes_* import 없음" "0" "$(grep -cE '^(import|from) hermes' "$S/hermes_reversed_guard.py"; true)"

echo; echo "crystallize-reversed: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
