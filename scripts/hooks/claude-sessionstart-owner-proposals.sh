#!/usr/bin/env bash
# SessionStart hook — 무인 세션이 남긴 "담당 없음" 제안 중 답이 없는 것을 한 줄 알린다.
# (creation-and-organization.md §5 "다음 대화형 세션에서 문의한다"; 계획 2026-09-17-design-gaps-tier2 목표 9)
#
# 답은 사람이 한다: 입사(hire)시키거나, "이 영역은 담당을 두지 않는다"(hermes-agent.py no-owner).
# no-owner 결정이 같은 영역에 있으면 답한 것으로 보고 조용하다. 제안이 없으면 무출력.
# stdout 은 세션 문맥이므로 알림은 stderr 로만(다른 SessionStart 훅과 같은 관례).
set -uo pipefail
cat >/dev/null 2>&1 || true
project_dir="${CLAUDE_PROJECT_DIR:-${HERMES_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
scripts_dir="$project_dir/scripts"
[[ -f "$scripts_dir/hermes_owner_memory.py" && -f "$project_dir/.hermes/state.db" ]] || exit 0
OUT="$(PYTHONPATH="$scripts_dir" python3 - "$project_dir" <<'PY' 2>/dev/null
import sys
from hermes_owner_memory import open_proposals
items = open_proposals(sys.argv[1])
if items:
    print(len(items))
    for it in items[:5]:
        print(f"  - {it['area']} ({it['ts'][:10]})")
PY
)" || exit 0
[[ -n "$OUT" ]] || exit 0
N="${OUT%%$'\n'*}"
{ echo "[owner-proposals] 무인 세션이 남긴 담당 없음 제안 ${N}건 — 입사(hire)시키거나 no-owner 로 답하십시오:"
  printf '%s\n' "$OUT" | tail -n +2; } >&2
exit 0
