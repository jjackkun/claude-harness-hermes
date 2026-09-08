#!/usr/bin/env bash
# PostToolUse(Bash) hook — Bash 도구 호출이 컨텍스트에 넣은 **실제 바이트**를 기록한다. (R-out)
#
# 근거: docs/exec-plans/active/2026-09-08-tool-output-budget.md
#
# 단일 책임: 출력 크기 1건을 재어 R-out 판정으로 남긴다. 명령을 해석하지 않는다.
#
# **왜 PostToolUse 인가 — 추측하지 않기 위해서다.**
#   PreToolUse 는 실행 *전*이라 출력 크기를 알 수 없어 명령 패턴으로 추측해야 한다.
#   그 추측이 틀린 것이 오탐이고, 이 저장소는 이미 대가를 치렀다 — R5 가 `-n` 을
#   단어로 잡아 20/20 오탐을 냈다(docs/audits/2026-09-03-gate-firing-first-observation.md).
#   훅은 12개 프로젝트에 **복사본**으로 깔리므로 잘못된 패턴 한 줄이 12배로 증폭되고,
#   복사본이라 update-all.sh 를 다시 돌릴 때까지 시차 동안 계속 오탐한다.
#   여기서는 실측값만 쓰므로 그 위험 자체가 없다. 명령 문자열은 **기록에만** 남기고
#   판정에는 쓰지 않는다.
#
# 한계(설계상 수용): 이미 컨텍스트에 들어온 출력은 되돌릴 수 없다. 이 훅의 산출물은
#   절감이 아니라 **다음 호출을 바꿀 근거**다. 절감 조치는 3주치 분포를 본 뒤 결정한다.
#
# 등록: .claude/settings.json 의 hooks.PostToolUse[matcher=Bash].

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
fi
declare -F gate_emit >/dev/null 2>&1 || gate_emit() { :; }

# 임계 — **이 값이 옳다는 근거는 아직 없다.** 약 2k 토큰에 해당하는 출발점일 뿐이며,
# 2026-09-29 에 3주치 분포를 보고 정한다(계획서 Step 6). 근거 없는 고정값을 남기지
# 않기 위해 그 사실을 여기 적어 둔다.
R_OUT_THRESHOLD=${R_OUT_THRESHOLD:-8192}

# 파싱·판정·메시지 렌더를 python3 한 번에 끝낸다. 축마다 프로세스를 띄우면 관측 비용이
# 게이트 비용을 넘는다(gate_emit.sh 실측: 기동 1회 21ms).
#   1행: "<verdict> <bytes> <duration_ms>"
#   2행 이후: 주입할 JSON (없으면 빈 문자열)
# 페이로드를 파일로 받아 경로만 넘긴다.
#   - 히어독은 python3 의 stdin 을 차지하므로 `python3 - <<PY` 로는 페이로드를 읽을 수 없다
#     (2026-09-08 실측: 전 판정이 skipped 로 샜다. 시험이 잡았다).
#   - 환경변수로 넘기면 출력이 큰 명령에서 E2BIG 로 실패한다 — 하필 가장 재고 싶은 경우다.
PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/r-out.XXXXXX") || exit 0
cat > "$PAYLOAD_FILE"

PARSED=$(R_OUT_THRESHOLD="$R_OUT_THRESHOLD" R_OUT_PAYLOAD="$PAYLOAD_FILE" \
         python3 - <<'PY' 2>/dev/null || true
import json, os, sys

THRESHOLD = int(os.environ.get("R_OUT_THRESHOLD", "8192"))

def emit(verdict, nbytes, dur, payload=None):
    print(f"{verdict} {nbytes} {dur}")
    print(json.dumps(payload, ensure_ascii=False) if payload else "")
    sys.exit(0)

try:
    with open(os.environ["R_OUT_PAYLOAD"], "rb") as f:
        d = json.loads(f.read().decode("utf-8", "replace"))
except Exception:
    emit("skipped", 0, 0)

# 유효한 JSON 이지만 최상위가 dict 가 아닐 수 있다(`[]` `123` `"s"`).
# 이 가드가 없으면 다음 줄의 .get() 이 AttributeError 를 내고, 스크립트가 아무것도
# 출력하지 못한 채 죽어 **skipped 조차 남지 않는다**(2026-09-08 검토에서 재현).
# 아래 isinstance(tr, dict) 방어가 이미 "dict 가 아닐 수 있다" 를 상정하고 있었는데,
# 정작 그 앞이 무방비였다. 판정 불가는 반드시 기록으로 남아야 한다.
if not isinstance(d, dict):
    emit("skipped", 0, 0)

tr = d.get("tool_response")
dur = d.get("duration_ms") or 0

# 판정 불가는 통과가 아니다. `pass` 로 세면 분모가 부풀어 발화율이 실제보다 낮아진다
# — gate_report.py 의 _row() 가 skipped 를 분모에서 빼도록 정의한 이유다.
# (2026-09-08 검토에서 R-plan-stale 이 정확히 이 실수를 했다.)
if not isinstance(tr, dict):
    emit("skipped", 0, dur)
if tr.get("interrupted"):
    # 중단된 명령의 출력은 잘려 있어 크기 판정의 근거가 못 된다.
    emit("skipped", 0, dur)

# stderr 도 컨텍스트에 들어간다. 합산하지 않으면 시끄러운 명령을 절반만 센다.
try:
    n = len(str(tr.get("stdout") or "").encode("utf-8")) + \
        len(str(tr.get("stderr") or "").encode("utf-8"))
except Exception:
    emit("skipped", 0, dur)

if n < THRESHOLD:
    emit("pass", n, dur)

emit("warn", n, dur, {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"[R-out] 방금 명령이 컨텍스트에 {n:,}B 를 넣었습니다 (임계 {THRESHOLD:,}B). "
            "같은 명령을 다시 부를 때는 출력을 파일로 받고 필요한 부분만 읽으십시오 — "
            "`<명령> > .harness/out/run.log 2>&1; tail -40 .harness/out/run.log`. "
            "실패를 찾을 때는 grep 으로 파고드십시오. 이번 호출은 되돌릴 수 없습니다."
        )
    }
})
PY
)

rm -f "$PAYLOAD_FILE"

# 내장 read 로만 가른다. 이 훅은 **세션 내 모든 Bash 호출**에 걸리므로 프로세스 하나가
# 곧 세션 전체의 곱셈이 된다 — sed 3 + awk 3 을 쓰던 판을 걷어냈다(2026-09-08 검토).
# 주입 JSON 은 json.dumps 산출이라 항상 한 줄이다.
VERDICT="" NBYTES="" DUR="" JSON=""
{ read -r VERDICT NBYTES DUR; read -r JSON; } <<< "$PARSED"

[[ -n "${VERDICT:-}" ]] || exit 0

case "$VERDICT" in
  pass)    gate_emit R-out pass    posttooluse "" "${NBYTES}B ${DUR}ms" ;;
  warn)    gate_emit R-out warn    posttooluse "" "${NBYTES}B ${DUR}ms (임계 ${R_OUT_THRESHOLD}B 초과)" ;;
  skipped) gate_emit R-out skipped posttooluse "" "출력 크기 판정 불가" ;;
esac

# 임계 미만이면 아무것도 출력하지 않는다 — 관측이 스스로 컨텍스트를 태우면 본말전도다.
[[ -n "$JSON" ]] && printf '%s\n' "$JSON"

exit 0
