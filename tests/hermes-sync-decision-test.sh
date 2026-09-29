#!/usr/bin/env bash
# 사람이 정한 판정(둠·지움)이 컴퓨터를 따라간다 (계획 docs/exec-plans/completed/2026-09-29-carry-privacy-decisions.md 목표 1~4).
#
#   1 올리기: keep·drop 만 decision/<해시>/<시각>.json 으로 오른다(원문 없음) · clean·pending 은 안 오른다 · 같은 결정은 한 번 · 바꾸면 새 조각
#   2 받기 규칙: 행 없음→만든다 · 기계 판정은 덮는다(원문 비움) · 사람끼리는 더 새 시각이 이긴다 · 같은 시각이면 지움이 이긴다 ·
#     두 번 받아도 같다 · 받은 뒤 기계 판정이 못 덮는다 · 잘못된 조각(해시·상태·시각 형식)은 거부
#   3 끝에서 끝까지: 두 클론(bare 원격 공유) — A 의 지움은 B 에서 막히고, 둠은 통과하며 B 가 다시 판정하지 않는다
#   4 호환: 결정 조각은 잠금 조각으로 오인되지 않는다 · pull 뒤 status 가 오류 없이 돈다
#
# 평문 모드라 열쇠·age 가 필요 없다. 모델 호출 0. 실행: bash tests/hermes-sync-decision-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset CLAUDE_PROJECT_DIR HERMES_DISABLED HERMES_AGENT_ID HERMES_SUMMON_NONCE
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
fsig() { [[ -f "$FACTORY_DB" ]] && python3 -c "
import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); print(c.execute('select count(*) from privacy_review').fetchone()[0], c.execute('select count(*) from sync_outbox').fetchone()[0])" "$FACTORY_DB" 2>/dev/null || echo -; }
BEFORE="$(fsig)"

