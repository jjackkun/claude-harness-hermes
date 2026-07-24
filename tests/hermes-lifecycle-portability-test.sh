#!/usr/bin/env bash
# 헤르메스 생애주기 압축 — 이식성(다기계) 방어 테스트 (Part D 섹션 7 분리)
#
# 압축은 기계-로컬이다: 기계 A 가 압축·push 해도 기계 B 의 DB 는 원문 그대로다.
# 이 파일은 그 발산이 (1) 침묵 고착되지 않고 (2) 전량 export 로 되돌아가지 않으며
# (3) 압축 세션을 재개했을 때 신규 대화가 갇히지 않음을 검증한다.
#
# hermes-lifecycle-test.sh 에서 분리(파일 크기 하드리밋). 헬퍼는 의도적으로 복제한다
# — 테스트 파일은 각각 독립 실행 가능해야 한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_mock() {   # $1=bin 디렉터리, $2=본문 스크립트
  mkdir -p "$1"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$2"; } > "$1/claude"
  chmod +x "$1/claude"
}

# 픽스처 생성기: 오래됨(200일)+미재활용+결정화 세션 1건 (파일 N줄 ⟺ DB N행)
cat > "$TMP/apply-fixture.py" <<'PY'
import sqlite3, sys, os, json
from datetime import datetime, timedelta
sys.path.insert(0, os.environ["SCRIPTS"])
import hermes_reuse as r
db, hist, sid, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
con = sqlite3.connect(db)
r.ensure_reuse_table(con)
con.execute("UPDATE session_reuse SET last_reused_at=? WHERE session_id='__epoch__'",
            ((datetime.now() - timedelta(days=200)).isoformat(),))
day = (datetime.now() - timedelta(days=200)).strftime("%Y-%m-%d")
ts = day + "T10:00:00.000000"
path = os.path.join(hist, "%s-%s.jsonl" % (day, sid))
with open(path, "w", encoding="utf-8") as f:
    for i in range(n):
        row = {"seq": i, "session_id": sid, "project_id": "PA", "role": "user",
               "timestamp": ts, "content": "대화 %s-%d" % (sid, i)}
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
        con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                    "VALUES (?,?,?,?,?)", (row["content"], "user", ts, "PA", sid))
con.execute("INSERT OR REPLACE INTO session_summary (session_id, project_id, slots_json) "
            "VALUES (?,?,?)", (sid, "PA", json.dumps({"decisions": ["%s 결정" % sid]},
                                                     ensure_ascii=False)))
key = "pat-" + sid
con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count, crystallized) "
            "VALUES (?,3,1)", (key,))
con.execute("INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) VALUES (?,?)",
            (key, sid))
con.commit()
print(path)
PY

mk_project() {   # $1=프로젝트 경로
  python3 "$SCRIPTS/hermes-init.py" --both "$1" >/dev/null 2>&1
  mkdir -p "$1/.hermes/history"
  git -c init.defaultBranch=main init -q "$1" 2>/dev/null
}
commit_hist() {  # $1=프로젝트 경로
  git -C "$1" add .hermes/history >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm "history" >/dev/null 2>&1
}
fixture5() {     # $1=db $2=hist $3=sid $4=행수 → 파일 경로 출력
  SCRIPTS="$SCRIPTS" python3 "$TMP/apply-fixture.py" "$1" "$2" "$3" "$4"
}
rows_of() {      # $1=db $2=sid
python3 - "$1" "$2" <<'PY'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute(
    "SELECT COUNT(*) FROM session_history WHERE session_id=?", (sys.argv[2],)).fetchone()[0])
PY
}
lines_of() { wc -l < "$1" 2>/dev/null | tr -d ' '; }
is_compacted() {   # 요약본 JSONL 1줄인가 (compacted:true + orig_lines)
python3 - "$1" <<'PY'
import json, sys
try:
    lines = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
    o = json.loads(lines[0])
    print("YES" if len(lines) == 1 and o.get("compacted") is True
          and o.get("orig_lines") and o.get("role") == "system" else "NO")
except Exception as e:
    print("NO(%s)" % e)
PY
}

echo "── 압축의 기계-로컬성 방어 (다기계 발산·전량 export 되돌림·재개) ──"

# 압축은 기계-로컬이다: 기계 A 가 압축·push 해도 기계 B 의 DB 는 원문 그대로다.
# 그 발산 상태에서 (1) 재색인 훅이 "in-sync" 로 오기록하면 침묵 고착되고,
# (2) 전량 export 1회로 압축이 fleet 전체에서 되돌아간다.

RHOOK="$ROOT/assets/hooks/claude-sessionstart-history-reindex.sh"
total_rows() {   # $1=db → session_history 전체 행수
python3 - "$1" <<'PY'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM session_history").fetchone()[0])
PY
}

