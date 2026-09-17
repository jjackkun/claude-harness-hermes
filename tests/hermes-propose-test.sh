#!/usr/bin/env bash
# 제안 봉투·게이트·배달·상태 조회 (계획 docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 7·8·9·10·12).
#
#   - 금지 내용(티켓·경로·원문·이름) 4종은 봉투 작성 전 게이트가 거부(배달 불가)
#   - --deliver 없이는 gh 호출 0(봉투만 pending), --deliver 면 모의 gh 로 delivered
#   - --remote 인자는 거부(주소는 factory.json.remote_url 만, RV-16)
#   - 봉투 JSON 에 사람이 읽는 이름(명부 name·저장소 폴더 이름)이 없다(목표 8)
#   - 세션 시작 훅이 배달 결과(허가/거절/pending)를 알린다(목표 10)
#   - mesh_gate CLI 가 '사례 나열' 을 표시하고, 기존 스킬 파일을 건드리지 않는다(목표 12)
#
# 실행: bash tests/hermes-propose-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
H="$REPO_ROOT/assets/hooks"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}
has() { grep -qE "$2" <<<"$1" && echo yes || echo no; }

# 저장소 폴더 이름을 '팩토리소우주' 로 둔다(이름 게이트·목표8 grep 근거)
P="$TMP/팩토리소우주"; mkdir -p "$P/.hermes/skills" "$P/scripts"
cp "$S"/*.py "$P/scripts/"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
python3 -c "import json;json.dump({'remote_url':'git@github.com:jjackkun/claude-harness-hermes.git','installed_version':'abc123'},open('$P/.hermes/factory.json','w'))"

mkskill() { printf -- '---\nname: %s\ndescription: %s\n---\n# %s\n%s\n' "$2" "$3" "$2" "$4" > "$P/.hermes/skills/$2.md"; }
mkskill x retry-util  "지수 백오프 재시도" "재시도는 지수 백오프로 최대 3회 한다."
mkskill x tk-skill    "티켓 포함"          "JIRA-777 이슈에서 고친 방법."
mkskill x path-skill  "경로 포함"          "src/components/Login.tsx 를 고친다."
mkskill x raw-skill   "원문 포함"          "User: 이거 고쳐줘"$'\n'"내가 답함"
mkskill x name-skill  "이름 포함"          "팩토리소우주 저장소에서 쓰는 방법."
mkskill x dirpath-skill "확장자없는 경로"    "backend/app/execution 모듈을 고쳤다."
mkskill x nlticket-skill "자연어 티켓"     "이슈 4521 에서 드러난 문제."
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1

# 모의 gh
GHDIR="$TMP/bin"; mkdir -p "$GHDIR"
cat > "$GHDIR/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == "issue create" ]]; then echo "https://github.com/jjackkun/claude-harness-hermes/issues/7"; exit 0; fi
if [[ "$1 $2" == "issue view" ]]; then echo '{"state":"OPEN","labels":[{"name":"proposal"},{"name":"approved"}]}'; exit 0; fi
exit 1
SH
chmod +x "$GHDIR/gh"
prop() { python3 "$S/hermes-propose.py" --project "$P" --no-model "$@"; }

echo "== 1. 금지 내용 4종 거부 (목표 7) =="
prop --reason r new tk-skill   >/dev/null 2>&1; assert "티켓 포함 → 거부" 3 "$?"
prop --reason r new path-skill >/dev/null 2>&1; assert "파일 경로 → 거부" 3 "$?"
prop --reason r new raw-skill  >/dev/null 2>&1; assert "대화 원문 → 거부" 3 "$?"
prop --reason r new name-skill >/dev/null 2>&1; assert "사람이 읽는 이름 → 거부" 3 "$?"
prop --reason r new retry-util >/dev/null 2>&1; assert "깨끗한 스킬 → 통과(봉투 작성)" 0 "$?"
prop --reason "JIRA-555 때문에 넣음" new retry-util >/dev/null 2>&1; assert "reason 에 티켓 있으면 거부(누출 방지)" 3 "$?"
prop --reason "팩토리소우주 팀 요청" new retry-util >/dev/null 2>&1; assert "reason 에 이름 있으면 거부" 3 "$?"
prop --reason r new dirpath-skill >/dev/null 2>&1; assert "확장자 없는 디렉터리 경로 → 거부" 3 "$?"
prop --reason r new nlticket-skill >/dev/null 2>&1; assert "자연어 티켓(이슈 4521) → 거부" 3 "$?"

echo ""
echo "== 2. 배달 게이트 (목표 7·9) =="
NDELIV_BEFORE="$(ls "$P/.hermes/outbox" 2>/dev/null | wc -l)"
prop --reason r new retry-util >/dev/null 2>&1     # --deliver 없음
assert "--deliver 없으면 전부 pending(gh 호출 0)" 0 "$(python3 -c "import sys;sys.path.insert(0,'$S');from hermes_envelope import list_envelopes;print(len(list_envelopes('$P','delivered')))")"
prop --remote evil.example.com --reason r new retry-util >/dev/null 2>&1
assert "--remote 인자는 거부(RV-16)" 2 "$?"
PATH="$GHDIR:$PATH" prop --deliver --reason r new retry-util >/dev/null 2>&1
assert "--deliver + 모의 gh → delivered 1건 이상" yes "$([[ $(python3 -c "import sys;sys.path.insert(0,'$S');from hermes_envelope import list_envelopes;print(len(list_envelopes('$P','delivered')))") -ge 1 ]] && echo yes || echo no)"

echo ""
echo "== 3. 봉투에 사람이 읽는 이름 없음 (목표 8) =="
EID="$(python3 -c "import sys;sys.path.insert(0,'$S');from hermes_envelope import list_envelopes;print(list_envelopes('$P','delivered')[0]['envelope_id'])")"
EJSON="$P/.hermes/outbox/$EID/envelope.json"
assert "봉투에 저장소 폴더 이름 없음" 0 "$(grep -c '팩토리소우주' "$EJSON")"
assert "봉투에 universe_id 칸 있음" 1 "$([[ $(grep -c 'universe_id' "$EJSON") -ge 1 ]] && echo 1 || echo 0)"

echo ""
echo "== 4. 세션 시작 훅 배달 결과 알림 (목표 10) =="
# 상태 파일로 제어하는 mock gh: create→URL, view→$GHSTATE 의 JSON.
GHSTATE="$TMP/ghstate.json"
cat > "$GHDIR/gh" <<SH
#!/usr/bin/env bash
if [[ "\$1 \$2" == "issue create" ]]; then echo "https://github.com/jjackkun/claude-harness-hermes/issues/\$RANDOM"; exit 0; fi
if [[ "\$1 \$2" == "issue view" ]]; then cat "$GHSTATE"; exit 0; fi
exit 1
SH
chmod +x "$GHDIR/gh"
deliver_fresh() { PATH="$GHDIR:$PATH" prop --deliver --reason r new retry-util >/dev/null 2>&1; }
runhook() { echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" PATH="$GHDIR:$PATH" bash "$H/claude-sessionstart-outbox-status.sh" 2>&1; }

echo '{"state":"OPEN","labels":[{"name":"approved"}]}' > "$GHSTATE"
deliver_fresh
OUT="$(runhook)"
assert "허가 라벨 → 제거 안내" yes "$(has "$OUT" '소우주 확장분 제거 안내')"
assert "pending 봉투 개수 알림" yes "$(has "$OUT" '배달 못 한 봉투')"
assert "훅 stdout 무출력" "" "$(echo '{}' | CLAUDE_PROJECT_DIR="$P" PATH="$GHDIR:$PATH" bash "$H/claude-sessionstart-outbox-status.sh" 2>/dev/null)"

echo '{"state":"CLOSED","labels":[{"name":"rejected"}]}' > "$GHSTATE"
deliver_fresh
OUT2="$(runhook)"
assert "거절 라벨 → 확장으로 계속" yes "$(has "$OUT2" '확장으로 계속')"

# 라벨 감지 시 상태 전이 → 다음 세션엔 재알림 없음(LOW 수정)
echo '{"state":"OPEN","labels":[{"name":"approved"}]}' > "$GHSTATE"
deliver_fresh
R1="$(runhook)"; R2="$(runhook)"
assert "1회차 허가 알림 있음" yes "$(has "$R1" '제거 안내')"
assert "2회차엔 이미 approved 라 재알림 없음" no "$(has "$R2" '제거 안내')"

echo ""
echo "== 5. mesh_gate CLI 사례 나열 + 파일 불변 (목표 12) =="
SCEN="$TMP/scen.md"
printf '# scen\n1. 로그인 화면이면 A 하면\n2. 결제 화면일 때 B\n3. 홈이면 C 할 때\n' > "$SCEN"
V="$(python3 "$S/hermes_mesh_gate.py" --no-model "$SCEN" 2>&1)"
assert "사례 나열 표시(scenario_list=true)" yes "$(has "$V" '"scenario_list": true')"
BEFORE="$(md5sum "$P/.hermes/skills/retry-util.md" | awk '{print $1}')"
python3 "$S/hermes_mesh_gate.py" --no-model "$P/.hermes/skills/retry-util.md" >/dev/null 2>&1
assert "게이트는 스킬 파일을 건드리지 않음" "$BEFORE" "$(md5sum "$P/.hermes/skills/retry-util.md" | awk '{print $1}')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
