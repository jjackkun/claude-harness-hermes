#!/usr/bin/env bash
# review-coverage 스킬 (계획 2026-11-19-review-coverage 목표 G1~G5) — 모델 0, 네트워크 0.
# [범위] 작업 중·범위·커밋 · [기준] 내장·프로젝트 덮어쓰기·합치기·깨진 파일 · [장부] 빠짐·줄 번호 · [등록] 에이전트·프리셋
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/review-coverage"; R="$SKILL/scripts/review_scope.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
rs() { python3 "$R" "$@" --repo "$G"; }
jq_py() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }

G="$TMP/repo"; mkdir -p "$G"; cd "$G" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
printf 'a\nb\nc\n' > keep.py; printf 'x\n' > gone.py; printf 'old\n' > moved.ts; printf '{}\n' > package-lock.json
git add -A; git commit -qm base
git checkout -qb feature
printf 'a\nB\nc\nd\n' > keep.py; git mv moved.ts renamed.ts; git commit -qam feat
FEATURE=$(git rev-parse HEAD)
git checkout -q main; printf 'main\n' > other.py; git add other.py; git commit -qm main-only; git checkout -q feature

echo "[범위] 작업 중 방식 — staged·unstaged·untracked·뺄 파일"
printf 'a\nB\nc\nd\ne\n' > keep.py                       # unstaged
printf 'new\n' > staged.py; git add staged.py            # staged
printf 'u1\nu2\n' > fresh.svelte                         # untracked
git rm -q gone.py                                        # 삭제
mkdir -p node_modules/x; printf 'm\n' > node_modules/x/i.js
printf '\0bin' > img.bin; printf '{"a":1}\n' > package-lock.json; printf 'g\n' > gen.py
S=$(rs scope --json --exclude 'gen.py')
assert "리뷰할 파일 3개 (keep·staged·fresh)" "fresh.svelte keep.py staged.py" "$(echo "$S" | jq_py "' '.join(sorted(e['path'] for e in d['reviewable']))")"
assert "삭제 파일은 뺀다" "삭제된 파일 — 새 코드가 없다" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path']=='gone.py'][0]")"
assert "잠금 파일은 뺀다" "생성물(잠금 파일·압축본)" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path']=='package-lock.json'][0]")"
assert "바이너리는 뺀다" "바이너리" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path']=='img.bin'][0]")"
assert "--exclude 패턴" "--exclude gen.py" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path']=='gen.py'][0]")"
assert "node_modules 는 gitignore 없어도 뺀다" "제외 디렉터리 node_modules/" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path'].startswith('node_modules')][0]")"
git reset -q --hard; git clean -qfdx   # 작업 중 변경 버림 (임시 저장소 안)

echo "[범위] 범위·커밋 방식"
S=$(rs scope --json --from main)
assert "--from main 은 merge-base 부터 (main 쪽 other.py 없음)" "keep.py renamed.ts" "$(echo "$S" | jq_py "' '.join(sorted(e['path'] for e in d['reviewable']))")"
assert "이름 변경은 새 경로·R" "R" "$(echo "$S" | jq_py "[e['status'] for e in d['reviewable'] if e['path']=='renamed.ts'][0]")"
assert "--from 은 range 방식" "range" "$(echo "$S" | jq_py "d['mode']")"
assert "커밋 방식 파일 수" 2 "$(rs scope --json --commit "$FEATURE" | jq_py "len(d['reviewable'])")"
rs scope --commit HEAD --from main >/dev/null 2>&1; assert "--commit 와 --from 함께 → 2" 2 "$?"
rs scope --to main >/dev/null 2>&1; assert "--to 만 → 2" 2 "$?"
assert "첫 커밋도 된다 (부모 없음)" 4 "$(rs scope --json --commit "$(git rev-list --max-parents=0 HEAD)" | jq_py "len(d['reviewable'])+len(d['excluded'])")"

echo "[기준] 내장 대응표·프로젝트 규칙"
RJ=$(rs rule --json --from main keep.py renamed.ts x.svelte)
assert ".py → python.md" "python.md" "$(echo "$RJ" | jq_py "[g['rule'] for g in d if 'keep.py' in g['files']][0]")"
assert ".svelte → default.md" "default.md" "$(echo "$RJ" | jq_py "[g['rule'] for g in d if 'x.svelte' in g['files']][0]")"
mkdir -p .claude
echo '{"rules":[{"path":"**/*.py","rule":"PROJECT-ONLY"},{"path":"*.ts","rule":"TS-EXTRA","merge_system_rule":true}]}' > .claude/review-rules.json
RJ=$(rs rule --json --from main)
assert "프로젝트 규칙이 내장을 바꾼다" "PROJECT-ONLY" "$(echo "$RJ" | jq_py "[g['text'] for g in d if 'keep.py' in g['files']][0]")"
TS_TEXT=$(echo "$RJ" | jq_py "[g['text'] for g in d if 'renamed.ts' in g['files']][0]")
assert "merge_system_rule 은 내장 + 프로젝트" "2" "$(( $(grep -c 'TS-EXTRA' <<<"$TS_TEXT") + ($(wc -l <<<"$TS_TEXT") > 10) ))"
echo '{"rules":[{"path":"*.py"}]}' > .claude/review-rules.json
OUT=$(rs rule --from main 2>&1); CODE=$?
assert "rule 없는 항목 → 2" 2 "$CODE"
assert "원인 줄에 위치" 1 "$(grep -c 'rules\[0\]' <<<"$OUT")"
echo '{oops' > .claude/review-rules.json; rs rule --from main >/dev/null 2>&1; assert "깨진 JSON → 2" 2 "$?"
rm -rf .claude