# ── 기계 A: 후보 2세션을 압축(파일 1행 ⟺ DB 1행)한 뒤 커밋 ──────────────────
MA="$TMP/m-a"; MADB="$MA/.hermes/state.db"; MAH="$MA/.hermes/history"
mk_project "$MA"
FGA="$(fixture5 "$MADB" "$MAH" g-a 5)"
FGB="$(fixture5 "$MADB" "$MAH" g-b 5)"
commit_hist "$MA"
mk_mock "$TMP/bin-s7" '
cat <<JSON
[{"topic":"기계A 압축","session_ids":["g-a","g-b"],"summary":"두 세션의 공통 결론"}]
JSON
exit 0'
PATH="$TMP/bin-s7:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" \
  --db "$MADB" --project "$MA" --propose --age-days 90 >/dev/null 2>&1
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$MADB" --project "$MA" --apply \
  >/dev/null 2>"$TMP/s7-apply.err"
if [[ "$(lines_of "$FGA")" == "1" && "$(rows_of "$MADB" g-a)" == "1" &&
      "$(lines_of "$FGB")" == "1" && "$(rows_of "$MADB" g-b)" == "1" ]]; then
  ok "전제(G) 기계A: 2세션 압축 완료(파일 1행 ⟺ DB 1행)"
else
  nope "전제(G) 기계A 압축 실패 (a=$(lines_of "$FGA")/$(rows_of "$MADB" g-a) b=$(lines_of "$FGB")/$(rows_of "$MADB" g-b))"
fi
commit_hist "$MA"

