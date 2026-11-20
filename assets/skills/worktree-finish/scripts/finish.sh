#!/usr/bin/env bash
# worktree-finish — 이 worktree 의 일을 로컬 main 에 합치고 worktree 를 지운다. 푸시하지 않는다.
#
# 순서: 검사 → 커밋(게이트 통과) → main 해시 기록 → main 위로 rebase → 메인 체크아웃에서 ff → worktree 지우기 → branch -d
# 멈춤(종료 코드): 10 메인 체크아웃에서 부름 · 11 메인 체크아웃이 main 이 아님 · 12 detached 또는 main 브랜치
#   13 원격에 있는 브랜치 · 14 메인의 커밋 안 된 변경과 겹침 · 15 rebase 충돌(abort 함) · 16 커밋 게이트가 막음
#   17 main 이 계속 움직여 ff 두 번 실패 · 18 허용 목록 밖 무시 파일 · 19 worktree 지우기·branch -d 거부
#   20 다른 마무리 진행 중(잠금) · 21 main 은 그대로인데 ff 거부 · 22 커밋 안 된 변경이 있는데 --message 없음
#   23 합친 뒤 main 이 브랜치 끝에 없음(지우지 않음) · 2 사용법·판정 오류
# 우회 플래그(--force · -D · --no-verify)는 쓰지 않는다 — 막히면 멈추고 사람에게 넘긴다.
# 사용: (worktree 안에서) bash finish.sh [--message "<커밋 메시지>"] [--main <브랜치>]
# 계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (G1)
set -uo pipefail

MSG="" ; MAIN_BRANCH="main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --message) MSG="${2:-}"; shift 2 ;;
    --main) MAIN_BRANCH="${2:-}"; shift 2 ;;
    *) echo "usage: finish.sh [--message <msg>] [--main <branch>]" >&2; exit 2 ;;
  esac
done

stop() { echo "stopped($1): $2" >&2; [[ -n "${3:-}" ]] && echo "  되돌리기·다음: $3" >&2; exit "$1"; }

WT="$(git rev-parse --show-toplevel 2>/dev/null)" || stop 2 "git 저장소 안이 아닙니다"
COMMON="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)"
MAIN_DIR="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[[ "$WT" == "$MAIN_DIR" ]] && stop 10 "메인 체크아웃에서 불렀습니다 — worktree 안에서 부르십시오"

STATE_PY="${WORKTREE_STATE_PY:-}"
for c in "$STATE_PY" "$(dirname "$0")/../../../hooks/worktree_state.py" "$MAIN_DIR/scripts/hooks/worktree_state.py"; do
  [[ -n "$c" && -f "$c" ]] && { STATE_PY="$c"; break; }
done
[[ -f "$STATE_PY" ]] || stop 2 "worktree_state.py 를 찾지 못했습니다"
field() { python3 -c 'import json,sys;v=json.load(sys.stdin)[sys.argv[1]];print("\n".join(v) if isinstance(v,list) else ("" if v is None else v))' "$1" <<<"$STATE"; }

# ⑩ 잠금 — mkdir 은 원자적이다. 남의 잠금은 지우지 않는다.
LOCK="$COMMON/worktree-finish.lock"
mkdir "$LOCK" 2>/dev/null || stop 20 "다른 마무리가 진행 중입니다($LOCK)" "그 세션이 끝난 뒤 다시 부르십시오. 남은 잠금이면 사람이 지웁니다"
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

STATE="$(python3 "$STATE_PY" "$WT" "$MAIN_BRANCH")" || stop 2 "상태를 읽지 못했습니다"
BRANCH="$(field branch)"
# ②
[[ -z "$BRANCH" ]] && stop 12 "detached HEAD 입니다" "git switch -c <브랜치> 로 브랜치를 만든 뒤 다시 부르십시오"
[[ "$BRANCH" == "$MAIN_BRANCH" ]] && stop 12 "이 worktree 가 $MAIN_BRANCH 자신입니다"
# ①
on="$(git -C "$MAIN_DIR" symbolic-ref --quiet --short HEAD)"
[[ "$on" == "$MAIN_BRANCH" ]] || stop 11 "메인 체크아웃이 $MAIN_BRANCH 가 아니라 '${on:-detached}' 에 있습니다" "메인 체크아웃을 쓰는 세션에 확인한 뒤 사람이 $MAIN_BRANCH 로 돌립니다"
# ③ upstream 이 있거나, 같은 이름의 원격 브랜치가 있다
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
  || git for-each-ref --format='%(refname:lstrip=3)' refs/remotes | grep -qxF "$BRANCH"; then
  stop 13 "브랜치 $BRANCH 가 원격에 있습니다 — rebase 하면 해시가 바뀝니다" "사람이 합칠 방법(merge 커밋 등)을 정합니다"
fi
# ⑧
stray="$(field stray_ignored)"
[[ -n "$stray" ]] && stop 18 "지우면 잃는 무시 파일이 있습니다: $(tr '\n' ' ' <<<"$stray")" "옮기거나 백업한 뒤 다시 부르십시오"

# 커밋
if [[ "$(field changes)" != "0" ]]; then
  [[ -z "$MSG" ]] && stop 22 "커밋 안 된 변경이 있습니다" "--message 로 커밋 메시지를 주십시오"
  git -C "$WT" add -A || stop 2 "git add 실패"
  if ! git -C "$WT" commit -q -m "$MSG"; then
    git -C "$WT" reset -q   # 스테이징만 되돌린다 — 파일은 그대로
    stop 16 "커밋 게이트가 막았습니다" "게이트가 말한 것을 고친 뒤 다시 부르십시오"
  fi
