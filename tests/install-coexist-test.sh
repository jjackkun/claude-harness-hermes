#!/usr/bin/env bash
# 공존 설치 검증 (계획 docs/exec-plans/active/2026-09-17-install-coexistence.md 목표 2·3·4).
#
#   - 분기 ⓪·a·b·c·d·충돌·구문실패·ⓔ 각 1건, 실행 비트 보존, 심링크 dst
#   - 실물 픽스처(terminal-shipping plan_state) → 분기 c, byte-equal — 사고 5건이 전부 이 분기였다
#   - base 복원 실패 3종(미등록 · 없는 커밋 · 얕은 clone) → ⓔ, 절대 덮지 않음
#   - manifest 하위호환: src/mode 없는 옛 항목으로 verify·field 가 죽지 않음
#   - 옛 방식(raw cp)으로 되돌리면 c 가 빨개진다 — 통과만 보는 검증 금지(08-27 §8)
#
# 실행: bash tests/install-coexist-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$REPO_ROOT/tests/fixtures/coexist"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# ── 가짜 공장(git 저장소) + 프로젝트 ────────────────────────────────────────
F="$TMP/factory"; P="$TMP/proj"; C="$P/.claude"
mkdir -p "$F/assets/hooks" "$F/lib" "$C" "$P/scripts/hooks"
cp "$REPO_ROOT/lib/factory_manifest.sh" "$REPO_ROOT/lib/factory_coexist.sh" "$F/lib/"
git -C "$F" init -q; git -C "$F" config user.email t@t; git -C "$F" config user.name t
export DEV_SETTING_DIR="$F"
# shellcheck source=/dev/null
source "$F/lib/factory_coexist.sh"

S="$F/assets/hooks/h.py"; D="$P/scripts/hooks/h.py"; N="scripts/hooks/h.py"
fac() { printf '%s' "$1" > "$S"; git -C "$F" add -A; git -C "$F" commit -qm "$2"; }
run() { install_factory_file "$S" "$D" hook "$N" "$C" "$@" 2>"$TMP/err"; }
# 줄을 떨어뜨린 픽스처 — git merge-file 은 **인접** 수정을 한 덩어리로 보아 충돌시킨다(2026-09-17 실측)
BODY=$'# A\n#1\n#2\n#3\n# B\n#4\n#5\n#6\n# C\n'

echo "== 1. 분기 a·⓪·b (조용한 셋) =="
fac "$BODY" c1
run 755
assert "a 새 파일 → 복사" a "$COEXIST_LAST_BRANCH"
assert "a 새 파일 모드 = 호출자 지정 755" 755 "$(stat -c %a "$D")"
assert "a manifest 에 src 기록" "assets/hooks/h.py" "$(manifest_field "$C" hook "$N" src)"
assert "a manifest 에 mode 기록" 755 "$(manifest_field "$C" hook "$N" mode)"
run
assert "⓪ 내용 같음 → no-op" 0 "$COEXIST_LAST_BRANCH"
assert "⓪ 무출력(G6)" "" "$(cat "$TMP/err")"
fac "${BODY/\# C/\# C2}" c2
run
assert "b 하류 미수정·공장 개정 → 덮음" b "$COEXIST_LAST_BRANCH"
assert "b 공장 판이 전달됨" "# C2" "$(sed -n 9p "$D")"
assert "b 기존 모드 보존(755)" 755 "$(stat -c %a "$D")"
assert "b 무출력(G6)" "" "$(cat "$TMP/err")"

echo ""
echo "== 2. 분기 c — 하류만 고쳤다 (사고 5건의 자리) =="
sed -i '1s/.*/# A_local/' "$D"
run
assert "c 공장 그대로·하류 수정 → 손대지 않음" c "$COEXIST_LAST_BRANCH"
assert "c 하류 수정이 살아 있음" "# A_local" "$(sed -n 1p "$D")"
assert "c .factory-new 없음" 0 "$([[ -e "$D.factory-new" ]] && echo 1 || echo 0)"
assert "c 무출력(G6)" "" "$(cat "$TMP/err")"
# 옛 방식(raw cp)이면 여기서 하류 수정이 사라진다 — 이 단언이 빨개져야 회귀 보호가 진짜다
cp "$D" "$TMP/keep"; cp "$S" "$D"
assert "[대조] 옛 raw cp 는 하류 수정을 지운다" "# A" "$(sed -n 1p "$D")"
cp "$TMP/keep" "$D"

