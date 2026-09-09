#!/usr/bin/env bash
# 진화 대상 어휘 테스트 — 코드에 박은 기술어 목록 대신 프로젝트 자기 코퍼스를 쓴다.
#
# 배경: `_SKILL_KW_RE` 가 pnpm·svelte 등 18개를 박아 두어, 그 목록에 없는 도메인은
# 진화가 영원히 0이었다(novel-bc 진화율 0%). 목록을 걷어내면 그것이 사실상 하던
# 상한 노릇도 사라지므로 명시적 상한이 필요하다.
# 근거: docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md 목표 3
#
# 실행: bash tests/hermes-evolve-vocab-test.sh
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

echo "== 1. 도메인 어휘를 로직에 박지 않는다 =="
# 주석·독스트링은 근거 서술이므로 제외한다 — 규칙은 *로직*에 대한 것이다.
hits=$(python3 - "$REPO_ROOT/scripts/hermes-dream.py" "$REPO_ROOT/scripts/hermes_dream_evolve.py" <<'EOF'
import ast, re, sys
pat = r"(pnpm|yarn|poetry|fastapi|svelte|postgres|mysql|redis|pytest|vitest|eslint|prettier|ruff|mypy)"
total = 0
for path in sys.argv[1:]:
    tree = ast.parse(open(path, encoding="utf-8").read())
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
            body.pop(0)
    total += len(re.findall(pat, ast.unparse(tree), re.I))
print(total)
EOF
)
assert "dream·진화 로직에 기술어 목록 없음" "0" "$hits"

echo "== 2. 후보는 스킬 이름 토큰으로 좁힌다 =="
out=$(python3 - "$REPO_ROOT" "$TMP" <<'EOF'
import importlib.util, os, sqlite3, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
proj = os.path.join(tmp, "p1"); os.makedirs(proj, exist_ok=True)
subprocess.run(["python3", root + "/scripts/hermes-init.py", "--project", proj],
               capture_output=True)
db = os.path.join(proj, ".hermes", "state.db")
c = sqlite3.connect(db)
# 이름은 'kiosk', 본문 키워드에만 '본문전용어' 가 있다.
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES (?,?,'local')",
          ("/s/kiosk.md", "kiosk,본문전용어,공통"))
# 이름이 숫자뿐인 스킬 — 일련번호는 주제가 아니므로 후보에서 빠져야 한다.
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES (?,?,'local')",
          ("/s/3.md", "3,공통"))
c.commit()

sys.path.insert(0, root + "/scripts")
spec = importlib.util.spec_from_file_location("dr", root + "/scripts/hermes_dream_evolve.py")
dr = importlib.util.module_from_spec(spec); spec.loader.exec_module(dr)
df = dr.skill_name_frequency(c)
print("names:", ",".join(sorted(df)))

def hints(text):
    return dr.collect_evolution_hints([{"slots": {"open": [text]}}], df)

print("name_hit:", [k for k, _ in hints("kiosk 말고 다른 걸로 바꿔")])
print("body_only:", [k for k, _ in hints("본문전용어 말고 다른 걸로 바꿔")])
print("no_correction:", [k for k, _ in hints("kiosk 화면 구현")])
EOF
)
assert "숫자만인 이름 토큰은 후보가 아니다" "names: kiosk" "$(echo "$out" | sed -n 1p)"
assert "이름 토큰이면 힌트가 나온다"        "name_hit: ['kiosk']" "$(echo "$out" | sed -n 2p)"
assert "본문에만 있는 말은 후보가 아니다"   "body_only: []"       "$(echo "$out" | sed -n 3p)"
assert "교정 문장이 아니면 힌트 없음"       "no_correction: []"   "$(echo "$out" | sed -n 4p)"

echo "== 3. 상한과 중복 제거 =="
out=$(HERMES_DREAM_EVOLVE_MAX=2 python3 - "$REPO_ROOT" "$TMP" 2>"$TMP/cap.err" <<'EOF'
import importlib.util, os, sqlite3, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
proj = os.path.join(tmp, "p2"); os.makedirs(proj, exist_ok=True)
subprocess.run(["python3", root + "/scripts/hermes-init.py", "--project", proj],
               capture_output=True)
db = os.path.join(proj, ".hermes", "state.db")
c = sqlite3.connect(db)
# aaa 는 1개 스킬(구체적), ccc 는 3개(덜 구체적)
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/aaa.md','aaa','local')")
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/bbb.md','bbb,ccc','local')")
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/bbb2.md','bbb,ccc','local')")
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/ccc.md','ccc','local')")
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/ddd.md','ddd,ccc','local')")
c.commit()

sys.path.insert(0, root + "/scripts")
spec = importlib.util.spec_from_file_location("dr", root + "/scripts/hermes_dream_evolve.py")
dr = importlib.util.module_from_spec(spec); spec.loader.exec_module(dr)
df = dr.skill_name_frequency(c)
items = ["ccc 말고 다른 걸로", "bbb 말고 다른 걸로", "aaa 말고 다른 걸로",
         "aaa 를 또 수정해야 한다"]
h = dr.collect_evolution_hints([{"slots": {"open": items}}], df)
print("max:", dr.EVOLVE_MAX)
print("picked:", [k for k, _ in h])
EOF
)
assert "환경변수로 상한을 바꾼다"            "max: 2" "$(echo "$out" | sed -n 1p)"
assert "구체적인 것부터 상한만큼, 중복 없음" "picked: ['aaa', 'bbb']" "$(echo "$out" | sed -n 2p)"
grep -q '상한' "$TMP/cap.err" && r=yes || r=no
assert "상한에 걸려 버린 사실을 로그로 남긴다 (조용한 손실 금지)" "yes" "$r"

echo "== 4. 진화 대상 조회가 토큰 일치다 =="
out=$(python3 - "$REPO_ROOT" "$TMP" <<'EOF'
import importlib.util, os, sqlite3, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
proj = os.path.join(tmp, "p3"); os.makedirs(proj, exist_ok=True)
subprocess.run(["python3", root + "/scripts/hermes-init.py", "--project", proj],
               capture_output=True)
db = os.path.join(proj, ".hermes", "state.db")
c = sqlite3.connect(db)
# 'api' 를 토큰으로 가진 스킬 둘 — 키워드가 적은 쪽이 그 주제일 가능성이 크다.
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/wide.md','api,a,b,c,d,e','local')")
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/narrow.md','api,a','local')")
# 부분 문자열이면 걸리지만 토큰 일치면 안 걸려야 하는 것
c.execute("INSERT INTO skill_index (skill_path, keywords, scope) VALUES ('/s/sub.md','apikey','local')")
c.commit(); c.close()

sys.path.insert(0, root + "/scripts")
spec = importlib.util.spec_from_file_location("ev", root + "/scripts/hermes-evolve-skill.py")
ev = importlib.util.module_from_spec(spec); spec.loader.exec_module(ev)
row = ev.find_skill_by_keyword(db, "api")
print("pick:", os.path.basename(row[0]) if row else "-")
print("substr:", "hit" if ev.find_skill_by_keyword(db, "apike") else "miss")
EOF
)
assert "키워드가 가장 적은 스킬을 고른다" "pick: narrow.md" "$(echo "$out" | sed -n 1p)"
assert "부분 문자열로는 걸리지 않는다"    "substr: miss"    "$(echo "$out" | sed -n 2p)"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
