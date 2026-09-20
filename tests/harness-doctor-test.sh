#!/usr/bin/env bash
# 설치 doctor/repair 검증 (계획 2026-09-20-install-doctor-repair 목표 1~4).
#
#   - 1절 진단: 픽스처 설치(harness adhd) → 깨끗 rc 0 → 스킬 변조·에이전트 삭제·lock 에서 adhd 제거·사용자 스킬 추가 → 각각 보고, rc 1, --json 유효, --brief 한 줄
#   - 2절 복구: --repair 는 계획만(파일 불변) → --yes 뒤 변조·누락 0, .hermes/skills 파일 그대로, 사용자 스킬 그대로
#   - 3절 공장: 가짜 공장(미등록 스크립트 1·미등록 훅 1) → 보고 rc 1; 실제 공장 → rc 0
#   - 4절 update-all: 재설치 전 doctor 한 줄 + lock 어긋남 경고
#   - 진단 불가: 매니페스트 없는 폴더 → rc 2
#   - 자기 검사: sha 대조를 끄면 변조 검출이 빨개진다
#
# 실행: bash tests/harness-doctor-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/scripts/harness-doctor.py"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HARNESS_REGISTER=0
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q
bash "$REPO_ROOT/project-claude.sh" "$P" harness adhd > "$T/install.out" 2>&1 || { echo "FAIL: 픽스처 설치 실패"; tail -5 "$T/install.out"; exit 1; }
D() { python3 "$DOC" "$@"; }

echo "== 1절 진단"
D "$P" > "$T/d0.out" 2>&1; RC=$?
assert "깨끗한 설치: rc 0" 0 "$RC"
assert "깨끗 표시" 1 "$(grep -c '깨끗' "$T/d0.out")"
assert "갱신 대기 0/N (방금 설치)" 1 "$(grep -c '갱신 대기 0/' "$T/d0.out")"
python3 "$DOC" "$T/없는폴더" >/dev/null 2>&1; assert "매니페스트 없으면 rc 2" 2 "$?"
# 변조: 첫 스킬의 SKILL.md 에 한 줄 추가
SK="$(ls -d "$P"/.claude/skills/*/ | head -1)"; SKN="$(basename "$SK")"
echo "# 손댐" >> "$SK/SKILL.md"
# 누락: 에이전트 하나 삭제
AG="$(ls "$P"/.claude/agents/*.md | head -1)"; AGN="$(basename "$AG" .md)"; rm -f "$AG"
# lock 어긋남: adhd 제거
sed -i '/^adhd$/d' "$P/.claude/presets.lock"
# 사용자 자산: 매니페스트 밖 스킬
mkdir -p "$P/.claude/skills/my-own"; echo "---\nname: my-own\n---" > "$P/.claude/skills/my-own/SKILL.md"
D "$P" > "$T/d1.out" 2>&1; RC=$?
assert "발견 시 rc 1" 1 "$RC"
assert "변조 보고 skills/$SKN" 1 "$(grep -c "^    - skills/$SKN\$" "$T/d1.out")"
assert "누락 보고 agents/$AGN" 1 "$(grep -c "^    - agents/$AGN\$" "$T/d1.out")"
assert "lock 어긋남 rules/adhd" 1 "$(grep -c '^    - rules/adhd$' "$T/d1.out")"
assert "사용자 자산 skills/my-own (오류 아님)" 1 "$(grep -c '^    - skills/my-own$' "$T/d1.out")"
assert "요약 줄 수치" 1 "$(grep -c '불일치 1 · 누락 1 · lock 어긋남 1' "$T/d1.out")"
D "$P" --json > "$T/d1.json" 2>/dev/null
assert "--json 유효 + 필드" "1 1 1" "$(python3 -c "
import json;d=json.load(open('$T/d1.json'));print(int(d['tampered']==['skills/$SKN']), int('agents/$AGN' in d['missing']), int(d['lock_drift']==['rules/adhd']))")"
assert "--brief 한 줄" 1 "$(D "$P" --brief 2>/dev/null | wc -l)"
# 자기 검사: sha 대조를 끄면 변조를 못 잡는다
sed 's/_sha_target(path) != it\["sha256"\]/False/' "$DOC" > "$T/doctor-broken.py"
python3 "$T/doctor-broken.py" "$P" > "$T/broken.out" 2>&1
assert "자기 검사: 대조를 끄면 불일치 0 이 된다" 1 "$(grep -c '불일치 0 ' "$T/broken.out")"