echo ""
echo "== 3. 분기 d — 둘 다 바뀜, 다른 자리 → 합쳐서 둘 다 산다 =="
fac "${BODY/\# C/\# C2}" c2b >/dev/null 2>&1 || true   # base 는 c2 판 그대로
fac "$(printf '%s' "${BODY/\# C/\# C2}" | sed '5s/.*/# B_fac/')" c3
run
assert "d 병합" d "$COEXIST_LAST_BRANCH"
assert "d 하류 수정 남음(1행)" "# A_local" "$(sed -n 1p "$D")"
assert "d 공장 개정 들어옴(5행)" "# B_fac" "$(sed -n 5p "$D")"
assert "d 모드 보존 755" 755 "$(stat -c %a "$D")"
assert "d MERGED 한 줄 알림(G4)" 1 "$(grep -c '\[factory-merge MERGED\]' "$TMP/err")"
assert "d manifest sha 가 병합본으로 갱신" 0 "$(manifest_verify "$C" hook "$N" "$D"; echo $?)"

echo ""
echo "== 4. 충돌 — 같은 자리 → 세워 두고 사람이 푼다 =="
# §3 의 병합이 manifest 를 병합본으로 갱신했으므로, 지금 dst 는 "설치판 그대로" 다. 충돌을 만들려면
# 하류가 **다시** 같은 줄을 고쳐야 한다 — 안 고치면 b(덮음)가 옳은 동작이다(2026-09-17 실측).
sed -i '1s/.*/# A_local2/' "$D"
fac "$(printf '%s' "${BODY/\# C/\# C2}" | sed '1s/.*/# A_fac/;5s/.*/# B_fac/')" c4
run
assert "x 충돌 분기" x "$COEXIST_LAST_BRANCH"
assert "x 하류 판 안 덮임" "# A_local2" "$(sed -n 1p "$D")"
assert "x 공장 판이 옆에 섬" 1 "$([[ -f "$D.factory-new" ]] && echo 1 || echo 0)"
assert "x .factory-new 내용 = 공장판" "# A_fac" "$(sed -n 1p "$D.factory-new")"
assert "x CONFLICT 알림" 1 "$(grep -c '\[factory-merge CONFLICT\]' "$TMP/err")"
rm -f "$D.factory-new"

echo ""
echo "== 5. 구문 실패 — 줄은 안 겹치나 병합본이 깨지면 충돌 취급 =="
# base 를 공장 커밋으로 심고(a 분기로 설치), 하류는 1행을 고장내고, 공장은 멀리 떨어진 줄만 개정한다.
# 그러면 진짜 d 로 들어가고, 병합은 깨끗하지만 병합본이 파이썬으로 깨진다 → 구문검사가 막아야 한다.
rm -f "$D"; python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p)); m["items"]=[i for i in m["items"] if i["name"]!="scripts/hooks/h.py"]; json.dump(m,open(p,"w"))
PY
fac $'y = 2\n#1\n#2\n#3\nz = 3\n#4\n#5\n#6\nw = 4\n' c5
run 755; assert "[준비] a 로 base 심음" a "$COEXIST_LAST_BRANCH"
sed -i '1s/.*/y = (2/' "$D"                        # 하류: 1행을 고의로 깨뜨림(괄호 미닫힘)
fac $'y = 2\n#1\n#2\n#3\nz = 3\n#4\n#5\n#6\nw = 5\n' c6   # 공장: 9행만 개정
run
assert "구문 실패 → 충돌 취급(덮지 않음)" x "$COEXIST_LAST_BRANCH"
assert "구문 실패 시 하류 판 안 덮임" "y = (2" "$(sed -n 1p "$D")"
assert "구문 실패 시 .factory-new 생김" 1 "$([[ -f "$D.factory-new" ]] && echo 1 || echo 0)"
# 대조: 검사기가 '항상 실패' 가 아님을 증명 — 하류를 고치면 같은 상황이 d 로 병합돼야 한다
rm -f "$D.factory-new"; sed -i '1s/.*/y = 20/' "$D"
run
assert "[대조] 구문이 맞으면 같은 상황이 병합(d)" d "$COEXIST_LAST_BRANCH"
assert "[대조] 병합본에 공장 개정(9행) 들어옴" "w = 5" "$(sed -n 9p "$D")"
rm -f "$D.factory-new"

