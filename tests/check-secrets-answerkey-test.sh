#!/usr/bin/env bash
# 시크릿 차단기의 **정답지 선별**을 고정한다 — 무엇을 막고 무엇을 놓아주는지.
#
# 왜 이 테스트가 필요한가:
#   정답지(`.env` 실제 값) 대조는 라벨도 형태도 안 보고 값 그대로 찾는다. 강력한
#   대신 **넣지 말아야 할 값을 넣으면 차단기가 통째로 무용지물이 된다.**
#
#   실제로 겪은 일: 어느 프로젝트의 `*_ID` 값이 그 머신의 사용자명과 같아
#   모든 경로 문자열(`/home/<사용자>/…`)에 걸렸다. 결과가 오탐으로 뒤덮여
#   커밋이 통째로 막혔고, 그 상태의 차단기는 "끄고 싶은 것" 이 된다.
#
#   그래서 **아이디는 놓아주고 비밀번호·키는 잡는다** 를 여기서 못 박는다.
#   ⚠️ 통과만 보는 검증은 silent-skip 을 못 잡는다 — 실제 위반을 만들어 exit code 를 본다.
#
# 실행: bash tests/check-secrets-answerkey-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/assets/hooks/check-secrets.py"
VALUES_MOD="$REPO_ROOT/assets/scripts/hermes_secret_values.py"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }

# ⚠️ 실재하지 않는 값. 형태만 자격증명을 닮게 둔다 —
#    진짜를 닮지 않으면 규칙을 검사할 수 없다.
FAKE_ID="testuser42"
FAKE_PW='Zq7!kePw31x'

cd "$TMP" || exit 1
git init -q .
git config user.email t@t; git config user.name t

if [[ ! -f "$VALUES_MOD" ]]; then
  # 프리셋 배치 경로가 바뀌었을 수 있다. 찾아서 쓴다.
  VALUES_MOD=$(find "$REPO_ROOT" -name hermes_secret_values.py -not -path '*/.git/*' | head -1)
fi
[[ -f "$VALUES_MOD" ]] || { echo "hermes_secret_values.py 를 못 찾았다"; exit 1; }
cp "$VALUES_MOD" .

cat > .env <<EOF
SOME_ID=$FAKE_ID
SOME_PASSWORD=$FAKE_PW
EOF

# ① 아이디만 있는 파일 — 놓아줘야 한다
printf '경로 /home/%s/PROJECT 에서 작업한다\n' "$FAKE_ID" > id_only.md
# ② 비밀번호가 라벨 없이 산문에 박힌 파일 — 잡아야 한다
printf '로그인 비번 %s 입니다\n' "$FAKE_PW" > pw.md
# ③ 같은 줄에 자리표시자와 평문이 함께 — 잡아야 한다 (구간 면제 회귀 방지)
printf 'example 참고 · 실제 비번 %s\n' "$FAKE_PW" > mixed.md

git add id_only.md pw.md mixed.md
OUT=$(python3 "$CHECKER" 2>&1); CODE=$?

echo "check-secrets 정답지 선별"
[[ $CODE -ne 0 ]] && ok "위반을 차단했다 (exit $CODE)" || bad "위반을 통과시켰다"
grep -q 'pw.md'    <<<"$OUT" && ok "라벨 없는 평문을 잡았다"        || bad "라벨 없는 평문을 놓쳤다"
grep -q 'mixed.md' <<<"$OUT" && ok "자리표시자 옆 평문을 잡았다"     || bad "자리표시자가 줄 전체를 면제시켰다"
grep -q 'id_only'  <<<"$OUT" && bad "아이디를 오탐으로 잡았다"       || ok "아이디는 놓아줬다"

# ④ 정답지가 없어도 (모듈 미탐색) 차단기는 계속 돌아야 한다
rm -f hermes_secret_values.py .env
python3 "$CHECKER" >/dev/null 2>&1
[[ $? -le 2 ]] && ok "정답지가 없어도 죽지 않는다" || bad "정답지가 없을 때 죽었다"

exit $FAIL
