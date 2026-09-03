#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 편집 직후 두 신호를 낸다.
#   (1) 줄 수 두 단계 경고 (안전망)
#   (2) 책임 증가 신호 — 줄 수와 무관하게, 마지막 커밋 대비 최상위 심볼이 급증하면 경고
#
# 목적: pre-commit 의 R-size 한도(MAX_LINES_HARD=500) 에 *도달한 뒤* 알게 되는 문제.
# 2026-04-15 한 프로젝트 세션 자성: watch.py 가 833 줄까지 부풀어 split 타이밍을 놓쳤다.
# 본 hook 은 400 줄 (soft) 에서 미리 경고하여 split 판단을 조기 유도한다.
#
# 차단하지 않는다(exit 0) — 감각 학습 목적. 강제 차단은 pre-commit 의 몫.
#
# 임계값:
#   SOFT_WARN_LINES (기본 400) — "곧 한도" 경고
#   HARD_WARN_LINES (기본 MAX_LINES_HARD=500) — "한도 초과, 즉시 split" 경고
#   RESP_DELTA_WARN (기본 5) — 마지막 커밋 대비 최상위 심볼 증가량 임계
#
# (2) 의 근거: docs/superpowers/specs/2026-08-21-responsibility-over-linecount-design.md
# 줄 수는 책임 수의 대리 지표로 실패한다 — 실측에서 책임이 둘이 된 커밋의 파일은 398 줄로
# soft 400 을 2 줄 차이로 비껴갔다. 절 개수 *절대값* 도 실패한다 (정상 설계 문서 다수가 같은 값).
# 판별력이 있었던 것은 *한 편집에서의 증가량* 뿐이다: 위반 커밋 +13, 차순위 +9, 나머지 전부 +3 이하.
# 임계 5 는 그 간극에서 잡았고 마크다운·코드 양쪽 실측에서 같은 자리다.
# 등록: .claude/settings.json 의 hooks.PostToolUse[matcher=Write|Edit].

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
RESP_DELTA_WARN="${RESP_DELTA_WARN:-5}"
[[ -f .harnessrc ]] && source .harnessrc
SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
RESP_DELTA_WARN="${RESP_DELTA_WARN:-5}"

# 발화 기록 호출 규약. 없으면 gate_emit 이 정의되지 않으므로 no-op 로 대체한다.
if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
fi
declare -F gate_add >/dev/null 2>&1 || { gate_add() { :; }; gate_flush() { :; }; }

FILE_PATH=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

# `.vue` 포함(2026-08-07) — pre-commit R-size 의 CHECKABLE 과 같은 목록을 쓴다.
# 경고 대상과 차단 대상이 어긋나면 "편집 중엔 조용하다가 커밋에서 막히는" 상태가 된다.
# `.md` 는 줄 수 경고 대상이 아니다 — 문서에 500 줄 한도를 걸면 과발화한다.
# 그러나 책임 신호(2) 의 대상에는 넣는다. 실측한 위반 사례가 전부 설계 문서였다.
case "$FILE_PATH" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue) CHECK_LINES=1 ;;
  *.md) CHECK_LINES=0 ;;
  *) exit 0 ;;
esac

WARNED_LINES=0

if (( CHECK_LINES )); then
LC=$(wc -l < "$FILE_PATH")

if (( LC > HARD_WARN_LINES )); then
  echo "[R-size HARD] $FILE_PATH = $LC 줄 > $HARD_WARN_LINES. commit 시 차단됨."
  echo "  이 파일에 책임이 몇 개인지 세고, 2개 이상이면 파일별 책임 분리 → 배럴 재export."
  echo "  정말 한 책임이면 파일 상단에 waiver 주석 + docs/audits/ 근거 기록 후 .harnessrc MAX_LINES_HARD 상향."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
elif (( LC > SOFT_WARN_LINES )); then
  echo "[R-size SOFT] $FILE_PATH = $LC 줄 (한도 $HARD_WARN_LINES, 잔여 $((HARD_WARN_LINES - LC))). 이미 늦었을 가능성."
  echo "  이 파일에 책임이 몇 개인지 먼저 세기. 2개 이상이면 지금 split, 1개면 계속."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
fi
# 줄 수 축의 판정이 여기서 끝난다. 세 갈래를 모두 기록해야 분모가 생긴다.
if (( LC > HARD_WARN_LINES )); then
  gate_add R-size warn posttooluse "$FILE_PATH" "$LC 줄 > hard $HARD_WARN_LINES"
elif (( LC > SOFT_WARN_LINES )); then
  gate_add R-size warn posttooluse "$FILE_PATH" "$LC 줄 > soft $SOFT_WARN_LINES"
else
  gate_add R-size pass posttooluse "$FILE_PATH" "$LC 줄"
fi
(( LC > SOFT_WARN_LINES )) && WARNED_LINES=1
fi

# ── (2) 책임 증가 신호 ──────────────────────────────────────────────
# 이미 줄 수 경고가 나갔으면 침묵한다. 그쪽이 이미 "책임을 세라" 고 말했고,
# 같은 편집에 두 경고를 겹치면 경고 피로로 사람이 hook 을 꺼 버린다.
(( WARNED_LINES )) && exit 0

