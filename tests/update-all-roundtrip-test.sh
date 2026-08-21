#!/usr/bin/env bash
# update-all.sh 재실행 경로 검증.
#
# 왜 필요한가: setup.sh / update-all.sh 를 도는 테스트가 하나도 없었다(2026-08-13 확인).
# 기존 테스트는 전부 project-claude.sh 를 직접 호출한다. 그런데 해시 마커 판정은
# **재실행 경로에서만** 발동한다 — 신규 설치는 파일이 없어 무조건 배치되므로
# 판정 자체가 일어나지 않는다.
#
# 격리: 저장소를 통째로 임시 사본에 복사하고 거기서 실행한다.
#   update-all.sh 는 레지스트리 경로를 자기 위치($DEV_SETTING_DIR)에서 유도하므로,
#   실 저장소에서 돌리면 사용자의 실제 프로젝트 전체를 재설치해 버린다.
#   실 레지스트리를 임시로 바꿔치기하는 방식은 중단 시 사용자 데이터가 날아간다.
#
# 실행: bash tests/update-all-roundtrip-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"          # ~/.claude 오염 방지
mkdir -p "$HOME"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# ── 저장소 사본 (실 레지스트리·실 자산 격리) ─────────────────────────────────
SANDBOX="$TMP/harness"
mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"

WF_SRC="$SANDBOX/assets/cron-templates/github-actions/weekly-doc-gardening.yml"

PROJ="$TMP/proj"
mkdir -p "$PROJ"
cd "$PROJ"
git init -q .
git config user.email "harness-test@example.com"
git config user.name "harness-test"
# 워크플로 배치는 git remote 로 호스트를 판별한다 (install_harness_gc_workflows).
git remote add origin https://github.com/example/proj.git

echo "== 1. 신규 설치 =="
bash "$SANDBOX/project-claude.sh" "$PROJ" harness >/dev/null 2>&1
WF="$PROJ/.github/workflows/weekly-doc-gardening.yml"
[[ -f "$WF" ]]; _rc=$?
assert "워크플로 배치됨" "0" "$_rc"
grep -q "^# harness-template-sha:" "$WF"; _rc=$?
assert "해시 마커 포함" "0" "$_rc"
grep -q "PLACEHOLDER" "$WF"; _rc=$?
assert "마커가 실제 해시로 치환됨" "1" "$_rc"

echo ""
echo "== 2. 사용자 미수정 + 템플릿 개정 → 덮어씀 =="
echo "# TEMPLATE REVISION MARKER" >> "$WF_SRC"
bash "$SANDBOX/update-all.sh" >/dev/null 2>&1
grep -q "TEMPLATE REVISION MARKER" "$WF"; _rc=$?
assert "미수정 워크플로는 갱신됨" "0" "$_rc"

echo ""
echo "== 3. 사용자 수정 + 템플릿 개정 → 보존 =="
echo "# USER EDIT" >> "$WF"
echo "# SECOND TEMPLATE REVISION" >> "$WF_SRC"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
grep -q "USER EDIT" "$WF"; _rc=$?
assert "사용자 수정분 보존" "0" "$_rc"
grep -q "SECOND TEMPLATE REVISION" "$WF"; _rc=$?
assert "사용자 수정 시 덮어쓰지 않음" "1" "$_rc"

echo ""
echo "== 4. 마커 없는 구버전 → 보존 + 경고 =="
grep -v "^# harness-template-sha:" "$WF" > "$WF.tmp" && mv "$WF.tmp" "$WF"
echo "# LEGACY CONTENT" >> "$WF"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
grep -q "LEGACY CONTENT" "$WF"; _rc=$?
assert "마커 없는 파일 보존" "0" "$_rc"
echo "$UPD_OUT" | grep -q "수동 갱신"; _rc=$?
assert "수동 갱신 경고 출력" "0" "$_rc"

echo ""
echo "== 5. core-beliefs 마커 블록 =="
CB="$PROJ/docs/design-docs/core-beliefs.md"
[[ -f "$CB" ]]; _rc=$?
assert "core-beliefs 배치됨" "0" "$_rc"
grep -q "HARNESS-RULES:BEGIN" "$CB"; _rc=$?
assert "하네스 룰 마커 블록 존재" "0" "$_rc"
printf '\n### R1. 프로젝트 고유 룰\n' >> "$CB"
bash "$SANDBOX/update-all.sh" >/dev/null 2>&1
grep -q "R1. 프로젝트 고유 룰" "$CB"; _rc=$?
assert "마커 밖 사용자 룰 보존" "0" "$_rc"
assert "마커 블록 중복 없음" "1" "$(grep -c 'HARNESS-RULES:BEGIN' "$CB")"

echo ""
echo "== 6. presets.lock 부재 → 스킵 =="
rm -f "$PROJ/.claude/presets.lock"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
echo "$UPD_OUT" | grep -q "presets.lock 없음"; _rc=$?
assert "lock 부재 시 스킵 사유 출력" "0" "$_rc"

