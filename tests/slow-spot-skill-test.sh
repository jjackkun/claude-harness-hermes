#!/usr/bin/env bash
# slow-spot 스킬 (계획 2026-11-25-slow-spot-skill 목표 G1·G2·G4) — 모델 0, 네트워크 0.
# [프로파일] 심어 둔 느린 함수를 1위로 · [대조] 내용·모드·링크 변화와 잡음 무시 · [배치] 공장 전용
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/slow-spot"; S="$SKILL/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

echo "[프로파일] 외부 명령 20번 띄우는 함수 vs 셸 내장만 도는 함수"
cat > "$TMP/target.sh" <<'SH'
slow_fn() { local i; for i in $(seq 20); do python3 -c pass; done; }
fast_fn() { local i n=0; for ((i=0; i<20; i++)); do n=$((n+i)); done; }
fast_fn
slow_fn
echo done
SH
out="$(bash "$S/bash_profile.sh" "$TMP/t.trace" "$TMP/target.sh" 2>/dev/null)"; rc=$?
assert "스크립트 출력과 종료 코드가 그대로 지나간다" "done 0" "$out $rc"
python3 "$S/trace_agg.py" "$TMP/t.trace" > "$TMP/agg.txt"
assert "함수별 1위 = slow_fn" "slow_fn" "$(sed -n '/^== 함수별/{n;p}' "$TMP/agg.txt" | awk '{print $NF}')"
assert "명령별 표에 python3 ×20" 1 "$(grep -cE '×20 +python3$' "$TMP/agg.txt")"
echo "형식이 다른 줄" > "$TMP/bad.trace"
python3 "$S/trace_agg.py" "$TMP/bad.trace" > "$TMP/bad.txt"; rc=$?
assert "형식이 다른 파일은 종료 0 + 안내" "0 1" "$rc $(grep -c '추적 줄이 2개보다 적습니다' "$TMP/bad.txt")"
bash "$S/bash_profile.sh" "$TMP/x.trace" "$TMP/none.sh" 2>/dev/null; assert "없는 스크립트는 종료 2" 2 "$?"
printf 'g(){ echo err-in-g >&2; python3 -c pass; }\ng 2>"$1"\n' > "$TMP/redir.sh"
bash "$S/bash_profile.sh" "$TMP/r.trace" "$TMP/redir.sh" "$TMP/g.err" 2>/dev/null
assert "표준 오류를 돌린 함수 안 줄도 추적된다" 1 "$(grep -c '@g@ python3 -c pass' "$TMP/r.trace")"
assert "스크립트의 표준 오류는 추적과 섞이지 않는다" "err-in-g" "$(cat "$TMP/g.err")"

echo "[대조] 찍음 두 장"
D="$TMP/d"; mkdir -p "$D/sub" "$D/.git"
echo a > "$D/a.txt"; echo b > "$D/sub/b sp.txt"; echo t > "$D/stamp.log"; echo g > "$D/.git/HEAD"
ln -s "a.txt" "$D/link"; ln -s sub "$D/dirlink"
snap() { python3 "$S/snapshot.py" take "$D" "$TMP/$1" >/dev/null; }
dif() { python3 "$S/snapshot.py" diff "$TMP/$1" "$TMP/$2" "${@:3}" >/dev/null; echo $?; }
snap s1; snap s2
assert "같은 폴더 두 번 = 차이 0(종료 0)" 0 "$(dif s1 s2)"
assert ".git 은 찍지 않는다" 0 "$(grep -c '^\.git/' "$TMP/s1")"
assert "디렉터리 링크는 따라가지 않고 링크로 적는다" "1 0" "$(grep -c $'^dirlink\tL sub$' "$TMP/s1") $(grep -c '^dirlink/' "$TMP/s1")"
echo changed > "$D/sub/b sp.txt"; snap s3
assert "내용 변화(공백 든 이름) → 종료 1" 1 "$(dif s2 s3)"
assert "다른 경로 이름이 출력된다" 1 "$(python3 "$S/snapshot.py" diff "$TMP/s2" "$TMP/s3" | grep -c '~ 달라짐    sub/b sp.txt')"
chmod 755 "$D/a.txt"; snap s4
assert "모드 변화 → 종료 1" 1 "$(dif s3 s4)"
rm "$D/link"; ln -s "sub/b sp.txt" "$D/link"; snap s5
assert "링크 대상 변화 → 종료 1" 1 "$(dif s4 s5)"
echo t2 > "$D/stamp.log"; snap s6
assert "잡음만 바뀌면 --ignore 로 차이 0" 0 "$(dif s5 s6 --ignore '\.log$')"
assert "--ignore 없으면 잡음도 차이" 1 "$(dif s5 s6)"
assert "잘못된 정규식은 종료 2" 2 "$(dif s5 s6 --ignore '(')"

echo "[배치] 공장 전용"
assert "SKILL.md 의 name 이 폴더 이름과 같다" "slow-spot" "$(sed -n 's/^name: *//p' "$SKILL/SKILL.md" | head -1)"
assert "공장 .claude/skills 링크가 git 에 추적된다" 1 "$(git -C "$REPO_ROOT" ls-files .claude/skills/slow-spot | wc -l | tr -d ' ')"
assert "링크가 assets 를 가리킨다" "../../assets/skills/slow-spot" "$(readlink "$REPO_ROOT/.claude/skills/slow-spot")"
assert "어느 프리셋에도 없다(소우주 미배포)" 0 "$(grep -rlw 'slow-spot' "$REPO_ROOT/presets" | wc -l | tr -d ' ')"
assert "README 공장 전용 스킬 표에 1줄" 1 "$(grep -c '^| `slow-spot` |' "$REPO_ROOT/README.md")"
assert "run-all 에 등록" 1 "$(grep -cE '^\s+slow-spot-skill-test\.sh$' "$REPO_ROOT/tests/run-all.sh")"
assert "전역 설치 명령 없음" 0 "$(grep -rcE 'pip install|apt(-get)? install|npm i(nstall)? -g' "$S" | awk -F: '{s+=$2} END{print s+0}')"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
