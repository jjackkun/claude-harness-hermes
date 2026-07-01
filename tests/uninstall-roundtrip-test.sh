#!/usr/bin/env bash
# 설치 → 사용자 자산 심기 → 언인스톨 라운드트립 테스트.
#
# 검증 목표:
#   1. uninstall.sh 가 하네스 설치물을 잔재 없이 제거한다
#   2. 사용자가 직접 추가한 자산(hook 항목, 스킬 실디렉터리, CLAUDE.md/.gitignore
#      마커 밖 내용)은 절대 건드리지 않는다
#   3. .installed-projects 레지스트리에서 해당 프로젝트가 제거된다
#
# 실행: bash tests/uninstall-roundtrip-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$REPO_ROOT/.installed-projects"

TMP=$(mktemp -d)
PROJ="$TMP/proj"
mkdir -p "$PROJ"

# 테스트 설치가 레지스트리를 오염시키지 않도록 끝에서 원복 (uninstall 실패 대비 안전망)
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$PROJ" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected='$expected' actual='$actual')"; FAIL=$((FAIL+1))
  fi
}
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }

echo "== 0. harness 설치 =="
git -C "$PROJ" init -q
bash "$REPO_ROOT/project-claude.sh" "$PROJ" harness >/dev/null 2>&1
assert "설치: settings.json 생성" "1" "$(exists "$PROJ/.claude/settings.json")"
assert "설치: scripts/hooks 생성" "1" "$(exists "$PROJ/scripts/hooks")"
assert "설치: 레지스트리 등록" "0" "$(grep -qxF "$PROJ" "$REGISTRY"; echo $?)"

echo ""
echo "== 1. 사용자 자산 심기 =="
# 1a. settings.json 에 사용자 hook 항목 추가
python3 - "$PROJ/.claude/settings.json" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data.setdefault("hooks", {}).setdefault("PostToolUse", []).append(
    {"matcher": "Write", "hooks": [{"type": "command", "command": "echo user-custom-hook"}]}
)
data["model"] = "user-pinned-model"   # 사용자 top-level 키
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF
# 1b. 사용자 스킬 실디렉터리 (symlink 아님)
mkdir -p "$PROJ/.claude/skills/user-own-skill"
printf -- '---\ndescription: user skill\n---\n# user-own-skill\n' > "$PROJ/.claude/skills/user-own-skill/SKILL.md"
# 1c. CLAUDE.md 마커 밖 사용자 내용
printf '\n# USER-SECTION-KEEP-ME\n사용자 직접 작성 내용\n' >> "$PROJ/CLAUDE.md"
# 1d. .gitignore 마커 밖 사용자 항목
echo "user-secret.txt" >> "$PROJ/.gitignore"

echo "  (사용자 hook + 스킬 실디렉터리 + CLAUDE.md/.gitignore 사용자 내용 심음)"

echo ""
echo "== 2. uninstall.sh 실행 =="
# 확인 프롬프트(진행할까요?)에 y 응답. .hermes 없으므로 추가 프롬프트 없음.
printf 'y\n' | bash "$REPO_ROOT/uninstall.sh" "$PROJ" >/dev/null 2>&1
assert "uninstall 종료 코드 0" "0" "$?"

echo ""
echo "== 3. 하네스 설치물 잔재 0 검증 =="
assert "settings.local.json 제거" "0" "$(exists "$PROJ/.claude/settings.local.json")"
assert "presets.lock 제거" "0" "$(exists "$PROJ/.claude/presets.lock")"
assert "scripts/hooks/ 제거" "0" "$(exists "$PROJ/scripts/hooks")"
assert ".git/hooks/pre-commit 제거" "0" "$(exists "$PROJ/.git/hooks/pre-commit")"

# .claude/{skills,agents,rules} 에 ai-dev-setting assets 를 가리키는 symlink 잔재 0
LINK_LEFT=0
for sub in skills agents rules; do
  dir="$PROJ/.claude/$sub"
  [[ -d "$dir" ]] || continue
  for entry in "$dir"/*; do
    [[ -L "$entry" ]] || continue
    [[ "$(readlink "$entry")" == "$REPO_ROOT/assets"* ]] && LINK_LEFT=$((LINK_LEFT+1))
  done
done
assert "하네스 asset symlink 잔재 0" "0" "$LINK_LEFT"

# CLAUDE.md / .gitignore 마커 블록 제거
MARKER_LEFT=$(grep -c 'DS:BEGIN\|DS:END' "$PROJ/CLAUDE.md" 2>/dev/null; true)
assert "CLAUDE.md 관리 블록 제거" "0" "${MARKER_LEFT:-0}"
GI_LEFT=$(grep -c 'harness-agent-preset' "$PROJ/.gitignore" 2>/dev/null; true)
assert ".gitignore 하네스 블록 제거" "0" "${GI_LEFT:-0}"

# settings.json 에 하네스 hook 잔재 0
HARNESS_HOOKS_LEFT=$(grep -c 'scripts/hooks/claude-' "$PROJ/.claude/settings.json" 2>/dev/null; true)
assert "settings.json 하네스 hooks 잔재 0" "0" "${HARNESS_HOOKS_LEFT:-0}"

# 레지스트리에서 제거
assert "레지스트리에서 제거" "1" "$(grep -qxF "$PROJ" "$REGISTRY"; echo $?)"

echo ""
echo "== 4. 사용자 자산 보존 검증 =="
assert "사용자 hook 항목 보존" "1" "$(grep -qF 'user-custom-hook' "$PROJ/.claude/settings.json" && echo 1 || echo 0)"
assert "사용자 top-level 키(model) 보존" "1" "$(grep -qF 'user-pinned-model' "$PROJ/.claude/settings.json" && echo 1 || echo 0)"
assert "사용자 스킬 실디렉터리 보존" "1" "$(exists "$PROJ/.claude/skills/user-own-skill/SKILL.md")"
assert "사용자 스킬이 symlink 가 아님" "0" "$([[ -L "$PROJ/.claude/skills/user-own-skill" ]] && echo 1 || echo 0)"
assert "CLAUDE.md 사용자 내용 보존" "1" "$(grep -qF 'USER-SECTION-KEEP-ME' "$PROJ/CLAUDE.md" && echo 1 || echo 0)"
assert ".gitignore 사용자 항목 보존" "1" "$(grep -qxF 'user-secret.txt' "$PROJ/.gitignore" && echo 1 || echo 0)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
