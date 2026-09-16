#!/usr/bin/env bash
# 운반 계층 검증 (계획 docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 6~11·14·15).
#
#   두 클론 A·B 가 bare 원격 하나를 공유한다.
#   - push: refs/hermes/sync 에 조각·이력·자물쇠가 오르고, 코드 브랜치·작업 트리는 변화 0 (목표 6)
#   - 두 클론이 각자 push 해도 둘 다 올라간다, --force 0 (목표 7)
#   - 열쇠 없는 클론은 H-10 안내를 내고 DB 변경 0, 자물쇠 등록 뒤 pull 로 합류·복호·재색인 (목표 8)
#   - "기억 없음" 3분류가 서로 다른 문구 (목표 9)
#   - backfill 두 번 → 조각 수 동일 (목표 10)
#   - 원격 이력의 자유 글 3칸은 age 암호문, 기계 칸은 평문 (목표 11)
#   - age 없는 컴퓨터에서 훅 exit 0 · 한 줄 알림 · DB 변경 0 (목표 14)
#   - 참조 거부 서버 → "이식 불가 — 사람 판단" (목표 15)
#
# 열쇠는 임시 HOME 에만 만든다. 실행: bash tests/hermes-sync-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}
command -v age >/dev/null 2>&1 || { echo "  ✗ 전제: age 미설치"; echo "PASS=0 FAIL=1"; exit 1; }

