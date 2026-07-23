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

echo "── 섹션 4: --apply 원문 교체 + compaction_log 감사 (무손실 가드) ──"

# 실제 git 저장소에서 검증한다 — HEAD blob 실재 가드가 이 섹션의 핵심이라
# git 상태를 흉내내면 의미가 없다.
AP="$TMP/apply"; ADB="$AP/.hermes/state.db"; AH="$AP/.hermes/history"
python3 "$SCRIPTS/hermes-init.py" --both "$AP" >/dev/null 2>&1
mkdir -p "$AH"
git -c init.defaultBranch=main init -q "$AP" 2>/dev/null

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

mkfix() { SCRIPTS="$SCRIPTS" python3 "$TMP/apply-fixture.py" "$ADB" "$AH" "$1" "$2"; }
fline()  { wc -l < "$1" 2>/dev/null | tr -d ' '; }
dbrows() {
python3 - "$ADB" "$1" <<'PY'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute(
    "SELECT COUNT(*) FROM session_history WHERE session_id=?", (sys.argv[2],)).fetchone()[0])
PY
}
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

FA="$(mkfix c-a 5)"; FB="$(mkfix c-b 4)"; FE="$(mkfix c-e 3)"
git -C "$AP" add .hermes/history >/dev/null 2>&1
git -C "$AP" -c user.email=t@t -c user.name=t commit -qm "history" >/dev/null 2>&1

# (d2) 픽스처: gitignore 된 history 파일 — `git status --porcelain` 은 **완전히 조용**
#      하지만 HEAD blob 은 없다. clean 만 보는 가드가 실제로 뚫리는 유일한 경로이며,
#      원문이 git 어디에도 없어 덮어쓰면 영구 소실된다.
printf '.hermes/history/*-c-g.jsonl\n' > "$AP/.gitignore"
git -C "$AP" add .gitignore >/dev/null 2>&1
git -C "$AP" -c user.email=t@t -c user.name=t commit -qm "ignore" >/dev/null 2>&1
FG="$(mkfix c-g 2)"
RELG=".hermes/history/$(basename "$FG")"
COMMIT="$(git -C "$AP" rev-parse HEAD 2>/dev/null)"

# (d) 픽스처: 커밋 0회 — git add 만 된 파일(HEAD blob 없음, 그러나 naive clean)
FD="$(mkfix c-d 2)"
git -C "$AP" add "$FD" >/dev/null 2>&1
RELD=".hermes/history/$(basename "$FD")"
RELA=".hermes/history/$(basename "$FA")"
# (e) 픽스처: 커밋 후 워킹트리 수정(dirty)
printf '%s\n' '{"seq":9,"session_id":"c-e","project_id":"PA","role":"user","content":"dirty"}' >> "$FE"

# 전제 확인 — (d) 는 "HEAD blob 없음 + 미추적변경 없음(naive clean)" 이어야 의미가 있다
if ! git -C "$AP" cat-file -e "HEAD:$RELD" 2>/dev/null; then
  ok "전제(d): 커밋 0회 파일은 HEAD blob 부재"
else
  nope "전제(d) 실패 — HEAD 에 blob 이 있음"
fi
if git -C "$AP" diff --quiet -- "$RELD" 2>/dev/null; then
  ok "전제(d): 그럼에도 naive clean(diff 없음) — 가드가 clean 만 보면 뚫린다"
else
  nope "전제(d): naive clean 이 아님"
fi
if ! git -C "$AP" cat-file -e "HEAD:$RELG" 2>/dev/null &&
   [[ -z "$(git -C "$AP" status --porcelain -- "$RELG" 2>/dev/null)" ]]; then
  ok "전제(d2): gitignore 파일은 HEAD blob 부재 + status 완전 clean"
else
  nope "전제(d2): 시나리오 구성 실패"
fi

# 제안 생성(mock claude) — apply 는 이 리포트를 읽는다
mk_mock "$TMP/bin-apply" '
cat <<JSON
[{"topic":"압축 대상 A","session_ids":["c-a","c-b"],"summary":"두 세션의 공통 결론"},
 {"topic":"가드 대상 B","session_ids":["c-d","c-e","c-g"],"summary":"가드에 걸려 스킵돼야 한다"}]
JSON
exit 0'
PATH="$TMP/bin-apply:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" --db "$ADB" --project "$AP" \
  --propose --age-days 90 >/dev/null 2>&1
AREPORT="$AP/.hermes/lifecycle/$(date +%F)-proposal.md"
AJSON="$AP/.hermes/lifecycle/$(date +%F)-proposal.json"
if [[ -f "$AJSON" ]]; then ok "propose: 기계가독 proposal.json 동반 생성"; else nope "proposal.json 미생성"; fi

