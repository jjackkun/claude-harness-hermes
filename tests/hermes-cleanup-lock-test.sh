#!/usr/bin/env bash
# hermes-cleanup 잠김 처리 회귀 테스트
#
# 왜 이 테스트가 있는가 (2026-08-25):
#   `hermes-pipeline-test.sh` §20(e) "--apply 는 junk 스킬 삭제" 가 간헐 실패했고,
#   하루 넘게 원인 불명이었다. 자기 설치 후 잡힌 근거로 사슬이 드러났다:
#     1. hermes-dream 이 DB 연결을 연 채로 hermes-cleanup 을 하위 프로세스로 띄운다.
#     2. cleanup 의 skill_index 조회가 그 경합에서 OperationalError 를 만나면
#        **stderr 에 찍고 조용히 계속**한다 → 삭제 대상이 비고 junk 가 남는다.
#     3. dream 은 그 stderr 를 캡처만 하고 버린다.
#   조용히 넘어가는 대신 실패를 종료코드로 드러내야 한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP="$ROOT/scripts/hermes-cleanup.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$CLEANUP" ]] || { echo "  ✗ 전제: cleanup 없음"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: cleanup 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/fakehome"; mkdir -p "$HOME"
cd "$WORK"; mkdir -p proj
PROJ="$WORK/proj"
# 스키마를 손으로 적지 않는다 — 실제 초기화기로 만든다.
# 손으로 적은 스키마는 본체가 바뀌면 조용히 어긋나고, 그 어긋남이 테스트 실패로 위장한다.
python3 "$ROOT/scripts/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
DB="$PROJ/.hermes/state.db"
[[ -f "$DB" ]] || { echo "  ✗ 전제: DB 생성 실패"; echo "PASS=$PASS FAIL=$((FAIL+1))"; exit 1; }
ok "전제: 실제 초기화기로 DB 생성"

SKILLS="$PROJ/.hermes/skills"; mkdir -p "$SKILLS"
# junk 스킬 하나를 skill_index 로만 등록한다 — pattern_count 에는 없다.
# 파이프라인 테스트의 픽스처와 같은 형태이며, 이 항목은 오직 skill_index 조회로만 발견된다.
printf '# 내가\njunk\n' > "$SKILLS/내가.md"
python3 - "$DB" "$SKILLS" <<'EOF'
import sqlite3, sys, os
con = sqlite3.connect(sys.argv[1])
con.execute("INSERT OR IGNORE INTO skill_index (skill_path, keywords, scope) VALUES (?,?,'local')",
            (os.path.join(sys.argv[2], "내가.md"), "내가"))
con.commit()
EOF

echo "── 정상 경로 ──"
python3 "$CLEANUP" --db "$DB" --apply --skills-dir "$SKILLS" >/dev/null 2>&1
RC=$?
[[ $RC -eq 0 ]] && ok "잠김 없으면 정상 종료" || nope "잠김 없으면 정상 종료 (rc=$RC)"
[[ ! -f "$SKILLS/내가.md" ]] && ok "junk 스킬 삭제됨" || nope "junk 스킬 삭제됨"

echo "── 잠김 경로 — 조용히 성공했다고 보고하면 안 된다 ──"
# 파일만 되살리면 안 된다 — 정상 경로가 skill_index 행까지 지웠다.
# 행이 없으면 잠금과 무관하게 대상이 0개라 이 구간이 공허해진다.
printf '# 내가\njunk\n' > "$SKILLS/내가.md"
python3 - "$DB" "$SKILLS" <<'EOF'
import sqlite3, sys, os
con = sqlite3.connect(sys.argv[1])
con.execute("INSERT OR IGNORE INTO skill_index (skill_path, keywords, scope) VALUES (?,?,'local')",
            (os.path.join(sys.argv[2], "내가.md"), "내가"))
con.commit()
EOF
python3 - "$DB" <<'EOF' &
import sqlite3, sys, time
con = sqlite3.connect(sys.argv[1], timeout=1.0)
con.execute("BEGIN EXCLUSIVE")
con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key, count) VALUES ('lockholder', 1)")
sys.stderr.write("LOCKED\n"); sys.stderr.flush()
time.sleep(25)
EOF
LOCKER=$!
# 고정 대기 대신 락 획득을 폴링한다 — 부하에서 흔들리지 않게.
for _ in $(seq 1 100); do
  python3 -c "
import sqlite3,sys
try:
    c=sqlite3.connect('$DB', timeout=0.2)
    c.execute('BEGIN IMMEDIATE'); c.rollback(); sys.exit(1)
except sqlite3.OperationalError:
    sys.exit(0)" && break
  sleep 0.1
done

OUT=$(python3 "$CLEANUP" --db "$DB" --apply --skills-dir "$SKILLS" 2>&1); RC=$?
kill "$LOCKER" 2>/dev/null; wait "$LOCKER" 2>/dev/null

[[ $RC -ne 0 ]] && ok "잠김이면 0 이 아닌 종료코드" \
  || nope "잠김인데 성공으로 보고한다 — 호출부가 실패를 알 수 없다 (rc=$RC)"
echo "$OUT" | grep -q '잠' && ok "잠김 사실을 메시지로 알린다" || nope "잠김 사실을 메시지로 알린다"
echo "$OUT" | grep -qE 'junk 스킬 파일: 0개' \
  && nope "잠겨서 못 본 것을 '0개' 로 보고하면 안 된다" \
  || ok "'0개' 라는 거짓 보고를 하지 않는다"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
