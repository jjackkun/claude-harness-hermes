#!/usr/bin/env bash
# 설치 목록 모아 쓰기 검증 (계획 docs/exec-plans/active/2026-11-25-manifest-batch-write.md 목표 G1·G4).
#
#   - 묶음 모드와 바로 쓰기의 결과가 바이트까지 같다(같은 이름 교체·공백/탭 이름·선택 필드 포함)
#   - 묶음 안에서는 목록 파일이 그대로이고, 읽는 함수(field)는 모아 둔 기록을 먼저 반영해 본다
#   - 서브셸에서 부른 manifest_add 도 잃지 않는다
#   - 도중에 죽어 .pending 이 남아도 다음 manifest 호출이 먼저 반영한다
#   - 바로 쓰기(묶음 밖)는 .pending 을 남기지 않는다 — 직접 source 하는 쪽(uninstall·시험)의 동작이 그대로
#
# 실행: bash tests/manifest-batch-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export DEV_SETTING_DIR="$REPO_ROOT" TMPDIR="$TMP"
# shellcheck source=lib/factory_manifest.sh
source "$REPO_ROOT/lib/factory_manifest.sh"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

F1="$TMP/f1"; echo one > "$F1"
F2="$TMP/f2"; echo two > "$F2"
SK="$TMP/skill"; mkdir -p "$SK/sub"; echo a > "$SK/SKILL.md"; echo b > "$SK/sub/x.md"

# 같은 순서의 기록 — 같은 이름(rules/r1) 교체와 공백·탭이 든 이름을 섞는다
sequence() {   # <claude_dir>
  manifest_add "$1" rules r1 "$F1"
  manifest_add "$1" skills "my skill" "$SK"
  manifest_add "$1" hooks $'scripts/a\tb.sh' "$F2" scripts/a.sh 755
  manifest_add "$1" rules r1 "$F2" assets/rules/r1.md 644
  manifest_add "$1" agents z "$F1"
}

echo "── 1. 바로 쓰기(묶음 밖)"
D1="$TMP/direct/.claude"
sequence "$D1"
assert "목록 파일이 생긴다" 1 "$([[ -f "$D1/.factory-manifest.json" ]] && echo 1 || echo 0)"
assert ".pending 이 남지 않는다" 0 "$(ls -a "$D1" | grep -c pending)"
assert "항목 4개(r1 은 교체)" 4 "$(python3 -c "import json;print(len(json.load(open('$D1/.factory-manifest.json'))['items']))")"

echo "── 2. 묶음 모드"
D2="$TMP/batch/.claude"
manifest_batch_begin
manifest_add "$D2" rules r0 "$F1"
assert "묶음 안에서는 목록 파일을 아직 쓰지 않는다" 0 "$([[ -f "$D2/.factory-manifest.json" ]] && echo 1 || echo 0)"
assert "읽는 함수는 모아 둔 기록을 먼저 반영해 본다" "$(sha256sum "$F1" | cut -d' ' -f1)" "$(manifest_field "$D2" rules r0 sha256)"
manifest_add "$D2" rules r0b "$F1"
( manifest_add "$D2" agents from-subshell "$F2" )
assert "묶음 안 두 번째 기록도 아직 쓰지 않았다" 1 "$(grep -c '"name"' "$D2/.factory-manifest.json")"
REG="$_MANIFEST_BATCH_REG"
manifest_batch_end
assert "끝에 모두 반영(r0·r0b·서브셸)" "agents/from-subshell rules/r0 rules/r0b" \
  "$(python3 -c "import json;print(' '.join(i['kind']+'/'+i['name'] for i in json.load(open('$D2/.factory-manifest.json'))['items']))")"
assert "끝난 뒤 .pending 없음" 0 "$(ls -a "$D2" | grep -c pending)"
assert "묶음 등록 임시 파일 없음" 0 "$([[ -e "$REG" ]] && echo 1 || echo 0)"
assert "끝을 두 번 불러도 된다(EXIT trap 겸용)" 0 "$(manifest_batch_end; echo $?)"

echo "── 3. 묶음과 바로 쓰기의 결과가 바이트까지 같다"
D3="$TMP/batch3/.claude"
manifest_batch_begin; sequence "$D3"; manifest_batch_end
assert "같은 기록 순서 → 같은 목록 파일" same "$(cmp -s "$D1/.factory-manifest.json" "$D3/.factory-manifest.json" && echo same || echo diff)"

echo "── 4. 도중에 죽은 묶음"
D4="$TMP/crash/.claude"
( manifest_batch_begin; manifest_add "$D4" rules lost "$F1"; exit 1 )   # 끝을 부르지 않고 죽는다
assert "죽은 뒤 .pending 이 남는다" 1 "$(ls -a "$D4" | grep -c pending)"
assert "다음 manifest_read 가 먼저 반영한다" lost "$(manifest_read "$D4" rules)"
assert "반영 뒤 .pending 없음" 0 "$(ls -a "$D4" | grep -c pending)"

echo "── 5. 다른 읽기·쓰기 함수도 반영 뒤에 동작한다"
D5="$TMP/other/.claude"
manifest_batch_begin
manifest_add "$D5" rules keep "$F1"; manifest_add "$D5" rules gone "$F1"
assert "prune 이 모아 둔 항목을 보고 뺀다" gone "$(manifest_prune "$D5" rules keep)"
manifest_add "$D5" rules v "$F1"
assert "verify 가 모아 둔 항목과 대조한다(같음=0)" 0 "$(manifest_verify "$D5" rules v "$F1"; echo $?)"
manifest_batch_end
assert "prune 결과가 끝까지 유지된다" "keep v" "$(manifest_read "$D5" rules | tr '\n' ' ' | sed 's/ $//')"

echo "── 6. 쓰다 죽어 잘린 기록은 버린다"
D6="$TMP/torn/.claude"; mkdir -p "$D6"
printf '%s\0' rules whole aaa c1 "" "" > "$D6/.factory-manifest.json.pending"
printf '%s\0%s' rules torn >> "$D6/.factory-manifest.json.pending"   # 여섯 칸을 다 못 쓰고 죽음
assert "여섯 칸이 다 찬 기록만 반영" whole "$(manifest_read "$D6" rules)"

echo "── 7. 묶음 끝에서 쓰기 실패"
D7="$TMP/ro/.claude"
manifest_batch_begin
manifest_add "$D7" rules r "$F1"
REG="$_MANIFEST_BATCH_REG"
chmod 555 "$D7"
manifest_batch_end 2>"$TMP/ro.err"; rc=$?
chmod 755 "$D7"
assert "실패를 종료 코드로 알린다" 1 "$rc"
assert "실패를 경고 줄로 알린다" 1 "$(grep -c '설치 목록을 쓰지 못했습니다' "$TMP/ro.err")"
assert "실패해도 등록 임시 파일은 지운다" 0 "$([[ -e "$REG" ]] && echo 1 || echo 0)"
assert "기록은 .pending 에 남아 다음 호출이 반영한다" r "$(manifest_read "$D7" rules)"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