# ── --apply 실행 (LLM 불필요 — PATH 모킹 없이) ────────────────────────────
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$ADB" --project "$AP" --apply \
  >"$TMP/apply.out" 2>"$TMP/apply.err"
rc_apply=$?
if [[ $rc_apply -eq 0 ]]; then ok "apply: exit 0"; else nope "apply exit=$rc_apply"; fi

# (a) 파일·DB 동시 교체 — 양쪽 1행
if [[ "$(fline "$FA")" == "1" && "$(dbrows c-a)" == "1" ]]; then
  ok "(a) c-a: 파일 1행 ⟺ DB 1행 동시 교체"
else
  nope "(a) c-a 동시교체 실패 (file=$(fline "$FA") db=$(dbrows c-a))"
fi
if [[ "$(fline "$FB")" == "1" && "$(dbrows c-b)" == "1" ]]; then
  ok "(a) c-b: 파일 1행 ⟺ DB 1행 동시 교체"
else
  nope "(a) c-b 동시교체 실패 (file=$(fline "$FB") db=$(dbrows c-b))"
fi
if [[ "$(is_compacted "$FA")" == "YES" ]]; then
  ok "(a) 요약본 포맷: 유효 JSONL 1줄 + compacted/orig_lines"
else
  nope "(a) 요약본 포맷 위반 ($(is_compacted "$FA"))"
fi

# (b) compaction_log 감사 기록
clog() {
python3 - "$ADB" <<'PY'
import sqlite3, sys
try:
    rows = sqlite3.connect(sys.argv[1]).execute(
        "SELECT cluster_topic, session_ids, lines_before, lines_after, report_path "
        "FROM compaction_log").fetchall()
except sqlite3.OperationalError as e:
    print("NOTABLE:%s" % e); raise SystemExit
print(len(rows))
for r in rows:
    print("|".join(str(x) for x in r))
PY
}
CLOG="$(clog)"
if printf '%s' "$CLOG" | grep -q "압축 대상 A"; then
  ok "(b) compaction_log: 클러스터 주제 기록"
else
  nope "(b) compaction_log 미기록 ($CLOG)"
fi
if printf '%s' "$CLOG" | grep -q "c-a" && printf '%s' "$CLOG" | grep -q "9|2"; then
  ok "(b) compaction_log: session_ids + lines_before 9 → lines_after 2"
else
  nope "(b) compaction_log 수치 불일치 ($CLOG)"
fi

# (d) HEAD blob 없는 파일 — clean 이어도 거부
if [[ "$(fline "$FD")" == "2" && "$(dbrows c-d)" == "2" ]]; then
  ok "(d) HEAD blob 부재(커밋 0회) 세션은 apply 거부 — 파일·DB 원문 보존"
else
  nope "(d) 커밋 0회 파일이 압축됨 (file=$(fline "$FD") db=$(dbrows c-d))"
fi
if grep -q "c-d" "$TMP/apply.err" 2>/dev/null; then
  ok "(d) 스킵 경고 출력"
else
  nope "(d) 스킵 경고 없음"
fi

# (d2) ★HEAD blob 가드 단독 검증 — status 는 clean 이므로 clean 가드로는 못 막는다
if [[ "$(fline "$FG")" == "2" && "$(dbrows c-g)" == "2" ]]; then
  ok "(d2) gitignore 된(clean·HEAD blob 부재) 세션도 apply 거부 — 원문 보존"
else
  nope "(d2) 원문이 git 에 없는 파일을 압축함 — 영구 소실 (file=$(fline "$FG") db=$(dbrows c-g))"
fi

# (e) dirty 파일 거부
if [[ "$(fline "$FE")" == "4" && "$(dbrows c-e)" == "3" ]]; then
  ok "(e) dirty 세션은 apply 거부 — 파일·DB 불변"
else
  nope "(e) dirty 파일이 압축됨 (file=$(fline "$FE") db=$(dbrows c-e))"
fi

# 하드 삭제 없음 — 원문 blob 이 git 에 상존
if git -C "$AP" cat-file -e "HEAD:$RELA" 2>/dev/null &&
   [[ "$(git -C "$AP" show "HEAD:$RELA" 2>/dev/null | wc -l | tr -d ' ')" == "5" ]]; then
  ok "하드 삭제 없음: 원문 5줄이 HEAD blob 에 상존"
else
  nope "원문 blob 소실"
fi

# 복구 경로 안내 (리포트 또는 stderr) — git 복원 + reindex --force
if grep -q "git checkout" "$TMP/apply.err" "$AREPORT" 2>/dev/null &&
   grep -q "hermes-reindex.py" "$TMP/apply.err" "$AREPORT" 2>/dev/null &&
   grep -q -- "--force" "$TMP/apply.err" "$AREPORT" 2>/dev/null; then
  ok "복구 경로 안내(git checkout → reindex --force) 명시"
