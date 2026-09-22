#!/usr/bin/env bash
# 도움 없는 스킬의 증거 기반 강등 + 일반 코드 단어 키 결정화 거부 (계획 2026-09-18-skill-yield-junk).
#
#   (a) low_yield_skills: 판정(도움+헛주입) ≥50 · 판정 중 도움률 ≤5% 만 — 경계(50/5%)·판정 부족·도움 있음은 제외
#   (b) hermes-cleanup (e) dry-run: 목록만 보고, 파일·행 불변
#   (c) hermes-cleanup (e) --apply: 파일·skill_index 행 삭제 + pattern_count 거부(-1)
#   (d) is_generic_key + 결정화: 'index' 같은 키는 모델 호출 없이 REJECT (가짜 claude 가 불리면 실패)
#   (e) 모듈은 표준 라이브러리만 (R3)
#
# 실행: bash tests/hermes-skill-yield-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/scripts"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
# 불리면 안 되는 가짜 claude — 호출 흔적을 남긴다
printf '#!/usr/bin/env bash\necho called >> "%s/claude-called"\nprintf "# should-not\\n\\n## 규칙\\n- [ ] x\\n"\n' "$T" > "$T/bin/claude"
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"

P="$T/proj"; mkdir -p "$P"
HOME="$T/home" python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"; SK="$P/.hermes/skills"; mkdir -p "$SK"
# 스킬 6개 — (주입, 도움) 조합
python3 - "$DB" "$SK" <<'PY'
import sqlite3, sys, os
db, sk = sys.argv[1:3]
con = sqlite3.connect(db)
# (주입, 도움, 헛주입) — 판정 = 도움 + 헛주입. correlated 는 "판정을 마쳤다" 표시일 뿐 도움이 아니다(2026-09-22).
# unjudged: 주입 424 · 판정 17(전부 도움) — 옛 기준(correlated/주입 = 4%)이 강등 후보로 올리던 실측 사례.
cases = {"index": (775, 0, 775), "postgres": (146, 1, 145), "edge50": (50, 2, 48), "edge49": (49, 0, 49),
         "jira-gate": (200, 150, 50), "fresh": (3, 0, 3), "unjudged": (424, 17, 0)}
for key, (inj, help_, noop) in cases.items():
    p = os.path.join(sk, key + ".md")
    open(p, "w").write("# %s\n\n## 규칙\n- [ ] r\n" % key)
    con.execute("INSERT INTO skill_index (skill_path, keywords, scope, version, created_at, used_count, helpful_count, noop_count) "
                "VALUES (?,?,'local',1,'2026-01-01',0,?,?)", (p, key, help_, noop))
    con.execute("INSERT OR IGNORE INTO pattern_count (pattern_key, count, crystallized) VALUES (?, 3, 1)", (key,))
    for i in range(inj):
        con.execute("INSERT INTO skill_injection (session_id, skill_path, injected_at, correlated, source) VALUES (?,?,?,?,'prompt')",
                    ("s%d" % i, p, "2026-01-01", 1 if i < help_ + noop else 0))
con.commit()
PY

echo "[a] low_yield_skills 경계"
GOT=$(python3 - "$DB" "$S" <<'PY'
import sqlite3, sys, importlib.util, os
spec = importlib.util.spec_from_file_location("y", sys.argv[2] + "/hermes_skill_yield.py"); y = importlib.util.module_from_spec(spec); spec.loader.exec_module(y)
rows = y.low_yield_skills(sqlite3.connect(sys.argv[1]))
print(",".join(sorted(os.path.basename(r["skill_path"])[:-3] for r in rows)))
PY
)
assert "index·postgres·edge50 만 (판정 50 경계 포함 · 판정 49 · 도움 많음 · 신규 · 판정 부족 제외)" "edge50,index,postgres" "$GOT"

echo "[b] cleanup dry-run"
OUT=$(python3 "$S/hermes-cleanup.py" --db "$DB" --skills-dir "$SK" 2>&1)
assert "(e) 절이 3개 보고" "1" "$(grep -c '(e) 도움 없는 스킬: 3개' <<<"$OUT")"
assert "dry-run 은 파일 유지" "7" "$(ls "$SK" | wc -l | tr -d ' ')"

echo "[c] cleanup --apply"
OUT=$(python3 "$S/hermes-cleanup.py" --db "$DB" --skills-dir "$SK" --apply 2>&1)
assert "파일 3개 삭제 (7 → 4)" "4" "$(ls "$SK" | wc -l | tr -d ' ')"
assert "jira-gate·fresh·edge49·unjudged 남음 — 판정 17뿐인 스킬은 지우지 않는다" "edge49.md fresh.md jira-gate.md unjudged.md" "$(ls "$SK" | sort | tr '\n' ' ' | sed 's/ $//')"
assert "skill_index 행 4개 남음" "4" "$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(\"SELECT COUNT(*) FROM skill_index WHERE scope='local'\").fetchone()[0])" "$DB")"
assert "pattern_count 거부(-1) 표시" "3" "$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(\"SELECT COUNT(*) FROM pattern_count WHERE crystallized=-1 AND pattern_key IN ('index','postgres','edge50')\").fetchone()[0])" "$DB")"

echo "[d] 일반 코드 단어 키는 결정화 전에 거부, 모델 미호출"
python3 -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute(\"INSERT OR REPLACE INTO pattern_count (pattern_key,count,crystallized) VALUES ('shared',3,0)\");c.commit()" "$DB"
OUT=$(python3 "$S/hermes-crystallize.py" --db "$DB" --crystallize shared --project-dir "$P" 2>&1)
assert "REJECT 출력" "1" "$(grep -c 'REJECT:shared' <<<"$OUT")"
assert "가짜 claude 미호출" "0" "$(cat "$T/claude-called" 2>/dev/null | wc -l | tr -d ' ')"
assert "crystallized=-1" "-1" "$(python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(\"SELECT crystallized FROM pattern_count WHERE pattern_key='shared'\").fetchone()[0])" "$DB")"
assert "일반 단어 아닌 키(jira-comment-approval-gate)는 통과" "0" "$(python3 - "$S" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("y", sys.argv[1] + "/hermes_skill_yield.py"); y = importlib.util.module_from_spec(spec); spec.loader.exec_module(y)
print(int(y.is_generic_key("jira-comment-approval-gate")) + int(y.is_generic_key("noticemanagementpage")))
PY
)"

echo "[e] 표준 라이브러리만"
assert "hermes_* import 없음" "0" "$(grep -cE '^(import|from) hermes' "$S/hermes_skill_yield.py"; true)"

echo; echo "skill-yield: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
