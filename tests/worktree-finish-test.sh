#!/usr/bin/env bash
# worktree-finish 스킬 (계획 2026-11-20-worktree-finish G1) — 모델 0, 네트워크 0.
# 임시 저장소마다 worktree 하나를 만들고 finish.sh 를 돌린다. 정상 1 · 멈춤 ①~⑩ · 메시지 없음 1 · 열린 문서(24) 6 · --keep-worktree 1 · 낡은 판정 모듈 1.
# 멈춤이면 main 끝 해시가 그대로이고(⑦ 은 시험이 일부러 main 을 움직인다), worktree 와 잠금이 남지 않는지 본다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/worktree-finish"
FINISH="$SKILL/scripts/finish.sh"
export WORKTREE_STATE_PY="$REPO_ROOT/assets/hooks/worktree_state.py"
# 커밋 게이트 안에서 돌면 git 이 넘기는 위치 변수가 임시 저장소 대신 이 저장소를 가리킨다 — 지운다.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_PREFIX
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# 시험은 임시 폴더 안에서만 돈다 — 상대 경로가 이 저장소(.git)를 건드리지 않게(2026-11-20 사고: 상대 git-common-dir 로 공장 pre-commit 을 덮었다).
cd "$TMP" || exit 1
common_of() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

# 새 저장소 $TMP/<이름>/main 과 worktree $TMP/<이름>/wt(브랜치 feat). 전역 변수 M · WT 를 채운다.
fresh() {
  M="$TMP/$1/main"; WT="$TMP/$1/wt"
  mkdir -p "$M" && git -C "$M" init -q -b main
  printf 'node_modules/\nserver/uploads/\n' > "$M/.gitignore"
  printf 'line\n' > "$M/a.txt"
  git -C "$M" add -A && git -C "$M" commit -qm init
  git -C "$M" worktree add -q -b feat "$WT"
}
work() { printf '%s\n' "${2:-change}" > "$WT/$1"; git -C "$WT" add -A && git -C "$WT" commit -qm "work $1"; }
run() { (cd "$WT" && bash "$FINISH" "$@" >"$TMP/out.log" 2>&1); echo $?; }
head_of() { git -C "$M" rev-parse main; }
lock_left() { [[ -e "$(common_of "$M")/worktree-finish.lock" ]] && echo yes || echo no; }
on_rebase() {  # rebase 가 커밋을 다시 쓴 직후 메인 체크아웃에서 "$1" 을 돌린다(main 을 먼저 움직여야 rebase 가 다시 쓴다)
  local hooks; hooks="$(common_of "$M")/hooks"; mkdir -p "$hooks"
  printf '#!/bin/sh\nunset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE\ncd "%s" && %s\n' "$M" "$1" > "$hooks/post-rewrite"; chmod +x "$hooks/post-rewrite"
}
wt_left() { git -C "$M" worktree list | grep -c "/wt "; }
# 계획서·기획서(계획 2026-11-25-worktree-finish-open-docs) — "$1" 경로에 §2 항목 "$2"(예 "- [ ] G1") 로 쓴다.
PLAN="docs/exec-plans/active/2026-11-25-x-plan.md"; DONE="docs/exec-plans/completed/2026-11-25-x-plan.md"; PRD="docs/product-specs/x/prd.md"
doc() { mkdir -p "$(dirname "$WT/$1")"; printf '# x\n\n## 2. 목표\n\n%s\n\n## 3. 비목표\n' "$2" > "$WT/$1"; }
prd() { mkdir -p "$WT/docs/product-specs/x"; printf -- '- status: %s\n' "$1" > "$WT/$PRD"; }
commit_all() { git -C "$WT" add -A && git -C "$WT" commit -qm "${1:-docs}"; }

echo "[구조]"
assert "SKILL.md 의 name 이 폴더 이름과 같다" "worktree-finish" "$(sed -n 's/^name: *//p' "$SKILL/SKILL.md" | head -1)"
assert "workflow 프리셋에 등록" 1 "$(grep -cE '^\s+worktree-finish$' "$REPO_ROOT/presets/workflow/harness.conf")"
bash -n "$FINISH"; assert "finish.sh 문법 통과" 0 "$?"
assert "우회 플래그(--force · -D · --no-verify) 없음" 0 "$(grep -vE '^\s*#' "$FINISH" | grep -cE -- 'remove --force|branch -D|--no-verify')"
assert "푸시 없음" 0 "$(grep -vE '^\s*#' "$FINISH" | grep -cE 'git[^|]* push')"

