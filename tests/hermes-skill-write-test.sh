#!/usr/bin/env bash
# 올리기 전 판정 강화 — C 단계 (계획 docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 8).
#
#   1 write_skill_file: 지금 규칙으로 가린 본문을 원자적으로 쓴다 · 파일명이 아니라 본문 제목 때문에 이름에 비밀이 새지 않는다
#   2 결정화: 모델이 만든 스킬에 비밀이 있어도 파일에는 가려서 쓰고, 파일명에도 새지 않는다
#   3 진화: 고친 스킬도 가려서 쓴다
#   4 정적 확인: 결정화·진화가 스킬 파일을 직접 open(…, "w") 로 쓰지 않고 write_skill_file 만 쓴다
#
# 모델 호출 0(생성 함수를 대체한다). 실행: bash tests/hermes-skill-write-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID HERMES_SUMMON_NONCE CLAUDE_PROJECT_DIR HERMES_DISABLED
P="$T/proj"; mkdir -p "$P/.hermes"
git -C "$P" init -q
python3 "$S/hermes-init.py" --db "$P/.hermes/state.db" >/dev/null 2>&1
DB="$P/.hermes/state.db"
MAIL="kim.test@example.com"

echo "== 1. write_skill_file"
OUT="$(S="$S" P="$P" python3 -c "
import os, sys
sys.path.insert(0, os.environ['S'])
from hermes_skill_write import write_skill_file
path = os.path.join(os.environ['P'], 'x', 'y', 'a.md')
text = write_skill_file(path, '# 제목\n메일은 $MAIL 입니다\n', os.environ['P'])
body = open(path, encoding='utf-8').read()
print('masked', '$MAIL' not in body and '[REDACTED:EMAIL]' in body, text == body)
print('tmp-left', os.path.exists(path + '.tmp'))
write_skill_file(path, body, os.environ['P'])
print('idempotent', open(path, encoding='utf-8').read() == body)
")"
assert "본문의 비밀이 가려져 쓰이고 반환값과 파일이 같다" "masked True True" "$(grep '^masked' <<<"$OUT")"
assert "임시 파일이 남지 않는다" "tmp-left False" "$(grep '^tmp-left' <<<"$OUT")"
assert "이미 가린 본문을 다시 써도 그대로(멱등)" "idempotent True" "$(grep '^idempotent' <<<"$OUT")"

echo "== 2. 결정화"
OUT="$(S="$S" P="$P" DB="$DB" python3 -c "
import importlib.util, os, sys
sys.path.insert(0, os.environ['S'])
spec = importlib.util.spec_from_file_location('cry', os.path.join(os.environ['S'], 'hermes-crystallize.py'))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod._skip_reason = lambda *a, **k: None
mod.evidence_for = lambda *a, **k: ('근거', 3)
mod.register_skill = lambda *a, **k: None
mod.generate_skill_content = lambda *a, **k: '# $MAIL 계정 절차\n\n메일은 $MAIL 입니다\n'
mod.crystallize(os.environ['DB'], ['plot.md'], os.environ['P'])
d = os.path.join(os.environ['P'], '.hermes', 'skills')
names = os.listdir(d)
body = open(os.path.join(d, names[0]), encoding='utf-8').read()
print('count', len(names))
print('name-clean', not any(w in names[0] for w in ('kim', 'example')))
print('body-masked', '$MAIL' not in body and 'REDACTED' in body)
" 2>&1)"
assert "스킬 파일이 하나 만들어진다" "count 1" "$(grep '^count' <<<"$OUT")"
assert "파일명에 비밀이 새지 않는다" "name-clean True" "$(grep '^name-clean' <<<"$OUT")"
assert "본문의 비밀이 가려져 쓰인다" "body-masked True" "$(grep '^body-masked' <<<"$OUT")"

echo "== 3. 진화"
OUT="$(S="$S" P="$P" DB="$DB" python3 -c "
import importlib.util, os, sys
sys.path.insert(0, os.environ['S'])
spec = importlib.util.spec_from_file_location('evo', os.path.join(os.environ['S'], 'hermes-evolve-skill.py'))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
path = os.path.join(os.environ['P'], '.hermes', 'skills', 'evolve-target.md')
open(path, 'w', encoding='utf-8').write('# 대상\n<!-- hermes:auto-generated version:1 -->\n옛 본문\n')
mod.find_skill_by_keyword = lambda db, kw: (path, 'project', None)
mod.record_evolution = lambda *a, **k: None
mod.generate_evolved_content = lambda *a, **k: '# 대상\n<!-- hermes:auto-generated version:2 -->\n새 본문 – 메일 $MAIL\n'
print(mod.evolve_skill(os.environ['DB'], 'kw', '피드백'))
body = open(path, encoding='utf-8').read()
print('masked', '$MAIL' not in body and '[REDACTED:EMAIL]' in body)
" 2>&1)"
assert "진화가 성공한다" 1 "$(has "$OUT" "EVOLVED")"
assert "고친 본문의 비밀이 가려져 쓰인다" "masked True" "$(grep '^masked' <<<"$OUT")"

echo "== 4. 정적 확인"
for f in hermes-crystallize.py hermes-evolve-skill.py; do
  assert "$f 는 write_skill_file 을 쓴다" 1 "$([[ "$(grep -c 'write_skill_file' "$S/$f")" -ge 1 ]] && echo 1 || echo 0)"
  assert "$f 는 스킬 경로를 직접 open(…, \"w\") 하지 않는다" 0 "$(grep -c 'open(skill_path, "w"' "$S/$f")"
done

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
