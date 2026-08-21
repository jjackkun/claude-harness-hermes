#!/usr/bin/env bash
# hermes-recall --query 회귀 테스트 — 회상 검색이 요약(176행)이 아니라 원문(FTS5)을 뒤진다.
#
# 배경: do_query 가 session_summary.slots_json 을 LIKE 로 훑던 시절, 원문에만 있는
#   어휘로는 과거 세션을 찾을 수 없었다(zeroday 실측 recall@5 11.2%).
#   찾기는 session_history FTS5(bm25), 보여주기는 요약 — 2단 구조로 교체한다.
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

# 픽스처 — 원문 어휘와 요약 어휘를 일부러 어긋나게 심는다.
#   sessOLD  : 원문에 '메모이제이션' 다수, 요약엔 없음. 가장 오래됨.
#   sessNEW  : 원문에 '메모이제이션' 1회, 요약엔 없음. 가장 최신.
#   sessBARE : 원문만 있고 요약 없음 + 시크릿 포함 → 폴백·마스킹 대상.
#   sessSUM  : 요약에 '리팩터링' 있음 → 기존 동작 회귀 확인용.
python3 - "$DB" <<'PY'
import json, sqlite3, sys
con = sqlite3.connect(sys.argv[1])
def hist(sid, role, content):
    con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id)"
                " VALUES (?,?,?,?,?)", (content, role, "2026-08-01T00:00:00", "proj", sid))
def summ(sid, slots, when):
    con.execute("INSERT INTO session_summary (session_id, project_id, slots_json, updated_at)"
                " VALUES (?,?,?,?)", (sid, "proj", json.dumps(slots, ensure_ascii=False), when))

hist("sessOLD", "user", "메모이제이션 캐시가 자꾸 어긋난다")
hist("sessOLD", "assistant", "메모이제이션 결과를 무효화하는 시점이 문제다. 메모이제이션 키에 버전을 넣자")
summ("sessOLD", {"decisions": ["캐싱 전략을 버전 키 방식으로 결정"], "open": []}, "2026-08-01 00:00:00")

hist("sessNEW", "assistant", "메모이제이션 얘기는 지난번에 끝냈고 오늘은 빌드 설정만 본다")
summ("sessNEW", {"decisions": ["빌드 설정 정리"], "open": []}, "2026-08-20 00:00:00")

hist("sessBARE", "user", "쿼드트리 인덱스를 붙였다. token=ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 로 붙음")

hist("sessSUM", "user", "무관한 잡담")
summ("sessSUM", {"decisions": ["리팩터링 범위를 축소"], "open": []}, "2026-08-10 00:00:00")
con.commit()
PY

q() { python3 "$SCRIPTS/hermes-recall.py" --query "$1" --db "$DB" 2>&1; }

# T1 어휘일치 — 원문에만 있는 단어로 과거 세션이 잡힌다 (교체 전 실패 지점)
out="$(q '메모이제이션')"
if grep -q "sessOLD" <<<"$out"; then ok "T1 원문 어휘로 세션을 찾는다"; else nope "T1 원문 어휘로 세션을 찾는다"; fi

# T2 랭킹 — 최신순이 아니라 관련도순 (sessOLD 가 sessNEW 보다 먼저)
if [[ "$(grep -o 'sess\(OLD\|NEW\)' <<<"$out" | head -1)" == "sessOLD" ]]; then
  ok "T2 최신순이 아니라 bm25 관련도순"; else nope "T2 최신순이 아니라 bm25 관련도순"; fi

# T3 키워드 분해 — 원문에 그 어순 통짜로 없는 다어절 질의도 잡힌다
if grep -q "sessOLD" <<<"$(q '무효화 메모이제이션 버전')"; then
  ok "T3 다어절 질의를 키워드로 분해한다"; else nope "T3 다어절 질의를 키워드로 분해한다"; fi

# T4 폴백 — 요약 없는 세션이 히트하면 원문 스니펫으로 보여준다
bare="$(q '쿼드트리')"
if grep -q "sessBARE" <<<"$bare" && grep -q "쿼드트리" <<<"$bare"; then
  ok "T4 요약 없는 세션은 원문 스니펫 폴백"; else nope "T4 요약 없는 세션은 원문 스니펫 폴백"; fi

# T5 마스킹 — 폴백 스니펫은 원문을 그대로 흘리지 않는다
if ! grep -q "ghp_AAAAAAAA" <<<"$bare"; then
  ok "T5 폴백 스니펫이 시크릿을 마스킹한다"; else nope "T5 폴백 스니펫이 시크릿을 마스킹한다"; fi

# T6 회귀 — 요약 어휘로도 여전히 찾는다
if grep -q "sessSUM" <<<"$(q '리팩터링')"; then
  ok "T6 요약 어휘 검색이 유지된다"; else nope "T6 요약 어휘 검색이 유지된다"; fi

# T7 회귀 — 무매칭 메시지가 유지된다
if grep -q "일치" <<<"$(q '존재하지않는단어xyzzy')"; then
  ok "T7 무매칭 안내가 유지된다"; else nope "T7 무매칭 안내가 유지된다"; fi

# T8 회귀 — --inject(브리핑) 경로는 건드리지 않는다
inj="$(python3 "$SCRIPTS/hermes-recall.py" --inject --db "$DB" --project-id proj --session-id sessNEWEST 2>&1)"
if grep -q "빌드 설정 정리" <<<"$inj"; then
  ok "T8 --inject 는 직전 세션 요약 주입을 유지한다"; else nope "T8 --inject 는 직전 세션 요약 주입을 유지한다"; fi

echo
echo "  PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