else
  nope "복구 경로 안내 없음"
fi

# (f) ★전량 backfill export 후에도 요약본 유지 (DB 가 요약본이므로 되돌아가지 않는다)
#     export 는 DB 5컬럼을 재작성하므로 요약 content 는 그대로 살아남는다.
#     (JSON 최상위 compacted/orig_lines 는 export 가 명시적으로 물려준다 — 섹션 7 G5)
python3 "$SCRIPTS/hermes-export-history.py" --db "$ADB" --project "$AP" --all >/dev/null 2>&1
if [[ -f "$FA" && "$(fline "$FA")" == "1" ]] && grep -q "압축 요약" "$FA" &&
   ! grep -q "대화 c-a-0" "$FA"; then
  ok "(f) 전량 backfill export 후에도 요약본 유지(파일명·1행·요약 content)"
else
  nope "(f) 전량 export 가 요약본을 원문으로 되돌림 (file=$(fline "$FA"))"
fi

# (g) reindex(--force 없이) — 행수 1=1 이라 감소 가드 미발동
python3 "$SCRIPTS/hermes-reindex.py" --db "$ADB" --project "$AP" \
  >/dev/null 2>"$TMP/reindex.err"
if [[ "$(fline "$FA")" == "1" && "$(dbrows c-a)" == "1" ]]; then
  ok "(g) reindex(no --force): 요약본 유지, 행수 1=1"
else
  nope "(g) reindex 후 불일치 (file=$(fline "$FA") db=$(dbrows c-a))"
fi
if grep -q "재색인 거부" "$TMP/reindex.err" 2>/dev/null; then
  nope "(g) 행수 감소 가드가 발동함 — 파일·DB 발산"
else
  ok "(g) 행수 감소 가드 미발동(압축·export·reindex 3자 정합)"
fi

# (c) 원문 복구: git blob → 파일 → reindex --force → DB 원문 N행 복원
git -C "$AP" show "$COMMIT:$RELA" > "$FA" 2>/dev/null
python3 "$SCRIPTS/hermes-reindex.py" --db "$ADB" --project "$AP" --force >/dev/null 2>&1
if [[ "$(fline "$FA")" == "5" && "$(dbrows c-a)" == "5" ]]; then
  ok "(c) 원문 복구: git blob 복원 + reindex --force 로 DB 5행 복원"
else
  nope "(c) 원문 복구 실패 (file=$(fline "$FA") db=$(dbrows c-a))"
fi

# apply 는 커밋하지 않는다 — 압축 후에도 HEAD 는 그대로
if [[ "$(git -C "$AP" rev-parse HEAD 2>/dev/null)" == "$COMMIT" ]]; then
  ok "apply 는 git 커밋을 하지 않는다(HEAD 불변)"
else
  nope "apply 가 커밋을 만들었다"
fi

echo "── 섹션 5: 데이터손실 가드 · 발산 감사 · 재압축 멱등 (T4 리뷰) ──"

# 섹션 4 와 달리 시나리오마다 독립 git 프로젝트를 쓴다 — proposal 파일명이
# 날짜 1개뿐이라 한 프로젝트에서 여러 제안을 돌리면 서로 덮어쓴다.
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

# 섹션 5 공용 mock claude — 환각 필터가 프로젝트에 실재하는 id 만 남긴다
mk_mock "$TMP/bin-s5" '
cat <<JSON
[{"topic":"섹션5 클러스터","session_ids":["f1-a","f4-a","f5-a","f5-b"],"summary":"공통 결론"}]
JSON
exit 0'
propose5() {     # $1=db $2=project
  PATH="$TMP/bin-s5:$PATH" python3 "$SCRIPTS/hermes-lifecycle.py" \
    --db "$1" --project "$2" --propose --age-days 90 >/dev/null 2>&1
}

# ── (F1) DB 행수 > 파일 행수 드리프트 → 압축 거부 ────────────────────────────
# Stop 훅 export 가 조용히 실패해 파일만 뒤처진 상태. 압축하면 DB 에만 있던
# 원문이 git 어디에도 없이 영구 소실된다.
L1="$TMP/s5-drift"; L1DB="$L1/.hermes/state.db"; L1H="$L1/.hermes/history"
mk_project "$L1"
F1F="$(fixture5 "$L1DB" "$L1H" f1-a 8)"
head -n 3 "$F1F" > "$F1F.part" && mv "$F1F.part" "$F1F"   # 파일만 3행으로 뒤처짐
commit_hist "$L1"

if [[ "$(lines_of "$F1F")" == "3" && "$(rows_of "$L1DB" f1-a)" == "8" ]] &&
   [[ -z "$(git -C "$L1" status --porcelain -- ".hermes/history/$(basename "$F1F")" 2>/dev/null)" ]]; then
  ok "전제(F1): 파일 3행(커밋·clean) vs DB 8행 드리프트 구성"
