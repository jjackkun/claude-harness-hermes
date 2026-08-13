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
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
