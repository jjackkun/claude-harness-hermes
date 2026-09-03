#!/usr/bin/env bash
# Step 2a 계장 검증 — 런타임 훅이 판정마다 이벤트를 남기는지 단언한다.
#
# **통과만 보는 검증을 금지한다.** 발화(warn/block)뿐 아니라 pass 도 확인한다 —
# pass 가 안 남으면 분모가 없어 발화율이 계산되지 않는다.
# (harness-hooks-smoke.sh 의 silent-skip 사례와 같은 종류의 결함을 막는다.)
#
# 실행: bash tests/gate-instrumentation-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO_ROOT/assets/hooks"
TMP=$(mktemp -d)
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

EVENTS=".harness/gate-events.jsonl"

# proj <name> — 격리된 프로젝트 루트를 만들고 경로를 반환
proj() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }

# verdicts <root> <rule> — 해당 룰의 verdict 를 공백으로 이어 출력
verdicts() {
  python3 - "$1/$EVENTS" "$2" <<'PY'
import json, sys
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    print(""); raise SystemExit
out = []
for ln in lines:
    try:
        r = json.loads(ln)
    except ValueError:
        continue
    if r.get("rule") == sys.argv[2]:
        out.append(r.get("verdict", "?"))
print(" ".join(out))
PY
}

echo "== R-iface (pretooluse, python 내부 기록) =="

P=$(proj iface)
# 공개 심볼 2개 → pass
printf '{"tool_input":{"file_path":"%s/new_small.py","content":"def a():\\n    pass\\n\\ndef b():\\n    pass\\n"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-iface-guard.sh" >/dev/null 2>&1
assert "폭이 임계 미만이면 pass 기록" "pass" "$(verdicts "$P" R-iface)"

P=$(proj iface_block)
BIG=$(python3 -c "print('\\\\n'.join('def f%d():\\\\n    pass' % i for i in range(9)))")
printf '{"tool_input":{"file_path":"%s/wide.py","content":"%s"}}' "$P" "$BIG" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-iface-guard.sh" >/dev/null 2>&1
assert "폭이 임계 이상이면 block 기록" "block" "$(verdicts "$P" R-iface)"

P=$(proj iface_waive)
printf '{"tool_input":{"file_path":"%s/wide.py","content":"# R-iface-waiver: 한 책임\\n%s"}}' "$P" "$BIG" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-iface-guard.sh" >/dev/null 2>&1
assert "waiver 는 pass 가 아니라 waived 로 구분 기록" "waived" "$(verdicts "$P" R-iface)"

P=$(proj iface_skip)
printf '{"tool_input":{"file_path":"%s/readme.md","content":"# hi"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-iface-guard.sh" >/dev/null 2>&1
assert "대상 아닌 확장자는 분모에 넣지 않음" "" "$(verdicts "$P" R-iface)"

echo "== R-size (posttooluse) =="

P=$(proj size)
python3 -c "open('$P/small.py','w').write('x = 1\n' * 10)"
printf '{"tool_input":{"file_path":"%s/small.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-size-warn.sh" >/dev/null 2>&1
assert "한도 이하 편집은 pass 기록" "pass" "$(verdicts "$P" R-size)"

P=$(proj size_warn)
python3 -c "open('$P/big.py','w').write('x = 1\n' * 600)"
printf '{"tool_input":{"file_path":"%s/big.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-size-warn.sh" >/dev/null 2>&1
assert "하드 한도 초과는 warn 기록" "warn" "$(verdicts "$P" R-size)"

# 한 훅이 축을 둘 판정하면 레코드는 2건이되 프로세스는 1회여야 한다.
# 프로세스 수를 직접 세는 대신 배치 인자(`+` 구분)가 실제로 동작하는지로 확인한다 —
# 배치가 깨지면 두 번째 레코드가 사라지므로 이 단언이 먼저 실패한다.
P=$(proj size_batch)
git -C "$P" init -q 2>/dev/null
python3 -c "open('$P/mod.py','w').write('def a():\n    pass\n')"
git -C "$P" add mod.py >/dev/null 2>&1
git -C "$P" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
printf '{"tool_input":{"file_path":"%s/mod.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-size-warn.sh" >/dev/null 2>&1
assert "줄 수 축과 책임 축이 한 번의 기동으로 둘 다 기록됨" "pass|pass" \
  "$(verdicts "$P" R-size)|$(verdicts "$P" R-size-resp)"

echo "== R-declare (pretooluse) =="