else
  nope "전제(F1) 구성 실패 (file=$(lines_of "$F1F") db=$(rows_of "$L1DB" f1-a))"
fi

propose5 "$L1DB" "$L1"
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L1DB" --project "$L1" --apply \
  >/dev/null 2>"$TMP/s5-f1.err"
if [[ "$(lines_of "$F1F")" == "3" && "$(rows_of "$L1DB" f1-a)" == "8" ]]; then
  ok "(F1) DB 8행 > 파일 3행 → 압축 거부, 파일·DB 불변"
else
  nope "(F1) 드리프트 세션이 압축됨 — DB 원문 영구 소실 (file=$(lines_of "$F1F") db=$(rows_of "$L1DB" f1-a))"
fi
if grep -q "hermes-export-history.py" "$TMP/s5-f1.err" 2>/dev/null &&
   grep -q "f1-a" "$TMP/s5-f1.err" 2>/dev/null; then
  ok "(F1) 경고에 export 동기화 안내 포함"
else
  nope "(F1) export 동기화 안내 없음"
fi

# ── (F2)(F3) os.replace 실패 주입 → 발산 안내 방향 + 감사 기록 ───────────────
# 실제 발산을 재현한다: DB 는 요약본으로 교체되고 파일은 원문 그대로 남는다.
L2="$TMP/s5-diverge"; L2DB="$L2/.hermes/state.db"; L2H="$L2/.hermes/history"
mk_project "$L2"
F2F="$(fixture5 "$L2DB" "$L2H" f2-a 3)"
commit_hist "$L2"

cat > "$TMP/diverge.py" <<'PY'
import json, os, sqlite3, sys
sys.path.insert(0, os.environ["SCRIPTS"])
import hermes_lifecycle_apply as A
db, project, sid, path = sys.argv[1:5]
real_replace = os.replace
def boom(src, dst):                       # history 파일 교체만 실패시킨다
    if str(dst).endswith(".jsonl"):
        raise OSError(1, "주입된 파일 교체 실패")
    return real_replace(src, dst)
os.replace = boom
con = sqlite3.connect(db)
con.isolation_level = None
res = A.apply_proposal(
    con, project, {sid: path},
    {"clusters": [{"topic": "발산 주제", "session_ids": [sid], "summary": "요약"}]},
    "(테스트 리포트)")
print(json.dumps(res, ensure_ascii=False))
PY
D_OUT="$(SCRIPTS="$SCRIPTS" python3 "$TMP/diverge.py" "$L2DB" "$L2" f2-a "$F2F" 2>"$TMP/s5-f2.err")"

if [[ "$(lines_of "$F2F")" == "3" && "$(rows_of "$L2DB" f2-a)" == "1" ]]; then
  ok "전제(F2): 실제 발산 재현 — 파일 3행(원문) vs DB 1행(요약본)"
else
  nope "전제(F2) 발산 미재현 (file=$(lines_of "$F2F") db=$(rows_of "$L2DB" f2-a))"
fi
if grep -q "hermes-reindex.py" "$TMP/s5-f2.err" 2>/dev/null &&
   ! grep -q "hermes-export-history.py" "$TMP/s5-f2.err" 2>/dev/null; then
  ok "(F2) 발산 안내가 reindex(파일→DB) 방향 — 원문 파일이 정본"
else
  nope "(F2) 발산 안내가 export(DB→파일) 방향 — 살아남은 원문을 파괴 ($(tr '\n' ' ' < "$TMP/s5-f2.err"))"
fi

diverged_check() {
python3 - "$1" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    print("NO(파싱실패 %s)" % e); raise SystemExit
ok = d.get("diverged") == ["f2-a"] and "f2-a" not in (d.get("skipped") or [])
print("YES" if ok else "NO(%s)" % json.dumps(d, ensure_ascii=False))
PY
}
if [[ "$(diverged_check "$D_OUT")" == "YES" ]]; then
  ok "(F3) 발산이 skipped 와 분리된 diverged 로 집계"
else
  nope "(F3) 발산이 스킵으로 위장됨 ($(diverged_check "$D_OUT"))"
fi

clog5() {
python3 - "$1" <<'PY'
import sqlite3, sys
try:
    rows = sqlite3.connect(sys.argv[1]).execute(
        "SELECT session_ids, reason FROM compaction_log").fetchall()
except sqlite3.OperationalError as e:
    print("NOTABLE:%s" % e); raise SystemExit
for sids, reason in rows:
    print("%s|%s" % (sids, reason))
PY
}
CLOG5="$(clog5 "$L2DB")"
if grep -q "f2-a" <<<"$CLOG5" && grep -q "발산" <<<"$CLOG5"; then
  ok "(F3) compaction_log 에 발산 사유 감사 기록"