echo ""
echo "== 6. ⓔ base 불명 3종 — 판정 불가면 절대 덮지 않는다 =="
# 6a 미등록(옛 항목: src 없음)
printf '# old\n' > "$D"; manifest_add "$C" hook "$N" "$D"       # src·mode 없이 등록(옛 모양)
fac $'# new_fac\n' c7; printf '# ours_e\n' > "$D"
run
assert "ⓔ src 없는 옛 항목 → 세움" e "$COEXIST_LAST_BRANCH"
assert "ⓔ 하류 판 안 덮임" "# ours_e" "$(cat "$D")"
assert "ⓔ UNKNOWN-BASE 알림" 1 "$(grep -c 'UNKNOWN-BASE' "$TMP/err")"
rm -f "$D.factory-new"
# 6b 없는 커밋
printf '# x\n' > "$D"; manifest_add "$C" hook "$N" "$D" "assets/hooks/h.py" 644
python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p))
for i in m["items"]:
    if i["name"]=="scripts/hooks/h.py": i["factory_commit"]="0"*40
json.dump(m,open(p,"w"))
PY
fac $'# fac2\n' c8; printf '# ours2\n' > "$D"
run
assert "ⓔ 존재하지 않는 커밋 → 세움" e "$COEXIST_LAST_BRANCH"
assert "ⓔ(커밋 없음) 안 덮임" "# ours2" "$(cat "$D")"
rm -f "$D.factory-new"
# 6c 얕은 clone 공장 — 옛 커밋 내용을 못 꺼낸다
SH="$TMP/shallow"; git clone -q --depth 1 "file://$F" "$SH" 2>/dev/null
mkdir -p "$SH/lib"; cp "$F/lib/"*.sh "$SH/lib/"
printf '# base_s\n' > "$D"; OLD="$(git -C "$F" rev-parse HEAD~3)"
manifest_add "$C" hook "$N" "$D" "assets/hooks/h.py" 644
python3 - "$C/.factory-manifest.json" "$OLD" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p))
for i in m["items"]:
    if i["name"]=="scripts/hooks/h.py": i["factory_commit"]=sys.argv[2]
json.dump(m,open(p,"w"))
PY
printf '# ours_s\n' > "$D"; printf '# fac_s\n' > "$SH/assets/hooks/h.py"
( export DEV_SETTING_DIR="$SH"; source "$SH/lib/factory_coexist.sh"
  install_factory_file "$SH/assets/hooks/h.py" "$D" hook "$N" "$C" 2>"$TMP/err"; echo "$COEXIST_LAST_BRANCH" > "$TMP/br" )
assert "ⓔ 얕은 clone(옛 커밋 없음) → 세움" e "$(cat "$TMP/br")"
assert "ⓔ(얕은 clone) 안 덮임" "# ours_s" "$(cat "$D")"
rm -f "$D.factory-new"

echo ""
echo "== 7. 심링크 dst — 링크는 두고 타깃이 실물 =="
rm -f "$D"; printf '# t\n' > "$P/real.py"; ln -s "$P/real.py" "$D"
fac $'# t\n' c9
run
assert "심링크가 그대로" 1 "$([[ -L "$D" ]] && echo 1 || echo 0)"
assert "타깃 기준 판정(⓪)" 0 "$COEXIST_LAST_BRANCH"
fac $'# t2\n' c10; run
assert "타깃에 씀(b)" "# t2" "$(cat "$P/real.py")"
rm -f "$D"

echo ""
echo "== 7b. 프로젝트 밖 심링크 — 공장 원본을 절대 덮지 않는다 (리뷰 HIGH①) =="
OUT="$TMP/outside"; mkdir -p "$OUT"; printf '# factory-original\n' > "$OUT/orig.py"
ln -s "$OUT/orig.py" "$D"; fac $'# fac_out\n' c11
run
assert "밖 심링크 → 분기 f(손대지 않음)" f "$COEXIST_LAST_BRANCH"
assert "밖 원본 불변" "# factory-original" "$(cat "$OUT/orig.py")"
assert "OUTSIDE 알림" 1 "$(grep -c 'OUTSIDE' "$TMP/err")"
rm -f "$D"

