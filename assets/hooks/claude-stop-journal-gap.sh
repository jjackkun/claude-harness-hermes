#!/usr/bin/env bash
# Stop hook — 세션이 끝날 때 시작만 되고 끝나지 않은 작업에 누락 이벤트를 붙인다.
#
# "누가 무엇을 했고 끝냈는가" 를 나중에 알 수 있게 하려면, 끝나지 않은 채 사라진 작업도
# 그 사실이 남아야 한다. 사람이 적지 않아도 기계가 적는다.
# 계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 6
#
# 이력이 없는 구 스키마·rollback 상태에서도 죽지 않는다(exit 0).

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
JOURNAL="$PROJECT_DIR/scripts/hermes-journal.py"
[[ -f "$JOURNAL" && -f "$PROJECT_DIR/.hermes/state.db" ]] || exit 0

N="$(python3 "$JOURNAL" --project "$PROJECT_DIR" gap-check --all 2>/dev/null || echo 0)"
[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || exit 0

echo "[journal-gap] 끝나지 않은 작업 ${N}건을 이력에 남겼습니다 (claimed=abandoned)." >&2
echo "  → 확인: python3 scripts/hermes-journal.py mismatch" >&2
exit 0
