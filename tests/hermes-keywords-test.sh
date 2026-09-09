#!/usr/bin/env bash
# 키워드 채점 테스트 — hermes_keywords(IDF) + 검색 매칭·순위.
#
# 배경: extract_keywords 에 불용어 필터가 없어 `확인` 이 zeroday 전체 스킬의 67%,
# `api` 42% 에 붙었다. 매칭 수만 세면 흔한 말 한 번 맞은 것과 `basebutton`(5개)
# 한 번 맞은 것이 동점이 된다.
# 근거: docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md §7
#
# 실행: bash tests/hermes-keywords-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "== 1. 채점 모듈 =="
out=$(python3 - "$REPO_ROOT" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("kw", sys.argv[1] + "/scripts/hermes_keywords.py")
kw = importlib.util.module_from_spec(spec); spec.loader.exec_module(kw)

print("tokens:", ",".join(kw.split_keywords("A, b\tC")))
print("none:", len(kw.split_keywords(None)))

# 10개 문서 중 '확인' 은 10개, 'rare' 는 1개
sets = [{"확인", "공통"} | ({"rare"} if i == 0 else set()) for i in range(10)]
df = kw.document_frequency(sets)
print("df:", df["확인"], df["rare"])

common = kw.idf_score(["확인"], df, 10)
rare = kw.idf_score(["rare"], df, 10)
print("common0:", "yes" if abs(common) < 1e-9 else "no")
print("rare_beats_common:", "yes" if rare > common else "no")
# 흔한 말을 여러 개 맞춰도 드문 말 하나를 못 이긴다
print("rare_beats_many:", "yes" if rare > kw.idf_score(["확인", "공통"], df, 10) else "no")
print("total0:", kw.idf_score(["rare"], df, 0))
EOF
)
assert "토큰 분해"                    "tokens: a,b,c" "$(echo "$out" | sed -n 1p)"
assert "문자열이 아니면 빈 목록"        "none: 0"       "$(echo "$out" | sed -n 2p)"
assert "문서빈도를 센다"               "df: 10 1"      "$(echo "$out" | sed -n 3p)"
assert "모든 문서에 있는 말은 0점"      "common0: yes"  "$(echo "$out" | sed -n 4p)"
assert "드문 말이 흔한 말을 이긴다"     "rare_beats_common: yes" "$(echo "$out" | sed -n 5p)"
assert "드문 말 하나가 흔한 말 여럿을 이긴다" "rare_beats_many: yes" "$(echo "$out" | sed -n 6p)"
assert "코퍼스가 0이면 0점"            "total0: 0.0"   "$(echo "$out" | sed -n 7p)"

echo "== 2. 도메인 어휘를 하드코딩하지 않는다 =="
# 주석·독스트링의 어휘는 근거 서술이므로 제외한다 — 규칙은 *로직*에 대한 것이다.
hits=$(python3 - "$REPO_ROOT/scripts/hermes_keywords.py" <<'EOF'
import ast, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
# 독스트링을 제거한 뒤 남는 코드만 본다.
for node in ast.walk(tree):
    if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        body = getattr(node, "body", [])
        if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                and isinstance(body[0].value.value, str):
            body.pop(0)
code = ast.unparse(tree)
pat = r"(pnpm|yarn|poetry|fastapi|svelte|postgres|redis|pytest|eslint|swagger|jira|figma)"
print(len(re.findall(pat, code, re.I)))
EOF
)
assert "채점 로직에 도메인 어휘 없음" "0" "$hits"

echo "== 3. 검색 매칭·순위 =="
out=$(python3 - "$REPO_ROOT" "$TMP" <<'EOF'
import importlib.util, os, sqlite3, sys
root, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, root + "/scripts")
spec = importlib.util.spec_from_file_location("hs", root + "/scripts/hermes-search.py")
hs = importlib.util.module_from_spec(spec); spec.loader.exec_module(hs)

db = os.path.join(tmp, "match.db")
c = sqlite3.connect(db)
c.execute("CREATE TABLE skill_index (skill_path TEXT PRIMARY KEY, keywords TEXT, "
          "helpful_count INT DEFAULT 0, used_count INT DEFAULT 0, state TEXT)")
# '확인' 은 전부에, 'basebutton' 은 두 곳에만. basebutton.md 는 이름까지 같다.
c.execute("INSERT INTO skill_index VALUES ('/other.md','확인,잡토큰',0,0,'active')")
c.execute("INSERT INTO skill_index VALUES ('/aaa.md','확인,basebutton',0,0,'active')")
c.execute("INSERT INTO skill_index VALUES ('/basebutton.md','확인,basebutton',0,0,'active')")
c.execute("INSERT INTO skill_index VALUES ('/확인해.md','확인해,잡토큰2',0,0,'active')")
c.commit(); c.close()

r = hs.search_db(db, ["basebutton", "확인"], 3)
print("top:", os.path.basename(r[0]["path"]) if r else "-")
print("hits:", ",".join(sorted(os.path.basename(x["path"]) for x in r)))

# 흔한 말만 있는 질의도 결과는 준다 — 지우지 않고 점수만 낮추기 때문
print("common_only:", len(hs.search_db(db, ["확인"], 3)))

d = os.path.join(tmp, "skills")
for n, body in (("aa", "토큰1"), ("zz", "토큰1 토큰2")):
    os.makedirs(f"{d}/{n}", exist_ok=True)
    open(f"{d}/{n}/SKILL.md", "w", encoding="utf-8").write(f"# {n}\n{body}\n")
