#!/usr/bin/env bash
# 결정화 스킬 파일명 회귀 테스트
# 패턴 키가 원시 토큰(`claude.md`, `wr-scene`, `이유가`)이어도
# 이중 확장자(`claude.md.md`)가 생기지 않아야 한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

run() {
HERMES_SCRIPTS="$SCRIPTS" python3 - <<'PY'
import importlib.util, os, sys

path = os.path.join(os.environ["HERMES_SCRIPTS"], "hermes-crystallize.py")
spec = importlib.util.spec_from_file_location("hermes_crystallize", path)
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as e:
    print(f"FAIL::모듈 로드 ({e})")
    sys.exit(0)

def expect(name, content, key, want):
    got = mod.skill_filename(content, key)
    print(f"{'OK' if got == want else 'FAIL'}::{name} (기대:{want} 실제:{got})")

# --- 정상: 모델이 이름 규칙을 지킨 경우 ---
expect("kebab 제목 그대로",
       "# canon-check-before-writing\n\n## 문제 상황\n...", "claude.md",
       "canon-check-before-writing.md")

# --- 회귀: 이중 확장자가 생기면 안 된다 ---
expect("제목에 확장자가 붙어도 한 번만",
       "# claude.md\n\n## 문제 상황\n...", "claude.md",
       "claude.md")
expect("제목 없으면 키로 폴백 — 이중 확장자 금지 · 밑줄은 하이픈으로",
       "## 문제 상황\n...", "plot_outline.md",
       "plot-outline.md")
expect("키가 파일명이어도 이중 확장자 금지",
       "", "critique.md",
       "critique.md")

# --- 슬러그화 ---
expect("공백·대문자 정리",
       "# Stage Artifacts As Files\n", "critique.md",
       "stage-artifacts-as-files.md")
expect("한글 제목 허용",
       "# 공간 정합 확인\n", "world.md",
       "공간-정합-확인.md")
expect("특수문자 제거",
       "# foo/bar: baz!\n", "x",
       "foo-bar-baz.md")

# --- 경계 ---
expect("제목과 키가 모두 비면 기본값",
       "", "",
       "skill.md")
expect("제목이 기호뿐이면 키로 폴백",
       "# ###\n", "wr-scene",
       "wr-scene.md")

# --- 프롬프트 템플릿에 naming_rule 자리가 있는가 ---
for tname in ("SKILL_PROMPT", "SKILL_PROMPT_FROM_EVIDENCE"):
    tpl = getattr(mod, tname, "")
    if "{naming_rule}" not in tpl:
        print(f"FAIL::{tname} 에 naming_rule 자리 없음")
    elif "# {key}" in tpl:
        print(f"FAIL::{tname} 이 아직 패턴 키를 제목으로 강제함")
    else:
        print(f"OK::{tname} naming_rule 적용")

# --- format 호출이 KeyError 없이 되는가 ---
try:
    mod.SKILL_PROMPT.format(
        quality_gate="", naming_rule="", key="k", description="d",
        known_rule="r", evidence="e", date="2026-01-01", count=3)
    mod.SKILL_PROMPT_FROM_EVIDENCE.format(
        quality_gate="", naming_rule="", key="k", description="d",
        evidence="e", date="2026-01-01", count=3)
    print("OK::프롬프트 format 인자 일치")
except KeyError as e:
    print(f"FAIL::프롬프트 format 인자 누락 ({e})")
PY
}

echo "[hermes-crystallize-naming-test]"
while IFS= read -r line; do
  case "$line" in
    OK::*)   ok "${line#OK::}" ;;
    FAIL::*) nope "${line#FAIL::}" ;;
    *)       [ -n "$line" ] && echo "  $line" ;;
  esac
done < <(run)

echo "  통과 $PASS / 실패 $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