# ── 기계 B: 압축 전 상태(원문 5행씩)로 DB 구성 → pull 로 압축본 파일만 도착 ──
MB="$TMP/m-b"; MBDB="$MB/.hermes/state.db"; MBH="$MB/.hermes/history"
mk_project "$MB"
FGBA="$(fixture5 "$MBDB" "$MBH" g-a 5)"
fixture5 "$MBDB" "$MBH" g-b 5 >/dev/null
commit_hist "$MB"
cp "$MAH"/*.jsonl "$MBH"/                      # pull 시뮬 — 압축본이 원문 파일 대체
if [[ "$(lines_of "$FGBA")" == "1" && "$(total_rows "$MBDB")" == "10" ]]; then
  ok "전제(G1) 기계B: pull 후 발산 — 파일 1행씩(총 2행) vs DB 10행"
else
  nope "전제(G1) 발산 미재현 (file=$(lines_of "$FGBA") dbtotal=$(total_rows "$MBDB"))"
fi

# ── (G1) 재색인 훅이 발산을 skip:diverged 로 분리 분류 + --force 안내 ────────
RLOG="$MB/.hermes/hooks.log"; rm -f "$RLOG"
out_g1="$(printf '%s' '{"source":"startup"}' | \
  env CLAUDE_PROJECT_DIR="$MB" bash "$RHOOK" 2>/dev/null)"
sleep 1
if [[ -z "$out_g1" ]]; then ok "(G1) 훅 stdout 무출력"; else nope "(G1) stdout 오염 ('$out_g1')"; fi
if grep -q "skip:diverged" "$RLOG" 2>/dev/null; then
  ok "(G1) 발산을 skip:diverged 로 분리 분류"
else
  nope "(G1) 발산이 in-sync 로 오기록됨 — 침묵 고착 (log='$(tr '\n' ' ' < "$RLOG" 2>/dev/null)')"
fi
if grep -q "skip:in-sync" "$RLOG" 2>/dev/null; then
  nope "(G1) 발산인데 in-sync 도 기록됨"
else
  ok "(G1) in-sync 오기록 없음"
fi
if grep -q "skip:diverged:compacted" "$RLOG" 2>/dev/null; then
  ok "(G1) 발산 사유를 compacted 로 세분 분류"
else
  nope "(G1) 압축 발산인데 하위 사유 미분류 (log='$(tr '\n' ' ' < "$RLOG" 2>/dev/null)')"
fi
if grep -q "전역" "$RLOG" 2>/dev/null; then
  ok "(G1) --force 안내에 '전역이라 다른 세션도 덮어쓴다' 경고 동반"
else
  nope "(G1) --force 전역 경고 없음 (log='$(tr '\n' ' ' < "$RLOG" 2>/dev/null)')"
fi
if grep -q -- "--force" "$RLOG" 2>/dev/null && grep -q "hermes-reindex" "$RLOG" 2>/dev/null; then
  ok "(G1) 해결 안내가 reindex --force(파일→DB) 방향"
else
  nope "(G1) --force 해결 안내 없음 (log='$(tr '\n' ' ' < "$RLOG" 2>/dev/null)')"
fi
if grep -q "hermes-export-history" "$RLOG" 2>/dev/null; then
  nope "(G1) 안내에 export(DB→파일) 방향 포함 — 압축을 되돌리는 방향"
else
  ok "(G1) 안내에 export(DB→파일) 방향 없음"
fi
if [[ "$(total_rows "$MBDB")" == "10" && "$(lines_of "$FGBA")" == "1" ]]; then
  ok "(G1) 자동 복구 없음 — 훅은 로그 안내까지만(DB·파일 불변)"
else
  nope "(G1) 훅이 자동으로 DB/파일을 바꿈 (dbtotal=$(total_rows "$MBDB") file=$(lines_of "$FGBA"))"
fi

# ── (G2) 전량 export 는 --all 명시 동의 필요 (F2a) ───────────────────────────
python3 "$SCRIPTS/hermes-export-history.py" --db "$MBDB" --project "$MB" \
  >/dev/null 2>"$TMP/s7-noall.err"
rc_noall=$?
if [[ $rc_noall -ne 0 ]]; then
  ok "(G2) --session/--all 없는 전량 export 는 비-0 종료"
else
  nope "(G2) 무플래그 전량 export 가 그대로 실행됨(exit $rc_noall)"
fi
if grep -q -- "--all" "$TMP/s7-noall.err" 2>/dev/null; then
  ok "(G2) stderr 에 --all 사용법 안내"
else
  nope "(G2) --all 안내 없음 ('$(tr '\n' ' ' < "$TMP/s7-noall.err")')"
fi
if [[ "$(lines_of "$FGBA")" == "1" ]]; then
  ok "(G2) 거부된 전량 export 는 파일을 건드리지 않음"
else
  nope "(G2) 거부됐는데 파일이 바뀜 (file=$(lines_of "$FGBA"))"
fi

# ── (G3) 발산 기계에서 --all 전량 export → 압축본 덮어쓰기 거부 (F2b) ────────
python3 "$SCRIPTS/hermes-export-history.py" --db "$MBDB" --project "$MB" --all \
  >/dev/null 2>"$TMP/s7-all.err"
if [[ "$(lines_of "$FGBA")" == "1" ]] && [[ "$(is_compacted "$FGBA")" == "YES" ]]; then
  ok "(G3) 발산 기계의 전량 export 가 압축본을 원문으로 되돌리지 않음"
else
  nope "(G3) 전량 export 1회로 압축이 원문으로 복귀 (file=$(lines_of "$FGBA") compacted=$(is_compacted "$FGBA"))"
fi
if grep -q "g-a" "$TMP/s7-all.err" 2>/dev/null && grep -q -- "--force" "$TMP/s7-all.err" 2>/dev/null; then
  ok "(G3) 스킵 경고에 세션 id + reindex --force 안내"
else
  nope "(G3) 스킵 경고 없음 ('$(tr '\n' ' ' < "$TMP/s7-all.err")')"
fi
# 사용자가 가장 자주 보는 stderr 경로에도 --force 전역성 경고가 있어야 한다
# (훅 로그·apply docstring 과 동일 문장). 없으면 뒤처진 다른 세션이 소실된다.
if grep -q "전역" "$TMP/s7-all.err" 2>/dev/null; then
  ok "(G3) stderr 안내에 '--force 는 전역' 경고 동반"
else
  nope "(G3) stderr 안내에 --force 전역 경고 없음 ('$(tr '\n' ' ' < "$TMP/s7-all.err")')"
fi

# ── (G4) 대조: 압축 직후 정상 기계(파일1행/DB1행)는 --all 전량 export 정상 통과 ──
#      이 단언이 없으면 가드가 모든 압축본을 과잉 차단해도 (G3) 이 통과한다.
python3 "$SCRIPTS/hermes-export-history.py" --db "$MADB" --project "$MA" --all \
  >"$TMP/s7-a-all.out" 2>"$TMP/s7-a-all.err"
if grep -q "2 sessions" "$TMP/s7-a-all.out" 2>/dev/null &&
   ! grep -q "거부" "$TMP/s7-a-all.err" 2>/dev/null; then
  ok "(G4) 대조: 파일1행 ⟺ DB1행 정상 기계는 전량 export 통과(과잉 차단 없음)"
else
  nope "(G4) 가드가 정상 압축본까지 차단 (out='$(tr '\n' ' ' < "$TMP/s7-a-all.out")' err='$(tr '\n' ' ' < "$TMP/s7-a-all.err")')"
fi

# ── (G5) 왕복 내구성: 전량 export 후에도 compacted 마커 생존 (F2c) ───────────
if [[ "$(is_compacted "$FGA")" == "YES" ]]; then
  ok "(G5) 전량 export 왕복 후에도 compacted/orig_lines 마커 보존"
else
  nope "(G5) 전량 export 가 compacted 마커를 소실시킴 — 다음 기계에서 (G3) 가드 무력화 ($(is_compacted "$FGA"))"
fi

# ── (G6) get_tracking_epoch: session_reuse 부재 DB 에서 조용히 None (F3) ─────
epoch_guard() {
PYTHONPATH="$SCRIPTS" python3 - "$TMP/s7-noreuse.db" <<'PY'
import sqlite3, sys
import hermes_reuse as r
con = sqlite3.connect(sys.argv[1])
try:
    v = r.get_tracking_epoch(con)
except Exception as e:
    print("RAISE:%s" % type(e).__name__); raise SystemExit
print("NONE" if v is None else "VAL")
PY
}
if [[ "$(epoch_guard 2>/dev/null)" == "NONE" ]]; then
  ok "(G6) session_reuse 부재 DB 에서 get_tracking_epoch 는 None 반환(예외 없음)"
else
  nope "(G6) get_tracking_epoch 가 OperationalError 를 누출 ($(epoch_guard 2>&1 | tr '\n' ' '))"
fi

# ── 후반 공용 헬퍼: 압축본 파일 쓰기 · 훅 실행 ──────────────────────────────
write_compacted() {   # $1=파일경로 $2=sid $3=orig_lines → 요약 content 를 stdout 으로
python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, sid, orig = sys.argv[1], sys.argv[2], int(sys.argv[3])
content = "[압축 요약] 테스트 주제\n공통 결론\n(원문 %d줄 — git 히스토리에서 복구)" % orig
rec = {"seq": 0, "session_id": sid, "project_id": "PA", "role": "system",
       "timestamp": "2026-01-01T10:00:00.000000", "content": content,
       "compacted": True, "orig_lines": orig}
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
sys.stdout.write(content)
PY
}
write_transcript() {   # $1=경로 $2=sid $3=원문행수 — Claude Code transcript JSONL(원문+신규 2턴)
python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, sid, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
recs = [{"type": "user", "message": {"role": "user", "content": "대화 %s-%d" % (sid, i)}}
        for i in range(n)]
recs.append({"type": "user", "message": {"role": "user", "content": "재개 신규 질문"}})
recs.append({"type": "assistant", "message": {"role": "assistant", "content": "재개 신규 답변"}})
with open(path, "w", encoding="utf-8") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}
has_marker() {   # $1=파일 → 어느 행에든 compacted/orig_lines 최상위 마커가 있으면 YES
python3 - "$1" <<'PY'
import json, sys
hit = "NO"
try:
    for line in open(sys.argv[1], encoding="utf-8"):
        if not line.strip():
            continue
        o = json.loads(line)
        if isinstance(o, dict) and ("compacted" in o or "orig_lines" in o):
            hit = "YES"
except Exception as e:
    hit = "ERR(%s)" % e
print(hit)
PY
}
run_hook() {   # $1=프로젝트 → 훅 1회 실행, stdout 을 stdout 으로
  printf '%s' '{"source":"startup"}' > "$TMP/hook-in.json"
  env CLAUDE_PROJECT_DIR="$1" bash "$RHOOK" < "$TMP/hook-in.json" 2>/dev/null
}

# ── (G7) 뒤처짐 발산: 압축과 무관 — --force 를 절대 안내하면 안 된다 (F5) ────
# Stop 훅 export 실패로 파일만 뒤처진 상태(§5 (F1) 이 데이터손실로 규정한 그 상태).
# 여기서 --force(파일→DB)를 따르면 DB 원문 5행이 영구 소실된다.
ML="$TMP/m-lag"; MLDB="$ML/.hermes/state.db"; MLH="$ML/.hermes/history"
mk_project "$ML"
FLAG="$(fixture5 "$MLDB" "$MLH" lag-a 8)"
head -n 3 "$FLAG" > "$FLAG.part" && mv "$FLAG.part" "$FLAG"
commit_hist "$ML"
LLOG="$ML/.hermes/hooks.log"; rm -f "$LLOG"
out_g7="$(run_hook "$ML")"
if [[ -z "$out_g7" ]]; then ok "(G7) 훅 stdout 무출력"; else nope "(G7) stdout 오염 ('$out_g7')"; fi
if grep -q "skip:diverged:lagging" "$LLOG" 2>/dev/null; then
  ok "(G7) 뒤처짐 발산을 skip:diverged:lagging 으로 분류"
else
  nope "(G7) 뒤처짐 발산 미분류 (log='$(tr '\n' ' ' < "$LLOG" 2>/dev/null)')"
fi
if grep -q -- "--force" "$LLOG" 2>/dev/null; then
  nope "(G7) 뒤처짐 발산에 --force 안내 — 따르면 DB 원문 5행 영구 소실"
else
  ok "(G7) 뒤처짐 발산에 --force 안내 없음"
fi
if grep -q "hermes-export-history" "$LLOG" 2>/dev/null &&
   grep -q -- "--session lag-a" "$LLOG" 2>/dev/null; then
  ok "(G7) 안내가 세션 단위 export(--session lag-a) 방향"
else
  nope "(G7) 세션 단위 export 안내 없음 (log='$(tr '\n' ' ' < "$LLOG" 2>/dev/null)')"
fi

# ── (G8) 혼재: 압축본 + 뒤처짐 동거 → --force 권유 금지 (F5) ─────────────────
# --force 는 세션 단위가 아니라 전역이라 압축 수용과 동시에 무관한 뒤처짐 세션을 파괴한다.
MX="$TMP/m-mixed"; MXDB="$MX/.hermes/state.db"; MXH="$MX/.hermes/history"
mk_project "$MX"
FXC="$(fixture5 "$MXDB" "$MXH" mix-comp 10)"
FXL="$(fixture5 "$MXDB" "$MXH" mix-lag 8)"
write_compacted "$FXC" mix-comp 10 >/dev/null
head -n 3 "$FXL" > "$FXL.part" && mv "$FXL.part" "$FXL"
commit_hist "$MX"
XLOG="$MX/.hermes/hooks.log"; rm -f "$XLOG"
run_hook "$MX" >/dev/null
if grep -q "skip:diverged:mixed" "$XLOG" 2>/dev/null; then
  ok "(G8) 혼재 발산을 skip:diverged:mixed 로 분류"
else
  nope "(G8) 혼재 미분류 (log='$(tr '\n' ' ' < "$XLOG" 2>/dev/null)')"
fi
if grep -q -- "--force" "$XLOG" 2>/dev/null; then
  nope "(G8) 혼재인데 --force 권유 — 무관한 뒤처짐 세션 5행이 경고 없이 소실"
else
  ok "(G8) 혼재에 --force 권유 없음"
fi
if grep -q -- "--session mix-lag" "$XLOG" 2>/dev/null; then
  ok "(G8) 뒤처진 세션을 먼저 --session 동기화하라고 안내"
else
  nope "(G8) 선-동기화 대상 세션 안내 없음 (log='$(tr '\n' ' ' < "$XLOG" 2>/dev/null)')"
fi

# ── (G9) ts<ds 양성: DB 에만 있는 세션 → --backfill 방향 (F5) ────────────────
MD="$TMP/m-dbonly"; MDDB="$MD/.hermes/state.db"; MDH="$MD/.hermes/history"
mk_project "$MD"
fixture5 "$MDDB" "$MDH" db-keep 3 >/dev/null
FDO="$(fixture5 "$MDDB" "$MDH" db-only 4)"
rm -f "$FDO"                                   # DB 에만 남은 세션(파일 없음)
commit_hist "$MD"
DLOG="$MD/.hermes/hooks.log"; rm -f "$DLOG"
run_hook "$MD" >/dev/null
if grep -q "skip:diverged:db-only" "$DLOG" 2>/dev/null; then
  ok "(G9) 파일 없는 DB 전용 세션을 skip:diverged:db-only 로 분류"
else
  nope "(G9) db-only 미분류 (log='$(tr '\n' ' ' < "$DLOG" 2>/dev/null)')"
fi
if grep -q -- "--backfill" "$DLOG" 2>/dev/null && ! grep -q -- "--force" "$DLOG" 2>/dev/null; then
  ok "(G9) 양성 케이스는 --backfill 안내(파괴적 --force 없음)"
else
  nope "(G9) --backfill 안내 없음/--force 오안내 (log='$(tr '\n' ' ' < "$DLOG" 2>/dev/null)')"
fi

# ── (G10) db_ok 방어: DB 조회 실패는 거짓 발산을 만들면 안 된다 (F8) ─────────
# 폴백 2**31 이 db_ok 로 게이팅되지 않으면 모든 정상 프로젝트가 발산으로 오분류된다.
MK="$TMP/m-brokendb"; MKDB="$MK/.hermes/state.db"; MKH="$MK/.hermes/history"
mk_project "$MK"
fixture5 "$MKDB" "$MKH" ok-a 3 >/dev/null
commit_hist "$MK"
printf 'NOT-A-SQLITE-FILE\n' > "$MKDB"          # 비-SQLite 바이트로 덮어씀
KLOG="$MK/.hermes/hooks.log"; rm -f "$KLOG"
run_hook "$MK" >/dev/null
if grep -q "skip:in-sync" "$KLOG" 2>/dev/null && ! grep -q "skip:diverged" "$KLOG" 2>/dev/null; then
  ok "(G10) 손상 DB → 보수적 skip:in-sync (거짓 발산 없음)"
else
  nope "(G10) 손상 DB 가 거짓 발산/오분류 (log='$(tr '\n' ' ' < "$KLOG" 2>/dev/null)')"
fi
if [[ "$(id -u)" != "0" ]]; then
  MP="$TMP/m-permdb"; MPDB="$MP/.hermes/state.db"; MPH="$MP/.hermes/history"
  mk_project "$MP"
  fixture5 "$MPDB" "$MPH" ok-b 3 >/dev/null
  commit_hist "$MP"
  chmod 000 "$MPDB"
  PLOG="$MP/.hermes/hooks.log"; rm -f "$PLOG"
  run_hook "$MP" >/dev/null
  if grep -q "skip:in-sync" "$PLOG" 2>/dev/null && ! grep -q "skip:diverged" "$PLOG" 2>/dev/null; then
    ok "(G10) 권한 000 DB → 보수적 skip:in-sync (거짓 발산 없음)"
  else
    nope "(G10) 권한 000 DB 가 거짓 발산/오분류 (log='$(tr '\n' ' ' < "$PLOG" 2>/dev/null)')"
  fi
  chmod 644 "$MPDB"
else
  ok "(G10) 권한 000 케이스 건너뜀(root 실행 — chmod 무력)"
fi

# ── (G11) 압축 세션 재개 e2e — 실제 hermes-save-session.py 를 태운다 ─────────
#   손으로 DB 상태를 만들지 않는다. 프로덕션 경로 그대로:
#     압축(--apply) → --resume(Stop 훅의 save-session) → Stop 훅의 --session export.
#   save-session 은 세션 행을 통째로 지우고 transcript 를 재삽입하며
#   role not in (user,assistant,tool) 인 요약행을 버린다 → DB 가 원문으로 되돌아온다.
MR="$TMP/m-resume"; MRDB="$MR/.hermes/state.db"; MRH="$MR/.hermes/history"
mk_project "$MR"
FRS="$(fixture5 "$MRDB" "$MRH" res-a 5)"
commit_hist "$MR"
mk_mock "$TMP/bin-resume" '
cat <<JSON
[{"topic":"재개 대상","session_ids":["res-a"],"summary":"압축 요약 본문"}]
JSON
exit 0'
PATH="$TMP/bin-resume:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" \
  --db "$MRDB" --project "$MR" --propose --age-days 90 >/dev/null 2>&1
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$MRDB" --project "$MR" --apply \
  >/dev/null 2>&1
clog_has() {   # $1=db $2=sid → YES/NO
python3 - "$1" "$2" <<'PY'
import sqlite3, sys
ids = set()
for (s,) in sqlite3.connect(sys.argv[1]).execute("SELECT session_ids FROM compaction_log"):
    ids.update(x.strip() for x in (s or "").split(",") if x.strip())
print("YES" if sys.argv[2] in ids else "NO")
PY
}
if [[ "$(lines_of "$FRS")" == "1" && "$(rows_of "$MRDB" res-a)" == "1" &&
      "$(clog_has "$MRDB" res-a)" == "YES" ]]; then
  ok "전제(G11) 실제 --apply 로 압축(파일 1행 ⟺ DB 1행) + compaction_log 기록"
else
  nope "전제(G11) 압축 실패 (file=$(lines_of "$FRS") db=$(rows_of "$MRDB" res-a) clog=$(clog_has "$MRDB" res-a))"
fi
commit_hist "$MR"

# 재개: Claude transcript 에는 원문 5턴이 그대로 있고 신규 2턴이 덧붙는다.
write_transcript "$TMP/resume-transcript.jsonl" res-a 5
python3 "$SCRIPTS/hermes-save-session.py" --db "$MRDB" \
  --transcript "$TMP/resume-transcript.jsonl" --project-id PA --session-id res-a \
  >/dev/null 2>"$TMP/s7-save.err"
if [[ "$(rows_of "$MRDB" res-a)" == "7" ]]; then
  ok "전제(G11) 재개 save-session 이 DB 를 원문5+신규2=7행으로 되돌림(요약행 소멸)"
else
  nope "전제(G11) save-session 재현 실패 (db=$(rows_of "$MRDB" res-a) err='$(tr '\n' ' ' < "$TMP/s7-save.err")')"
fi

# (G11a) export 가 실패·타임아웃한 상태로 SessionStart 를 맞으면(Stop 훅은 `|| true`)
#        파일=압축본 / DB=원문 이다. 이걸 타 기계 압축본 pull(compacted)로 오분류해
#        --force 를 권하면 신규 대화가 DB 에서 삭제되고 파일·git 어디에도 없다.
RRLOG="$MR/.hermes/hooks.log"; rm -f "$RRLOG"
out_g11="$(run_hook "$MR")"
if [[ -z "$out_g11" ]]; then ok "(G11a) 훅 stdout 무출력"; else nope "(G11a) stdout 오염 ('$out_g11')"; fi
if grep -q "skip:diverged:self-clobbered" "$RRLOG" 2>/dev/null; then
  ok "(G11a) 자기-원복을 skip:diverged:self-clobbered 로 분류"
else
  nope "(G11a) 자기-원복이 미분류/compacted 오분류 (log='$(tr '\n' ' ' < "$RRLOG" 2>/dev/null)')"
fi
if grep -q "skip:diverged:compacted" "$RRLOG" 2>/dev/null; then
  nope "(G11a) 자기-원복을 compacted(타 기계 압축본 pull)로 오분류"
else
  ok "(G11a) compacted 오분류 없음"
fi
# 로그 접두 '[hermes-reindex-hook]' 과 구분하려고 스크립트 파일명으로 좁힌다.
if grep -q "hermes-reindex.py" "$RRLOG" 2>/dev/null; then
  nope "(G11a) 해결책으로 reindex --force 를 제시 — 따르면 신규 대화 영구 소실"
else
  ok "(G11a) 해결책으로 reindex --force 를 제시하지 않음"
fi
if grep -q "hermes-export-history" "$RRLOG" 2>/dev/null &&
   grep -q -- "--session res-a" "$RRLOG" 2>/dev/null; then
  ok "(G11a) 안내가 세션 단위 export(--session res-a) 방향"
else
  nope "(G11a) 세션 단위 export 안내 없음 (log='$(tr '\n' ' ' < "$RRLOG" 2>/dev/null)')"
fi
if grep -q "신규 대화" "$RRLOG" 2>/dev/null; then
  ok "(G11a) --force 가 신규 대화를 삭제한다는 경고 동반"
else
  nope "(G11a) --force 파괴성 경고 없음 (log='$(tr '\n' ' ' < "$RRLOG" 2>/dev/null)')"
fi
if [[ "$(rows_of "$MRDB" res-a)" == "7" && "$(lines_of "$FRS")" == "1" ]]; then
  ok "(G11a) 훅은 자동 복구하지 않음(DB·파일 불변)"
else
  nope "(G11a) 훅이 자동으로 DB/파일을 바꿈 (db=$(rows_of "$MRDB" res-a) file=$(lines_of "$FRS"))"
fi

# (G11b) Stop 훅과 동일한 --session export — 신규 대화가 실제로 파일에 나가야 한다.
python3 "$SCRIPTS/hermes-export-history.py" --db "$MRDB" --project "$MR" \
  --session res-a >/dev/null 2>"$TMP/s7-resume.err"
FRS2="$(printf '%s' "$MRH"/*res-a.jsonl)"
if [[ "$(lines_of "$FRS2")" == "7" ]]; then
  ok "(G11b) 재개 세션이 정상 export — 신규 대화가 파일에 반영(7행)"
else
  nope "(G11b) 재개인데 가드가 스킵 — 신규 대화가 영구히 git 밖에 갇힘 (file=$(lines_of "$FRS2") err='$(tr '\n' ' ' < "$TMP/s7-resume.err")')"
fi
if grep -q "거부" "$TMP/s7-resume.err" 2>/dev/null; then
  nope "(G11b) 재개인데 '덮어쓰기 거부' 경고 — 사실과 다른 진단"
else
  ok "(G11b) 재개에는 거부 경고 없음"
fi
if grep -q "재개 신규 답변" "$FRS2" 2>/dev/null; then
  ok "(G11b) export 된 파일에 신규 대화 내용 실재"
else
  nope "(G11b) 신규 대화가 파일에 없음"
fi
# carry 게이팅의 살아있는 조건 — 압축이 해제된 파일에 compacted 마커가 남으면
# 다음 기계가 이 7행 파일을 압축본으로 오인할 수 있다(그리고 사실과 다르다).
if [[ "$(has_marker "$FRS2")" == "NO" ]]; then
  ok "(G11b) 압축 해제된 파일에 compacted/orig_lines 마커 없음"
else
  nope "(G11b) 재개 export 결과에 compacted 마커 위조 ($(has_marker "$FRS2"))"
fi
if grep -q "압축 해제" "$TMP/s7-resume.err" 2>/dev/null; then
  ok "(G11b) 압축 해제를 stderr 로 고지(침묵 원복 아님)"
else
  nope "(G11b) 압축 해제가 침묵으로 진행 ('$(tr '\n' ' ' < "$TMP/s7-resume.err")')"
fi

# (G11c) export 로 파일이 맞춰지면 다음 SessionStart 는 다시 in-sync 여야 한다.
rm -f "$RRLOG"
run_hook "$MR" >/dev/null
if grep -q "skip:in-sync" "$RRLOG" 2>/dev/null && ! grep -q "diverged" "$RRLOG" 2>/dev/null; then
  ok "(G11c) 동기화 후 훅은 in-sync — 발산 경보 고착 없음"
else
  nope "(G11c) 동기화 후에도 발산 경보 (log='$(tr '\n' ' ' < "$RRLOG" 2>/dev/null)')"
fi

# ── (G12) 덮어쓰기 거부 가드는 --all 전용 · --session 은 고지 후 통과 ────────
#   되돌림 위험이 실재하는 곳은 "타 기계에서 전량 재작성"(--all)뿐이다.
#   --session 은 Stop 훅이 **살아있는 세션**에만 넘기며, 살아있는 세션은 이미
#   게이트 ②(미사용)가 깨진 것이라 압축 해제가 정상 동작이다. 다만 침묵은 안 된다.
MV="$TMP/m-div-sess"; MVDB="$MV/.hermes/state.db"; MVH="$MV/.hermes/history"
mk_project "$MV"
FDV="$(fixture5 "$MVDB" "$MVH" div-a 6)"
write_compacted "$FDV" div-a 6 >/dev/null       # 파일만 압축본, DB 는 원문 6행
commit_hist "$MV"
python3 "$SCRIPTS/hermes-export-history.py" --db "$MVDB" --project "$MV" --all \
  >/dev/null 2>"$TMP/s7-divall.err"
if [[ "$(lines_of "$FDV")" == "1" ]] && [[ "$(is_compacted "$FDV")" == "YES" ]]; then
  ok "(G12) 발산 세션의 --all 전량 export 는 압축본을 되돌리지 않음"
else
  nope "(G12) --all export 가 압축을 원문으로 복귀 (file=$(lines_of "$FDV") compacted=$(is_compacted "$FDV"))"
fi
if grep -q "div-a" "$TMP/s7-divall.err" 2>/dev/null; then
  ok "(G12) --all 거부 경고에 세션 id 포함"
else
  nope "(G12) --all 거부 경고 없음 ('$(tr '\n' ' ' < "$TMP/s7-divall.err")')"
fi
python3 "$SCRIPTS/hermes-export-history.py" --db "$MVDB" --project "$MV" \
  --session div-a >/dev/null 2>"$TMP/s7-divsess.err"
FDV2="$(printf '%s' "$MVH"/*div-a.jsonl)"
if [[ "$(lines_of "$FDV2")" == "6" ]]; then
  ok "(G12) --session 은 가드 대상이 아니다 — 살아있는 세션이므로 압축 해제(6행)"
else
  nope "(G12) --session 이 스킵됨 — 살아있는 세션의 신규 대화가 갇힌다 (file=$(lines_of "$FDV2"))"
fi
if grep -q "div-a" "$TMP/s7-divsess.err" 2>/dev/null &&
   grep -q "압축 해제" "$TMP/s7-divsess.err" 2>/dev/null; then
  ok "(G12) --session 압축 해제를 세션 id 와 함께 stderr 고지(침묵 아님)"
else
  nope "(G12) --session 압축 해제가 침묵 ('$(tr '\n' ' ' < "$TMP/s7-divsess.err")')"
fi

# ── (G13) 1행 발산도 되돌리지 않는다 — 행수 임계 없이 술어 하나로 판정 (F7) ──
#   DB 1행이 그 요약 자신이 아니라 원문이면, 행수가 1이라는 이유로 통과시키면
#   압축이 조용히 원문으로 복귀한다(그리고 그 원문 행에 마커가 위조된다).
MF="$TMP/m-forge"; MFDB="$MF/.hermes/state.db"; MFH="$MF/.hermes/history"
mk_project "$MF"
FFG="$(fixture5 "$MFDB" "$MFH" forge-a 1)"      # DB 1행 = 원문
write_compacted "$FFG" forge-a 1 >/dev/null     # 파일만 압축본(다른 기계 산물)
commit_hist "$MF"
python3 "$SCRIPTS/hermes-export-history.py" --db "$MFDB" --project "$MF" --all \
  >/dev/null 2>"$TMP/s7-forge.err"
FFG2="$(printf '%s' "$MFH"/*forge-a.jsonl)"
if [[ "$(lines_of "$FFG2")" == "1" ]] && [[ "$(is_compacted "$FFG2")" == "YES" ]]; then
  ok "(G13) DB 1행이 원문이어도 압축본을 되돌리지 않음(행수 임계 없음)"
else
  nope "(G13) 1행 발산에서 압축이 원문으로 복귀 (file=$(lines_of "$FFG2") compacted=$(is_compacted "$FFG2"))"
fi
if grep -q "대화 forge-a" "$FFG2" 2>/dev/null; then
  nope "(G13) DB 원문이 압축본을 덮어씀 — 커밋 시 fleet 전체 압축 원복"
else
  ok "(G13) DB 원문이 파일에 기록되지 않음"
fi
if grep -q "forge-a" "$TMP/s7-forge.err" 2>/dev/null; then
  ok "(G13) 1행 발산 스킵 경고에 세션 id 포함"
else
  nope "(G13) 1행 발산 스킵 경고 없음 ('$(tr '\n' ' ' < "$TMP/s7-forge.err")')"
fi

echo "통과:$PASS 실패:$FAIL"
[[ $FAIL -eq 0 ]]
