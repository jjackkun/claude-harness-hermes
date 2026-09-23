#!/usr/bin/env bash
# R-lock (계획 2026-09-23-r-lock) — 설치 구성은 저장소에 산다.
#
# 2026-09-22 사고: 로컬 lock(3줄)이 커밋된 매니페스트(5개 프리셋 분량)보다 모자라
# 재설치가 git 에 추적된 심링크 2개와 CLAUDE.md 두 절을 지웠다. lock 은 argv 를 그대로
# 적고 .gitignore 안에 있어, 원인은 로컬에 결과는 저장소에 남아 갈라졌다.
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다(copy-install-test 와 같은 방식).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"

P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name t; git -C "$P" config user.email t@t
install() { bash "$SANDBOX/project-claude.sh" "$P" "$@" >"$TMP/install.log" 2>&1; }
judge() { python3 "$REPO_ROOT/scripts/git_ignore_judge.py" --repo "$P" "$1" >/dev/null 2>&1; echo $?; }

echo "== 목표 1. lock 은 무시되지 않는다 =="
install harness hermes mcp
assert "설치 rc 0" 0 "$?"
assert "lock 파일 생성" 1 "$([[ -f "$P/.claude/presets.lock" ]] && echo 1 || echo 0)"
# judge: 0 = 무시됨, 1 = 무시 아님
assert "lock 이 git 에 무시되지 않는다" 1 "$(judge .claude/presets.lock)"
assert "무시 블록에 그 줄이 없다" 0 "$(grep -c '^\.claude/presets\.lock$' "$P/.gitignore")"

echo "== 목표 2. 옛 블록이 있어도 재설치가 걷어낸다 =="
# 옛 설치본을 흉내낸다 — 마커 블록 안에 그 줄이 있는 상태
python3 - "$P/.gitignore" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
mark = ".claude/.dev-setting-manifest.json\n"
assert mark in s, "마커 블록 안 앵커를 찾지 못했다"
open(p, "w", encoding="utf-8").write(s.replace(mark, mark + ".claude/presets.lock\n", 1))
PY
assert "옛 줄 심기 성공" 1 "$(grep -c '^\.claude/presets\.lock$' "$P/.gitignore")"
install harness hermes mcp
assert "재설치 뒤 옛 줄 사라짐" 0 "$(grep -c '^\.claude/presets\.lock$' "$P/.gitignore")"
assert "재설치 뒤에도 무시 아님" 1 "$(judge .claude/presets.lock)"

echo "== 목표 3·4. 추적된 설치물을 지우려 하면 경고하되 막지는 않는다 =="
git -C "$P" add -A >/dev/null 2>&1; git -C "$P" commit -qm installed >/dev/null 2>&1
assert "mcp-builder 가 추적된다" 0 "$(git -C "$P" ls-files --error-unmatch .claude/skills/mcp-builder >/dev/null 2>&1; echo $?)"
install harness hermes            # mcp 를 뺀다 → 추적된 스킬이 지워질 상황
assert "프리셋을 빼도 rc 0(차단 아님)" 0 "$?"
assert "경고가 떴다" 1 "$([[ $(grep -c 'preset-drop WARN' "$TMP/install.log") -ge 1 ]] && echo 1 || echo 0)"
# 이름은 **경고 줄 안**에 있어야 한다 — 로그 어딘가에 있는 것으로는 부족하다(removed → … 에 걸린다)
assert "경고 줄에 이름이 있다" 1 "$([[ $(grep 'preset-drop WARN' "$TMP/install.log" | grep -c 'mcp-builder') -ge 1 ]] && echo 1 || echo 0)"
assert "실제로 제거됐다(경고는 막지 않는다)" 0 "$([[ -e "$P/.claude/skills/mcp-builder" ]] && echo 1 || echo 0)"

echo "== 추적되지 않은 항목을 지울 때는 조용하다 =="
# 앞 절의 삭제를 커밋해 색인에서 지운다 — 그래야 다음 설치분이 진짜 미추적이 된다.
# (색인에 남아 있으면 ls-files 는 여전히 "추적됨" 이라 답하고, 그 판정은 옳다.)
git -C "$P" add -A >/dev/null 2>&1; git -C "$P" commit -qm "drop mcp" >/dev/null 2>&1
assert "삭제가 커밋돼 미추적이 됐다" 1 "$(git -C "$P" ls-files --error-unmatch .claude/skills/mcp-builder >/dev/null 2>&1; echo $?)"
install harness hermes mcp >/dev/null 2>&1     # 되돌려 깔고 커밋하지 않는다
install harness hermes                          # 다시 뺀다 — 이번엔 미추적 상태
assert "미추적 제거는 경고 없음" 0 "$(grep -c 'preset-drop WARN' "$TMP/install.log")"

echo; echo "preset-lock-tracked: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