echo ""
echo "== 7c. 첫 전환 — manifest 에 없던 파일을 installed_version 으로 판정 (리허설 구멍) =="
# 옛 설치기가 깔아 둔 상태 흉내: manifest 항목 없음, factory.json 만 있음(계획 1). 하류가 고쳐 둠.
python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p)); m["items"]=[i for i in m["items"] if i["name"]!="scripts/hooks/h.py"]; json.dump(m,open(p,"w"))
PY
fac "$BODY" c12; INSTALLED="$(git -C "$F" rev-parse HEAD)"
mkdir -p "$P/.hermes"; printf '{"remote_url":"x","installed_version":"%s"}' "$INSTALLED" > "$P/.hermes/factory.json"
printf '%s' "$BODY" | sed '1s/.*/# A_local3/' > "$D"; chmod 755 "$D"
run
assert "폴백 base==theirs → 사실상 c(안 덮음)" c "$COEXIST_LAST_BRANCH"
assert "폴백 출처 = installed_version" installed_version "$COEXIST_BASE_SOURCE"
assert "하류 수정 생존" "# A_local3" "$(sed -n 1p "$D")"
assert "무출력(사람 손 안 감)" "" "$(cat "$TMP/err")"
assert "manifest 에 base(=공장판) sha 기록, 하류 sha 아님" 1 "$([[ "$(manifest_field "$C" hook "$N" sha256)" == "$(_manifest_sha "$S")" ]] && echo 1 || echo 0)"
# 회귀 보호: 다음 설치가 하류 판을 '설치판' 으로 오인해 덮으면 안 된다
run
assert "다음 설치도 c — 하류 판이 base 로 오인되지 않음" c "$COEXIST_LAST_BRANCH"
assert "하류 수정 여전히 생존" "# A_local3" "$(sed -n 1p "$D")"
# 이제 공장이 다른 자리를 개정하면 폴백 base 로 d 병합
fac "$(printf '%s' "$BODY" | sed '9s/.*/# C_fac/')" c13
run
assert "폴백 base 로 d 병합" d "$COEXIST_LAST_BRANCH"
assert "병합본: 하류 1행 + 공장 9행" "# A_local3|# C_fac" "$(sed -n 1p "$D")|$(sed -n 9p "$D")"

echo ""
echo "== 7c2. base 없음 + ours 가 옛 공장판 → 하류 수정 아님, 덮는다 (라이브 전파 실측) =="
# factory.json 도 manifest 항목도 없는 harness-only 소우주 흉내. dst 는 두 커밋 전 공장판 그대로.
rm -f "$P/.hermes/factory.json"; python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p)); m["items"]=[i for i in m["items"] if i["name"]!="scripts/hooks/h.py"]; json.dump(m,open(p,"w"))
PY
fac $'# gen1\n' c15; fac $'# gen2\n' c16; fac $'# gen3\n' c17
git -C "$F" show HEAD~2:assets/hooks/h.py > "$D"; chmod 755 "$D"; printf 'stale\n' > "$D.factory-new"   # 지난 전파가 세워 둔 것 흉내
run
assert "옛 공장판 → b(덮음)" b "$COEXIST_LAST_BRANCH"
assert "공장 최신판이 전달됨" "# gen3" "$(cat "$D")"
assert "지난 .factory-new 도 치워짐" 0 "$([[ -e "$D.factory-new" ]] && echo 1 || echo 0)"
assert "무출력(사람 손 안 감)" "" "$(cat "$TMP/err")"
# 대조: 진짜 하류 수정(공장 이력 어디에도 없음)은 base 없으면 여전히 ⓔ — 옛판 검사가 하류 수정까지 덮지 않는다
printf '# nobody-ever-wrote-this\n' > "$D"; python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p)); m["items"]=[i for i in m["items"] if i["name"]!="scripts/hooks/h.py"]; json.dump(m,open(p,"w"))
PY
run
assert "[대조] 진짜 하류 수정 + base 없음 → ⓔ(안 덮음)" e "$COEXIST_LAST_BRANCH"
assert "[대조] 하류 판 보존" "# nobody-ever-wrote-this" "$(cat "$D")"
rm -f "$D.factory-new"

echo ""
echo "== 7d. manifest 값의 옵션 스머글링 차단 (리뷰 MED②) =="
python3 - "$C/.factory-manifest.json" <<'PY'
import json,sys; p=sys.argv[1]; m=json.load(open(p))
for i in m["items"]:
    if i["name"]=="scripts/hooks/h.py": i["factory_commit"]="--output=/tmp/pwned"; i["src"]="x"