echo ""
echo "== 7. GitLab 배포 경로 =="
# 등록된 실제 프로젝트 중 워크플로를 가진 곳은 전부 GitLab 이다(2026-08-13 확인, GitHub 0개).
# 즉 이 분기가 현실에서 유일하게 쓰이는 경로인데 위 1~4 는 GitHub 만 덮는다.
GL_SRC="$SANDBOX/assets/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml"
GLPROJ="$TMP/glproj"
mkdir -p "$GLPROJ"
cd "$GLPROJ"
git init -q .
git config user.email "harness-test@example.com"
git config user.name "harness-test"
git remote add origin https://gitlab.com/example/glproj.git

bash "$SANDBOX/project-claude.sh" "$GLPROJ" harness >/dev/null 2>&1
GLWF="$GLPROJ/.gitlab/doc-gardening.yml"
[[ -f "$GLWF" ]]; _rc=$?
assert "GitLab 워크플로 배치됨" "0" "$_rc"
grep -q "^# harness-template-sha:" "$GLWF"; _rc=$?
assert "GitLab 해시 마커 포함" "0" "$_rc"
grep -q "PLACEHOLDER" "$GLWF"; _rc=$?
assert "GitLab 마커가 실제 해시로 치환됨" "1" "$_rc"

echo "# GL TEMPLATE REVISION" >> "$GL_SRC"
bash "$SANDBOX/update-all.sh" >/dev/null 2>&1
grep -q "GL TEMPLATE REVISION" "$GLWF"; _rc=$?
assert "GitLab 미수정 워크플로는 갱신됨" "0" "$_rc"

# 마커 없는 구버전 — novel-bc 등 기존 설치본이 전부 이 상태다.
grep -v "^# harness-template-sha:" "$GLWF" > "$GLWF.tmp" && mv "$GLWF.tmp" "$GLWF"
echo "# GL LEGACY CONTENT" >> "$GLWF"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
grep -q "GL LEGACY CONTENT" "$GLWF"; _rc=$?
assert "GitLab 마커 없는 파일 보존" "0" "$_rc"
echo "$UPD_OUT" | grep -q "doc-gardening.yml (마커 없는 구버전"; _rc=$?
assert "GitLab 수동 갱신 경고 출력" "0" "$_rc"

echo ""
echo "== 8. 알려진 구버전 해시는 마커가 없어도 갱신된다 =="
# 마커 도입 이전에 배포된 설치본은 마커가 없어 "사용자 수정본" 으로 보존된다.
# 그러면 마커 도입의 목적(개정본을 기존 프로젝트에 전달)이 첫 세대에 대해 달성되지 않는다.
# 실제로 2026-08-13 전파에서 8개 프로젝트가 손대지 않은 구버전인데도 전부 보존됐다.
# HARNESS_LEGACY_TEMPLATE_SHAS 에 등록된 해시와 일치하면 미수정으로 보고 갱신한다.
LEGACY_PROJ="$TMP/legacyproj"
mkdir -p "$LEGACY_PROJ"
cd "$LEGACY_PROJ"
git init -q .
git config user.email "harness-test@example.com"
git config user.name "harness-test"
git remote add origin https://gitlab.com/example/legacyproj.git
bash "$SANDBOX/project-claude.sh" "$LEGACY_PROJ" harness >/dev/null 2>&1
LGWF="$LEGACY_PROJ/.gitlab/doc-gardening.yml"

# 마커를 떼어 "구버전" 상태를 만들고, 그 내용의 해시를 legacy 목록에 등록한다.
grep -v "^# harness-template-sha:" "$LGWF" > "$LGWF.tmp" && mv "$LGWF.tmp" "$LGWF"
LEGACY_SHA=$(sha256sum "$LGWF" | cut -d' ' -f1)
sed -i "s|^HARNESS_LEGACY_TEMPLATE_SHAS=(|HARNESS_LEGACY_TEMPLATE_SHAS=(\n  \"$LEGACY_SHA\"|" \
  "$SANDBOX/lib/harness_installers.sh"
echo "# LEGACY TEMPLATE REVISION" >> "$GL_SRC"

UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
grep -q "LEGACY TEMPLATE REVISION" "$LGWF"; _rc=$?
assert "알려진 구버전 → 갱신됨" "0" "$_rc"
grep -q "^# harness-template-sha:" "$LGWF"; _rc=$?
assert "갱신 시 마커가 심어짐 (다음부터 정상 판정)" "0" "$_rc"
echo "$UPD_OUT" | grep -q "알려진 구버전"; _rc=$?
assert "구버전 갱신 사실을 로그로 알림" "0" "$_rc"

echo ""
echo "== 9. 배포 중단된 프리셋이 lock 에 남아도 재설치가 막히지 않는다 =="
# 2026-08-21: serena 프리셋을 저장소에서 지웠는데 설치본 lock 에는 남아 있어
# `Unknown preset: 'serena'` 로 재설치가 실패했다. 그 프로젝트들은 세레나만 못 받은 게
# 아니라 *이후 모든 하네스 업데이트*를 못 받고 있었다 — 11곳 중 6곳.
# lock 은 기계가 쓴 파일이므로 유효하지 않은 항목 = 하네스가 버린 프리셋이다.
# 근거: docs/superpowers/specs/2026-08-21-preset-retirement-ownership-design.md
GHOST_LOCK="$LEGACY_PROJ/.claude/presets.lock"
printf 'harness\nserena\n' > "$GHOST_LOCK"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)