else
  nope "(F3) 파괴적 부분실패가 감사에 미기록 (clog='$CLOG5')"
fi

# ── (F4) 압축 후 재-select_candidates 에서 제외 (재압축·정보 퇴화 차단) ──────
L4="$TMP/s5-idem"; L4DB="$L4/.hermes/state.db"; L4H="$L4/.hermes/history"
mk_project "$L4"
F4F="$(fixture5 "$L4DB" "$L4H" f4-a 6)"
commit_hist "$L4"
propose5 "$L4DB" "$L4"
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L4DB" --project "$L4" --apply \
  >/dev/null 2>"$TMP/s5-f4.err"
if [[ "$(lines_of "$F4F")" == "1" && "$(rows_of "$L4DB" f4-a)" == "1" ]]; then
  ok "전제(F4): 1차 압축 성공(파일 1행 ⟺ DB 1행)"
else
  nope "전제(F4): 1차 압축 실패 (file=$(lines_of "$F4F") db=$(rows_of "$L4DB" f4-a))"
fi
CAND4="$(python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L4DB" --project "$L4" --age-days 90 2>/dev/null)"
if grep -q "f4-a" <<<"$CAND4"; then
  nope "(F4) 압축된 세션이 여전히 후보 — 2차 압축·정보 퇴화 (cand='$CAND4')"
else
  ok "(F4) 압축된 세션은 후보에서 제외(2차 압축 차단)"
fi
# 전량 export → reindex 왕복 후에도 유지되는가 (JSONL 필드가 아니라 DB 가 정본)
python3 "$SCRIPTS/hermes-export-history.py" --db "$L4DB" --project "$L4" --all >/dev/null 2>&1
python3 "$SCRIPTS/hermes-reindex.py" --db "$L4DB" --project "$L4" >/dev/null 2>&1
CAND4B="$(python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L4DB" --project "$L4" --age-days 90 2>/dev/null)"
if grep -q "f4-a" <<<"$CAND4B"; then
  nope "(F4) export/reindex 왕복 후 압축 표식 소실 — 후보로 부활 (cand='$CAND4B')"
else
  ok "(F4) 전량 export→reindex 왕복 후에도 후보에서 제외 유지"
fi

# ── (F5) apply 시 게이트 재평가 + 리포트 소비 표시 ───────────────────────────
L5="$TMP/s5-gate"; L5DB="$L5/.hermes/state.db"; L5H="$L5/.hermes/history"
mk_project "$L5"
F5A="$(fixture5 "$L5DB" "$L5H" f5-a 5)"
F5B="$(fixture5 "$L5DB" "$L5H" f5-b 4)"
commit_hist "$L5"
propose5 "$L5DB" "$L5"
L5JSON="$L5/.hermes/lifecycle/$(date +%F)-proposal.json"
if [[ -f "$L5JSON" ]] && grep -q "f5-b" "$L5JSON"; then
  ok "전제(F5): 제안에 f5-a·f5-b 포함"
else
  nope "전제(F5): 제안 생성 실패"
fi
# 제안 이후 f5-b 가 재활용됨 → ② 게이트 탈락
PYTHONPATH="$SCRIPTS" python3 -c "
import sqlite3, sys, hermes_reuse as r
con = sqlite3.connect(sys.argv[1]); r.mark_reused(con, ['f5-b']); con.commit()
" "$L5DB" >/dev/null 2>&1
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L5DB" --project "$L5" --apply \
  >/dev/null 2>"$TMP/s5-f5.err"
if [[ "$(lines_of "$F5A")" == "1" && "$(rows_of "$L5DB" f5-a)" == "1" ]]; then
  ok "(F5) 게이트 유지 세션(f5-a)은 정상 압축"
else
  nope "(F5) f5-a 압축 실패 (file=$(lines_of "$F5A") db=$(rows_of "$L5DB" f5-a))"
fi
if [[ "$(lines_of "$F5B")" == "4" && "$(rows_of "$L5DB" f5-b)" == "4" ]]; then
  ok "(F5) 제안 이후 재활용된 세션(f5-b)은 apply 가 재평가해 스킵"
else
  nope "(F5) 낡은 리포트로 게이트 탈락 세션이 압축됨 (file=$(lines_of "$F5B") db=$(rows_of "$L5DB" f5-b))"
fi
if grep -q "f5-b" "$TMP/s5-f5.err" 2>/dev/null; then
  ok "(F5) 게이트 탈락 스킵 사유 출력"
else
  nope "(F5) 게이트 탈락 사유 미출력"
fi
if grep -q "applied_at" "$L5JSON" 2>/dev/null; then
  ok "(F5) 적용된 proposal.json 에 applied_at 기록"
else
  nope "(F5) applied_at 미기록 — 낡은 리포트 재적용 차단 불가"
