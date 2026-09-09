#!/usr/bin/env bash
# UserPromptSubmit 디스패처 테스트 — stdin 경쟁으로 페이로드를 잃지 않는지 검증한다.
#
# 배경: 같은 이벤트에 훅을 나란히 등록하면 먼저 `cat` 하는 훅이 stdin 을 전부
# 가져가고 나머지는 0바이트를 받는다. 2026-06 ~ 09 스킬 주입 0건의 원인.
# 근거: docs/audits/2026-09-09-hermes-injection-gap.md
#
# 실행: bash tests/hook-stdin-dispatch-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISPATCH="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-dispatch.sh"
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

PAYLOAD='{"prompt":"커밋 푸시하자","session_id":"dispatch-test"}'

# 페이로드를 읽어 받은 바이트 수를 출력하는 가짜 하위 훅 2개.
mk_hooks() {
  local d="$1"
  mkdir -p "$d"
  cp "$DISPATCH" "$d/claude-userpromptsubmit-dispatch.sh"
  cat > "$d/claude-userpromptsubmit-aaa.sh" <<'EOF'
in="$(cat 2>/dev/null || true)"; echo "aaa=${#in}"
EOF
  cat > "$d/claude-userpromptsubmit-zzz.sh" <<'EOF'
in="$(cat /dev/stdin 2>/dev/null || true)"; echo "zzz=${#in}"
EOF
}

echo "== 1. 회귀 재현 — 나란히 실행하면 뒤쪽이 굶는다 =="
D="$TMP/regress"; mk_hooks "$D"
out=$(printf '%s' "$PAYLOAD" | { bash "$D/claude-userpromptsubmit-aaa.sh"; bash "$D/claude-userpromptsubmit-zzz.sh"; })
assert "먼저 읽는 훅은 페이로드를 받는다" "aaa=${#PAYLOAD}" "$(echo "$out" | sed -n 1p)"
assert "뒤 훅은 0바이트를 받는다 (이것이 사고의 형태)" "zzz=0" "$(echo "$out" | sed -n 2p)"

echo "== 2. 디스패처를 거치면 둘 다 받는다 =="
D="$TMP/fixed"; mk_hooks "$D"
out=$(printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh")
assert "이름순 첫 훅이 받는다" "aaa=${#PAYLOAD}" "$(echo "$out" | sed -n 1p)"
assert "두 번째 훅도 같은 페이로드를 받는다" "zzz=${#PAYLOAD}" "$(echo "$out" | sed -n 2p)"

echo "== 3. 자기 자신을 부르지 않는다 (무한 재귀 방지) =="
assert "출력은 하위 훅 2줄뿐" "2" "$(printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh" | wc -l | tr -d ' ')"

echo "== 4. 차단 신호(exit 2)를 삼키지 않는다 =="
D="$TMP/block"; mk_hooks "$D"
cat > "$D/claude-userpromptsubmit-aaa.sh" <<'EOF'
cat >/dev/null 2>&1; echo "blocked"; exit 2
EOF
printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh" >/dev/null
assert "하위 훅의 exit 2 가 그대로 올라온다" "2" "$?"

echo "== 5. 차단(exit 2) 이면 뒤 훅을 돌리지 않는다 =="
# zzz 가 돌면 부수효과 파일이 생긴다. 차단됐는데 생기면 버려질 프롬프트에
# DB·로그를 쓴 것과 같다.
cat > "$D/claude-userpromptsubmit-zzz.sh" <<EOF
cat >/dev/null 2>&1; touch "$D/zzz-ran"; echo "zzz"
EOF
rm -f "$D/zzz-ran"
printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh" >/dev/null
assert "차단 시 rc=2" "2" "$?"
assert "차단 뒤 훅은 실행되지 않는다" "no" "$([[ -f "$D/zzz-ran" ]] && echo yes || echo no)"