echo "$UPD_OUT" | grep -q "Unknown preset"; _rc=$?
assert "유령 프리셋으로 실패하지 않음" "1" "$_rc"
echo "$UPD_OUT" | grep -q "✗ 실패 — legacyproj"; _rc=$?
assert "해당 프로젝트가 실패로 집계되지 않음" "1" "$_rc"
echo "$UPD_OUT" | grep -q "배포 중단된 프리셋"; _rc=$?
assert "제거 사실을 경고로 알림 (조용히 빼지 않음)" "0" "$_rc"
grep -qx "serena" "$GHOST_LOCK"; _rc=$?
assert "lock 에서 유령 항목이 제거됨" "1" "$_rc"
grep -qx "harness" "$GHOST_LOCK"; _rc=$?
assert "유효한 프리셋은 lock 에 보존됨" "0" "$_rc"

# 전부 유령이면 설치할 것이 없다 — 빈 인자로 재설치를 강행하지 않고 스킵한다.
printf 'serena\n' > "$GHOST_LOCK"
UPD_OUT=$(bash "$SANDBOX/update-all.sh" 2>&1)
echo "$UPD_OUT" | grep -q "유효한 프리셋이 없음"; _rc=$?
assert "전부 유령이면 스킵" "0" "$_rc"

echo ""
echo "== 10. permissions.allow 소유권 동기화 =="
# 2026-08-21: allow 가 merge-only 라 프리셋에서 빠진 권한이 영구히 남았다.
# 세레나 제거 후 6개 프로젝트에 죽은 권한 184건이 쌓여 있었다.
# hooks 와 같은 소유권 동기화를 적용한다 — 하네스가 배포한 항목만 회수하고
# 사용자가 넣은 항목은 보존한다. settings.local.json 은 건드리지 않는다.
# 근거: docs/superpowers/specs/2026-08-21-preset-retirement-ownership-design.md
PERMPROJ="$TMP/permproj"
mkdir -p "$PERMPROJ"
cd "$PERMPROJ"
git init -q .
git config user.email "harness-test@example.com"
git config user.name "harness-test"

bash "$SANDBOX/project-claude.sh" "$PERMPROJ" harness python >/dev/null 2>&1
PS="$PERMPROJ/.claude/settings.json"
_has() { python3 -c "
import json,sys
a=json.load(open('$PS')).get('permissions',{}).get('allow',[])
sys.exit(0 if '$1' in a else 1)"; }

_has 'Bash(black:*)'; _rc=$?
assert "python 프리셋 권한이 배치됨" "0" "$_rc"

# 사용자가 손으로 넣은 항목 + 은퇴 프리셋이 남긴 유령 항목을 주입한다.
python3 -c "
import json
p='$PS'; d=json.load(open(p))
a=d.setdefault('permissions',{}).setdefault('allow',[])
a.append('Bash(my-own-tool:*)')
a.append('mcp__plugin_serena_serena__find_symbol')
json.dump(d,open(p,'w'),indent=2,ensure_ascii=False)
"
# python 프리셋을 빼고 재설치 — 그 권한은 걷히고 사용자 것은 남아야 한다.
bash "$SANDBOX/project-claude.sh" "$PERMPROJ" harness >/dev/null 2>&1

_has 'Bash(my-own-tool:*)'; _rc=$?
assert "사용자가 넣은 권한은 보존" "0" "$_rc"
_has 'Bash(black:*)'; _rc=$?
assert "프리셋에서 빠진 권한은 회수됨" "1" "$_rc"
_has 'mcp__plugin_serena_serena__find_symbol'; _rc=$?
assert "은퇴 등재된 유령 권한도 회수됨" "1" "$_rc"
_has 'Bash(cat:*)'; _rc=$?
assert "여전히 제공되는 권한은 유지됨" "0" "$_rc"

# settings.local.json 은 하네스가 권한을 건드리지 않는 자리다.
PL="$PERMPROJ/.claude/settings.local.json"
python3 -c "
import json
p='$PL'
try: d=json.load(open(p))
except Exception: d={}
d.setdefault('permissions',{}).setdefault('allow',[]).append('mcp__plugin_serena_serena__find_symbol')
json.dump(d,open(p,'w'),indent=2,ensure_ascii=False)
"
bash "$SANDBOX/project-claude.sh" "$PERMPROJ" harness >/dev/null 2>&1
python3 -c "
import json,sys
a=json.load(open('$PL')).get('permissions',{}).get('allow',[])
sys.exit(0 if 'mcp__plugin_serena_serena__find_symbol' in a else 1)"; _rc=$?
assert "settings.local.json 의 승인은 건드리지 않음" "0" "$_rc"

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