fi
# 같은 리포트 재적용 → 거부. 요약본을 커밋해 git 가드를 통과시켜 놓고(= 가드가
# 아니라 소비 표시가 막는 것임을 분리), compaction_log 행수 불변으로 확인한다.
commit_hist "$L5"
CLOG_BEFORE="$(clog5 "$L5DB" | wc -l | tr -d ' ')"
python3 "$SCRIPTS/hermes-lifecycle.py" --db "$L5DB" --project "$L5" --apply \
  >/dev/null 2>"$TMP/s5-f5b.err"
CLOG_AFTER="$(clog5 "$L5DB" | wc -l | tr -d ' ')"
if [[ "$CLOG_BEFORE" == "$CLOG_AFTER" ]] && grep -q "재적용" "$TMP/s5-f5b.err" 2>/dev/null; then
  ok "(F5) 적용 완료된 proposal.json 재적용 거부"
else
  nope "(F5) 재적용이 다시 실행됨 (clog $CLOG_BEFORE→$CLOG_AFTER, err='$(tr '\n' ' ' < "$TMP/s5-f5b.err")')"
fi

echo "── 섹션 6: SessionStart throttle 훅 — 3~6개월 자동 dry-run 제안 ──"

# 격리 프로젝트 — 섹션 1~5 상태와 분리
H6="$TMP/hook"; H6DB="$H6/.hermes/state.db"; H6H="$H6/.hermes/history"
H6BIN="$TMP/bin-hook"
HOOK="$ROOT/assets/hooks/claude-sessionstart-lifecycle-lint.sh"
python3 "$SCRIPTS/hermes-init.py" --both "$H6" >/dev/null 2>&1
mkdir -p "$H6H" "$H6BIN"

# mock claude — 클러스터링 프롬프트에 고정 클러스터 JSON 반환(실 LLM 호출 0회)
cat > "$H6BIN/claude" <<'EOF'
#!/usr/bin/env bash
if printf '%s' "$*" | grep -q '주제'; then
  cat <<'JSON'
[{"topic":"모의 훅 주제","session_ids":["h-a","h-b"],"summary":"두 세션의 공통 결론"}]
JSON
  exit 0
fi
echo "NONE"
EOF
chmod +x "$H6BIN/claude"

# 후보 픽스처: 오래됨(200일) + 미재활용 + 결정화 세션 2개(원문 여러 줄 + DB 행)
PYTHONPATH="$SCRIPTS" python3 - "$H6DB" "$H6H" <<'PY' >/dev/null 2>&1
import sqlite3, sys, os, json
from datetime import datetime, timedelta
import hermes_reuse as r
db, hist = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
r.ensure_reuse_table(con)
con.execute("UPDATE session_reuse SET last_reused_at=? WHERE session_id='__epoch__'",
            ((datetime.now() - timedelta(days=200)).isoformat(),))
day = (datetime.now() - timedelta(days=200)).strftime("%Y-%m-%d")
def mk(sid, lines, slots):
    with open(os.path.join(hist, "%s-%s.jsonl" % (day, sid)), "w", encoding="utf-8") as f:
        for i in range(lines):
            row = {"seq": i, "session_id": sid, "role": "user", "content": "대화 %s-%d" % (sid, i)}
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                        "VALUES (?,?,?,?,?)", (row["content"], "user", day, "H6", sid))
    if slots:
        con.execute("INSERT OR REPLACE INTO session_summary (session_id, project_id, slots_json) "
                    "VALUES (?,?,?)", (sid, "H6", json.dumps(slots, ensure_ascii=False)))
    key = "pat-" + sid
    con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count, crystallized) VALUES (?,3,1)", (key,))
    con.execute("INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) VALUES (?,?)", (key, sid))
mk("h-a", 5, {"decisions": ["A 채택"], "facts": ["B 느림"]})
mk("h-b", 4, None)
con.commit()
PY

MARKER="$H6/.hermes/.lifecycle-lint-marker"
H6REPORT="$H6/.hermes/lifecycle/$(date +%F)-proposal.md"

# 훅 실행 헬퍼 — startup source 주입, claude mock PATH, 워크트리 아닌 실경로
run_hook() {
  printf '%s' '{"source":"startup"}' | \
    env CLAUDE_PROJECT_DIR="$H6" PATH="$H6BIN:$PATH" bash "$HOOK" 2>/dev/null
}

# 불변 스냅샷: history 원문 라인수 합 + DB session_history 행수 + compaction_log 행수
snap6() {
python3 - "$H6DB" "$H6H" <<'PY'
import sqlite3, sys, os
db, hist = sys.argv[1], sys.argv[2]
total = 0
for n in sorted(os.listdir(hist)):
    with open(os.path.join(hist, n), encoding="utf-8") as f:
        total += sum(1 for _ in f)
con = sqlite3.connect(db)
rows = con.execute("SELECT COUNT(*) FROM session_history").fetchone()[0]
try:
    clog = con.execute("SELECT COUNT(*) FROM compaction_log").fetchone()[0]
except Exception:
    clog = 0
print("lines=%d rows=%d clog=%d" % (total, rows, clog))
PY
}

