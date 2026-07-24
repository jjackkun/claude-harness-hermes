#!/usr/bin/env bash
# 그물망 소비 측 — hermes-search 가 --global-skills-dir 를 검색 풀에 포함하는지
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MESH="$TMP/mesh/skills"
mkdir -p "$MESH"
cat > "$MESH/relay-pagination.md" <<'EOF'
# GraphQL relay 커서 페이지네이션
relay 커서 규약으로 페이지네이션을 구현한다.
EOF

# --db 는 없는 경로여도 dir-scan 은 독립 동작. --no-fallback 로 claude 회피.
OUT="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$TMP/nonexistent.db" --query "relay 커서 페이지네이션 구현" \
  --global-skills-dir "$MESH" --no-fallback --max 3 2>/dev/null || true)"
if grep -q "relay-pagination" <<<"$OUT"; then
  ok "그물망 스킬이 주입 결과에 포함됨"
else
  nope "그물망 스킬이 주입 결과에 없음"
fi

# 격리: --global-skills-dir 미지정 시 그물망 스킬은 안 나와야 한다.
OUT2="$(python3 "$SCRIPTS/hermes-search.py" \
  --db "$TMP/nonexistent.db" --query "relay 커서 페이지네이션 구현" \
  --no-fallback --max 3 2>/dev/null || true)"
if grep -q "relay-pagination" <<<"$OUT2"; then
  nope "격리 실패 — global dir 미지정인데 그물망 스킬 노출"
else
  ok "global dir 미지정 시 그물망 스킬 비노출(격리 OK)"
fi

# init --global 이 그물망 골격 디렉토리를 만드는지 (HOME 격리)
HOME="$TMP/fakehome" python3 "$SCRIPTS/hermes-init.py" --global >/dev/null 2>&1 || true
if [[ -d "$TMP/fakehome/.hermes/mesh/skills" ]]; then
  ok "init --global 이 ~/.hermes/mesh/skills 생성"
else
  nope "init --global 이 그물망 골격 디렉토리 미생성"
fi

# 주입 훅이 --global-skills-dir 를 전달하는지 (정적 확인)
HOOK="$ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh"
if grep -q -- "--global-skills-dir" "$HOOK"; then
  ok "주입 훅이 --global-skills-dir 전달"
else
  nope "주입 훅이 --global-skills-dir 미전달"
fi

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