P=$(proj declare)
mkdir -p "$P/docs/exec-plans/active" "$P/scripts/hooks"
cp "$HOOKS/plan_state.py" "$P/scripts/hooks/" 2>/dev/null
cat > "$P/docs/exec-plans/active/2026-01-01-x.md" <<'EOF'
## 4. 영향 영역
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `declared.py` — 선언된 파일
EOF
printf '{"tool_input":{"file_path":"%s/declared.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-plan-declare.sh" >/dev/null 2>&1
assert "계획서에 선언된 새 파일은 pass" "pass" "$(verdicts "$P" R-declare)"

printf '{"tool_input":{"file_path":"%s/undeclared.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-plan-declare.sh" >/dev/null 2>&1
assert "선언 없는 새 파일은 warn 추가" "pass warn" "$(verdicts "$P" R-declare)"

echo "== R-agent (pretooluse) =="

P=$(proj agent)
printf '{"tool_input":{"subagent_type":"general-purpose","prompt":"문서 정리","description":""}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-agent-guard.sh" >/dev/null 2>&1
assert "도메인 신호 없으면 pass" "pass" "$(verdicts "$P" R-agent)"

printf '{"tool_input":{"subagent_type":"general-purpose","prompt":"svelte component 수정","description":""}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-agent-guard.sh" >/dev/null 2>&1
assert "도메인 신호 있으면 warn 추가" "pass warn" "$(verdicts "$P" R-agent)"

echo "== R5 / R-review (bash-guard) =="

P=$(proj bash)
printf '{"tool_input":{"command":"git commit --no-verify -m x"}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-bash-guard.sh" >/dev/null 2>&1
assert "--no-verify 시도는 R5 warn" "warn" "$(verdicts "$P" R5)"

P=$(proj bash_clean)
mkdir -p "$P/.claude"
printf '{"tool_input":{"command":"git commit -m x"}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-bash-guard.sh" >/dev/null 2>&1
assert "빚 없는 커밋은 R-review pass" "pass" "$(verdicts "$P" R-review)"

echo "$(date)" > "$P/.claude/.review-dirty"
printf '{"tool_input":{"command":"git commit -m x"}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-bash-guard.sh" >/dev/null 2>&1
assert "빚 남은 커밋은 R-review warn 추가" "pass warn" "$(verdicts "$P" R-review)"

P=$(proj bash_plain)
printf '{"tool_input":{"command":"ls -la"}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-pretooluse-bash-guard.sh" >/dev/null 2>&1
assert "평범한 명령은 아무것도 기록하지 않음 (분모 오염 방지)" "0" \
  "$([[ -e "$P/$EVENTS" ]] && echo 1 || echo 0)"

echo "== R-review-debt (review-reminder) =="

P=$(proj debt)
printf '{"tool_input":{"file_path":"%s/a.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-review-reminder.sh" >/dev/null 2>&1
assert "첫 코드 편집에 빚 발생 기록" "warn" "$(verdicts "$P" R-review-debt)"

printf '{"tool_input":{"file_path":"%s/b.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-review-reminder.sh" >/dev/null 2>&1
assert "이어지는 편집은 같은 빚이라 중복 기록 안 함" "warn" "$(verdicts "$P" R-review-debt)"
assert "커밋 시점 R-review 와 키가 섞이지 않음" "" "$(verdicts "$P" R-review)"

echo "== R-dead-file (posttooluse) =="

P=$(proj dead)
mkdir -p "$P"
python3 -c "open('$P/orphan_widget.py','w').write('def go():\n    pass\n')"
python3 -c "open('$P/user_main.py','w').write('from used_helper import go\n')"
python3 -c "open('$P/used_helper.py','w').write('def go():\n    pass\n')"
(cd "$P" && printf '{"tool_input":{"file_path":"%s/orphan_widget.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-dead-file-warn.sh" >/dev/null 2>&1)
assert "참조 0건이면 warn" "warn" "$(verdicts "$P" R-dead-file)"

(cd "$P" && printf '{"tool_input":{"file_path":"%s/used_helper.py"}}' "$P" \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/claude-posttooluse-dead-file-warn.sh" >/dev/null 2>&1)
assert "참조가 있으면 pass 추가" "warn pass" "$(verdicts "$P" R-dead-file)"

echo "== 설치 목록 등록 (조용한 관측 중단 방지) =="

# 계장된 훅만 배포되고 emitter 가 빠지면, 훅은 계속 동작하지만 기록만 조용히 멈춘다.
# 이 저장소가 R-test·R-pipe 에서 이미 두 번 겪은 실패 형태다.
CONF="$REPO_ROOT/presets/workflow/harness.conf"
for mod in gate_event.py gate_emit.sh; do
  assert "$mod 이 HARNESS_HOOK_SOURCES 에 등록됨" "1" \
    "$(grep -A 40 'HARNESS_HOOK_SOURCES' "$CONF" | grep -qxF "  $mod" && echo 1 || echo 0)"
done

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
