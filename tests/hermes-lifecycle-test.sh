#!/usr/bin/env bash
# 헤르메스 지식 생애주기 린트 테스트 (Part D)
#
# 섹션 1: 세션 재활용 추적 — session_reuse 테이블 + tracking_epoch 마커.
#         오래된 세션이 이후 recall 로 다시 참조되면 last_reused_at 을 기록한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DB="$TMP/.hermes/state.db"

python3 "$SCRIPTS/hermes-init.py" --both "$TMP" >/dev/null 2>&1

echo "── 섹션 1: 세션 재활용 추적 (session_reuse + tracking_epoch) ──"

# DDL 정본: init.py 가 session_reuse 를 만든다
ddl_check() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
tabs = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
assert "session_reuse" in tabs, "session_reuse 테이블 없음"
cols = {r[1] for r in con.execute("PRAGMA table_info(session_reuse)")}
assert {"session_id", "last_reused_at", "reuse_count"} <= cols, cols
print("OK")
PY
}
if ddl_check 2>/dev/null | grep -q OK; then ok "DDL: init.py 가 session_reuse 정본 생성"; else nope "DDL session_reuse"; fi

# (b)+(c) ensure_reuse_table 최초 호출 → __epoch__ 마커 + get_tracking_epoch, 재호출 멱등
epoch_check() {
PYTHONPATH="$SCRIPTS" python3 - "$TMP" <<'PY'
import sqlite3, os, sys, time
import hermes_reuse as r
db = os.path.join(sys.argv[1], ".hermes", "reuse-epoch.db")
con = sqlite3.connect(db)
# 최초 호출 → epoch 마커 기록
r.ensure_reuse_table(con)
e1 = r.get_tracking_epoch(con)
assert e1 is not None, "최초 ensure 후 epoch None"
# __epoch__ 는 일반 세션이 아니다 — mark_reused 입력에서 제외돼야 한다
r.mark_reused(con, ["__epoch__"])
rc = con.execute("SELECT reuse_count FROM session_reuse WHERE session_id='__epoch__'").fetchone()[0]
assert rc == 0, f"__epoch__ 가 세션으로 취급됨 (reuse_count={rc})"
# 재호출 멱등 — epoch 불변
time.sleep(0.01)
r.ensure_reuse_table(con)
e2 = r.get_tracking_epoch(con)
assert e1 == e2, f"epoch 재호출로 변함 {e1} != {e2}"
print("OK")
PY
}
if epoch_check 2>/dev/null | grep -q OK; then ok "epoch: 최초 마커 기록 + get_tracking_epoch + 멱등"; else nope "epoch 멱등"; fi

# (a) recall 이 다른 세션 요약 주입 → 그 원본 세션에 last_reused_at 생김
reuse_check() {
# 픽스처: 원본 세션 요약 1건 (project P)
python3 - "$DB" <<'PY'
import sqlite3, json, sys
con = sqlite3.connect(sys.argv[1])
con.execute(
    "INSERT OR REPLACE INTO session_summary (session_id, project_id, slots_json) "
    "VALUES ('sess-old', 'P', ?)",
    (json.dumps({"decisions": ["X 결정"], "open": ["Y 미해결"]}),),
)
con.commit()
PY
# recall inject: 새 세션이 원본 세션(sess-old) 요약을 주입받는다
python3 "$SCRIPTS/hermes-recall.py" --inject --db "$DB" \
  --project-id "P" --session-id "sess-new" >/dev/null 2>&1
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
row = con.execute(
    "SELECT last_reused_at, reuse_count FROM session_reuse WHERE session_id='sess-old'"
).fetchone()
assert row is not None, "원본 세션 재활용 미기록"
assert row[0], f"last_reused_at 비어있음 {row}"
assert row[1] >= 1, f"reuse_count {row[1]}"
# 현재 세션(sess-new)은 재활용 원본이 아니다 — 기록 안 돼야 한다
assert con.execute(
    "SELECT 1 FROM session_reuse WHERE session_id='sess-new'"
).fetchone() is None, "현재 세션이 잘못 기록됨"
print("OK")
PY
}
if reuse_check 2>/dev/null | grep -q OK; then ok "recall: 원본 세션 요약 주입 시 last_reused_at 기록"; else nope "recall 재활용 기록"; fi

echo "── 섹션 2: 3중 게이트 판정기 (나이 AND 미사용 AND 결정화) ──"

# 격리 프로젝트 — 섹션 1 상태와 분리
G="$TMP/gate"; GDB="$G/.hermes/state.db"; GH="$G/.hermes/history"
python3 "$SCRIPTS/hermes-init.py" --both "$G" >/dev/null 2>&1
mkdir -p "$GH"