echo "[정상] 커밋 + 커밋 안 된 변경 → 커밋 · rebase · ff · 지우기"
fresh ok; work b.txt
git -C "$M" commit -q --allow-empty -m "main moved"   # main 이 앞서도 rebase 로 합친다
printf 'x\n' > "$WT/c.txt"                             # 커밋 안 된 변경
printf 'x\n' > "$M/unrelated.txt"                      # 겹치지 않는 메인의 변경은 막지 않는다
mkdir -p "$WT/node_modules/p" && printf 'x\n' > "$WT/node_modules/p/i.js"  # 다시 만들 수 있는 무시 파일
assert "종료 0" 0 "$(run --message 'feat: c')"
assert "main 에 b.txt 커밋" 1 "$(git -C "$M" log --format=%s main | grep -c '^work b.txt$')"
assert "main 에 c.txt 커밋" 1 "$(git -C "$M" log --format=%s main | grep -c '^feat: c$')"
assert "worktree 가 사라짐" 0 "$(wt_left)"
assert "브랜치 feat 가 사라짐" 0 "$(git -C "$M" branch --list feat | wc -l)"
assert "잠금이 남지 않음" no "$(lock_left)"
assert "result 줄" 1 "$(grep -c '^result: merged feat into main' "$TMP/out.log")"
assert "main 끝 커밋이 브랜치 끝" "feat: c" "$(git -C "$M" log -1 --format=%s main)"

echo "[멈춤 ①] 메인 체크아웃이 main 이 아님 → 11"
fresh m1; work b.txt; git -C "$M" checkout -q -b other; before=$(head_of)
assert "종료 11" 11 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "worktree 남음" 1 "$(wt_left)"; assert "잠금 없음" no "$(lock_left)"

echo "[멈춤 ②] detached HEAD → 12"
fresh m2; work b.txt; git -C "$WT" checkout -q --detach; before=$(head_of)
assert "종료 12" 12 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "잠금 없음" no "$(lock_left)"

echo "[멈춤 ③] 원격에 있는 브랜치 → 13"
fresh m3; work b.txt; git init -q --bare "$TMP/m3/remote.git"; git -C "$M" remote add origin "$TMP/m3/remote.git"
git -C "$WT" push -q origin feat 2>/dev/null; before=$(head_of)
assert "종료 13" 13 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "잠금 없음" no "$(lock_left)"

echo "[멈춤 ④] 메인 체크아웃의 커밋 안 된 변경이 합칠 파일과 겹침 → 14"
fresh m4; work b.txt; printf 'mine\n' > "$M/b.txt"; before=$(head_of)
assert "종료 14" 14 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "메인의 파일 보존" mine "$(cat "$M/b.txt")"

echo "[멈춤 ⑤] rebase 충돌 → 15, 브랜치는 rebase 전 그대로"
fresh m5; work a.txt theirs; branch_before=$(git -C "$WT" rev-parse HEAD)
printf 'ours\n' > "$M/a.txt"; git -C "$M" commit -qam "main edits a"; before=$(head_of)
assert "종료 15" 15 "$(run)"; assert "main 그대로" "$before" "$(head_of)"
assert "브랜치 그대로" "$branch_before" "$(git -C "$WT" rev-parse HEAD)"
assert "rebase 진행 중 아님" no "$([[ -d "$(git -C "$WT" rev-parse --git-dir)/rebase-merge" ]] && echo yes || echo no)"

echo "[멈춤 ⑥] 커밋 게이트가 막음 → 16"
fresh m6; hooks="$(common_of "$M")/hooks"; mkdir -p "$hooks"
printf '#!/bin/sh\necho gate says no >&2\nexit 1\n' > "$hooks/pre-commit"; chmod +x "$hooks/pre-commit"
printf 'x\n' > "$WT/b.txt"; before=$(head_of)
assert "종료 16" 16 "$(run --message 'feat: b')"; assert "main 그대로" "$before" "$(head_of)"
assert "변경은 커밋 안 된 채 남음" 1 "$(git -C "$WT" status --porcelain | wc -l)"
assert "스테이징도 되돌림" 0 "$(git -C "$WT" diff --cached --name-only | wc -l)"

echo "[멈춤 ⑦] rebase 와 ff 사이에 main 이 두 번 움직임 → 17"
fresh m7; work b.txt; git -C "$M" commit -q --allow-empty -m "main moved"
on_rebase "git commit -q --allow-empty -m race"
assert "종료 17" 17 "$(run)"; assert "잠금 없음" no "$(lock_left)"
assert "feat 는 main 에 없음" 0 "$(git -C "$M" log --format=%s main | grep -c '^work b.txt$')"; assert "worktree 남음" 1 "$(wt_left)"