json.dump(m,open(p,"w"))
PY
rm -f /tmp/pwned; printf '# ours_sm\n' > "$D"; fac $'# fac_sm\n' c14
run
assert "비-sha 커밋값 → base 불명(ⓔ), git 에 안 넘김" e "$COEXIST_LAST_BRANCH"
assert "/tmp/pwned 안 생김" 0 "$([[ -e /tmp/pwned ]] && echo 1 || echo 0)"
rm -f "$D.factory-new"

echo ""
echo "== 8. 실물 픽스처 — terminal-shipping plan_state → 분기 c, byte-equal =="
if [[ -f "$FIX/plan_state.ours" ]]; then
  RS="$F/assets/hooks/plan_state.py"; RD="$P/scripts/hooks/plan_state.py"; RN="scripts/hooks/plan_state.py"
  cp "$FIX/plan_state.base" "$RS"; git -C "$F" add -A; git -C "$F" commit -qm base
  cp "$FIX/plan_state.base" "$RD"; manifest_add "$C" hook "$RN" "$RD" "assets/hooks/plan_state.py" 755   # 마지막 설치 = base
  cp "$FIX/plan_state.ours" "$RD"; chmod 755 "$RD"                                               # 하류가 고침
  cp "$FIX/plan_state.theirs" "$RS"; git -C "$F" add -A; git -C "$F" commit -qm theirs >/dev/null 2>&1 || true
  install_factory_file "$RS" "$RD" hook "$RN" "$C" 2>"$TMP/err"
  assert "실물: 분기 c(공장 미개정·하류 수정)" c "$COEXIST_LAST_BRANCH"
  assert "실물: 하류 판 byte-equal 보존" 1 "$(cmp -s "$RD" "$FIX/plan_state.ours" && echo 1 || echo 0)"
  assert "실물: 실행 비트 유지" 755 "$(stat -c %a "$RD")"
  assert "실물: 무출력" "" "$(cat "$TMP/err")"
else
  echo "  ⊘ 픽스처 없음 — 건너뜀"
fi

echo ""
echo "== 8b. R-merge 게이트 — .factory-new 가 있으면 커밋 차단 (목표 6) =="
G="$TMP/gaterepo"; mkdir -p "$G/.git/hooks"; git -C "$G" init -q; git -C "$G" config user.email t@t; git -C "$G" config user.name t
cp "$REPO_ROOT/assets/hooks/pre-commit.sh" "$G/.git/hooks/pre-commit"; chmod +x "$G/.git/hooks/pre-commit"
printf 'x\n' > "$G/a.txt"; git -C "$G" add a.txt
( cd "$G" && bash .git/hooks/pre-commit >"$TMP/gate.out" 2>&1 ); RC0=$?
assert "R-merge: .factory-new 없으면 통과" 0 "$RC0"
printf 'fac\n' > "$G/scripts_hook.py.factory-new"
( cd "$G" && bash .git/hooks/pre-commit >"$TMP/gate.out" 2>&1 ); RC1=$?
assert "R-merge: .factory-new 있으면 차단(rc≠0)" 1 "$([[ $RC1 -ne 0 ]] && echo 1 || echo 0)"
assert "R-merge 메시지에 파일명" 1 "$(grep -c 'scripts_hook.py.factory-new' "$TMP/gate.out")"
rm -f "$G/scripts_hook.py.factory-new"
( cd "$G" && bash .git/hooks/pre-commit >"$TMP/gate.out" 2>&1 ); RC2=$?
assert "R-merge: 지우면 다시 통과" 0 "$RC2"
assert "게이트 선언 존재(# GATE: R-merge block)" 1 "$(grep -c '^# GATE: R-merge block$' "$REPO_ROOT/assets/hooks/pre-commit.sh")"