# 시나리오 구성: 나이는 파일명 날짜, 재활용은 session_reuse, 결정화는 pattern_session⋈pattern_count
gate_setup() {
PYTHONPATH="$SCRIPTS" python3 - "$GDB" "$GH" "$1" <<'PY'
import sqlite3, sys, os, json
from datetime import datetime, timedelta
import hermes_reuse as r
db, hist, epoch_age = sys.argv[1], sys.argv[2], int(sys.argv[3])
con = sqlite3.connect(db)
r.ensure_reuse_table(con)
# tracking_epoch 를 epoch_age 일 전으로 조정(관측 기간 제어)
con.execute("UPDATE session_reuse SET last_reused_at=? WHERE session_id='__epoch__'",
            ((datetime.now() - timedelta(days=epoch_age)).isoformat(),))
now = datetime.now()
def hist_file(sid, age_days):
    d = (now - timedelta(days=age_days)).strftime("%Y-%m-%d")
    with open(os.path.join(hist, "%s-%s.jsonl" % (d, sid)), "w", encoding="utf-8") as f:
        f.write(json.dumps({"seq":0,"session_id":sid,"role":"user","content":"x"}) + "\n")
def crystallize(sid, done):
    key = "pat-" + sid
    con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count, crystallized) VALUES (?,?,?)",
                (key, 3, 1 if done else 0))
    con.execute("INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) VALUES (?,?)", (key, sid))
# (a) 오래됨 + 미재활용 + 결정화 → 후보
hist_file("s-a", 200); crystallize("s-a", True)
# (b) 오래됨 + 재활용됨 + 결정화 → 제외
hist_file("s-b", 200); crystallize("s-b", True); r.mark_reused(con, ["s-b"])
# (c) 오래됨 + 미재활용 + 미결정화 → 제외
hist_file("s-c", 200); crystallize("s-c", False)
# (d) 최신 + 미재활용 + 결정화 → 제외
hist_file("s-d", 3);   crystallize("s-d", True)
# (e) 날짜 불명 파일 → 제외
with open(os.path.join(hist, "unknown-date-s-e.jsonl"), "w", encoding="utf-8") as f:
    f.write("{}\n")
con.commit()
print("OK")
PY
}

run_gate() { python3 "$SCRIPTS/hermes-lifecycle.py" --db "$GDB" --project "$G" --age-days 90 2>/dev/null; }

# 관측 기간 충분(epoch 200일 전) → (a)만 후보
gate_setup 200 >/dev/null 2>&1
out="$(run_gate)"
if [[ "$(printf '%s' "$out" | tr -d '[:space:]')" == "s-a" ]]; then
  ok "3중 게이트: 오래됨+미재활용+결정화 만 후보(s-a)"
else
  nope "3중 게이트 후보 산출 (actual='$out')"
fi

# 개별 배제 근거 확인
for sid in s-b s-c s-d s-e; do
  if printf '%s' "$out" | grep -q "$sid"; then nope "$sid 는 배제돼야 함"; else ok "배제 확인: $sid"; fi
done

# 관측 기간 부족(epoch 방금) → 보수적으로 후보 0
rm -rf "$G"; python3 "$SCRIPTS/hermes-init.py" --both "$G" >/dev/null 2>&1; mkdir -p "$GH"
gate_setup 1 >/dev/null 2>&1
out2="$(run_gate)"
if [[ -z "$(printf '%s' "$out2" | tr -d '[:space:]')" ]]; then
  ok "추적 관측 기간 부족(epoch 최근) → 후보 0 (보수)"
else
  nope "관측 기간 부족인데 후보 나옴 (actual='$out2')"
fi

echo "── 섹션 3: 압축 제안 — LLM 주제 클러스터링 dry-run 리포트 ──"

# 격리 프로젝트 — 섹션 1~2 상태와 분리
P3="$TMP/prop"; PDB="$P3/.hermes/state.db"; PH="$P3/.hermes/history"
python3 "$SCRIPTS/hermes-init.py" --both "$P3" >/dev/null 2>&1
mkdir -p "$PH" "$TMP/bin"

# mock claude — 클러스터링 프롬프트를 감지해 고정 클러스터 JSON 을 stdout 으로
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
if printf '%s' "$*" | grep -q '주제'; then
  cat <<'JSON'
[{"topic":"모의 주제 A","session_ids":["p-a","p-b"],"summary":"두 세션의 공통 결론 요약"}]
JSON
  exit 0