BARE="$T/bare"; git init -q --bare "$BARE"
mk_clone() {   # mk_clone <dir> <HOME>
  mkdir -p "$1/scripts/data" "$1/.hermes" "$2"
  cp "$S"/*.py "$1/scripts/"
  git init -q "$1"; git -C "$1" config user.name alice; git -C "$1" config user.email a@t
  git -C "$1" remote add origin "$BARE"; git -C "$1" commit -q --allow-empty -m init
  python3 "$S/hermes-init.py" --project "$1" >/dev/null 2>&1
  echo '{"push": true, "mode": "plain"}' > "$1/.hermes/sync.json"
}
A="$T/A"; HA="$T/homeA"; B="$T/B"; HB="$T/homeB"
mk_clone "$A" "$HA"; mk_clone "$B" "$HB"; cp "$A/.hermes/universe.id" "$B/.hermes/universe.id"
py() {   # py <클론> <파이썬 본문> — 그 클론의 DB 를 con 으로 연다
  D="$1/.hermes/state.db" S="$S" python3 -c "
import os, sys, sqlite3, json
sys.path.insert(0, os.environ['S'])
con = sqlite3.connect(os.environ['D'])
$2"
}
push() { HOME="$2" python3 "$1/scripts/hermes-sync.py" --project "$1" push 2>&1; }
pull() { HOME="$2" python3 "$1/scripts/hermes-sync.py" --project "$1" pull 2>&1; }
remote_files() { git -C "$A" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$A" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
hash_of() { S="$S" python3 -c "import os,sys; sys.path.insert(0, os.environ['S']); from hermes_privacy_pending import text_hash; print(text_hash(sys.argv[1]))" "$1"; }
S_KEEP="배포 일정은 금요일로 미룬다"; S_DROP="요즘 허리가 아파서 쉬는 중이다"; S_CLEAN="테스트는 배포 전에 돌린다"; S_PEND="주말에 가족 여행 간다"
H_KEEP="$(hash_of "$S_KEEP")"; H_DROP="$(hash_of "$S_DROP")"

echo "== 1. 올리기"
py "$A" "
from hermes_privacy_pending import mark, decide, text_hash
mark(con, 'summary', 'r1', '$S_KEEP', 'pending'); decide(con, text_hash('$S_KEEP'), 'keep')
mark(con, 'summary', 'r2', '$S_DROP', 'pending'); decide(con, text_hash('$S_DROP'), 'drop')
mark(con, 'summary', 'r3', '$S_CLEAN', 'clean')
mark(con, 'summary', 'r4', '$S_PEND', 'pending')
con.execute(\"UPDATE privacy_review SET ts='2026-09-29 10:00:00' WHERE status IN ('keep','drop')\")
con.commit()"
push "$A" "$HA" >/dev/null
FILES="$(remote_files)"
assert "keep 결정이 조각으로 오른다" 1 "$(grep -c "^decision/$H_KEEP/" <<<"$FILES")"
assert "drop 결정이 조각으로 오른다" 1 "$(grep -c "^decision/$H_DROP/" <<<"$FILES")"
assert "결정 조각은 정확히 2개(clean·pending 은 안 오른다)" 2 "$(grep -c '^decision/' <<<"$FILES")"
BODY="$(git -C "$A" show "refs/hermes/sync-remote:$(grep "^decision/$H_DROP/" <<<"$FILES")" 2>/dev/null)"
assert "조각에 해시·상태·결정 시각이 있다" "1 1 1" "$(has "$BODY" "$H_DROP") $(has "$BODY" '"drop"') $(has "$BODY" '2026-09-29 10:00:00')"
assert "조각에 문장 원문이 없다" 0 "$(has "$BODY" "허리")"
push "$A" "$HA" >/dev/null
assert "다시 push 해도 같은 결정은 한 번뿐이다" 2 "$(remote_files | grep -c '^decision/')"
py "$A" "
con.execute(\"UPDATE privacy_review SET status='drop', ts='2026-09-29 11:00:00' WHERE hash='$H_KEEP'\"); con.commit()"
push "$A" "$HA" >/dev/null
assert "결정을 바꾸면(시각이 달라지면) 새 조각이 오른다" 2 "$(remote_files | grep -c "^decision/$H_KEEP/")"
assert "조각 경로 끝에 상태가 들어간다(같은 초 충돌이 다른 경로가 되게)" 1 "$(remote_files | grep -c "^decision/$H_DROP/.*-drop\.json$")"
py "$A" "
con.execute(\"UPDATE privacy_review SET status='keep', ts='2026-09-29 12:00:00' WHERE hash='$H_KEEP'\"); con.commit()"
push "$A" "$HA" >/dev/null

echo "== 2. 받기 규칙"
H() { python3 -c "import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:32])" "$1"; }
apply() {   # apply <해시> <상태> <시각> → import_decision 의 반환(True/False)
  py "$B" "
import hermes_sync_decisions as d
print(d.import_decision(con, {'hash': '$1', 'status': '$2', 'decided_at': '$3'})); con.commit()"
}
row() { py "$B" "r = con.execute(\"SELECT status || '|' || text || '|' || ts FROM privacy_review WHERE hash='$1'\").fetchone(); print(r[0] if r else 'none')"; }
N1="$(H 규칙시험-새행)"
assert "행이 없으면 만든다(원문 없음)" "True" "$(apply "$N1" keep '2026-09-29 09:00:00')"
assert "  … 상태·빈 원문·시각" "keep||2026-09-29 09:00:00" "$(row "$N1")"
py "$B" "
from hermes_privacy_pending import mark, text_hash
mark(con, 'summary', 'r', '규칙시험-기계통과', 'clean'); mark(con, 'summary', 'r', '규칙시험-대기문장', 'pending'); con.commit()"
apply "$(H 규칙시험-기계통과)" drop '2026-09-29 09:00:00' >/dev/null
assert "기계 판정(clean)은 사람의 지움이 덮는다" "drop||2026-09-29 09:00:00" "$(row "$(H 규칙시험-기계통과)")"
apply "$(H 규칙시험-대기문장)" keep '2026-09-29 09:00:00' >/dev/null
assert "대기(pending) 문장도 덮고 원문을 비운다" "keep||2026-09-29 09:00:00" "$(row "$(H 규칙시험-대기문장)")"
apply "$N1" drop '2026-09-29 10:00:00' >/dev/null
assert "사람끼리는 더 새 시각이 이긴다" "drop||2026-09-29 10:00:00" "$(row "$N1")"
apply "$N1" keep '2026-09-29 08:00:00' >/dev/null
assert "더 옛 결정은 무시한다" "drop||2026-09-29 10:00:00" "$(row "$N1")"
apply "$N1" keep '2026-09-29 10:00:00' >/dev/null
assert "같은 시각에 keep 이 와도 지움(drop)이 유지된다" "drop||2026-09-29 10:00:00" "$(row "$N1")"
N2="$(H 규칙시험-같은시각)"
apply "$N2" keep '2026-09-29 10:00:00' >/dev/null; apply "$N2" drop '2026-09-29 10:00:00' >/dev/null
assert "같은 시각이면 keep 다음 drop 이 이긴다(받는 순서와 무관)" "drop||2026-09-29 10:00:00" "$(row "$N2")"
N3="$(H 규칙시험-순서)"
apply "$N3" drop '2026-09-29 10:00:00' >/dev/null; apply "$N3" keep '2026-09-29 10:00:00' >/dev/null
assert "같은 시각이면 drop 다음 keep 도 drop 이 남는다(수렴)" "drop||2026-09-29 10:00:00" "$(row "$N3")"
apply "$N1" drop '2026-09-29 10:00:00' >/dev/null
assert "같은 조각을 두 번 받아도 같다(멱등)" "drop||2026-09-29 10:00:00" "$(row "$N1")"
py "$B" "
from hermes_privacy_pending import mark
mark(con, 'summary', 'r', '규칙시험-새행', 'clean'); con.commit()"
assert "받은 결정 뒤 기계 판정(clean)이 덮지 못한다" "drop||2026-09-29 10:00:00" "$(row "$N1")"
assert "해시 모양이 아니면 거부" "False" "$(apply 'zzzz' keep '2026-09-29 09:00:00')"
assert "keep/drop 이 아닌 상태는 거부(clean 을 심을 수 없다)" "False" "$(apply "$(H 규칙시험-거부)" clean '2026-09-29 09:00:00')"
assert "결정 시각이 없으면 거부" "False" "$(apply "$(H 규칙시험-거부2)" keep '')"
assert "시각 형식이 다르면 거부(글자 비교가 틀어지지 않게)" "False" "$(apply "$(H 규칙시험-거부3)" keep '2026/09/29 10:00')"
assert "거부한 조각은 행을 만들지 않는다" "none" "$(row "$(H 규칙시험-거부)")"

echo "== 3. 끝에서 끝까지 — A 의 결정이 B 에서 효과를 낸다"
OUT="$(pull "$B" "$HB")"
assert "B 가 pull 로 결정 조각을 받는다" 1 "$([[ "$(py "$B" "print(con.execute(\"SELECT COUNT(*) FROM sync_cursor WHERE path LIKE 'decision/%'\").fetchone()[0])")" -ge 2 ]] && echo 1 || echo 0)"
assert "A 가 지움한 문장은 B 에서 통과하지 못한다" "False" "$(py "$B" "
from hermes_privacy_pending import allowed
print(allowed(con, '$S_DROP'))")"
assert "A 가 둠한 문장은 B 에서 통과한다(최신 결정이 keep)" "True" "$(py "$B" "
from hermes_privacy_pending import allowed
print(allowed(con, '$S_KEEP'))")"
assert "B 의 판정 단계는 그 문장들을 다시 판정하지 않는다(모델 호출 없음)" "0" "$(py "$B" "
from hermes_privacy_judge import judge_and_mark
print(judge_and_mark(con, [('summary', 'r', '$S_KEEP'), ('summary', 'r', '$S_DROP')]))")"

echo "== 4. 호환"
assert "결정 조각은 잠금(암호문) 조각으로 오인되지 않는다" "False" "$(S="$S" python3 -c "
import importlib.util, os, sys
sys.path.insert(0, os.environ['S'])
spec = importlib.util.spec_from_file_location('hs', os.path.join(os.environ['S'], 'hermes-sync.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m._is_locked_fragment('decision/abc/2026.json', b'{\"hash\": \"abc\", \"status\": \"keep\", \"decided_at\": \"2026-09-29 10:00:00\"}'))")"
HOME="$HB" python3 "$B/scripts/hermes-sync.py" --project "$B" status >/dev/null 2>&1
assert "pull 뒤 status 가 오류 없이 돈다" 0 "$?"

assert "시험이 공장의 실제 DB 를 건드리지 않았다" "$BEFORE" "$(fsig)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