BEFORE6="$(snap6)"

# (a) throttle 안 지남(마커 방금) → 스킵. propose 미실행·리포트 미생성·stdout 무출력.
mkdir -p "$H6/.hermes"; touch "$MARKER"
rm -rf "$H6/.hermes/lifecycle"
out_a="$(run_hook)"
sleep 1   # 혹시 백그라운드가 떴다면 리포트가 생길 시간을 준다(스킵이면 안 생겨야 함)
if [[ -z "$out_a" ]]; then ok "(a) throttle 스킵: stdout 무출력"; else nope "(a) stdout 오염 ('$out_a')"; fi
if [[ ! -e "$H6REPORT" ]]; then ok "(a) throttle 스킵: propose 미실행(리포트 미생성)"; else nope "(a) throttle 내인데 리포트 생성됨"; fi

# (b) throttle 지남(마커 없음) + 후보 있음 → propose 백그라운드 → 폴링(≤15s) → 리포트 생성.
rm -f "$MARKER"; rm -rf "$H6/.hermes/lifecycle"
out_b="$(run_hook)"
if [[ -z "$out_b" ]]; then ok "(b) 실행 경로: stdout 무출력"; else nope "(b) stdout 오염 ('$out_b')"; fi
for _ in $(seq 1 30); do [[ -f "$H6REPORT" ]] && break; sleep 0.5; done
if [[ -f "$H6REPORT" ]] && grep -q "모의 훅 주제" "$H6REPORT" 2>/dev/null; then
  ok "(b) throttle 경과: propose 백그라운드 실행 → proposal 리포트 생성"
else
  nope "(b) 리포트 미생성/주제 누락 (report exists: $([[ -f "$H6REPORT" ]] && echo yes || echo no))"
fi

# (c) --apply 자동 미실행: 훅 실행 후에도 history 원문·DB session_history 불변(자동 압축 없음).
AFTER6="$(snap6)"
if [[ "$BEFORE6" == "$AFTER6" ]]; then
  ok "(c) --apply 자동 미실행: history 원문·DB·compaction_log 불변 ($AFTER6)"
else
  nope "(c) 자동 압축 발생 (before='$BEFORE6' after='$AFTER6')"
fi

# (d) 마커 선-touch 로 throttle 갱신 → 재실행 즉시 스킵(리포트 재생성 안 됨).
if [[ -f "$MARKER" ]]; then ok "(d) 실행 시 마커 선-touch 생성"; else nope "(d) 마커 미생성 — 이중기동 방지 불가"; fi
rm -rf "$H6/.hermes/lifecycle"
out_d="$(run_hook)"
sleep 1
if [[ ! -e "$H6REPORT" ]]; then
  ok "(d) 마커 선-touch 로 throttle 갱신 → 재실행 즉시 스킵"
else
  nope "(d) 재실행이 스킵되지 않음(리포트 재생성됨) — 마커 선-touch 미동작"
fi
if [[ -z "$out_d" ]]; then ok "(d) 재실행 스킵: stdout 무출력"; else nope "(d) stdout 오염 ('$out_d')"; fi

echo "── 섹션 7: 압축의 기계-로컬성 방어 (다기계 발산·전량 export 되돌림) ──"

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

# ── 섹션 7 후반 공용 헬퍼: 압축본 파일 쓰기 · DB 행 조작 ─────────────────────
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
db_replace_with_summary() {   # $1=db $2=sid $3=요약 content — DB 세션 행을 요약 1행으로
python3 - "$1" "$2" "$3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("DELETE FROM session_history WHERE session_id=?", (sys.argv[2],))
con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
            "VALUES (?,?,?,?,?)",
            (sys.argv[3], "system", "2026-01-01T10:00:00.000000", "PA", sys.argv[2]))
con.commit()
PY
}
db_append_rows() {   # $1=db $2=sid $3=행수 — 재개 대화 n행 추가
python3 - "$1" "$2" "$3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
for i in range(int(sys.argv[3])):
    con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?,?,?,?,?)",
                ("재개 대화 %d" % i, "user", "2026-01-02T10:00:00.000000", "PA", sys.argv[2]))
con.commit()
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

