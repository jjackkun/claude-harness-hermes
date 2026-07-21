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

echo "통과:$PASS 실패:$FAIL"
[[ $FAIL -eq 0 ]]