res = hs.search_skills_dir(d, ["토큰1", "토큰2"], 5)
print("order:", ",".join(x["name"] for x in res))
EOF
)
assert "이름이 같은 스킬이 1위"            "top: basebutton.md" "$(echo "$out" | sed -n 1p)"
assert "부분 문자열로 걸리지 않는다 (확인 ≠ 확인해)" \
  "hits: aaa.md,basebutton.md,other.md" "$(echo "$out" | sed -n 2p)"
assert "흔한 말만 있어도 결과는 나온다 (지우지 않는다)" "common_only: 3" "$(echo "$out" | sed -n 3p)"
assert "디렉터리 검색도 희소성으로 정렬"    "order: zz,aa" "$(echo "$out" | sed -n 4p)"

echo "== 4. 프롬프트 경로는 claude -p 폴백을 켜지 않는다 =="
hook="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh"
grep -q -- '--no-fallback' "$hook" && r=yes || r=no
assert "reminders 훅에 --no-fallback 이 있다" "yes" "$r"
assert "폴백은 별도 모듈이 소유한다" "yes" \
  "$([[ -f "$REPO_ROOT/scripts/hermes_search_fallback.py" ]] && echo yes || echo no)"

echo "== 5. 이름 가산은 흔한 말에서 순위를 뒤집지 못한다 =="
out=$(python3 - "$REPO_ROOT" "$TMP" <<'EOF'
import importlib.util, os, sqlite3, sys
root, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, root + "/scripts")
spec = importlib.util.spec_from_file_location("hs", root + "/scripts/hermes-search.py")
hs = importlib.util.module_from_spec(spec); spec.loader.exec_module(hs)

db = os.path.join(tmp, "bonus.db")
c = sqlite3.connect(db)
c.execute("CREATE TABLE skill_index (skill_path TEXT PRIMARY KEY, keywords TEXT, "
          "helpful_count INT DEFAULT 0, used_count INT DEFAULT 0, state TEXT)")
# 점수가 실제로 갈리도록 짠 픽스처다.
#   common : 9/10 문서 → idf = log(10/9) = 0.105
#   mid    : 5/10 문서 → idf = log(10/5) = 0.693
# 이름이 'common' 인 스킬은 흔한 말 하나만 맞춘다.
#   비례 가산: common.md 는 0.105 + 0.105 = 0.21 에 그쳐,
#              둘 다 맞춘 f0.md(0.105 + 0.693 = 0.798)가 1위가 된다
#   고정 가산: common.md 가 0.105 + 1.0 = 1.105 로 뛰어 1위를 가로챈다(잡아야 할 회귀)
for i in range(8):
    kws = "common," + ("mid," if i < 4 else "") + "잡%d" % i
    c.execute("INSERT INTO skill_index VALUES (?,?,0,0,'active')", (f"/f{i}.md", kws))
c.execute("INSERT INTO skill_index VALUES ('/common.md','common,잡x',0,0,'active')")
c.execute("INSERT INTO skill_index VALUES ('/real.md','mid,잡y',0,0,'active')")
c.commit(); c.close()

r = hs.search_db(db, ["common", "mid"], 3)
print("top:", os.path.basename(r[0]["path"]) if r else "-")
EOF
)
assert "이름이 흔한 말과 같다고 1위가 되지 않는다" "top: f0.md" "$(echo "$out" | sed -n 1p)"

echo "== 6. 훅 로그가 주입/무주입을 구별한다 (0건 비율 측정 근거) =="
LOGDIR="$TMP/logproj"; mkdir -p "$LOGDIR/.hermes" "$LOGDIR/scripts/hooks" "$LOGDIR/.claude/skills"
cp "$REPO_ROOT"/scripts/hermes*.py "$LOGDIR/scripts/" 2>/dev/null
cp "$REPO_ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh" "$LOGDIR/scripts/hooks/"
python3 - "$LOGDIR" <<'EOF'
import sqlite3, sys, os
db = os.path.join(sys.argv[1], ".hermes", "state.db")
c = sqlite3.connect(db)
c.execute("CREATE TABLE skill_index (skill_path TEXT PRIMARY KEY, keywords TEXT, "
          "helpful_count INT DEFAULT 0, used_count INT DEFAULT 0, state TEXT)")
c.execute("CREATE TABLE skill_injection (id INTEGER PRIMARY KEY, session_id TEXT, "
          "skill_path TEXT, injected_at DATETIME DEFAULT CURRENT_TIMESTAMP, "
          "correlated INT DEFAULT 0, source TEXT DEFAULT 'prompt')")
p = os.path.join(sys.argv[1], ".hermes", "skills")
os.makedirs(p, exist_ok=True)
open(os.path.join(p, "고유토큰.md"), "w", encoding="utf-8").write("# 고유토큰\\n내용\\n")
c.execute("INSERT INTO skill_index VALUES ('%s','고유토큰',0,0,'active')" % os.path.join(p, "고유토큰.md"))
c.commit()
EOF
run_hook() { echo "$1" | CLAUDE_PROJECT_DIR="$LOGDIR" bash "$LOGDIR/scripts/hooks/claude-userpromptsubmit-reminders.sh" >/dev/null 2>&1; }
: > "$LOGDIR/.hermes/hooks.log"
run_hook '{"prompt":"고유토큰 알려줘","session_id":"s1"}'
run_hook '{"prompt":"zzqqxxnomatch 어쩌구","session_id":"s2"}'
inj=$(grep -c 'injected bytes=' "$LOGDIR/.hermes/hooks.log" || true)
emp=$(grep -c 'empty rc=' "$LOGDIR/.hermes/hooks.log" || true)
assert "주입된 턴이 로그에 남는다"   "1" "$inj"
assert "무주입 턴도 로그에 남는다"   "1" "$emp"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
