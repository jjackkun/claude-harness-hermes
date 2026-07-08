#!/usr/bin/env bash
# 헤르메스 스킬 재활용 측정 루프 회귀 테스트
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DB="$TMP/.hermes/state.db"

# --- Task1: 스키마 ---
python3 "$SCRIPTS/hermes-init.py" --both "$TMP" >/dev/null 2>&1
schema_check() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
tabs = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
assert "skill_injection" in tabs, "skill_injection 테이블 없음"
cols = {r[1] for r in con.execute("PRAGMA table_info(skill_index)")}
for c in ("helpful_count","noop_count","last_helpful_at","state","demoted_at"):
    assert c in cols, f"{c} 컬럼 없음"
icols = {r[1] for r in con.execute("PRAGMA table_info(skill_injection)")}
for c in ("session_id","skill_path","injected_at","correlated"):
    assert c in icols, f"skill_injection.{c} 없음"
print("OK")
PY
}
if schema_check 2>/dev/null | grep -q OK; then ok "스키마: skill_injection + skill_index 컬럼 5개"; else nope "스키마"; fi

# --- Task2: 공유 헬퍼 ---
SK="$TMP/skills"; mkdir -p "$SK/folderskill"
printf '%s\n' '# baseinput' '' '## 트리거' '`BaseInput` 컴포넌트' > "$SK/flatone.md"
printf '%s\n' '---' 'name: x' '---' '# folderskill title' '`v-model` 패턴' > "$SK/folderskill/SKILL.md"
# 드림 자동생성 스타일: 제목은 영문 슬러그, 한글은 문제 상황·규칙 섹션에 있음(①)
printf '%s\n' '# token-ttl-auth-layer-issue' '' '## 문제 상황' '백오피스 API 호출 시 토큰 없으면 401 인증 에러' '' '## 규칙' '- [ ] 요청에 Bearer 토큰 포함' > "$SK/token-ttl-auth-layer-issue.md"
helper_check() {
PYTHONPATH="$SCRIPTS" python3 - "$SK" <<'PY'
import sys, os, hermes_skills as h
names = {n for n, _ in h.iter_skill_files(sys.argv[1])}
assert names == {"flatone", "folderskill", "token-ttl-auth-layer-issue"}, names
kws = h.extract_keywords(os.path.join(sys.argv[1], "flatone.md"))
assert "baseinput" in kws, kws
# ① 드림 스킬: 영문 제목뿐이라도 한글 본문 키워드가 색인돼야 한다
dkws = h.extract_keywords(os.path.join(sys.argv[1], "token-ttl-auth-layer-issue.md"))
assert "토큰" in dkws and "인증" in dkws, dkws
print("OK")
PY
}
if helper_check 2>/dev/null | grep -q OK; then ok "공유 헬퍼: 평면+폴더 순회·키워드(드림 한글 섹션 포함)"; else nope "공유 헬퍼"; fi

# --- Task3: 인덱싱 통일 (평면 .md 포함) ---
python3 "$SCRIPTS/hermes-index-skills.py" --db "$DB" --skills-dir "$SK" --scope local >/dev/null 2>&1
index_check() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
paths = [r[0] for r in con.execute("SELECT skill_path FROM skill_index")]
flat = [p for p in paths if p.endswith("flatone.md")]
folder = [p for p in paths if p.endswith("folderskill/SKILL.md")]
assert flat, "평면 스킬 미인덱싱"
assert folder, "폴더 스킬 미인덱싱"
print("OK")
PY
}
if index_check 2>/dev/null | grep -q OK; then ok "인덱싱: 평면+폴더 둘 다 등록"; else nope "인덱싱"; fi

# --- Task4: 주입 원장 ---
# flatone 스킬이 'baseinput' 키워드로 검색되도록 질의
python3 "$SCRIPTS/hermes-search.py" --db "$DB" --query "baseinput 만들고 싶어" \
  --session-id "sess-A" --max 3 >/dev/null 2>&1
ledger_check() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
n = con.execute("SELECT COUNT(*) FROM skill_injection WHERE session_id='sess-A'").fetchone()[0]
assert n >= 1, f"원장 기록 없음 (n={n})"
print("OK")
PY
}
if ledger_check 2>/dev/null | grep -q OK; then ok "주입 원장: 검색 시 skill_injection 기록"; else nope "주입 원장"; fi

# 랭킹: 톰브스톤 스킬은 검색에서 제외 (heredoc 안에서 $DB 전개되도록 따옴표 없는 PY 구분자)
python3 - <<PY
import sqlite3
con = sqlite3.connect("$DB")
con.execute("UPDATE skill_index SET state='tombstoned' WHERE skill_path LIKE '%flatone.md'")
con.commit()
PY
out=$(python3 "$SCRIPTS/hermes-search.py" --db "$DB" --query "baseinput" --session-id "sess-B" --max 3 2>/dev/null)
if ! grep -q "flatone" <<<"$out"; then ok "랭킹: 톰브스톤 스킬 검색 제외"; else nope "랭킹 톰브스톤 제외"; fi

