#!/usr/bin/env bash
# 복사 설치 전환 검증 (계획 docs/exec-plans/active/2026-09-15-copy-install.md 목표 1~7 · 11 · 12).
#
# 설계 근거: docs/hermes-universe/design/world/copy-install.md
#   - 소우주 설치물은 저장소 밖 경로를 가리키지 않는다 (E-02, R 룰 후보)
#   - 정리·제거는 링크 여부가 아니라 설치 목록 기준 (I-02)
#   - 변조 감지는 경고, 공장 자기 설치만 저장소 안 상대경로 링크
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다.
# 실행: bash tests/copy-install-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail
export HARNESS_TOOL_INSTALL=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"
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

SANDBOX="$TMP/harness"
mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"
git -C "$SANDBOX" init -q && git -C "$SANDBOX" add -A >/dev/null 2>&1 \
  && git -C "$SANDBOX" -c user.name=t -c user.email=t@t commit -qm init >/dev/null 2>&1
git -C "$SANDBOX" remote add origin git@example.invalid:factory.git

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git -C "$PROJ" init -q
install() { bash "$SANDBOX/project-claude.sh" "$PROJ" "$@" >"$TMP/install.log" 2>&1; }
MANIFEST="$PROJ/.claude/.factory-manifest.json"
count_links() { find "$PROJ/.claude/skills" "$PROJ/.claude/agents" "$PROJ/.claude/rules" -type l 2>/dev/null | wc -l; }
# 3 kind 만 센다. 공존 설치(2026-09-17) 뒤로 목록은 훅·git훅·스크립트·lint 도 기록하므로 전체를 세면
# "설치한 것 = 기록한 것" 이 아니라 다른 것을 비교하게 된다(그때 23 vs 145 로 빨개졌다).
manifest_n() { python3 -c "import json;print(sum(1 for i in json.load(open('$MANIFEST'))['items'] if i['kind'] in ('skills','agents','rules')))" 2>/dev/null || echo 0; }

echo "== 1. 복사 설치 (목표 1 · 2 · 5) =="
install harness hermes
assert "설치 종료 코드 0" "0" "$?"
assert "심링크 0개" "0" "$(count_links)"
installed_n=$(find "$PROJ/.claude/skills" "$PROJ/.claude/agents" "$PROJ/.claude/rules" -mindepth 1 -maxdepth 1 | wc -l)
assert "설치 목록 항목 수 = 설치된 항목 수" "$installed_n" "$(manifest_n)"
assert "목록 항목에 name·kind·factory_commit·sha256" "ok" "$(python3 -c "
import json; i=json.load(open('$MANIFEST'))['items'][0]
print('ok' if all(k in i for k in ('name','kind','factory_commit','sha256')) and len(i['sha256'])==64 else i)")"
assert "factory.json 에 remote_url·installed_version(40자)" "ok" "$(python3 -c "
import json; d=json.load(open('$PROJ/.hermes/factory.json'))
print('ok' if d['remote_url'] and len(d['installed_version'])==40 else d)")"
assert "factory.json 은 git 추적 대상(무시 아님)" "1" "$(git -C "$PROJ" check-ignore -v .hermes/factory.json | grep -c '!.hermes/factory.json')"
assert "manifest 는 gitignore 마커에 없음" "0" "$(grep -c 'factory-manifest' "$PROJ/.gitignore")"

echo ""
echo "== 2. 재설치 멱등 =="
install harness hermes
assert "재설치 후 항목 수 불변" "$installed_n" "$(find "$PROJ/.claude/skills" "$PROJ/.claude/agents" "$PROJ/.claude/rules" -mindepth 1 -maxdepth 1 | wc -l)"
assert "재설치 로그에 백업 없음" "0" "$(grep -c '백업' "$TMP/install.log")"

echo ""
echo "== 3. 목록 기준 정리 (목표 3) =="
mkdir -p "$PROJ/.claude/skills/my-own"; echo "# mine" > "$PROJ/.claude/skills/my-own/SKILL.md"
install hermes
assert "프리셋에서 빠진 항목은 제거됨(harness 스킬 목록에 없음)" "0" "$(grep -c 'harness-reasoning-sandwich' "$MANIFEST")"
assert "harness 스킬 폴더 제거됨" "0" "$([[ -d "$PROJ/.claude/skills/harness-reasoning-sandwich" ]] && echo 1 || echo 0)"
assert "소우주 자체 스킬 my-own 은 남음" "1" "$([[ -f "$PROJ/.claude/skills/my-own/SKILL.md" ]] && echo 1 || echo 0)"

