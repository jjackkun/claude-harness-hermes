#!/usr/bin/env bash
# sveltekit-fastapi-scaffold 스킬의 scaffold.py 단위 시험 (모델 호출 0, 설치 없음).
#
# 왜 필요한가: 스킬은 사용자 프로젝트 루트에 수십 개 파일을 쓴다. 기존 파일을 덮어쓰거나
# 치환 안 된 {{자리}}·tsukiji 잔재를 남기거나, 이미 쓰는 포트를 고르면 그 프로젝트가 깨진다.
# 계획: docs/exec-plans/active/2026-11-13-sveltekit-fastapi-scaffold-plan.md §2
#
# 실행: bash tests/sveltekit-fastapi-scaffold-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/sveltekit-fastapi-scaffold"
SCAFFOLD="$SKILL/scripts/scaffold.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "[1] 빈 폴더에 생성"
out=$(python3 "$SCAFFOLD" --name demo-app --dest "$TMP/p1"); rc=$?
check "exit 0" '[[ $rc -eq 0 ]]'
check "템플릿 수만큼 파일 + .env 2개" \
  '[[ $(find "$TMP/p1" -type f | wc -l) -eq $(( $(find "$SKILL/templates" -name "*.tmpl" | wc -l) + 2 )) ]]'
check ".tmpl 접미사가 남지 않음" '[[ -z $(find "$TMP/p1" -name "*.tmpl") ]]'
check "dot. 접두가 . 으로 바뀜" '[[ -f "$TMP/p1/.gitignore" && -f "$TMP/p1/backend/.env.example" ]]'
check "치환 안 된 {{ 자리 0" '! grep -rq "{{[A-Z_]*}}" "$TMP/p1"'
check "기준 예시 이름(tsukiji) 잔재 0" '! grep -rqi "tsukiji" "$TMP/p1"'
check "프로젝트 이름이 package.json 에 들어감" 'grep -q "\"name\": \"demo-app\"" "$TMP/p1/package.json"'
check ".env 권한 600" '[[ $(stat -c %a "$TMP/p1/.env") == 600 && $(stat -c %a "$TMP/p1/backend/.env") == 600 ]]'
check "uv.sh 실행 권한" '[[ -x "$TMP/p1/scripts/uv.sh" ]]'
check "DATABASE_URL 이 asyncpg + DB_PORT 를 씀" \
  'port=$(grep ^DB_PORT= "$TMP/p1/.env" | cut -d= -f2); grep -q "^DATABASE_URL=postgresql+asyncpg://.*:$port/demo_app$" "$TMP/p1/backend/.env"'
check "포트 5개가 서로 다름" \
  '[[ $(grep -E "^(VITE_FRONTEND_PORT_|API_PORT_|DB_PORT)" "$TMP/p1/.env" | cut -d= -f2 | sort -u | wc -l) -eq 5 ]]'

echo "[2] 같은 폴더에 다시 실행 → 덮어쓰지 않음"
before=$(find "$TMP/p1" -type f -exec md5sum {} + | sort)
python3 "$SCAFFOLD" --name demo-app --dest "$TMP/p1" > "$TMP/rerun.json"; rc=$?
after=$(find "$TMP/p1" -type f -exec md5sum {} + | sort)
check "exit 2 (충돌)" '[[ $rc -eq 2 ]]'
check "충돌 목록에 package.json" 'grep -q "\"package.json\"" "$TMP/rerun.json"'
check "파일 내용 변화 0" '[[ "$before" == "$after" ]]'

echo "[3] 기존 .gitignore 는 충돌이 아니라 빠진 줄만 덧붙임"
mkdir -p "$TMP/p2"; printf 'node_modules/\nmy-own-line\n' > "$TMP/p2/.gitignore"
python3 "$SCAFFOLD" --name p-two --dest "$TMP/p2" > /dev/null; rc=$?
check "exit 0" '[[ $rc -eq 0 ]]'
check "사용자 줄 유지" 'grep -qx "my-own-line" "$TMP/p2/.gitignore"'
check "node_modules/ 중복 없음" '[[ $(grep -cx "node_modules/" "$TMP/p2/.gitignore") -eq 1 ]]'
check ".pgdata/ 추가됨" 'grep -qx ".pgdata/" "$TMP/p2/.gitignore"'

echo "[4] 형제 프로젝트 .env 가 쓰는 포트는 피함"
p1_ports=$(grep -E "^(VITE_FRONTEND_PORT_|API_PORT_|DB_PORT)" "$TMP/p1/.env" | cut -d= -f2 | sort)
p2_ports=$(grep -E "^(VITE_FRONTEND_PORT_|API_PORT_|DB_PORT)" "$TMP/p2/.env" | cut -d= -f2 | sort)
check "p1·p2 포트 겹침 0" '[[ -z $(comm -12 <(echo "$p1_ports") <(echo "$p2_ports")) ]]'

echo "[5] 잘못된 이름 거부"
python3 "$SCAFFOLD" --name Bad_Name --dest "$TMP/p3" >/dev/null 2>&1; rc=$?
check "exit 1" '[[ $rc -eq 1 ]]'
check "아무 파일도 안 만듦" '[[ ! -e "$TMP/p3" ]]'

echo "[6] --dry-run 은 쓰지 않음"
python3 "$SCAFFOLD" --name dry-one --dest "$TMP/p4" --dry-run > /dev/null; rc=$?
check "exit 0 + 폴더 없음" '[[ $rc -eq 0 && ! -e "$TMP/p4" ]]'

echo "[7] 기존 .env 는 값을 지키고 빠진 키만 덧붙임 (예: GEMINI_API_KEY 만 있던 프로젝트)"
mkdir -p "$TMP/p5"; printf 'GEMINI_API_KEY=keep-me\nDB_NAME=my_own_db\n' > "$TMP/p5/.env"
python3 "$SCAFFOLD" --name p-five --dest "$TMP/p5" > "$TMP/p5.json"; rc=$?
check "exit 0 (충돌 아님)" '[[ $rc -eq 0 ]]'
check "기존 키 값 유지" 'grep -qx "GEMINI_API_KEY=keep-me" "$TMP/p5/.env" && grep -qx "DB_NAME=my_own_db" "$TMP/p5/.env"'
check "같은 키를 두 번 쓰지 않음" '[[ $(grep -c "^DB_NAME=" "$TMP/p5/.env") -eq 1 ]]'
check "빠진 키(DB_PORT·API_PORT_DEV) 추가" 'grep -q "^DB_PORT=[0-9]" "$TMP/p5/.env" && grep -q "^API_PORT_DEV=[0-9]" "$TMP/p5/.env"'
check "요약의 포트가 .env 와 같음" 'grep -q "\"DB_PORT\": \"$(grep ^DB_PORT= "$TMP/p5/.env" | cut -d= -f2)\"" "$TMP/p5.json"'

echo
echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