fi

# ④ 메인 체크아웃의 커밋 안 된 변경과, 합칠 파일이 겹치는가 — 두 목록 모두 -z 로 받는다(한글 경로가 따옴표로 감싸여 어긋나지 않게).
MAIN_REF="refs/heads/$MAIN_BRANCH"; BRANCH_REF="refs/heads/$BRANCH"   # 전체 이름 — 같은 이름의 태그를 고르지 않게
incoming="$(git -C "$WT" diff --name-only -z "$MAIN_REF...HEAD" | tr '\0' '\n' | sed '/^$/d')"
dirty="$(git -C "$MAIN_DIR" status --porcelain -z --no-renames --untracked-files=all | tr '\0' '\n' | cut -c4- | sed '/^$/d')"
overlap="$(comm -12 <(sort -u <<<"$incoming") <(sort -u <<<"$dirty") | sed '/^$/d')"
[[ -n "$overlap" ]] && stop 14 "메인 체크아웃의 커밋 안 된 변경과 겹칩니다: $(tr '\n' ' ' <<<"$overlap")" "그 변경의 주인 세션이 커밋한 뒤 다시 부르십시오"

MAIN_BEFORE="$(git -C "$MAIN_DIR" rev-parse "$MAIN_REF")"
echo "main 이전 해시: $MAIN_BEFORE"

# 한 번 합치기. 0 성공 · 1 main 이 움직임(다시 해 볼 만함). 다른 실패는 그 자리에서 멈춘다.
merge_once() {
  local err main_now
  if ! err="$(git -C "$WT" rebase -q "$MAIN_REF" 2>&1)"; then
    if [[ -d "$(git -C "$WT" rev-parse --path-format=absolute --git-dir)/rebase-merge" || -d "$(git -C "$WT" rev-parse --path-format=absolute --git-dir)/rebase-apply" ]]; then
      git -C "$WT" rebase --abort >/dev/null 2>&1 || stop 15 "rebase 가 실패했고 되돌리기(--abort)도 실패했습니다: $err" "git -C $WT status 로 상태를 보고 사람이 정리합니다"
    fi
    stop 15 "rebase 가 실패했습니다 — 브랜치를 rebase 전으로 되돌렸습니다: $(head -3 <<<"$err" | tr '\n' ' ')" "충돌이면 손으로 풀고 다시 부르십시오"
  fi
  # ff 직전에 메인 체크아웃이 아직 main 인지 다시 본다 — 앞의 확인 뒤 게이트·rebase 가 도는 동안 바뀔 수 있다.
  on="$(git -C "$MAIN_DIR" symbolic-ref --quiet --short HEAD)"
  [[ "$on" == "$MAIN_BRANCH" ]] || stop 11 "메인 체크아웃이 도중에 '${on:-detached}' 로 바뀌었습니다 — 합치지 않았습니다" "메인 체크아웃을 쓰는 세션에 확인한 뒤 다시 부르십시오"
  if ! err="$(git -C "$MAIN_DIR" merge -q --ff-only "$BRANCH_REF" 2>&1)"; then
    main_now="$(git -C "$MAIN_DIR" rev-parse "$MAIN_REF")"
    [[ "$main_now" != "$MAIN_BEFORE" ]] && return 1
    stop 21 "main 은 그대로인데 ff 가 거부됐습니다: $(head -3 <<<"$err" | tr '\n' ' ')" "메인 체크아웃의 작업 트리를 확인하십시오"
  fi
  return 0
}
if ! merge_once; then
  echo "main 이 움직였습니다 — 한 번 다시 합칩니다" >&2
  MAIN_BEFORE="$(git -C "$MAIN_DIR" rev-parse "$MAIN_REF")"
  merge_once || stop 17 "main 이 계속 움직여 합치지 못했습니다" "main 은 다른 세션의 커밋만 받았습니다. 잠시 뒤 다시 부르십시오"
fi
MAIN_AFTER="$(git -C "$MAIN_DIR" rev-parse "$MAIN_REF")"
# 사후 확인 — main 이 정말 이 브랜치 끝에 와 있을 때만 지운다(태그·다른 브랜치로 합친 경우를 여기서 막는다).
[[ "$MAIN_AFTER" == "$(git -C "$MAIN_DIR" rev-parse "$BRANCH_REF")" ]] \
  || stop 23 "합친 뒤 확인이 맞지 않습니다: $MAIN_BRANCH=$MAIN_AFTER, $BRANCH=$(git -C "$MAIN_DIR" rev-parse "$BRANCH_REF") — 지우지 않았습니다" "사람이 git log 로 확인합니다"

# 지우기 — 이 셸이 지울 worktree 안에 있지 않도록 먼저 옮긴다.
cd "$MAIN_DIR" || stop 2 "메인 체크아웃으로 옮기지 못했습니다"
git worktree remove "$WT" 2>&1 >&2 || stop 19 "worktree 를 지우지 못했습니다(합치기는 끝남: $MAIN_BEFORE..$MAIN_AFTER)" "git worktree list 로 상태를 보고 사람이 정리합니다"
git branch -q -d "$BRANCH" 2>&1 >&2 || stop 19 "브랜치 $BRANCH 를 지우지 못했습니다(합치기·worktree 지우기는 끝남)" "git branch -d $BRANCH 의 이유를 보십시오"

echo "result: merged $BRANCH into $MAIN_BRANCH ($MAIN_BEFORE..$MAIN_AFTER), removed $WT"