BARE="$TMP/bare"; git init -q --bare "$BARE"
mk_clone() {  # <dir> <HOME>
  mkdir -p "$1/scripts/data" "$1/.hermes" "$2"
  cp "$S"/*.py "$S/hermes-keys.sh" "$S/hermes-sync.py" "$1/scripts/"
  cp "$REPO_ROOT/assets/data/bip39-english.txt" "$1/scripts/data/"
  cp "$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh" "$1/scripts/" 2>/dev/null || true
  git init -q "$1"; git -C "$1" config user.name jjackkun; git -C "$1" config user.email t@t
  git -C "$1" remote add origin "$BARE"
  git -C "$1" commit -q --allow-empty -m init
  python3 "$S/hermes-init.py" --project "$1" >/dev/null 2>&1
  echo '{"push": true}' > "$1/.hermes/sync.json"
}
A="$TMP/A"; HA="$TMP/homeA"; B="$TMP/B"; HB="$TMP/homeB"
mk_clone "$A" "$HA"; mk_clone "$B" "$HB"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$A')"
cp "$A/.hermes/universe.id" "$B/.hermes/"          # clone 으로 받는 커밋 파일을 흉내
UNI="$(cat "$A/.hermes/universe.id")"
SYNC_A() { HOME="$HA" python3 "$A/scripts/hermes-sync.py" --project "$A" "$@"; }
SYNC_B() { HOME="$HB" python3 "$B/scripts/hermes-sync.py" --project "$B" "$@"; }
KEYS_A() { HOME="$HA" bash "$A/scripts/hermes-keys.sh" "$@" --project "$A"; }
KEYS_B() { HOME="$HB" bash "$B/scripts/hermes-keys.sh" "$@" --project "$B"; }
remote_ls() { git -C "$A" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$A" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
rows() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]+'/.hermes/state.db').execute(sys.argv[2]).fetchone()[0])" "$1" "$2" 2>/dev/null || echo err; }

echo "== 1. 없음 3분류 — 저장소 없음 (목표 9) =="
KEYS_A init >/dev/null 2>&1
assert "원격에 저장소 없음 문구" 1 "$(SYNC_A status | grep -c '기억 저장소.*없습니다')"

echo ""
echo "== 2. A push — 조각·이력·자물쇠 (목표 6·11) =="
mkdir -p "$A/.hermes/history/sess-1"
printf '{"seq":0,"session_id":"sess-1","project_id":"p","role":"user","timestamp":"2026-09-16T00:00:00","content":"A 의 대화 원문 첫 줄"}\n' > "$A/.hermes/history/sess-1/0000.jsonl"
HOME="$HA" python3 "$A/scripts/hermes-journal.py" --project "$A" emit --json '{"kind":"task.started","task_id":"t1","intent":"비밀 의도 한 줄","actor":"agent:main"}' >/dev/null
HEAD_BEFORE="$(git -C "$A" rev-parse HEAD)"; WT_BEFORE="$(git -C "$A" status --porcelain | md5sum)"
SYNC_A push >"$TMP/pushA.out" 2>&1
assert "push 종료 코드 0" 0 "$?"
assert "원격에 refs/hermes/sync 존재" 1 "$(git ls-remote "$BARE" refs/hermes/sync | grep -c .)"
assert "코드 브랜치 HEAD 불변" "$HEAD_BEFORE" "$(git -C "$A" rev-parse HEAD)"
assert "작업 트리 변경 0(전후 동일)" "$WT_BEFORE" "$(git -C "$A" status --porcelain | md5sum)"
assert "원격에 조각 1개" 1 "$(remote_ls | grep -c '^history/sess-1/0000\.enc$')"
assert "원격에 이력 1개" 1 "$(remote_ls | grep -c '^journal/2026/09/16/.*\.json$')"
assert "원격에 자물쇠 + 감싼 마스터" 2 "$(remote_ls | grep -c '^keys/jjackkun/')"
assert "조각은 age 암호문" 1 "$(git -C "$A" show refs/hermes/sync-remote:history/sess-1/0000.enc | head -c 21 | grep -c 'age-encryption.org')"
JPATH="$(remote_ls | grep '^journal/')"
assert "이력의 intent 는 age 암호문(J-07)" 1 "$(git -C "$A" show "refs/hermes/sync-remote:$JPATH" | python3 -c "import json,sys;print(1 if json.load(sys.stdin)['intent'].startswith('-----BEGIN AGE ENCRYPTED FILE-----') else 0)")"
assert "이력의 기계 칸(kind)은 평문" task.started "$(git -C "$A" show "refs/hermes/sync-remote:$JPATH" | python3 -c "import json,sys;print(json.load(sys.stdin)['kind'])")"
assert "원문 어디에도 평문 없음" 0 "$(git -C "$A" show refs/hermes/sync-remote:history/sess-1/0000.enc | grep -ac '대화 원문')"
SYNC_A push >"$TMP/pushA2.out" 2>&1
assert "재push 는 올릴 것 없음(멱등)" 1 "$(grep -c '올릴 것 없음' "$TMP/pushA2.out")"

echo ""
echo "== 3. B — 열쇠 없음 → H-10 안내, DB 변경 0 (목표 8·9) =="
DB_B_BEFORE="$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
SYNC_B pull >"$TMP/pullB.out" 2>&1
assert "pull 종료 코드 0(멈추지 않음)" 0 "$?"
assert "'열쇠가 없습니다' 안내" 1 "$(grep -c '열쇠가 없습니다' "$TMP/pullB.out")"
assert "안내에 조각 수(1건) 포함" 1 "$(grep -c '조각 1건' "$TMP/pullB.out")"
assert "state.db 변경 0" "$DB_B_BEFORE" "$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
assert "status 도 열쇠 없음 분류" 1 "$(SYNC_B status | grep -c '열쇠가 없습니다')"

echo ""
echo "== 4. B 합류 — 자물쇠 등록 → pull 로 마스터 풀고 조각 복호 (목표 8) =="
# B 는 자기 컴퓨터 자물쇠만 만든다(마스터 없음). 실제로는 age-keygen 을 사람이 세션 밖에서.
mkdir -p "$HB/.hermes/keys/$UNI"; age-keygen -o "$HB/.hermes/keys/$UNI/computer.key" >/dev/null 2>&1
B_LOCK="$(age-keygen -y "$HB/.hermes/keys/$UNI/computer.key")"
KEYS_A add-computer "$B_LOCK" >/dev/null 2>&1      # A 에서 B 자물쇠 등록
SYNC_A push >/dev/null 2>&1                        # 감싼 마스터가 원격으로
SYNC_B pull >"$TMP/pullB2.out" 2>&1
assert "B 가 감싼 마스터를 받아 풀었다" 1 "$(grep -c '감싼 마스터를 받아 풀었습니다' "$TMP/pullB2.out")"
assert "B 마스터 열쇠 생성(0600)" 600 "$(stat -c '%a' "$HB/.hermes/keys/$UNI/master.key")"
assert "B 에 조각이 복호돼 놓임" 1 "$([[ -f "$B/.hermes/history/sess-1/0000.jsonl" ]] && echo 1 || echo 0)"
assert "복호된 조각 내용 동일" "$(cat "$A/.hermes/history/sess-1/0000.jsonl")" "$(cat "$B/.hermes/history/sess-1/0000.jsonl")"
assert "B 이력에 이벤트 적재, intent 평문 복원" "비밀 의도 한 줄" "$(rows "$B" "select intent from journal_events where task_id='t1'")"
assert "sync_cursor 에 받은 경로 기록(조각 1 + 이력 1)" 2 "$(rows "$B" "select count(*) from sync_cursor")"
python3 "$S/hermes-reindex.py" --db "$B/.hermes/state.db" --project "$B" >/dev/null 2>&1
assert "재색인으로 session_history 복원" 1 "$(rows "$B" "select count(*) from session_history where session_id='sess-1'")"
SYNC_B pull >"$TMP/pullB3.out" 2>&1
assert "재pull 은 새 항목 0(멱등)" 1 "$(grep -c '새 항목 0건' "$TMP/pullB3.out")"

echo ""
echo "== 5. 두 클론 동시 push — 둘 다 올라감, --force 0 (목표 7) =="
mkdir -p "$A/.hermes/history/sess-A2" "$B/.hermes/history/sess-B2"
printf '{"seq":0,"session_id":"sess-A2","project_id":"p","role":"user","timestamp":"2026-09-16T01:00:00","content":"A2"}\n' > "$A/.hermes/history/sess-A2/0000.jsonl"
printf '{"seq":0,"session_id":"sess-B2","project_id":"p","role":"user","timestamp":"2026-09-16T01:00:00","content":"B2"}\n' > "$B/.hermes/history/sess-B2/0000.jsonl"
SYNC_A push >/dev/null 2>&1; SYNC_B push >"$TMP/pushB.out" 2>&1
assert "B push(뒤늦은 쪽) 성공" 0 "$?"
assert "원격 트리에 두 조각 모두" 2 "$(remote_ls | grep -cE '^history/sess-(A2|B2)/0000\.enc$')"
assert "push 명령에 --force 없음" 0 "$(grep -c 'push.*--force\|--force.*push' "$S/hermes_sync_ref.py")"
SYNC_A pull >/dev/null 2>&1
assert "A 가 B 조각을 받아 복호" 1 "$([[ -f "$A/.hermes/history/sess-B2/0000.jsonl" ]] && echo 1 || echo 0)"

echo ""
echo "== 6. backfill 멱등 (목표 10) =="
python3 - "$A/.hermes/state.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for i in range(3):
    c.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) VALUES (?,?,?,?,?)",
              (f"옛 원문 {i}", "user", "2026-09-10T00:00:00", "p", "old-sess"))
c.commit()
PY
SYNC_A backfill >/dev/null 2>&1
N1="$(remote_ls | grep -c '^history/')"; F1="$(find "$A/.hermes/history" -name '*.jsonl' | wc -l)"
SYNC_A backfill >/dev/null 2>&1
assert "두 번 backfill 해도 원격 조각 수 동일" "$N1" "$(remote_ls | grep -c '^history/')"
assert "두 번 backfill 해도 로컬 조각 수 동일" "$F1" "$(find "$A/.hermes/history" -name '*.jsonl' | wc -l)"
assert "old-sess 조각이 원격에 있음" 1 "$(remote_ls | grep -c '^history/old-sess/0000\.enc$')"

echo ""
echo "== 7. 없음 3분류 — 조회 0건 (목표 9) =="
C="$TMP/C"; HC="$TMP/homeC"; mk_clone "$C" "$HC"; cp "$A/.hermes/universe.id" "$C/.hermes/"
cp -r "$HA/.hermes" "$HC/"                          # 열쇠는 있음(같은 사람의 다른 컴퓨터 가정)
EMPTY_BARE="$TMP/bare2"; git init -q --bare "$EMPTY_BARE"; git -C "$C" remote set-url origin "$EMPTY_BARE"
HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" push >/dev/null 2>&1   # 자물쇠만 올라간다
OUT_C="$(HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" status)"
assert "저장소·열쇠 있으나 조각 0 → '기억 0건'" 1 "$(grep -c '기억 0건' <<<"$OUT_C")"
OUT_A="$(SYNC_A status)"; OUT_B0="$(cat "$TMP/pullB.out")"
assert "세 문구가 서로 다름" 3 "$(printf '%s\n%s\n%s\n' "기억 저장소(refs/hermes/sync)가 없습니다" "$(grep -o '열쇠가 없습니다' <<<"$OUT_B0" | head -1)" "$(grep -o '기억 0건' <<<"$OUT_C")" | sort -u | wc -l)"

echo ""
echo "== 8. 이식 꺼짐(기본) — sync.json 없으면 로컬 전용 =="
D="$TMP/D"; mk_clone "$D" "$TMP/homeD"; rm -f "$D/.hermes/sync.json"
assert "push 는 '이식 꺼짐' 한 줄, rc 0" 1 "$(HOME="$TMP/homeD" python3 "$D/scripts/hermes-sync.py" --project "$D" push | grep -c '이식 꺼짐')"

echo ""
echo "== 9. age 없는 컴퓨터 — 훅 exit 0 · 한 줄 · DB 변경 0 (목표 14) =="
DB_A_BEFORE="$(md5sum "$A/.hermes/state.db" | awk '{print $1}')"
NOAGE="$TMP/noage"; mkdir -p "$NOAGE"; for b in python3 git bash sed grep cat wc head awk basename dirname mktemp stat mkdir date timeout printf sh; do ln -sf "$(command -v $b)" "$NOAGE/$b"; done
OUT_NOAGE="$(PATH="$NOAGE" HOME="$HA" python3 "$A/scripts/hermes-sync.py" --project "$A" pull 2>&1)"
assert "age 없음: pull rc 0" 0 "$?"
assert "age 없음: 한 줄 알림" 1 "$(grep -c 'age 가 없어' <<<"$OUT_NOAGE")"
assert "age 없음: state.db 변경 0" "$DB_A_BEFORE" "$(md5sum "$A/.hermes/state.db" | awk '{print $1}')"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh"
OUT_HOOK="$(echo '{"source":"startup"}' | PATH="$NOAGE" HOME="$HA" CLAUDE_PROJECT_DIR="$A" bash "$HOOK" 2>&1)"
assert "세션 시작 훅: age 없어도 exit 0" 0 "$?"
assert "세션 시작 훅: stdout 무출력(컨텍스트 오염 방지)" "" "$OUT_HOOK"

echo ""
echo "== 10. 참조 거부 서버 → 이식 불가 (목표 15) =="
REJ="$TMP/reject"; git init -q --bare "$REJ"
cat > "$REJ/hooks/update" <<'EOF'
#!/bin/sh
case "$1" in refs/hermes/*) echo "refusing custom refs" >&2; exit 1;; esac
EOF
chmod +x "$REJ/hooks/update"
E="$TMP/E"; mk_clone "$E" "$TMP/homeE"; cp "$A/.hermes/universe.id" "$E/.hermes/"; cp -r "$HA/.hermes" "$TMP/homeE/"
git -C "$E" remote set-url origin "$REJ"
OUT_E="$(HOME="$TMP/homeE" python3 "$E/scripts/hermes-sync.py" --project "$E" push 2>&1)"
assert "거부 서버: '이식 불가 — 사람 판단'" 1 "$(grep -c '이식 불가 — 사람 판단' <<<"$OUT_E")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