fi
echo "NONE"
EOF
chmod +x "$TMP/bin/claude"

# 후보 픽스처: 오래됨(200일) + 미재활용 + 결정화된 세션 2개(원문 여러 줄 + DB 행)
prop_setup() {
PYTHONPATH="$SCRIPTS" python3 - "$PDB" "$PH" <<'PY'
import sqlite3, sys, os, json
from datetime import datetime, timedelta
import hermes_reuse as r
db, hist = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
r.ensure_reuse_table(con)
con.execute("UPDATE session_reuse SET last_reused_at=? WHERE session_id='__epoch__'",
            ((datetime.now() - timedelta(days=200)).isoformat(),))
now = datetime.now()
day = (now - timedelta(days=200)).strftime("%Y-%m-%d")
def mk(sid, lines, slots):
    path = os.path.join(hist, "%s-%s.jsonl" % (day, sid))
    with open(path, "w", encoding="utf-8") as f:
        for i in range(lines):
            row = {"seq": i, "session_id": sid, "role": "user",
                   "content": "대화 %s-%d" % (sid, i)}
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            con.execute(
                "INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?,?,?,?,?)", (row["content"], "user", day, "P3", sid))
    if slots:
        con.execute("INSERT OR REPLACE INTO session_summary "
                    "(session_id, project_id, slots_json) VALUES (?,?,?)",
                    (sid, "P3", json.dumps(slots, ensure_ascii=False)))
    key = "pat-" + sid
    con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count, crystallized) "
                "VALUES (?,3,1)", (key,))
    con.execute("INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) VALUES (?,?)",
                (key, sid))
mk("p-a", 5, {"decisions": ["A 를 채택"], "facts": ["B 는 느림"]})
mk("p-b", 4, None)      # slots 없음 → history 첫 N줄 폴백 경로
con.commit()
print("OK")
PY
}
prop_setup >/dev/null 2>&1

# dry-run 불변 스냅샷 헬퍼 (원문 라인수 합 + DB session_history 행수)
snapshot() {
python3 - "$PDB" "$PH" <<'PY'
import sqlite3, sys, os
db, hist = sys.argv[1], sys.argv[2]
total = 0
for n in sorted(os.listdir(hist)):
    with open(os.path.join(hist, n), encoding="utf-8") as f:
        total += sum(1 for _ in f)
rows = sqlite3.connect(db).execute("SELECT COUNT(*) FROM session_history").fetchone()[0]
print("lines=%d rows=%d" % (total, rows))
PY
}

REPORT="$P3/.hermes/lifecycle/$(date +%F)-proposal.md"
BEFORE="$(snapshot)"

PATH="$TMP/bin:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$PDB" --project "$P3" \
  --propose --age-days 90 >/dev/null 2>&1

if [[ -f "$REPORT" ]]; then ok "propose: proposal.md 생성"; else nope "proposal.md 미생성"; fi
if grep -q "모의 주제 A" "$REPORT" 2>/dev/null; then ok "propose: 클러스터 주제 기록"; else nope "클러스터 주제 누락"; fi
if grep -q "p-a" "$REPORT" 2>/dev/null && grep -q "p-b" "$REPORT" 2>/dev/null; then
  ok "propose: 클러스터에 session_id 포함"
else
  nope "session_id 누락"
fi

AFTER="$(snapshot)"
if [[ "$BEFORE" == "$AFTER" ]]; then
  ok "dry-run: history 원문 라인수·DB session_history 행수 불변 ($AFTER)"
else
  nope "dry-run 불변 위반 (before='$BEFORE' after='$AFTER')"
fi

# (c) claude 부재 → 보류. 원문·DB 여전히 불변.
rm -f "$REPORT"
env PATH="/usr/bin:/bin" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$PDB" --project "$P3" \
  --propose --age-days 90 >/dev/null 2>&1
if [[ ! -f "$REPORT" ]] || grep -q "보류" "$REPORT" 2>/dev/null; then
  ok "claude 부재: 보류 처리(리포트 미생성 또는 보류 표기)"
else
  nope "claude 부재인데 보류 표기 없음"
fi
if [[ "$(snapshot)" == "$BEFORE" ]]; then
  ok "claude 부재: 원문·DB 무손상"
else
  nope "claude 부재 경로에서 원문·DB 변경됨"
fi

