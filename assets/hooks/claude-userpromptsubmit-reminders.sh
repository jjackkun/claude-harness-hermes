#!/usr/bin/env bash
# UserPromptSubmit hook — 매 턴 에이전트 컨텍스트에 규율 리마인더를 주입.
#
# 출처: rim-kanban Phase 1 (scripts/hooks/user-prompt-reminders.sh) 를 generic 화.
# 근거: docs/design-docs/core-beliefs.md (컨텍스트 주입으로 규율 환기)
#
# 동작: stdout 으로 출력한 텍스트가 사용자 프롬프트 앞에 자동 부착되어
#       매 턴 에이전트 컨텍스트에 들어간다.
#
# 등록: .claude/settings.json 의 hooks.UserPromptSubmit 항목.
# 본 파일은 ai-dev-setting 의 setup.sh 가 프로젝트 scripts/hooks/ 로 복사한다.

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

# ── 진행 중인 계획 + 백로그 알림 (근거: docs/exec-plans-system.md) ──
ACTIVE_DIR="docs/exec-plans/active"
BACKLOG_DIR="docs/exec-plans/backlog"
_has_plan_output=0

if [[ -d "$ACTIVE_DIR" ]]; then
  ACTIVE_FILES=()
  while IFS= read -r f; do
    ACTIVE_FILES+=("$f")
  done < <(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
  if [[ ${#ACTIVE_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "--- [Active Plans] ---"
    echo "진행 중인 계획이 있습니다. 작업 전 다음 미완료 단계를 확인하세요."
    for f in "${ACTIVE_FILES[@]}"; do
      echo "  - $f"
    done
    _has_plan_output=1
  fi
fi

if [[ -d "$BACKLOG_DIR" ]]; then
  BACKLOG_FILES=()
  while IFS= read -r f; do
    BACKLOG_FILES+=("$f")
  done < <(find "$BACKLOG_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
  if [[ ${#BACKLOG_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "--- [Backlog] ---"
    for f in "${BACKLOG_FILES[@]}"; do
      echo "  - $f"
    done
    _has_plan_output=1
  fi
fi

[[ $_has_plan_output -eq 1 ]] && echo "---" 

# ── 헤르메스 FTS5 스킬 검색 + 주입 ──────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  _hermes_db="$PWD/.hermes/state.db"
  _hermes_scripts="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/scripts"
  _hermes_search="$_hermes_scripts/hermes-search.py"

  if [[ -f "$_hermes_db" && -f "$_hermes_search" ]]; then
    _raw_stdin="$(cat /dev/stdin 2>/dev/null || true)"
    _query="$(printf '%s' "$_raw_stdin" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    pass
" 2>/dev/null || true)"
    _sid="$(printf '%s' "$_raw_stdin" | python3 -c "import sys,json;print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)"

    if [[ -n "$_query" ]]; then
      _hermes_out=$(python3 "$_hermes_search" \
        --db "$_hermes_db" --query "$_query" --session-id "$_sid" \
        --skills-dir "$PWD/.claude/skills" \
        --global-skills-dir "$HOME/.hermes/mesh/skills" --max 3 2>/dev/null || true)
      [[ -n "$_hermes_out" ]] && printf '%s\n' "$_hermes_out"
    fi
  fi
fi

cat <<'EOF'

--- [Harness Reminders] ---
1. 기존 코드 검색 → 짧은 계획 → 구현 → 검증.
2. 파일 책임을 좁게 유지하고 soft 400 / hard 500 줄을 넘기기 전에 분리.
3. 큰 변경·공유 경계·보안/DB/동시성 영향이 있으면 reviewer 로 승격.
4. --no-verify 금지. UI 작업은 관련 frontend skill 확인.
근거: docs/design-docs/core-beliefs.md
EOF

if [[ "${HARNESS_VERBOSE_RULES:-0}" == "1" ]]; then
  cat <<'EOF'
8. 같은 지적 2회 반복 → Skill("harness-promote-rule").
9. Agent dispatch: 도메인 에이전트 우선. R-agent hook 강제.
10. 자율 판단 우선. 블로커만 사용자에 보고. Vision 강화 시 부분정보(스크린샷 단독)만으로 결정 금지.
EOF
fi

exit 0
