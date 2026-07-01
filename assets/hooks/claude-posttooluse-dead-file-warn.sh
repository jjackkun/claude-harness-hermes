#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 편집한 파일이 프로젝트 내에서 참조되는지 검사.
#
# 목적: Claude 가 파일명만 보고 "이 파일이 그 컴포넌트" 라고 단정해 dead file 을
# 수정·완료 보고하는 재발 패턴을 차단. LLM 의 자연스러운 실패 모드(파일명 추론 >
# import 그래프 추적) 를 기계로 잡는다.
#
# 동작: basename(확장자 제거) 을 프로젝트 전체에서 grep. 자기 자신 외 참조 0건이면
# stderr 로 경고 + 같은 디렉터리에서 실제 import 되는 이웃 후보 Top 3 제안.
# 블로킹 아님(exit 0) — 신규 파일/의도적 dead 정리 워크플로우 보호.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

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

case "$FILE_PATH" in
  *.svelte|*.tsx|*.jsx|*.ts|*.js|*.py|*.vue) ;;
  *) exit 0 ;;
esac

# 제외 패턴: 테스트·빌드 산출물·마이그레이션·타입 선언.
case "$FILE_PATH" in
  */node_modules/*|*/.svelte-kit/*|*/dist/*|*/build/*|*/.next/*) exit 0 ;;
  *.d.ts|*.test.*|*.spec.*|*.stories.*) exit 0 ;;
  */__tests__/*|*/test_*|*/tests/*) exit 0 ;;
  */alembic/versions/*|*/migrations/*) exit 0 ;;
esac

REL="${FILE_PATH#"$PWD"/}"
BASENAME="$(basename "$FILE_PATH")"
STEM="${BASENAME%.*}"

# 두 글자 이하 stem 은 오탐 위험 커서 스킵 (a, b, io 등).
[[ ${#STEM} -lt 3 ]] && exit 0

# 검색 도구: ripgrep 우선.
if command -v rg >/dev/null 2>&1; then
  SEARCHER="rg --no-messages -l -t svelte -t ts -t js -t tsx -t jsx -t py -t vue"
  SEARCHER_IMPORT="rg --no-messages -t svelte -t ts -t js -t tsx -t jsx -t py -t vue"
else
  # grep 폴백: include 확장자 반복 지정.
  INCLUDES='--include=*.svelte --include=*.ts --include=*.tsx --include=*.js --include=*.jsx --include=*.py --include=*.vue'
  SEARCHER="grep -rl $INCLUDES --exclude-dir=node_modules --exclude-dir=.svelte-kit --exclude-dir=dist --exclude-dir=build --exclude-dir=.next"
  SEARCHER_IMPORT="grep -rn $INCLUDES --exclude-dir=node_modules --exclude-dir=.svelte-kit --exclude-dir=dist --exclude-dir=build --exclude-dir=.next"
fi

# basename 기반 참조 검색. 단어 경계 \b 로 부분 일치 (ChartX) 배제.
PATTERN="\\b${STEM}\\b"

# 후보 파일 리스트 (자기 자신 제외).
mapfile -t REF_FILES < <($SEARCHER "$PATTERN" . 2>/dev/null | grep -v -F -x "./$REL" | grep -v -F -x "$REL" | head -20)

REF_COUNT=${#REF_FILES[@]}

if (( REF_COUNT > 0 )); then
  exit 0
fi

# 참조 0건 — 경고 + 후보 제안.
DIR="$(dirname "$FILE_PATH")"

# 같은 디렉터리 내 형제 파일 중 프로젝트 전체에서 실제 import 되는 것 Top 3.
# "basename (확장자 제거)" 로 grep 해서 자기 제외 hit 수 계산.
declare -a CANDIDATES
if [[ -d "$DIR" ]]; then
  while IFS= read -r sibling; do
    [[ "$sibling" == "$FILE_PATH" ]] && continue
    sib_base="$(basename "$sibling")"
    sib_stem="${sib_base%.*}"
    [[ ${#sib_stem} -lt 3 ]] && continue
    case "$sib_base" in
      *.test.*|*.spec.*|*.stories.*) continue ;;
    esac
    sib_rel="${sibling#"$PWD"/}"
    hit=$($SEARCHER "\\b${sib_stem}\\b" . 2>/dev/null | grep -v -F -x "./$sib_rel" | grep -v -F -x "$sib_rel" | wc -l)
    if (( hit > 0 )); then
      CANDIDATES+=("$hit|$sib_base")
    fi
  done < <(find "$DIR" -maxdepth 1 -type f \( -name '*.svelte' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' -o -name '*.js' -o -name '*.py' -o -name '*.vue' \) 2>/dev/null)
fi

{
  echo "[dead-file WARN] $REL — 프로젝트 내 참조 0건."
  echo "  신규 파일이거나 의도적 dead file 정리면 무시."
  echo "  실사용 컴포넌트를 고치려던 거면 *중단*하고 import 그래프 재확인."
  if (( ${#CANDIDATES[@]} > 0 )); then
    echo "  실사용 후보 (같은 디렉터리, 참조 많은 순):"
    printf '%s\n' "${CANDIDATES[@]}" | sort -t'|' -k1 -n -r | head -3 | awk -F'|' '{ printf "    - %s (참조 %d건)\n", $2, $1 }'
  fi
} >&2

exit 0