# 기준선은 마지막 커밋본이다 — 상태 파일이 필요 없고, 커밋마다 자동으로 재설정된다.
# HEAD 에 없는 파일(신규)은 건너뛴다: 기준선이 없으면 "증가" 를 말할 수 없고,
# 한 번에 써 내려간 새 문서를 전부 오탐으로 잡게 된다.
REL=$(git ls-files --full-name --error-unmatch -- "$FILE_PATH" 2>/dev/null) || exit 0
[[ -n "$REL" ]] || exit 0

# SYM_PAT 은 "책임 수"의 대리 지표(전체 심볼), PUB_PAT 은 "인터페이스 폭"(공개 심볼)이다.
# 둘이 갈라지는 것은 파이썬뿐이다 — 마크다운의 절은 전부 노출이고, `^export ` 는 이미 공개만 센다.
case "$FILE_PATH" in
  *.md) SYM_PAT='^### '        ; PUB_PAT='^### '        ; SYM_UNIT='하위 절' ;;
  *.py) SYM_PAT='^(def |class |async def )'
        PUB_PAT='^(def |class |async def )[a-zA-Z]'     ; SYM_UNIT='최상위 def/class' ;;
  *)    SYM_PAT='^export '     ; PUB_PAT='^export '     ; SYM_UNIT='export 심볼' ;;
esac

# SFC 는 grep 으로 셀 수 없다. `^export ` 는 <script> 안의 들여쓴 prop 을 못 잡고,
# Svelte 5 runes(`let { a } = $props()`)는 아예 형태가 다르다.
# 그래서 이 신호는 Svelte 에서 **한 번도 발화할 수 없었다** —
# 실측(2026-08-25): 표본 200개 중 `^export ` 매칭 0개, `$props()` 사용 177개.
# 폭 정의는 iface_width.py 한 곳에만 둔다. 두 곳에서 재면 반드시 갈라진다.
IFACE_MOD=""
for cand in "$(dirname "$0")/iface_width.py" scripts/hooks/iface_width.py; do
  [[ -f "$cand" ]] && IFACE_MOD="$cand" && break
done

count_iface() {  # stdin=내용, $1=확장자 → 공개 심볼 수 (셀 수 없으면 빈 문자열)
  local out
  out=$(python3 "$IFACE_MOD" count "$1" 2>/dev/null) || return 1
  printf '%s' "$out"
}

EXT=".${FILE_PATH##*.}"
if [[ -n "$IFACE_MOD" && ( "$EXT" == ".vue" || "$EXT" == ".svelte" ) ]]; then
  SYM_NOW=$(count_iface "$EXT" < "$FILE_PATH" 2>/dev/null || echo 0)
  SYM_BASE=$(git show "HEAD:$REL" 2>/dev/null | count_iface "$EXT" 2>/dev/null || echo 0)
  PUB_NOW="$SYM_NOW"; PUB_BASE="$SYM_BASE"   # SFC 는 공개 폭이 곧 심볼 수다
  SYM_UNIT='공개 심볼(props/export)'
else
  SYM_NOW=$(grep -cE "$SYM_PAT" "$FILE_PATH" 2>/dev/null || true)
  SYM_BASE=$(git show "HEAD:$REL" 2>/dev/null | grep -cE "$SYM_PAT" || true)
  PUB_NOW=$(grep -cE "$PUB_PAT" "$FILE_PATH" 2>/dev/null || true)
  PUB_BASE=$(git show "HEAD:$REL" 2>/dev/null | grep -cE "$PUB_PAT" || true)
fi
SYM_NOW="${SYM_NOW:-0}"; SYM_BASE="${SYM_BASE:-0}"
PUB_NOW="${PUB_NOW:-0}"; PUB_BASE="${PUB_BASE:-0}"

# 임계 5 는 그대로 두고 "공개도 늘었는가" 를 AND 로 더한다 (2026-08-24).
# 비공개 헬퍼만 늘어난 편집은 인터페이스를 넓히지 않는다 — 내부를 깊게 만드는 *개선*이다.
# 그것을 책임 증가로 경고하면 좋은 편집이 벌을 받고, 경고 피로로 사람이 hook 을 끈다.
# 임계값 재산정이 아니라 오탐 제거다 — 5 의 근거 문서는 그대로 유효하다.
# 근거: docs/superpowers/specs/2026-08-24-interface-width-gate-design.md 축 B
# 책임 축은 줄 수 축과 분모가 다르다 (기준선이 있는 파일만 평가된다).
# 같은 R-size 키로 합치면 두 분모가 섞여 발화율이 무의미해진다.
if (( SYM_NOW - SYM_BASE >= RESP_DELTA_WARN )) && (( PUB_NOW > PUB_BASE )); then
  gate_add R-size-resp warn posttooluse "$FILE_PATH" "$SYM_BASE → $SYM_NOW (공개 $PUB_BASE → $PUB_NOW)"
  echo "[R-size 책임] $FILE_PATH — 마지막 커밋 대비 $SYM_UNIT: $SYM_BASE → $SYM_NOW (+$((SYM_NOW - SYM_BASE)))."
  echo "  이 파일에 책임이 몇 개인지 세고, 2개 이상이면 파일별 책임 분리 → 배럴 재export."
  echo "  먼저 볼 것: 방금 늘어난 것이 *파일명이 약속한 책임* 안에 있는가."
  echo "  줄 수와 무관한 신호다. 400/500 은 안전망이지 분리 시점이 아니다."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
else
  gate_add R-size-resp pass posttooluse "$FILE_PATH" "$SYM_BASE → $SYM_NOW"
fi

exit 0
