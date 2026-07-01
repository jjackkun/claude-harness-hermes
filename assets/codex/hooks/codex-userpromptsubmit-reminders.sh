#!/usr/bin/env bash
# Codex UserPromptSubmit hook — project harness reminders.

set -uo pipefail

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

ACTIVE_DIR="docs/exec-plans/active"
if [[ -d "$ACTIVE_DIR" ]]; then
  mapfile -t ACTIVE_FILES < <(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
  if [[ ${#ACTIVE_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "--- [Active Plans] ---"
    echo "진행 중인 계획이 있습니다. 작업 전 아래 파일을 먼저 읽고 다음 미완료 단계부터 이어가세요."
    for f in "${ACTIVE_FILES[@]}"; do
      echo "  - $f"
    done
    echo "---"
  fi
fi

cat <<'EOF'

--- [Codex Harness Reminders] ---
1. 기존 코드와 문서를 먼저 검색하고, 프로젝트 패턴을 우선합니다.
2. 비자명한 변경은 짧은 계획을 세운 뒤 구현하고 검증합니다.
3. 큰 변경이나 공유 경계 변경 후에는 Codex review 흐름을 사용합니다.
4. 파일 크기 soft 400 / hard 500 기준을 넘기 전에 책임을 분리합니다.
5. `--no-verify`로 검증을 우회하지 않습니다.
6. 프로젝트 고유 불변 원칙은 `docs/design-docs/core-beliefs.md`를 기준으로 합니다.
EOF

exit 0
