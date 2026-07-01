#!/usr/bin/env bash
# UserPromptSubmit hook — 사용자 지적에서 실수 카테고리를 감지해 pattern_count 즉시 +1.
#
# 동작: stdin JSON {"prompt": "..."} 에서 메시지를 읽고,
#       키워드 조합으로 실수 카테고리를 특정한 뒤 hermes-increment.py 를 호출한다.
#       stdout 에는 아무것도 출력하지 않음 (프롬프트 주입 없음).
#
# 비차단 — 항상 exit 0. 오류는 stderr 에만 출력.

set -uo pipefail

[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)}"
db_path="$project_dir/.hermes/state.db"
scripts_dir="$project_dir/scripts"
# 회상 스크립트는 훅 설치 위치 기준으로 해석한다(프로젝트에 scripts/ 가 없을 수 있음 — Stop 훅과 동일 규칙)
hook_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/scripts"

[[ ! -f "$db_path" ]] && exit 0

# stdin 은 한 번만 읽는다 — prompt 와 session_id 동시 추출 (jq 우선, 부재 시 python3 폴백)
input="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
else
  parsed="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("prompt", "") or "")
print(d.get("session_id", "") or "")
' 2>/dev/null || true)"
  prompt="$(printf '%s\n' "$parsed" | sed -n 1p)"
  session_id="$(printf '%s\n' "$parsed" | sed -n 2p)"
fi

# ── 회상 자동주입 (세션 첫 프롬프트 1회) — stdout 출력이 컨텍스트로 주입됨 ──
if [[ -f "$hook_scripts/hermes-recall.py" && -n "$session_id" ]]; then
  python3 "$hook_scripts/hermes-recall.py" --inject \
    --db "$db_path" \
    --project-id "$(basename "$project_dir")" \
    --session-id "$session_id" 2>/dev/null || true
fi

# ── 실수 카테고리 감지 (기존) ──
[[ ! -f "$scripts_dir/hermes-increment.py" ]] && exit 0
[[ -z "$prompt" ]] && exit 0

# 소문자 변환 (한글은 그대로)
prompt_lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

# ── 실수 카테고리 감지 규칙 ────────────────────────────────────────────────
# 규칙: 두 키워드 그룹이 모두 메시지에 포함될 때 카테고리 매핑

detect_key=""

# 1. 워크트리 → 메인 미동기화
# 트리거 예: "워크트리하고 반영안하냐", "메인브랜치에 적용 안됨", "왜 워크트리만"
if printf '%s' "$prompt_lower" | grep -qiE '워크트리|worktree'; then
  if printf '%s' "$prompt_lower" | grep -qiE '메인|반영|못봄|안나|볼수가없|적용|sync|main'; then
    detect_key="worktree-not-synced"
  fi
fi

# 2. CSS 속성 누락
# 트리거 예: "display flex 없어", "css 안됨"
if [[ -z "$detect_key" ]]; then
  if printf '%s' "$prompt_lower" | grep -qiE 'display|flex|css|스타일'; then
    if printf '%s' "$prompt_lower" | grep -qiE '없어|안됨|안나|안먹|빠졌|누락'; then
      detect_key="css-property-missing"
    fi
  fi
fi

# 3. 같은 실수 반복 언급 ("또", "몇번째", "계속", "자꾸") — 직전 detect_key 재사용 불가 시 generic
if [[ -z "$detect_key" ]]; then
  if printf '%s' "$prompt_lower" | grep -qiE '자꾸|몇번째|또야|계속|반복|여러번'; then
    detect_key="repeated-mistake"
  fi
fi

[[ -z "$detect_key" ]] && exit 0

# ── 기록 ──────────────────────────────────────────────────────────────────
python3 "$scripts_dir/hermes-increment.py" \
  --db "$db_path" \
  --key "$detect_key" 2>/dev/null || true

exit 0