echo "== 2절 복구"
mkdir -p "$P/.hermes/skills"; echo "소우주 확장" > "$P/.hermes/skills/local.md"
H_BEFORE="$(md5sum "$SK/SKILL.md" | cut -c1-32)"
D "$P" --repair > "$T/r0.out" 2>&1; RC=$?
assert "--repair 계획만: rc 0" 0 "$RC"
assert "계획에 덮어쓰기·되살리기·제거 줄" "1 1 1" "$(grep -c "덮어쓴다: skills/$SKN" "$T/r0.out") $(grep -c "되살린다: agents/$AGN" "$T/r0.out") $(grep -c -F '남는다): rules/adhd' "$T/r0.out")"   # GNU grep 은 UTF-8 로케일에서 이 줄의 .* 를 못 맞춘다(2026-09-20 실측) — 고정 문자열로
assert "계획만일 때 파일 불변" "$H_BEFORE" "$(md5sum "$SK/SKILL.md" | cut -c1-32)"
assert "계획만일 때 에이전트 여전히 없음" 0 "$([[ -f "$AG" ]] && echo 1 || echo 0)"
D "$P" --repair --yes > "$T/r1.out" 2>&1; RC=$?
assert "--repair --yes rc 0" 0 "$RC"
D "$P" > "$T/d2.out" 2>&1; RC=$?
assert "복구 뒤 불일치·누락 0" 1 "$(grep -c '불일치 0 · 누락 0 · lock 어긋남 0' "$T/d2.out")"
assert "복구 뒤 rc 0" 0 "$RC"
assert "adhd 는 lock 대로 제거됨" 0 "$([[ -d "$P/.claude/rules/adhd" ]] && echo 1 || echo 0)"
assert ".hermes/skills 그대로" "소우주 확장" "$(cat "$P/.hermes/skills/local.md")"
assert "사용자 스킬 그대로" 1 "$([[ -f "$P/.claude/skills/my-own/SKILL.md" ]] && echo 1 || echo 0)"

echo "== 3절 공장 자기 점검"
F="$T/factory"; mkdir -p "$F/presets/workflow" "$F/scripts" "$F/assets/hooks" "$F/lib"
printf 'local hermes_scripts=(\n    hermes-a.py\n    hermes_b.py\n  )\nHARNESS_HOOK_SOURCES+=(claude-x.sh)\n' > "$F/presets/workflow/hermes.conf"
touch "$F/scripts/hermes-a.py" "$F/scripts/hermes_b.py" "$F/scripts/hermes-forgot.py" "$F/scripts/other.py"
touch "$F/assets/hooks/claude-x.sh" "$F/assets/hooks/claude-orphan.sh"
D --factory-self --factory "$F" > "$T/f.out" 2>&1; RC=$?
assert "가짜 공장: rc 1" 1 "$RC"
assert "복사 목록 누락 hermes-forgot.py" 1 "$(grep -c 'hermes-forgot.py' "$T/f.out")"
assert "hermes 접두 아닌 other.py 는 대상 아님" 0 "$(grep -c 'other.py' "$T/f.out")"
assert "미등록 훅 claude-orphan.sh" 1 "$(grep -c 'claude-orphan.sh' "$T/f.out")"
assert "등록된 훅은 안 나옴" 0 "$(grep -c 'claude-x.sh' "$T/f.out")"
D --factory-self > "$T/f2.out" 2>&1; RC=$?
assert "실제 공장: 폐로 rc 0" 0 "$RC"
[[ $RC -ne 0 ]] && cat "$T/f2.out"

echo "== 3b절 sha 일치 — 공백 든 파일 이름 (리뷰 HIGH, 2026-09-20)"
SP="$T/spacedir"; mkdir -p "$SP/sub dir"; printf 'x\n' > "$SP/a b.txt"; printf 'y\n' > "$SP/sub dir/c.txt"; printf 'z\n' > "$SP/plain.txt"
BASH_SHA="$(bash -c "source '$REPO_ROOT/lib/factory_manifest.sh'; _manifest_sha '$SP'")"
PY_SHA="$(python3 -c "
import importlib.util; s=importlib.util.spec_from_file_location('d','$DOC'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m._sha_target('$SP'))")"
assert "bash _manifest_sha == python _sha_target (공백 이름 포함)" "$BASH_SHA" "$PY_SHA"
assert "빈 목록 해시가 아니다(xargs 쪼개짐 결함 재발 방지)" 0 "$([[ "$BASH_SHA" == e3b0c442* ]] && echo 1 || echo 0)"

echo "== 4절 update-all 배선"
assert "update-all 이 doctor 를 부른다" 1 "$([[ $(grep -c 'harness-doctor.py' "$REPO_ROOT/update-all.sh") -ge 1 ]] && echo 1 || echo 0)"
sed -i '/^adhd$/d' "$P/.claude/presets.lock" 2>/dev/null; echo "adhd" >> "$P/.claude/presets.lock"
bash "$REPO_ROOT/project-claude.sh" "$P" harness adhd > /dev/null 2>&1      # adhd 다시 설치
sed -i '/^adhd$/d' "$P/.claude/presets.lock"                                 # lock 만 빼서 어긋남 유도
REG="$T/registry"; echo "$P" > "$REG"
HARNESS_REGISTRY_FILE="$REG" bash "$REPO_ROOT/update-all.sh" > "$T/ua.out" 2>&1; RC=$?
assert "update-all rc 0" 0 "$RC"
assert "재설치 전 doctor 한 줄" 1 "$(grep -c '\[doctor\]' "$T/ua.out")"
assert "lock 어긋남 경고(재설치로 사라질 항목)" 1 "$(grep -c '재설치로 사라' "$T/ua.out")"

echo; echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