echo ""
echo "== 4. 첫 재설치 이행 분기 (구버전 심링크 → 목록 → 복사본) =="
LEG="$TMP/legacy"; mkdir -p "$LEG/.claude/skills" "$LEG/.claude/agents" "$LEG/.claude/skills/legacy-own"; git -C "$LEG" init -q
ln -s "$SANDBOX/assets/skills/hermes-recall" "$LEG/.claude/skills/hermes-recall"
ln -s "$SANDBOX/assets/agents/planner.md" "$LEG/.claude/agents/planner.md"   # hermes 프리셋에 없음
echo x > "$LEG/.claude/skills/legacy-own/SKILL.md"
bash "$SANDBOX/project-claude.sh" "$LEG" hermes >"$TMP/legacy.log" 2>&1
assert "이행 로그 출력" "1" "$(grep -c '이행: 기존 심링크' "$TMP/legacy.log" | awk '{print ($1>0)}')"
assert "링크 → 복사본 건수 보고" "1" "$(grep -c '링크 → 복사본' "$TMP/legacy.log")"
assert "이행 후 심링크 0개" "0" "$(find "$LEG/.claude" -type l | wc -l)"
assert "hermes-recall 은 실디렉터리로" "1" "$([[ -d "$LEG/.claude/skills/hermes-recall" && ! -L "$LEG/.claude/skills/hermes-recall" ]] && echo 1 || echo 0)"
assert "프리셋에 없던 옛 링크(planner)는 정리됨" "0" "$([[ -e "$LEG/.claude/agents/planner.md" ]] && echo 1 || echo 0)"
assert "사용자 폴더 legacy-own 보존" "1" "$([[ -f "$LEG/.claude/skills/legacy-own/SKILL.md" ]] && echo 1 || echo 0)"

echo ""
echo "== 5. 변조 감지 훅 (목표 4) =="
install harness hermes   # 3절에서 harness 를 뺐으므로 훅 소유 프리셋을 되살린다
HOOK="$PROJ/scripts/hooks/claude-posttooluse-factory-tamper-warn.sh"
assert "훅 파일 배포됨" "1" "$([[ -x "$HOOK" ]] && echo 1 || echo 0)"
assert "settings.json 에 등록됨" "1" "$(grep -c 'factory-tamper-warn' "$PROJ/.claude/settings.json")"
run_hook() { echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>&1; }
assert "변조 없음 → 경고 없음" "0" "$(run_hook "$PROJ/.claude/skills/hermes-recall/SKILL.md" | grep -c 'factory-tamper WARN')"
echo "# tampered" >> "$PROJ/.claude/skills/hermes-recall/SKILL.md"
assert "변조 → [factory-tamper WARN]" "1" "$(run_hook "$PROJ/.claude/skills/hermes-recall/SKILL.md" | grep -c 'factory-tamper WARN')"
assert "자체 스킬 편집 → 경고 없음" "0" "$(run_hook "$PROJ/.claude/skills/my-own/SKILL.md" | grep -c 'factory-tamper WARN')"

echo ""
echo "== 5-b. 로컬에서 고친 공장 설치물은 재설치 때 백업된다 (리뷰 MEDIUM) =="
# 5절에서 hermes-recall 을 변조해 둔 상태. 재설치하면 덮어쓰기 전에 .backup-* 로 보존돼야 한다.
install harness hermes
assert "재설치 로그에 '로컬에서 수정됨' 백업 경고" "1" "$(grep -c '로컬에서 수정됨' "$TMP/install.log")"
assert "백업 폴더에 변조 내용이 남음" "1" "$(cat "$PROJ"/.claude/skills/hermes-recall.backup-*/SKILL.md 2>/dev/null | grep -c '# tampered')"
assert "설치본은 공장 원본으로 복원" "0" "$(grep -c '# tampered' "$PROJ/.claude/skills/hermes-recall/SKILL.md")"
rm -rf "$PROJ"/.claude/skills/hermes-recall.backup-*
echo ""
echo "== 5-c. 손상된 설치 목록은 조용히 삼키지 않는다 (리뷰 MEDIUM) =="
cp "$MANIFEST" "$TMP/manifest.bak"; echo '{broken' > "$MANIFEST"
install harness hermes
assert "손상 경고 출력" "1" "$(grep -c 'factory-manifest WARN' "$TMP/install.log" | awk '{print ($1>0)}')"
assert "재설치 후 목록이 정상 JSON 으로 복구" "$installed_n" "$(manifest_n)"
assert "임시 파일(.tmp) 잔존 없음" "0" "$(ls "$PROJ"/.claude/.factory-manifest.json.tmp 2>/dev/null | wc -l)"

