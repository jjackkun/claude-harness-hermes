#!/usr/bin/env bash
# 기계 프롬프트는 도구 없이 — 글만 만드는 헤르메스 배경 호출(요약·드리밍·결정화 …)은
# 기본 도구(--tools "")와 MCP 도구(--strict-mcp-config)를 끈 채로 돈다. 2026-10-22 요약기가 대화 속
# "커밋하고 푸시" 를 스스로 실행한 일(jj-agent-room f036723)의 재발 방지.
# 계획: docs/exec-plans/active/2026-10-22-machine-prompt-no-tools.md
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
fail() { echo "  ✗ $1"; FAIL=1; }
ok() { echo "  ✓ $1"; }

# 도구를 쓰는 것이 본래 일인 곳 — 각자 승인 게이트가 있다.
# run_eval.py 는 스킬 발동을 재므로 스킬 도구가 있어야 한다.
ALLOW="scripts/hermes-summon.py scripts/hermes-loop.py scripts/harness-eval.py assets/skills/skill-creator/scripts/run_eval.py"

echo "[1] 공용 함수가 두 옵션을 붙인다"
OUT=$(cd "$ROOT/scripts" && python3 -c 'from hermes_machine_prompt import machine_prompt_cmd as m; print(m("claude-haiku-4-5-20251001"))' 2>&1)
case "$OUT" in *"'--tools', ''"*) ok "--tools \"\"" ;; *) fail "--tools \"\" 없음: $OUT" ;; esac
case "$OUT" in *"--strict-mcp-config"*) ok "--strict-mcp-config" ;; *) fail "--strict-mcp-config 없음: $OUT" ;; esac
case "$OUT" in *"'-p'"*"'--model', 'claude-haiku-4-5-20251001'"*) ok "-p · --model 유지" ;; *) fail "명령 줄 모양: $OUT" ;; esac

echo "[2] 허용 목록 밖의 기계 프롬프트 호출은 모두 도구를 끈다"
cd "$ROOT"
while IFS= read -r f; do
  case " $ALLOW " in *" $f "*) continue ;; esac
  # claude 를 부르는 파일만 — git 의 -p · argparse 의 -p 는 다른 뜻이다.
  grep -qE '"claude"|HERMES_CLAUDE_BIN|claude_cmd' "$f" || continue
  if grep -q "machine_prompt_cmd(" "$f"; then ok "$f — 공용 함수"; continue; fi
  if grep -qF '"--tools", ""' "$f" && grep -qF '"--strict-mcp-config"' "$f"; then ok "$f — 두 옵션 직접"; continue; fi
  fail "$f — 도구 끄기 없이 부른다"
done < <(grep -rlE '"-p"' --include=*.py scripts assets/skills 2>/dev/null | sort)

echo "[3] 설치 목록에 공용 함수가 있다"
grep -qE "^\s+hermes_machine_prompt\.py\s*$" presets/workflow/hermes.conf && ok "hermes.conf" || fail "hermes.conf 에 hermes_machine_prompt.py 없음"

[ "$FAIL" -eq 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