# (d) 후보 0건(관측 기간 부족) → 리포트 미생성
Z="$TMP/prop-zero"; ZDB="$Z/.hermes/state.db"
python3 "$SCRIPTS/hermes-init.py" --both "$Z" >/dev/null 2>&1
mkdir -p "$Z/.hermes/history"
PYTHONPATH="$SCRIPTS" python3 -c "
import sqlite3, sys, hermes_reuse as r
r.ensure_reuse_table(sqlite3.connect(sys.argv[1]))
" "$ZDB" >/dev/null 2>&1
PATH="$TMP/bin:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$ZDB" --project "$Z" \
  --propose --age-days 90 >/dev/null 2>&1
if [[ ! -e "$Z/.hermes/lifecycle/$(date +%F)-proposal.md" ]]; then
  ok "후보 0건: 리포트 미생성(조용한 종료)"
else
  nope "후보 0건인데 리포트 생성됨"
fi

# ── 회귀 가드: 환각 필터 / 잘못된 JSON / rc≠0 ─────────────────────────────
# 프롬프트를 받아 지정한 방식으로 응답하는 mock claude 를 각각 별도 bin 에 만든다.
mk_mock() {   # $1=bin 디렉터리, $2=본문 스크립트
  mkdir -p "$1"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$2"; } > "$1/claude"
  chmod +x "$1/claude"
}

# (a) 환각 필터: 이번 청크에 없는 session_id 를 섞어 반환 → 리포트에 미포함
mk_mock "$TMP/bin-halluc" '
cat <<JSON
[{"topic":"환각 혼합","session_ids":["p-a","p-ghost-9999"],"summary":"가짜 id 혼입"}]
JSON
exit 0'
rm -f "$REPORT"
PATH="$TMP/bin-halluc:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$PDB" --project "$P3" \
  --propose --age-days 90 >/dev/null 2>&1
if [[ -f "$REPORT" ]] && grep -q "p-a" "$REPORT" && ! grep -q "p-ghost-9999" "$REPORT"; then
  ok "환각 필터: 존재하지 않는 session_id 는 리포트에서 제거"
else
  nope "환각 필터 실패 (리포트에 p-ghost-9999 잔존 또는 리포트 없음)"
fi
if [[ "$(snapshot)" == "$BEFORE" ]]; then ok "환각 필터 경로: 원문·DB 불변"; else nope "환각 필터 경로 원문·DB 변경됨"; fi

# (b) 잘못된 JSON → 해당 청크 보류, 크래시 없음, 원문·DB 불변
mk_mock "$TMP/bin-badjson" '
echo "{이건 JSON 이 아니다 ["
exit 0'
rm -f "$REPORT"
PATH="$TMP/bin-badjson:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$PDB" --project "$P3" \
  --propose --age-days 90 >/dev/null 2>&1
rc_badjson=$?
if [[ $rc_badjson -eq 0 ]]; then ok "잘못된 JSON: 크래시 없음(exit 0)"; else nope "잘못된 JSON exit=$rc_badjson"; fi
if [[ -f "$REPORT" ]] && grep -q "보류" "$REPORT"; then
  ok "잘못된 JSON: 해당 청크 보류 표기"
else
  nope "잘못된 JSON 인데 보류 표기 없음"
fi
if [[ "$(snapshot)" == "$BEFORE" ]]; then ok "잘못된 JSON: 원문·DB 불변"; else nope "잘못된 JSON 경로 원문·DB 변경됨"; fi

# (c) 비정상 종료(rc≠0) → 보류, 크래시 없음, 원문·DB 불변
mk_mock "$TMP/bin-rc" '
echo "boom" >&2
exit 3'
rm -f "$REPORT"
PATH="$TMP/bin-rc:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$PDB" --project "$P3" \
  --propose --age-days 90 >/dev/null 2>&1
rc_fail=$?
if [[ $rc_fail -eq 0 ]]; then ok "claude rc≠0: 크래시 없음(exit 0)"; else nope "claude rc≠0 에서 exit=$rc_fail"; fi
if [[ -f "$REPORT" ]] && grep -q "보류" "$REPORT"; then
  ok "claude rc≠0: 보류 표기"
else
  nope "claude rc≠0 인데 보류 표기 없음"
fi
if [[ "$(snapshot)" == "$BEFORE" ]]; then ok "claude rc≠0: 원문·DB 불변"; else nope "claude rc≠0 경로 원문·DB 변경됨"; fi

# (d) [Critical 회귀 가드] hermes_redact 부재 → LLM 입력 자체를 만들지 않는다.
#     scripts 사본에서 hermes_redact.py 만 제외하고, mock claude 가 받은 프롬프트를
#     파일로 덤프하게 해 민감 문자열이 실리지 않음을 단언한다.
S4="$TMP/scripts-noredact"
cp -r "$SCRIPTS" "$S4"
rm -f "$S4/hermes_redact.py"
rm -rf "$S4/__pycache__"