echo "[멈춤 ⑧] 허용 목록 밖 무시 파일 → 18"
fresh m8; work b.txt; mkdir -p "$WT/server/uploads" && printf 'x\n' > "$WT/server/uploads/a.bin"; before=$(head_of)
assert "종료 18" 18 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "파일 이름을 보임" 1 "$(grep -c 'server/uploads/' "$TMP/out.log")"

echo "[멈춤 ⑨] worktree 지우기가 거부됨(잠긴 worktree) → 19, 합치기는 이미 끝남"
fresh m9; work b.txt; git -C "$M" worktree lock "$WT"
assert "종료 19" 19 "$(run)"; assert "feat 는 main 에 있음" 1 "$(git -C "$M" log --format=%s main | grep -c '^work b.txt$')"
assert "worktree 남음" 1 "$(wt_left)"; assert "잠금 없음" no "$(lock_left)"

echo "[멈춤 ⑩] 다른 마무리가 진행 중(잠금) → 20"
fresh m10; work b.txt; mkdir "$(common_of "$M")/worktree-finish.lock"; before=$(head_of)
assert "종료 20" 20 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "남의 잠금은 지우지 않음" yes "$(lock_left)"

echo "[리뷰 H1] rebase 와 ff 사이에 메인 체크아웃이 다른 브랜치로 바뀜 → 11, 아무것도 지우지 않음"
fresh h1; work b.txt; git -C "$M" commit -q --allow-empty -m "main moved"; before=$(head_of)
on_rebase "git checkout -q -b other"
assert "종료 11" 11 "$(run)"; assert "main 그대로" "$before" "$(head_of)"
assert "worktree 남음" 1 "$(wt_left)"; assert "브랜치 feat 남음" 1 "$(git -C "$M" branch --list feat | wc -l)"
assert "other 에도 합치지 않음" 0 "$(git -C "$M" log --format=%s other | grep -c '^work b.txt$')"

echo "[리뷰 H2] 브랜치와 같은 이름의 태그가 있어도 브랜치를 합친다"
fresh h2; git -C "$M" tag feat main; work b.txt
assert "종료 0" 0 "$(run)"; assert "main 에 b.txt 커밋" 1 "$(git -C "$M" log --format=%s main | grep -c '^work b.txt$')"; assert "worktree 가 사라짐" 0 "$(wt_left)"

echo "[리뷰 M1] 한글 경로도 겹침으로 잡는다 → 14"
fresh m1k; work "한글.md"; printf 'mine\n' > "$M/한글.md"; before=$(head_of)
assert "종료 14" 14 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "한글 이름을 보임" 1 "$(grep -c '한글.md' "$TMP/out.log")"

echo "[메시지 없음] 커밋 안 된 변경이 있는데 --message 가 없음 → 22"
fresh m22; printf 'x\n' > "$WT/b.txt"; before=$(head_of)
assert "종료 22" 22 "$(run)"; assert "main 그대로" "$before" "$(head_of)"

echo "[열린 문서 24] 열린 계획서 + 커밋 안 된 변경 + --message → 24, 아무것도 바꾸지 않음"
fresh o1; doc "$PLAN" "- [ ] G1"; commit_all; printf 'x\n' > "$WT/b.txt"
before=$(head_of); tip=$(git -C "$WT" rev-parse HEAD)
assert "종료 24" 24 "$(run --message 'feat: b')"; assert "main 그대로" "$before" "$(head_of)"
assert "커밋도 안 생김" "$tip" "$(git -C "$WT" rev-parse HEAD)"; assert "변경은 커밋 안 된 채" 1 "$(git -C "$WT" status --porcelain | wc -l)"
assert "worktree 남음" 1 "$(wt_left)"; assert "브랜치 남음" 1 "$(git -C "$M" branch --list feat | wc -l)"; assert "잠금 없음" no "$(lock_left)"
assert "경로와 이유를 보임" 1 "$(grep -c "$PLAN — §2 미완료 1개" "$TMP/out.log")"
assert "다음 할 일에 --keep-worktree" 1 "$(grep -c -- '--keep-worktree 로 다시 부르십시오' "$TMP/out.log")"