echo ""
echo "== 8c. 변조 훅 — 훅·스크립트 편집에도 경고, 미등록은 침묵 (목표 8) =="
HOOK="$REPO_ROOT/assets/hooks/claude-posttooluse-factory-tamper-warn.sh"
tamper() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1; }
# §7c 에서 manifest 에 hook 항목이 있는 h.py — 내용을 바꾸면 경고, 목록 sha 와 같으면 침묵
printf '%s' "$BODY" > "$D"; manifest_add "$C" hook "$N" "$D" "assets/hooks/h.py" 755
assert "등록 훅, 미변조 → 침묵" 0 "$(tamper "$D" | grep -c 'factory-tamper')"
printf '# tampered\n' >> "$D"
assert "등록 훅, 변조 → 경고 1건" 1 "$(tamper "$D" | grep -c 'factory-tamper WARN')"
assert "경고 문구가 진실(보존됩니다), 옛 '덮어써집니다' 없음" "1|0" "$(tamper "$D" | grep -c '편집은 보존됩니다')|$(tamper "$D" | grep -c '덮어써집니다')"
printf 'mine\n' > "$P/scripts/hooks/my-own.py"
assert "미등록(소우주 자체) 파일 → 침묵" 0 "$(tamper "$P/scripts/hooks/my-own.py" | grep -c 'factory-tamper')"
mkdir -p "$P/.claude/skills/sk"; printf 'body\n' > "$P/.claude/skills/sk/SKILL.md"; manifest_add "$C" skills sk "$P/.claude/skills/sk"
printf 'edit\n' >> "$P/.claude/skills/sk/SKILL.md"
assert "옛 kind(.claude/skills) 경로도 여전히 경고" 1 "$(tamper "$P/.claude/skills/sk/SKILL.md" | grep -c 'factory-tamper WARN')"

echo ""
echo "== 9. manifest 하위호환 — src/mode 없는 옛 항목 =="
python3 -c "
import json;p='$C/.factory-manifest.json';m=json.load(open(p))
m['items'].append({'name':'legacy','kind':'skills','factory_commit':'abc','sha256':'00'})
json.dump(m,open(p,'w'))"
assert "옛 항목 field(src) → 빈 줄, 종료 0" "" "$(manifest_field "$C" skills legacy src; echo -n)"
assert "옛 항목 verify 가 죽지 않음(2=미존재)" 2 "$(manifest_verify "$C" skills legacy "$P/nope"; echo $?)"

echo ""
echo "== 9. 옛 공장판 보존 결함 (2026-09-20 doctor 실측 — backlog coexist-old-factory-detection) =="
# c 갈래: manifest 가 현재판 sha 인데 파일은 옛 공장판 → 하류 수정이 아니라 전파 누락 → 전달(b)
OLD9=$'# V1\n#1\n#2\n#3\n# B\n#4\n#5\n#6\n# C\n'; NEW9=$'# V2\n#1\n#2\n#3\n# B\n#4\n#5\n#6\n# C\n'
rm -f "$D" "$D.factory-new"             # 앞 절의 하류 상태를 비운다 → a 갈래로 v1 설치
fac "$OLD9" c-old-v1; run 755
fac "$NEW9" c-old-v2; run                # v2 전달(b) → manifest = v2
printf '%s' "$OLD9" > "$D"               # 파일만 옛 판으로 (ai-create pre-commit 상태 재현)
run
assert "c-old: ours 가 옛 공장판이면 c 가 아니라 b(전달)" b "$COEXIST_LAST_BRANCH"
assert "c-old: 현재판이 들어옴" "# V2" "$(sed -n 1p "$D")"
assert "c-old: manifest 가 현재 파일과 일치" 0 "$(manifest_verify "$C" hook "$N" "$D"; echo $?)"
# 사실상-c 갈래: manifest sha 가 ours·theirs 어느 쪽도 아닌데 base 복원이 theirs 와 같고 ours 는 옛 판 → 전달(b)
printf 'garbage\n' > "$TMP/g9"; manifest_add "$C" hook "$N" "$TMP/g9" "assets/hooks/h.py" 755
printf '%s' "$OLD9" > "$D"
run
assert "사실상-c: 옛 판이면 전달(b)" b "$COEXIST_LAST_BRANCH"
assert "사실상-c: 현재판이 들어옴" "# V2" "$(sed -n 1p "$D")"
# 대조: 진짜 하류 수정(이력에 없는 내용)은 여전히 c 로 보존된다
printf '# LOCAL9\n%s' "$NEW9" > "$D"; run
assert "c 유지: 진짜 하류 수정은 손대지 않음" c "$COEXIST_LAST_BRANCH"
assert "c 유지: 하류 수정 살아 있음" "# LOCAL9" "$(sed -n 1p "$D")"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