echo ""
echo "== 6. 공장 자기 설치 상대경로 링크 + 깨진 링크 훅 (목표 6 · 7) =="
bash "$SANDBOX/project-claude.sh" "$SANDBOX" harness hermes >"$TMP/self.log" 2>&1
assert "공장 자기 설치 종료 코드 0" "0" "$?"
self_links=$(find "$SANDBOX/.claude/skills" "$SANDBOX/.claude/agents" "$SANDBOX/.claude/rules" -type l | wc -l)
assert "공장은 링크로 설치됨" "1" "$([[ $self_links -gt 0 ]] && echo 1 || echo 0)"
assert "절대경로 링크 0개" "0" "$(find "$SANDBOX/.claude/skills" "$SANDBOX/.claude/agents" "$SANDBOX/.claude/rules" -type l -exec readlink {} \; | grep -c '^/')"
assert "모든 링크가 ../../assets/ 형태" "$self_links" "$(find "$SANDBOX/.claude/skills" "$SANDBOX/.claude/agents" "$SANDBOX/.claude/rules" -type l -exec readlink {} \; | grep -c '^\.\./\.\./assets/')"
assert "링크 대상이 전부 존재" "0" "$(find "$SANDBOX/.claude" -xtype l | wc -l)"
LINKHOOK="$SANDBOX/scripts/hooks/claude-sessionstart-factory-link-check.sh"
assert "정상 상태 → 경고 없음" "0" "$(CLAUDE_PROJECT_DIR="$SANDBOX" bash "$LINKHOOK" 2>&1 | grep -c 'factory-link WARN')"
ln -s ../../assets/skills/does-not-exist "$SANDBOX/.claude/skills/does-not-exist"
assert "깨진 링크 → [factory-link WARN]" "1" "$(CLAUDE_PROJECT_DIR="$SANDBOX" bash "$LINKHOOK" 2>&1 | grep -c 'factory-link WARN')"
assert "소우주(복사 설치)에서는 링크 훅 조용함" "0" "$(CLAUDE_PROJECT_DIR="$PROJ" bash "$LINKHOOK" 2>&1 | wc -c)"

echo ""
echo "== 6-b. 복사된 사본을 스테이징해도 소우주 커밋 게이트에 막히지 않는다 (2026-09-16 발견) =="
# 심링크 시절엔 링크 하나만 추적돼 안의 .md/.py 가 R-fmt·P9·R-cx 밖이었다. 복사본은 실제 파일이라
# 게이트에 잡힌다 — 사본은 공장이 검사하므로 pre-commit 이 제외해야 한다.
git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>/dev/null || true
git -C "$PROJ" add -A .claude .hermes/factory.json .gitignore scripts 2>/dev/null
GATE_OUT=$(cd "$PROJ" && .git/hooks/pre-commit 2>&1); GATE_RC=$?
assert "사본 전체 스테이징 시 pre-commit 통과" "0" "$GATE_RC"
assert "R-fmt 가 사본을 보고하지 않음" "0" "$(echo "$GATE_OUT" | grep -c '\[R-fmt\]')"
assert "P9 가 사본 예제 자격증명을 보고하지 않음" "0" "$(echo "$GATE_OUT" | grep -c '\[P9\]')"
assert "R-cx 가 사본 규칙 예시를 보고하지 않음" "0" "$(echo "$GATE_OUT" | grep -c '\[R-cx\]')"
git -C "$PROJ" reset -q