# ── (G11) 압축 세션 재개 → --session export 가 정상 통과해야 한다 (F6) ───────
# DB = 요약 1행 + 신규 2행. 이걸 스킵하면 새 대화가 영영 git 에 안 나간다.
MR="$TMP/m-resume"; MRDB="$MR/.hermes/state.db"; MRH="$MR/.hermes/history"
mk_project "$MR"
FRS="$(fixture5 "$MRDB" "$MRH" res-a 5)"
RSUM="$(write_compacted "$FRS" res-a 5)"
db_replace_with_summary "$MRDB" res-a "$RSUM"
db_append_rows "$MRDB" res-a 2
if [[ "$(lines_of "$FRS")" == "1" && "$(rows_of "$MRDB" res-a)" == "3" ]]; then
  ok "전제(G11) 재개 상태: 파일 1행(압축본) vs DB 3행(요약1+신규2)"
else
  nope "전제(G11) 구성 실패 (file=$(lines_of "$FRS") db=$(rows_of "$MRDB" res-a))"
fi
python3 "$SCRIPTS/hermes-export-history.py" --db "$MRDB" --project "$MR" \
  --session res-a >/dev/null 2>"$TMP/s7-resume.err"
FRS2="$(printf '%s' "$MRH"/*res-a.jsonl)"
if [[ "$(lines_of "$FRS2")" == "3" ]]; then
  ok "(G11) 재개 세션이 정상 export — 신규 대화가 파일에 반영(3행)"
else
  nope "(G11) 재개인데 가드가 스킵 — 신규 대화가 영구히 git 밖에 갇힘 (file=$(lines_of "$FRS2") err='$(tr '\n' ' ' < "$TMP/s7-resume.err")')"
fi
if grep -q "거부" "$TMP/s7-resume.err" 2>/dev/null; then
  nope "(G11) 재개인데 '덮어쓰기 거부' 경고 — 사실과 다른 진단"
else
  ok "(G11) 재개에는 거부 경고 없음"
fi
if grep -q "재개 대화" "$FRS2" 2>/dev/null; then
  ok "(G11) export 된 파일에 신규 대화 내용 실재"
else
  nope "(G11) 신규 대화가 파일에 없음"
fi

# ── (G12) 발산(DB 원문 N행) → --session 경로도 스킵 + 경고 (F6 반대 방향) ────
MV="$TMP/m-div-sess"; MVDB="$MV/.hermes/state.db"; MVH="$MV/.hermes/history"
mk_project "$MV"
FDV="$(fixture5 "$MVDB" "$MVH" div-a 6)"
write_compacted "$FDV" div-a 6 >/dev/null       # 파일만 압축본, DB 는 원문 6행
commit_hist "$MV"
python3 "$SCRIPTS/hermes-export-history.py" --db "$MVDB" --project "$MV" \
  --session div-a >/dev/null 2>"$TMP/s7-divsess.err"
if [[ "$(lines_of "$FDV")" == "1" ]] && [[ "$(is_compacted "$FDV")" == "YES" ]]; then
  ok "(G12) 발산 세션의 --session export 도 압축본을 되돌리지 않음"
else
  nope "(G12) --session export 가 압축을 원문으로 복귀 (file=$(lines_of "$FDV") compacted=$(is_compacted "$FDV"))"
fi
if grep -q "div-a" "$TMP/s7-divsess.err" 2>/dev/null; then
  ok "(G12) 발산 스킵 경고에 세션 id 포함"
else
  nope "(G12) 발산 스킵 경고 없음 ('$(tr '\n' ' ' < "$TMP/s7-divsess.err")')"
fi

# ── (G13) carry 위조 금지: DB 1행이 원문이면 compacted 마커를 붙이지 않는다 (F7) ──
MF="$TMP/m-forge"; MFDB="$MF/.hermes/state.db"; MFH="$MF/.hermes/history"
mk_project "$MF"
FFG="$(fixture5 "$MFDB" "$MFH" forge-a 1)"      # DB 1행 = 원문
write_compacted "$FFG" forge-a 1 >/dev/null     # 파일만 압축본(다른 기계 산물)
commit_hist "$MF"
python3 "$SCRIPTS/hermes-export-history.py" --db "$MFDB" --project "$MF" --all \
  >/dev/null 2>"$TMP/s7-forge.err"
FFG2="$(printf '%s' "$MFH"/*forge-a.jsonl)"
if grep -q "compacted" "$FFG2" 2>/dev/null; then
  nope "(G13) 원문 1행에 compacted 마커 위조 — 다음 기계 가드가 정상 export 를 거부하게 된다"
else
  ok "(G13) 원문 1행에는 compacted 마커를 붙이지 않음"
fi
if grep -q "대화 forge-a" "$FFG2" 2>/dev/null; then
  ok "(G13) 대조: DB 원문 1행이 그대로 export 됨"
else
  nope "(G13) DB 원문 1행이 export 되지 않음 (file='$(tr '\n' ' ' < "$FFG2" 2>/dev/null)')"
fi

echo "통과:$PASS 실패:$FAIL"
[[ $FAIL -eq 0 ]]