P4="$TMP/prop-secret"; P4DB="$P4/.hermes/state.db"; P4H="$P4/.hermes/history"
python3 "$SCRIPTS/hermes-init.py" --both "$P4" >/dev/null 2>&1
mkdir -p "$P4H"
SECRET_MAIL="secret@example.com"
SECRET_PW="password=hunter2SECRET"

PYTHONPATH="$SCRIPTS" python3 - "$P4DB" "$P4H" "$SECRET_MAIL" "$SECRET_PW" <<'PY' >/dev/null 2>&1
import sqlite3, sys, os, json
from datetime import datetime, timedelta
import hermes_reuse as r
db, hist, mail, pw = sys.argv[1:5]
con = sqlite3.connect(db)
r.ensure_reuse_table(con)
con.execute("UPDATE session_reuse SET last_reused_at=? WHERE session_id='__epoch__'",
            ((datetime.now() - timedelta(days=200)).isoformat(),))
day = (datetime.now() - timedelta(days=200)).strftime("%Y-%m-%d")
def mk(sid, slots, content):
    with open(os.path.join(hist, "%s-%s.jsonl" % (day, sid)), "w", encoding="utf-8") as f:
        f.write(json.dumps({"seq": 0, "session_id": sid, "role": "user",
                            "content": content}, ensure_ascii=False) + "\n")
    if slots:
        con.execute("INSERT OR REPLACE INTO session_summary "
                    "(session_id, project_id, slots_json) VALUES (?,?,?)",
                    (sid, "P4", json.dumps(slots, ensure_ascii=False)))
    key = "pat-" + sid
    con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count, crystallized) "
                "VALUES (?,3,1)", (key,))
    con.execute("INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) VALUES (?,?)",
                (key, sid))
mk("p-s1", {"facts": ["연락처는 %s" % mail]}, "무해한 본문")   # slots 경로
mk("p-s2", None, "접속정보 %s" % pw)                           # 폴백(원문) 경로
con.commit()
PY

DUMP="$TMP/prompt-dump.txt"
mkdir -p "$TMP/bin-dump"
cat > "$TMP/bin-dump/claude" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" >> "$DUMP"
echo "[]"
exit 0
EOF
chmod +x "$TMP/bin-dump/claude"

rm -f "$DUMP"
PATH="$TMP/bin-dump:$PATH" python3 "$S4/hermes-lifecycle.py" --db "$P4DB" --project "$P4" \
  --propose --age-days 90 >/dev/null 2>&1
rc_nored=$?
if [[ $rc_nored -eq 0 ]]; then ok "redact 부재: 크래시 없음(exit 0)"; else nope "redact 부재 exit=$rc_nored"; fi
if [[ ! -f "$DUMP" ]]; then
  ok "redact 부재: LLM 호출 자체 없음(프롬프트 덤프 미생성)"
else
  nope "redact 부재인데 LLM 호출됨(덤프 생성: $(wc -c <"$DUMP") bytes)"
fi
if [[ ! -f "$DUMP" ]] || { ! grep -qF "$SECRET_MAIL" "$DUMP" && ! grep -qF "$SECRET_PW" "$DUMP"; }; then
  ok "redact 부재: 민감 원문이 LLM 프롬프트에 실리지 않음"
else
  nope "redact 부재에서 민감 원문 유출 — 프롬프트 덤프에 존재"
fi
if [[ ! -e "$P4/.hermes/lifecycle/$(date +%F)-proposal.md" ]]; then
  ok "redact 부재: 청크 없음 → 리포트 미생성"
else
  nope "redact 부재인데 리포트 생성됨"
fi

# 대조군: redact 존재(정본 scripts) → 마스킹된 프롬프트가 실제로 만들어진다
rm -f "$DUMP"
PATH="$TMP/bin-dump:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$P4DB" --project "$P4" \
  --propose --age-days 90 >/dev/null 2>&1
if [[ -f "$DUMP" ]] && ! grep -qF "$SECRET_MAIL" "$DUMP" && ! grep -qF "$SECRET_PW" "$DUMP"; then
  ok "대조군(redact 존재): 프롬프트 생성되되 민감 원문은 마스킹됨"
else
  nope "대조군 실패 (덤프 존재=$([[ -f $DUMP ]] && echo y || echo n), 민감문자열 잔존 가능)"
fi

echo "통과:$PASS 실패:$FAIL"
[[ $FAIL -eq 0 ]]