echo ""
echo "== 7. 제거도 목록 기준 (목표 11) =="
printf 'y\nn\n' | bash "$SANDBOX/uninstall.sh" "$PROJ" >"$TMP/uninstall.log" 2>&1
assert "uninstall 종료 코드 0" "0" "$?"
assert "목록 항목이 제거됨" "1" "$(grep -c '설치 목록' "$TMP/uninstall.log" | awk '{print ($1>0)}')"
assert "hermes-recall 제거됨" "0" "$([[ -e "$PROJ/.claude/skills/hermes-recall" ]] && echo 1 || echo 0)"
assert "자체 스킬 my-own 은 남음" "1" "$([[ -f "$PROJ/.claude/skills/my-own/SKILL.md" ]] && echo 1 || echo 0)"
assert "manifest 제거됨" "0" "$([[ -f "$MANIFEST" ]] && echo 1 || echo 0)"

echo ""
echo "== 7-b. 임시 경로 설치는 실 레지스트리에 등록되지 않는다 (2026-09-16 오염 사고) =="
# 실 저장소의 project-claude.sh 로 /tmp 프로젝트를 설치해도 실 .installed-projects 가 바뀌면 안 된다.
REAL_REG="$REPO_ROOT/.installed-projects"
REG_BEFORE="$(cat "$REAL_REG" 2>/dev/null | md5sum)"
T2="$TMP/tmpproj"; mkdir -p "$T2"; git -C "$T2" init -q
UNTRACKED_BEFORE="$(git -C "$REPO_ROOT" status --short --untracked-files=all | grep -c '^??')"
bash "$REPO_ROOT/project-claude.sh" "$T2" hermes >"$TMP/tmpproj.log" 2>&1
assert "임시 경로 설치 종료 코드 0" "0" "$?"
assert "등록 생략 로그" "1" "$(grep -c '레지스트리 등록 생략' "$TMP/tmpproj.log")"
assert "실 .installed-projects 불변" "$REG_BEFORE" "$(cat "$REAL_REG" 2>/dev/null | md5sum)"
assert "실 레지스트리에 /tmp 경로 없음" "0" "$(grep -c '^/tmp/' "$REAL_REG" 2>/dev/null)"
# TMPDIR 이 다른 곳(백그라운드 잡의 tmp 등)을 가리켜도 /tmp 사본은 등록되지 않아야 한다
# (2026-09-17 리허설이 이 조합으로 실 레지스트리를 두 번 오염 — backlog installer-registers-rehearsal-paths).
T3="$(mktemp -d /tmp/harness-guard.XXXXXX)"; git -C "$T3" init -q; OTHER_TMP="$(mktemp -d)"
TMPDIR="$OTHER_TMP" bash "$REPO_ROOT/project-claude.sh" "$T3" hermes >"$TMP/tmpproj2.log" 2>&1
assert "TMPDIR 을 딴 곳으로 둔 /tmp 설치도 등록 생략" "1" "$(grep -c '레지스트리 등록 생략' "$TMP/tmpproj2.log")"
assert "  실 레지스트리에 그 경로 없음" "0" "$(grep -cF "$T3" "$REAL_REG" 2>/dev/null || true)"
grep -vF "$T3" "$REAL_REG" > "$TMP/reg.clean" 2>/dev/null; cp "$TMP/reg.clean" "$REAL_REG"; rm -rf "$T3" "$OTHER_TMP"
# 실 저장소가 이 임시 프로젝트를 설치했으므로 실 .hermes 등은 건드리지 않았는지도 본다.
# 설치 *전후* 를 비교한다 — 작업 중인 새 파일이 있어도 이 단언이 깨지지 않게(2026-09-16).
assert "실 저장소에 설치가 새 파일을 남기지 않음" "$UNTRACKED_BEFORE" "$(git -C "$REPO_ROOT" status --short --untracked-files=all | grep -c '^??')"

echo ""
echo "== 8. 저장소 안 ln -s 는 메모리 폴더 링크와 공장 자기 설치뿐 (목표 12) =="
assert "installers.sh 에 is_windows_path 없음" "0" "$(grep -c is_windows_path "$REPO_ROOT/lib/installers.sh")"
assert "lib/*.sh 의 ln -s 는 2곳(메모리 폴더 · 공장 자기 설치 상대경로)" "2" "$(grep -c 'ln -s' "$REPO_ROOT"/lib/*.sh | awk -F: '{s+=$2} END{print s}')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
