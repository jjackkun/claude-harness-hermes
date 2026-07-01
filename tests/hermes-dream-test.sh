#!/usr/bin/env bash
# 드림 propose 무손실·신뢰성 회귀 테스트 (HOME 격리 + PATH mock claude)
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"; mkdir -p "$HOME" "$T/bin" "$T/proj/.hermes"
PROJ="$T/proj"; DB="$PROJ/.hermes/state.db"
pass=0; fail=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }
pyq() { python3 -c "import sqlite3,sys; print(sqlite3.connect('$DB').execute(sys.argv[1]).fetchone()[0])" "$1"; }

# DB 초기화 후 드림 1회 호출 → 드림의 _ensure_schema 가 신규 컬럼/테이블 보강
# (요약 0개라 조용히 종료하지만 스키마 보강은 실행됨)
python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" >/dev/null 2>&1

# --- Task1: 스키마 ---
schema_ok() {
python3 - "$DB" <<'PY'
import sqlite3, sys
con=sqlite3.connect(sys.argv[1])
cols={r[1] for r in con.execute("PRAGMA table_info(dream_log)")}
for c in ("failed_chunks","skipped_chunks","watermark_at"): assert c in cols, c
tabs={r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
assert "dream_pending_keys" in tabs
pk={r[1] for r in con.execute("PRAGMA table_info(dream_pending_keys)")}
for c in ("key","created_at"): assert c in pk, c
print("OK")
PY
}
if schema_ok 2>/dev/null | grep -q OK; then check "스키마: dream_log 컬럼3 + dream_pending_keys" true; else check "스키마" false; fi

# --- Task2: 청킹 무손실 ---
chunk_ok() {
PYTHONPATH="$S" python3 - <<'PY'
import importlib.util, os
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
# 작은 요약 5개 + 거대 요약 1개
sums=[{"session_id":f"s{i}","updated_at":f"2026-06-2{i}","slots":{"decisions":[f"dec{i}"*3],"facts":[]}} for i in range(5)]
big={"session_id":"big","updated_at":"2026-06-29","slots":{"decisions":["X"*5000],"facts":[]}}
sums.append(big)
chunks=hd._chunk_summaries(sums, 4000)
# 무손실: 모든 요약이 어느 청크엔가 포함
seen={s["session_id"] for c in chunks for s in c["summaries"]}
assert seen=={s["session_id"] for s in sums}, seen
# 거대 요약은 단독 청크 + 통째(잘림 없음)
big_chunks=[c for c in chunks if any(s["session_id"]=="big" for s in c["summaries"])]
assert len(big_chunks)==1 and len(big_chunks[0]["summaries"])==1
assert "X"*5000 in big_chunks[0]["evidence"]
print("OK")
PY
}
S_DIR="$S"
if S_DIR="$S" chunk_ok 2>/dev/null | grep -q OK; then check "청킹: 무손실 + 거대요약 단독" true; else check "청킹" false; fi

# --- 최종리뷰: 동일 updated_at 형제는 분할 금지(부분실패 영구누락 방지) ---
tie_ok() {
PYTHONPATH="$S" python3 - <<'PY'
import importlib.util, os
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
# 같은 초 timestamp 형제 3개 — 예산이 작아 갈릴 법하나 한 청크에 묶여야 함
T="2026-06-25 10:00:00"
sums=[{"session_id":f"t{i}","updated_at":T,"slots":{"decisions":["w"*60],"facts":[]}} for i in range(3)]
chunks=hd._chunk_summaries(sums, 100)   # 60자×3 > 100 이지만 동일 T라 분할 금지
tied=[c for c in chunks if any(s["updated_at"]==T for s in c["summaries"])]
assert len(tied)==1, [len(c["summaries"]) for c in chunks]   # 형제 전원 한 청크
assert len(tied[0]["summaries"])==3
print("OK")
PY
}
if S_DIR="$S" tie_ok 2>/dev/null | grep -q OK; then check "청킹: 동일 timestamp 형제 분할 금지" true; else check "동일 timestamp 분할금지" false; fi

# --- 최종리뷰: claude 부재 시 _propose_chunk 보류(None) — 무신호 손실 차단 ---
noclaude_ok() {
PYTHONPATH="$S" python3 - <<'PY'
import importlib.util, os
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
os.environ["PATH"]=""   # shutil.which("claude") → None (python3 는 이미 기동됨)
assert hd._propose_chunk("") == []        # 빈 evidence는 정상 진행
assert hd._propose_chunk("- 결정 1") is None   # claude 부재는 보류(실패)
print("OK")
PY
}
if S_DIR="$S" noclaude_ok 2>/dev/null | grep -q OK; then check "청크호출: claude 부재 시 보류(None)" true; else check "claude 부재 보류" false; fi

# --- Task3: 이월 큐 ---
queue_ok() {
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sqlite3, sys
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
con=hd.connect_db(sys.argv[1]); hd._ensure_schema(con)
hd.enqueue_pending_keys(con, ["k1","k2","k2","k3"])   # k2 중복
assert hd.peek_pending_keys(con)==3
got=hd.drain_pending_keys(con, 2)
assert got==["k1","k2"], got            # FIFO
hd.delete_pending_keys(con, got)
assert hd.peek_pending_keys(con)==1
print("OK")
PY
}
if S_DIR="$S" queue_ok 2>/dev/null | grep -q OK; then check "이월 큐: enqueue/peek/drain/delete" true; else check "이월 큐" false; fi

# --- Task4: 청크 호출 재시도 ---
# 전용 mock: 호출 카운터 파일로 첫 호출 실패, 이후 성공
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
CF="${DREAM_CALLCOUNT:-/tmp/none}"
n=0; [ -f "$CF" ] && n=$(cat "$CF"); n=$((n+1)); echo "$n" > "$CF"
if [ "${DREAM_FAIL_FIRST:-0}" = "1" ] && [ "$n" = "1" ]; then echo "boom" >&2; exit 1; fi
echo "alpha-key"; echo "beta-key"
EOF
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"
retry_ok() {
DREAM_CALLCOUNT="$T/cc" DREAM_FAIL_FIRST=1 HERMES_DREAM_TIMEOUT=20 \
PYTHONPATH="$S" python3 - <<'PY'
import importlib.util, os
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
keys=hd._propose_chunk("- 결정 1\n- 사실 2")
assert keys==["alpha-key","beta-key"], keys   # 1회차 실패 후 재시도로 성공
print("OK")
PY
}
if S_DIR="$S" retry_ok 2>/dev/null | grep -q OK; then check "청크호출: 1회 실패 후 재시도 성공" true; else check "청크호출 재시도" false; fi

# --- Task5: 워터마크 + stall ---
wm_ok() {
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
con=hd.connect_db(sys.argv[1]); hd._ensure_schema(con)
con.execute("DELETE FROM dream_log")
# 요약 처리했으나(summary_count>0) 같은 워터마크(NULL)로 진척없음 → stall 2
hd.record_dream(con,3,0,0,0,"r", watermark_at=None, failed_chunks=1, skipped_chunks=0)
hd.record_dream(con,3,0,0,0,"r", watermark_at=None, failed_chunks=1, skipped_chunks=0)
assert hd.get_dream_watermark(con) is None
assert hd.stall_count(con, None)==2, hd.stall_count(con, None)   # NULL-안전
# 워터마크 전진 후 stall 리셋
hd.record_dream(con,1,1,0,0,"r", watermark_at="2026-06-25", failed_chunks=0, skipped_chunks=0)
assert hd.get_dream_watermark(con)=="2026-06-25"
assert hd.stall_count(con, "2026-06-25")==1
# 조용한 날 pending 소진(summary_count=0)은 stall 누적에서 제외 — false 독청크 skip 방지
hd.record_dream(con,0,0,0,0,"r", watermark_at="2026-06-25", failed_chunks=0, skipped_chunks=0)
assert hd.stall_count(con, "2026-06-25")==1, hd.stall_count(con, "2026-06-25")
print("OK")
PY
}
if S_DIR="$S" wm_ok 2>/dev/null | grep -q OK; then check "워터마크+stall: NULL안전 연속카운트" true; else check "워터마크+stall" false; fi

# --- Task6: map-reduce (독청크 skip + 이월) ---
# mock: evidence 에 POISON 있으면 실패, 아니면 키 2개 출력
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
if printf '%s' "$*" | grep -q POISON; then echo "boom" >&2; exit 1; fi
echo "k-$RANDOM"; echo "k-$RANDOM"
EOF
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"
mr_ok() {
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
con=hd.connect_db(sys.argv[1]); hd._ensure_schema(con); con.execute("DELETE FROM dream_log")
os.environ["HERMES_DREAM_STALL_SKIP"]="2"; os.environ["HERMES_DREAM_CHUNK_CHARS"]="100"
# 청크1 정상, 청크2 POISON(거대해서 단독 청크), 청크3 정상
sums=[
 {"session_id":"a","updated_at":"2026-06-21","slots":{"decisions":["x"*80],"facts":[]}},
 {"session_id":"b","updated_at":"2026-06-22","slots":{"decisions":["POISON "+"y"*120],"facts":[]}},
 {"session_id":"c","updated_at":"2026-06-23","slots":{"decisions":["z"*80],"facts":[]}},
]
# 1회차: 청크2에서 실패, stall<2 → break, 워터마크=청크1 마지막
tc,wm,fc,sk=hd.propose_keys(con, sums, None)
assert wm=="2026-06-21", wm            # 청크1까지만
assert fc>=1 and sk==0, (fc,sk)
hd.record_dream(con,len(sums),0,0,0,"r",watermark_at=wm,failed_chunks=fc,skipped_chunks=sk)
# 2회차: since=wm, stall_count=1, +1>=2 → 청크2 skip, 청크3 처리, skipped>=1
sums2=[s for s in sums if s["updated_at"]>"2026-06-21"]
tc2,wm2,fc2,sk2=hd.propose_keys(con, sums2, "2026-06-21")
assert sk2>=1, sk2                     # 독청크 skip
assert wm2=="2026-06-23", wm2          # 청크3까지 전진
print("OK")
PY
}
if S_DIR="$S" mr_ok 2>/dev/null | grep -q OK; then check "map-reduce: 독청크 skip + 워터마크 전진" true; else check "map-reduce" false; fi

# --- Task6: 상한초과 후보 pending 이월 ---
# mock: 호출마다 고유 키 2개(카운터 기반) → 충돌 없는 4개 후보 보장
export OVCTR="$T/ovctr"; : > "$OVCTR"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
n=$(cat "$OVCTR" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$OVCTR"
echo "ov-${n}-a"; echo "ov-${n}-b"
EOF
chmod +x "$T/bin/claude"
ov_ok() {
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
con=hd.connect_db(sys.argv[1]); hd._ensure_schema(con)
con.execute("DELETE FROM dream_log"); con.execute("DELETE FROM dream_pending_keys")
os.environ["HERMES_DREAM_CHUNK_CHARS"]="100"; os.environ["HERMES_DREAM_CRYSTALLIZE_MAX"]="2"
# 청크2개 → 청크당 2키 = 후보 4, cmax=2 → 결정화 2 + overflow 2 이월
sums=[
 {"session_id":"a","updated_at":"2026-06-24","slots":{"decisions":["x"*80],"facts":[]}},
 {"session_id":"b","updated_at":"2026-06-25","slots":{"decisions":["z"*80],"facts":[]}},
]
tc,wm,fc,sk=hd.propose_keys(con, sums, None)
assert len(tc)==2, tc                  # 상한 만큼만 결정화
assert fc==0 and sk==0, (fc,sk)        # 전부 성공
assert hd.peek_pending_keys(con)==2, hd.peek_pending_keys(con)  # 초과분 이월
print("OK")
PY
}
if S_DIR="$S" ov_ok 2>/dev/null | grep -q OK; then check "map-reduce: 상한초과 후보 pending 이월" true; else check "overflow 이월" false; fi

# --- Task7: main 배선 + G8 ---
# 정상 mock (키 1개)
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
if printf '%s' "$*" | grep -q '결정화 후보'; then echo "drained-key"; exit 0; fi
cat <<'MD'
# drained-key
<!-- hermes:auto-generated version:1 created:2026-06-25 -->
## 문제 상황
테스트
## 규칙
- [ ] 확인
## 근거
- 패턴 키: drained-key
MD
EOF
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH"
g8_ok() {
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location("hd", os.path.join(os.environ["S_DIR"],"hermes-dream.py"))
hd=importlib.util.module_from_spec(spec); spec.loader.exec_module(hd)
con=hd.connect_db(sys.argv[1]); hd._ensure_schema(con)
con.execute("DELETE FROM session_summary"); con.execute("DELETE FROM dream_pending_keys")
hd.enqueue_pending_keys(con, ["pk1","pk2"]); con.commit()
print("PENDING_BEFORE", hd.peek_pending_keys(con))
PY
}
S_DIR="$S" g8_ok >/dev/null 2>&1
# 요약 0개 + pending 2개 → 드림이 조기종료 안 하고 pending 소진
HERMES_DREAM_CRYSTALLIZE_MAX=2 python3 "$S/hermes-dream.py" --db "$DB" --project-dir "$PROJ" >/dev/null 2>&1
pend_after=$(pyq "SELECT COUNT(*) FROM dream_pending_keys")
# pending 2 + CRYSTALLIZE_MAX 2 → 전량 소진 기대(0). 부분 소진도 버그로 검출.
if [ "$pend_after" -eq 0 ]; then check "G8: 조용한 날 pending 전량 소진" true; else check "G8 pending 소진" false; fi

echo "통과:$pass 실패:$fail"; [[ $fail -eq 0 ]]
