#!/usr/bin/env bash
# SessionStart hook — 보낼 편지함(outbox) 봉투의 배달 결과를 알린다 (계획 5 목표 10).
#
# 배달된 봉투의 이슈 상태를 gh 로 조회한다: 허가(approved)면 "소우주 확장분 제거 안내",
# 거절(rejected)이면 "확장으로 계속" 을 한 줄 알린다. 아직 못 보낸 pending 봉투가 있으면 개수를 알린다.
# gh 없음·outbox 없음·오류에도 죽지 않는다(exit 0). SessionStart stdout 은 컨텍스트로 주입되므로 무출력.

set -uo pipefail
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
scripts_dir="$project_dir/scripts"
log="$project_dir/.hermes/hooks.log"

[[ -f "$scripts_dir/hermes_envelope.py" && -d "$project_dir/.hermes/outbox" ]] || exit 0

OUT="$(PYTHONPATH="$scripts_dir" python3 - "$project_dir" 2>>"$log" <<'PY'
import json, os, shutil, subprocess, sys
project = sys.argv[1]
try:
    from hermes_envelope import list_envelopes, set_status
except Exception:
    sys.exit(0)

msgs = []
pending = len(list_envelopes(project, "pending"))
if pending:
    msgs.append(f"배달 못 한 봉투 {pending}개 (사람이 --deliver 로 보내야 나갑니다)")

if shutil.which("gh"):
    for env in list_envelopes(project, "delivered"):
        url = env.get("issue_url")
        if not url:
            continue
        try:
            r = subprocess.run(["gh", "issue", "view", url, "--json", "state,labels"],
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            continue
        if r.returncode != 0:
            continue
        try:
            labels = {l.get("name") for l in json.loads(r.stdout).get("labels", [])}
        except (ValueError, AttributeError):
            continue
        sid = (env.get("skill_id") or "")[:8]
        # 라벨을 로컬 상태에 반영한다 — 다음 세션부터 같은 안내를 반복하지 않게(전이 1회).
        if "approved" in labels:
            msgs.append(f"승격 허가됨 — 소우주 확장분 제거 안내: {sid}")
            try:
                set_status(project, env["envelope_id"], "approved")
            except Exception:
                pass
        elif "rejected" in labels:
            msgs.append(f"승격 거절됨 — 확장으로 계속: {sid}")
            try:
                set_status(project, env["envelope_id"], "rejected")
            except Exception:
                pass

for m in msgs:
    print(f"[outbox] {m}")
PY
)" || OUT=""
[[ -n "$OUT" ]] && printf '%s\n' "$OUT" >&2
exit 0
