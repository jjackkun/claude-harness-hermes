#!/usr/bin/env bash
# PostToolUse(Task|Agent) hook — 리뷰어 dispatch 를 리뷰 빚 청산으로 기록한다.
#
# 근거: docs/design-docs/core-beliefs.md#r-review
# 스펙: docs/superpowers/specs/2026-08-24-agent-pipeline-enforcement-design.md
#
# 왜 필요한가:
#   core-beliefs 는 "code-reviewer dispatch 후 rm .claude/.review-dirty" 라고 적어 왔다.
#   그 rm 은 사람이(또는 에이전트가) 손으로 해야 했고, 그래서 지켜지지 않았다.
#   훅이 대신 지우면 문서가 참이 되고, commit 시점의 R-pipe 판정이 신뢰할 수 있어진다.
#
# 무엇을 주장하고 무엇을 주장하지 않는가:
#   주장한다 — "리뷰어를 불렀다".
#   주장하지 않는다 — "리뷰가 유효했다". 훅은 리뷰 결과를 읽을 수 없다.
#   그래서 R-pipe 는 차단이 아니라 경고다. 확인 못 하는 것을 차단 조건으로 삼으면
#   리뷰어를 부르고 결과를 무시하는 형식적 통과를 학습시킨다.
#
# 리뷰어 판별: subagent_type 이 `-reviewer` 로 끝나는가.
#   assets/agents/ 의 QA 역할 4개(code/python/typescript/database-reviewer)가 모두 이 형태다.
#   목록을 손으로 적지 않는 이유는, 에이전트를 추가할 때 이 훅을 같이 고쳐야 한다는 것을
#   아무도 기억하지 못하기 때문이다. 플러그인 네임스페이스(`plugin:foo-reviewer`)도 함께 잡힌다.
#   `silent-failure-hunter` 는 제외한다 — 스펙상 QA 가 아니라 Hardener 다.

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

SUBAGENT=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print((d.get('tool_input', {}) or {}).get('subagent_type', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$SUBAGENT" ]] && exit 0
[[ "$SUBAGENT" == *-reviewer ]] || exit 0

DIRTY_FILE=".claude/.review-dirty"
[[ -f "$DIRTY_FILE" ]] || exit 0

rm -f "$DIRTY_FILE" 2>/dev/null || exit 0
echo "[R-review] $SUBAGENT dispatch — 리뷰 빚 기록을 청산했습니다."

exit 0
