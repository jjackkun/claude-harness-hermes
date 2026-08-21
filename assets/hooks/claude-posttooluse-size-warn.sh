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

case "$FILE_PATH" in
  *.md) SYM_PAT='^### '        ; SYM_UNIT='하위 절' ;;
  *.py) SYM_PAT='^(def |class |async def )' ; SYM_UNIT='최상위 def/class' ;;
  *)    SYM_PAT='^export '     ; SYM_UNIT='export 심볼' ;;
esac

SYM_NOW=$(grep -cE "$SYM_PAT" "$FILE_PATH" 2>/dev/null || true)
SYM_BASE=$(git show "HEAD:$REL" 2>/dev/null | grep -cE "$SYM_PAT" || true)
SYM_NOW="${SYM_NOW:-0}"; SYM_BASE="${SYM_BASE:-0}"

if (( SYM_NOW - SYM_BASE >= RESP_DELTA_WARN )); then
  echo "[R-size 책임] $FILE_PATH — 마지막 커밋 대비 $SYM_UNIT: $SYM_BASE → $SYM_NOW (+$((SYM_NOW - SYM_BASE)))."
  echo "  이 파일에 책임이 몇 개인지 세고, 2개 이상이면 파일별 책임 분리 → 배럴 재export."
  echo "  먼저 볼 것: 방금 늘어난 것이 *파일명이 약속한 책임* 안에 있는가."
  echo "  줄 수와 무관한 신호다. 400/500 은 안전망이지 분리 시점이 아니다."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
fi

exit 0