# ② 관련도 우선 랭킹 — 매칭 많은 신규(used=0) 스킬이 매칭 적은 고사용 스킬을 앞선다(콜드스타트 구제)
python3 - <<PY
import sqlite3
con = sqlite3.connect("$DB")
con.execute("INSERT INTO skill_index (skill_path,keywords,scope,used_count,helpful_count,state) VALUES ('$SK/cold-rel.md','토큰,인증,token','local',0,0,'active')")
con.execute("INSERT INTO skill_index (skill_path,keywords,scope,used_count,helpful_count,state) VALUES ('$SK/hot-irrel.md','토큰,foo','local',50,0,'active')")
con.commit()
PY
rank_check() {
PYTHONPATH="$SCRIPTS" python3 - "$DB" "$SCRIPTS" <<'PY'
import sys, importlib.util, os
spec=importlib.util.spec_from_file_location("hs", os.path.join(sys.argv[2],"hermes-search.py"))
hs=importlib.util.module_from_spec(spec); spec.loader.exec_module(hs)
res=hs.search_db(sys.argv[1], ["토큰","인증"], 5)
paths=[r["path"] for r in res]
ci=next(i for i,p in enumerate(paths) if p.endswith("cold-rel.md"))
hi=next(i for i,p in enumerate(paths) if p.endswith("hot-irrel.md"))
assert ci < hi, (ci, hi, paths)   # 관련도 2인 신규(cold)가 관련도 1인 고사용(hot)보다 앞
print("OK")
PY
}
if rank_check 2>/dev/null | grep -q OK; then ok "랭킹: 관련도 우선 — 신규 고관련 스킬 콜드스타트 구제"; else nope "랭킹 관련도 우선"; fi

# --- Task5: 결과 상관 ---
# 픽스처: flatone(키워드 baseinput·컴포넌트) 을 sess-C 에 주입했다고 원장에 심고,
# transcript 에 BaseInput.vue 편집 이벤트를 넣는다 → helpful_count 증가 기대.
python3 - <<PY
import sqlite3
con = sqlite3.connect("$DB")
con.execute("INSERT INTO skill_injection (session_id, skill_path) VALUES ('sess-C', (SELECT skill_path FROM skill_index WHERE skill_path LIKE '%flatone.md'))")
con.execute("UPDATE skill_index SET state='active' WHERE skill_path LIKE '%flatone.md'")
con.commit()
PY
TR="$TMP/transcript.jsonl"
cat > "$TR" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/proj/src/컴포넌트/BaseInput.vue"}}]}}
JSONL
python3 "$SCRIPTS/hermes-correlate.py" --db "$DB" --transcript "$TR" --session-id "sess-C" >/dev/null 2>&1
corr_check() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
h = con.execute("SELECT helpful_count FROM skill_index WHERE skill_path LIKE '%flatone.md'").fetchone()[0]
c = con.execute("SELECT correlated FROM skill_injection WHERE session_id='sess-C'").fetchone()[0]
assert h >= 1, f"helpful_count 미증가 (h={h})"
assert c == 1, "원장 correlated 미표시"
print("OK")
PY
}
if corr_check 2>/dev/null | grep -q OK; then ok "결과 상관: 편집경로↔키워드 겹침 → helpful"; else nope "결과 상관"; fi

# --- Task6: 정리 (강등/톰브스톤) ---
python3 - <<PY
import sqlite3
con = sqlite3.connect("$DB")
# 강등 후보: noop 5, helpful 0
con.execute("INSERT INTO skill_index (skill_path, keywords, scope, noop_count, helpful_count, state) VALUES ('$SK/demoteme.md','x','local',5,0,'active')")
# 톰브스톤 후보: 이미 demoted, 20일 전 강등, helpful 없음
con.execute("INSERT INTO skill_index (skill_path, keywords, scope, noop_count, helpful_count, state, demoted_at) VALUES ('$SK/tombme.md','y','local',9,0,'demoted', datetime('now','-20 days'))")
con.commit()
PY
printf '# demoteme\n' > "$SK/demoteme.md"; printf '# tombme\n' > "$SK/tombme.md"
python3 "$SCRIPTS/hermes-prune.py" --db "$DB" >/dev/null 2>&1
prune_check() {
python3 - "$DB" "$SK" <<'PY'
import sqlite3, sys, os
con = sqlite3.connect(sys.argv[1])
d = con.execute("SELECT state FROM skill_index WHERE skill_path LIKE '%demoteme.md'").fetchone()[0]
t = con.execute("SELECT state FROM skill_index WHERE skill_path LIKE '%tombme.md'").fetchone()[0]
assert d == "demoted", f"강등 안 됨 ({d})"
assert t == "tombstoned", f"톰브스톤 안 됨 ({t})"
assert os.path.isfile(os.path.join(sys.argv[2], "tombme.md")), "파일이 삭제됨(금지)"
print("OK")
PY
}
if prune_check 2>/dev/null | grep -q OK; then ok "정리: 강등→톰브스톤, 파일 보존"; else nope "정리"; fi

# --- Task7: 설치 배선 ---
CONF="$ROOT/presets/workflow/hermes.conf"
HOOK="$ROOT/assets/hooks/claude-stop-retrospective.sh"
wiring_ok=1
for s in hermes_skills.py hermes-correlate.py hermes-prune.py; do
  grep -q "$s" "$CONF" || wiring_ok=0
done
grep -q "hermes-correlate.py" "$HOOK" || wiring_ok=0
grep -q "hermes-prune.py" "$HOOK" || wiring_ok=0
if [[ $wiring_ok -eq 1 ]]; then ok "설치 배선: conf 복사목록 + Stop 훅 호출"; else nope "설치 배선"; fi

echo "통과:$PASS 실패:$FAIL"
[[ $FAIL -eq 0 ]]