echo "[범위] 리뷰 지적으로 고친 경계 (하위 폴더·중첩 저장소·중괄호·이름 변경)"
mkdir -p sub; printf 's\n' > sub/u.py; printf 't\n' > top.py
git init -q nested; printf 'n\n' > nested/n.txt
S=$(cd sub && python3 "$R" scope --json)
assert "하위 폴더에서 불러도 저장소 전체·전체 경로" "sub/u.py top.py" "$(echo "$S" | jq_py "' '.join(sorted(e['path'] for e in d['reviewable']))")"
assert "중첩 저장소는 멈추지 않고 뺀다" "일반 파일이 아님(하위 저장소·폴더·링크)" "$(echo "$S" | jq_py "[e['reason'] for e in d['excluded'] if e['path'].startswith('nested')][0]")"
assert "중괄호 패턴 --exclude '*.{py,md}'" "" "$(rs scope --json --exclude '*.{py,md}' | jq_py "' '.join(e['path'] for e in d['reviewable'])")"
rs scope --exclude 'a{b' >/dev/null; assert "짝 없는 중괄호도 오류 없이" 0 "$?"
assert "끝 / 패턴은 그 폴더 아래 전부" "top.py" "$(rs scope --json --exclude 'sub/' | jq_py "' '.join(e['path'] for e in d['reviewable'])")"
rm -rf sub top.py nested

echo "[장부] 빠짐·건너뜀·줄 번호"
ck() { echo "$1" | rs check --from main --json - ; }
OK='{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"skipped","reason":"이름만 바뀜"}],"findings":[{"path":"keep.py","start_line":2,"end_line":2}]}'
ck "$OK" >/dev/null; assert "완전한 장부 → 0" 0 "$?"
assert "coverage_rate 는 읽은 비율 (1/2, 건너뜀 제외)" "0.5" "$(ck "$OK" | jq_py "d['summary']['coverage_rate']")"
ck '{"files":[{"path":"keep.py","status":"reviewed"}]}' >/dev/null; assert "빠진 파일 → 1" 1 "$?"
assert "빠진 파일 이름을 댄다" 1 "$(ck '{"files":[{"path":"keep.py","status":"reviewed"}]}' | grep -c 'renamed.ts: 장부에 없습니다')"
ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"skipped"}]}' >/dev/null; assert "이유 없는 skipped → 1" 1 "$?"
ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"reviewed"}],"findings":[{"path":"keep.py","start_line":40}]}' >/dev/null; assert "파일 길이 넘는 줄 → 1" 1 "$?"
ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"reviewed"}],"findings":[{"path":"other.py","start_line":1}]}' >/dev/null; assert "범위 밖 파일 지적 → 1" 1 "$?"
W=$(ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"reviewed"}],"findings":[{"path":"keep.py","start_line":1}]}')
assert "바뀐 줄 밖 지적은 경고만 (통과)" "True 1" "$(echo "$W" | jq_py "str(d['ok'])+' '+str(len(d['warnings']))")"
echo '[]' | rs check --from main - >/dev/null; assert "장부 맨 위가 목록 → 1" 1 "$?"
echo 'nope' | rs check --from main - >/dev/null 2>&1; assert "JSON 아닌 장부 → 2" 2 "$?"
BAD=$(ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"reviewed"},"x"],"findings":[{"path":"keep.py","start_line":"two"},3]}')
assert "형식 틀린 항목은 추적 없이 오류 줄 3개" 3 "$(echo "$BAD" | jq_py "len(d['errors'])")"
assert "이름 변경 파일의 안 바뀐 줄 지적은 경고" 1 "$(ck '{"files":[{"path":"keep.py","status":"reviewed"},{"path":"renamed.ts","status":"reviewed"}],"findings":[{"path":"renamed.ts","start_line":1}]}' | jq_py "len(d['warnings'])")"
printf 'u1\nu2\n' > fresh.py
assert "untracked 는 전 줄이 바뀐 줄" "True 0" "$(echo '{"files":[{"path":"fresh.py","status":"reviewed"}],"findings":[{"path":"fresh.py","start_line":2}]}' | rs check --json - | jq_py "str(d['ok'])+' '+str(len(d['warnings']))")"
rm fresh.py

echo "[등록] 스킬·에이전트·프리셋·출처"
cd "$REPO_ROOT" || exit 1
assert "SKILL.md name" "review-coverage" "$(sed -n 's/^name: *//p' "$SKILL/SKILL.md" | head -1)"
assert "code-reviewer 가 설치 경로를 부른다" 1 "$(grep -c '\.claude/skills/review-coverage/scripts/review_scope.py' assets/agents/code-reviewer.md | awk '{print ($1>0)}')"
assert "code-reviewer 에 스크립트 없을 때 폴백 문구" 1 "$(grep -c '스크립트가 없으면' assets/agents/code-reviewer.md)"
assert "workflow 프리셋에 등록" 1 "$(grep -cE '^\s+review-coverage$' presets/workflow/harness.conf)"
assert "code-reviewer 와 같은 프리셋" 1 "$(grep -cE '^\s+code-reviewer$' presets/workflow/harness.conf)"
assert "대응표의 규칙 문서가 모두 있다" "" "$(python3 -c "
import json,os;d=json.load(open('$SKILL/references/rules/path_rule_map.json'))
print(' '.join(v for v in set(d['path_rule_map'].values())|{d['default_rule']} if not os.path.isfile('$SKILL/references/rules/'+v)))")"
assert "NOTICE 에 Apache-2.0 출처" 1 "$(grep -c 'Apache' "$SKILL/NOTICE.md" | awk '{print ($1>0)}')"
assert "전역 설치 명령 없음" 0 "$(cat "$SKILL"/scripts/*.py "$SKILL/SKILL.md" | grep -cE 'npm i(nstall)? -g|pip install')"

echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