echo "[열린 문서 24] draft 기획서 → 24"
fresh o2; prd draft; commit_all; before=$(head_of)
assert "종료 24" 24 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "이유 status: draft" 1 "$(grep -c 'status: draft' "$TMP/out.log")"

echo "[열린 문서 24] 닫힌 계획서 · approved 기획서 → 평소대로 합치고 지움"
fresh o3; doc "$PLAN" "- [x] G1"; prd approved; commit_all
assert "종료 0" 0 "$(run)"; assert "worktree 가 사라짐" 0 "$(wt_left)"; assert "main 에 docs 커밋" 1 "$(git -C "$M" log --format=%s main | grep -c '^docs$')"

echo "[열린 문서 24] completed 로 옮겼는데 [ ] 남음 → 24"
fresh o4; doc "$DONE" "- [x] G1
- [ ] G2"; commit_all; before=$(head_of)
assert "종료 24" 24 "$(run)"; assert "main 그대로" "$before" "$(head_of)"; assert "이유 completed" 1 "$(grep -c 'completed 인데 §2 미완료 1개' "$TMP/out.log")"

echo "[열린 문서 24] 18 과 24 가 함께 → 18 이 먼저"
fresh o5; doc "$PLAN" "- [ ] G1"; commit_all; mkdir -p "$WT/server/uploads" && printf 'x\n' > "$WT/server/uploads/a.bin"
assert "종료 18" 18 "$(run)"

echo "[열린 문서 24] 커밋 안 된 변경 + --message 없음 + 열린 문서 → 24(22 가 아님)"
fresh o6; doc "$PLAN" "- [ ] G1"
assert "종료 24" 24 "$(run)"; assert "잠금 없음" no "$(lock_left)"

echo "[--keep-worktree] 열린 문서가 있어도 합치고 worktree · 브랜치를 남긴다"
fresh k1; doc "$PLAN" "- [ ] G1"; commit_all; printf 'x\n' > "$WT/b.txt"
assert "종료 0" 0 "$(run --keep-worktree --message 'feat: b')"
assert "main 이 브랜치 끝" "$(git -C "$WT" rev-parse HEAD)" "$(head_of)"; assert "main 끝 커밋" "feat: b" "$(git -C "$M" log -1 --format=%s main)"
assert "끝 줄에 kept" 1 "$(grep -c '^result: merged feat into main (.*), kept ' "$TMP/out.log")"; assert "removed 없음" 0 "$(grep -c 'removed' "$TMP/out.log")"
assert "worktree 남음" 1 "$(wt_left)"; assert "브랜치 남음" 1 "$(git -C "$M" branch --list feat | wc -l)"; assert "잠금 없음" no "$(lock_left)"
assert "바로 한 번 더 keep → 종료 0" 0 "$(run --keep-worktree)"; assert "main 그대로 브랜치 끝" "$(git -C "$WT" rev-parse HEAD)" "$(head_of)"
work c.txt; doc "$PLAN" "- [x] G1"; commit_all "close plan"
assert "문서를 닫고 keep 없이 → 종료 0" 0 "$(run)"; assert "worktree 가 사라짐" 0 "$(wt_left)"
assert "브랜치 feat 가 사라짐" 0 "$(git -C "$M" branch --list feat | wc -l)"; assert "main 끝 커밋" "close plan" "$(git -C "$M" log -1 --format=%s main)"

echo "[낡은 판정 모듈] worktree_state.py 가 open_docs 칸을 내지 않음 → 2, 트레이스백 없음"
fresh old; work b.txt; before=$(head_of)
printf '#!/usr/bin/env python3\nimport json\nprint(json.dumps({"branch":"feat","changes":0,"stray_ignored":[]}))\n' > "$TMP/old_state.py"
assert "종료 2" 2 "$( (cd "$WT" && WORKTREE_STATE_PY="$TMP/old_state.py" bash "$FINISH" >"$TMP/out.log" 2>&1); echo $?)"
assert "칸 이름을 보임" 1 "$(grep -c '칸 없음: open_docs' "$TMP/out.log")"; assert "트레이스백 없음" 0 "$(grep -c Traceback "$TMP/out.log")"
assert "main 그대로" "$before" "$(head_of)"; assert "잠금 없음" no "$(lock_left)"

echo "[메인 체크아웃에서 부름] → 10"
fresh m0; assert "종료 10" 10 "$( (cd "$M" && bash "$FINISH" >/dev/null 2>&1); echo $?)"

echo "결과: $PASS 통과 · $FAIL 실패"
[[ "$FAIL" -eq 0 ]]