echo "== 5-b. 비차단 오류(exit 1)는 뒤 훅을 막지 않는다 =="
D="$TMP/nonblock"; mk_hooks "$D"
cat > "$D/claude-userpromptsubmit-aaa.sh" <<EOF
cat >/dev/null 2>&1; exit 1
EOF
cat > "$D/claude-userpromptsubmit-zzz.sh" <<EOF
cat >/dev/null 2>&1; touch "$D/zzz-ran"; echo "zzz"
EOF
rm -f "$D/zzz-ran"
printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh" >/dev/null
assert "처음 만난 오류 코드를 올린다" "1" "$?"
assert "뒤 훅은 그대로 실행된다" "yes" "$([[ -f "$D/zzz-ran" ]] && echo yes || echo no)"

echo "== 6. 하위 훅이 하나도 없어도 죽지 않는다 =="
D="$TMP/empty"; mkdir -p "$D"; cp "$DISPATCH" "$D/claude-userpromptsubmit-dispatch.sh"
printf '%s' "$PAYLOAD" | bash "$D/claude-userpromptsubmit-dispatch.sh" >/dev/null 2>&1
assert "훅 없음 → rc=0" "0" "$?"

echo "== 7. 프리셋이 개별 훅을 등록하지 않는다 =="
reg=$(grep -c "USER_PROMPT_SUBMIT_HOOKS+=.*claude-userpromptsubmit-\(reminders\|mistake-detect\|docs-first\)" \
  "$REPO_ROOT"/presets/workflow/*.conf 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
assert "개별 훅 직접 등록 0건" "0" "$reg"

echo "== 8. 디스패처가 있으면 같은 네임스페이스 개별 등록은 회수된다 =="
res=$(python3 - "$REPO_ROOT" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gsj", sys.argv[1] + "/lib/generate_settings_json.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def names(h):
    return [c["command"].rsplit("/", 1)[-1] for g in h["UserPromptSubmit"] for c in g["hooks"]]

# 디스패처 + 형제 개별 등록 + 프리셋 밖 훅이 섞인 상태
hooks = {"UserPromptSubmit": [{"hooks": [
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/scripts/hooks/project-userpromptsubmit-kos.sh"},
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-docs-first.sh"},
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-dispatch.sh"},
]}]}
m._drop_dispatched_user_prompt_hooks(hooks)
print("A:" + ",".join(names(hooks)))

# 디스패처가 없으면 아무것도 건드리지 않는다 (가짜 위반)
hooks2 = {"UserPromptSubmit": [{"hooks": [
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-docs-first.sh"},
]}]}
m._drop_dispatched_user_prompt_hooks(hooks2)
print("B:" + ",".join(names(hooks2)))

# scripts/hooks/ 밖에 같은 이름 규칙으로 사용자가 등록한 훅 — 디스패처는 자기
# 디렉터리만 훑으므로 이걸 지우면 아무도 부르지 않는다(사용자 훅 소실).
hooks3 = {"UserPromptSubmit": [{"hooks": [
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/claude-userpromptsubmit-mine.sh"},
    {"type": "command", "command": "${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-dispatch.sh"},
]}]}
m._drop_dispatched_user_prompt_hooks(hooks3)
print("C:" + ",".join(names(hooks3)))
EOF
)
assert "형제 개별 등록만 제거, 프리셋 밖 훅은 보존" \
  "A:project-userpromptsubmit-kos.sh,claude-userpromptsubmit-dispatch.sh" "$(echo "$res" | sed -n 1p)"
assert "디스패처가 없으면 회수하지 않는다" \
  "B:claude-userpromptsubmit-docs-first.sh" "$(echo "$res" | sed -n 2p)"
assert "scripts/hooks 밖 사용자 훅은 보존한다 (같은 이름 규칙이어도)" \
  "C:claude-userpromptsubmit-mine.sh,claude-userpromptsubmit-dispatch.sh" "$(echo "$res" | sed -n 3p)"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
