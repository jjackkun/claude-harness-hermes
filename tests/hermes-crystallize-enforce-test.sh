#!/usr/bin/env bash
# 결정화 판정 — "기계 검사로 만들 수 있나" 를 먼저 묻는다 (계획 2026-11-19-crystallize-check-first, G1~G6).
#
#   [a] checkable:hook        → 스킬 1 · 본문에 ENFORCE 없음 · 장부 checkable/hook · crystallized 1
#   [b] covered:R-size        → 스킬 0 · crystallized -1 · 장부 covered/R-size
#   [c] covered:R-없는이름    → prose 로 강등 · 스킬 1 · 장부 note=unknown-gate
#   [d] 판정 줄 없음          → prose · 스킬 1 · 장부 note=missing
#   [e] 프롬프트에 게이트 목록 → 프로젝트 pre-commit 의 "차단" 줄 게이트가 들어간다
#   [f] 실제 pre-commit 원본    → 차단 게이트(R-size·R-secret·R-cx·R-privacy)만, 측정 훅(R-out)·경고(R-cov)는 없다
#   [g] list                  → 장부의 checkable 만, 스킬 파일을 다시 써도 같다
#   [h] 개인 층(--agent)      → covered 면 개인 skills 폴더에 0
#   [i] split_verdict 경계    → 펜스 뒤 판정 · 대소문자/백틱 · 본문 중간 예시 줄 보존 · 첫 줄 판정
#   [j] 장부 쓰기 실패        → 결정화는 계속(스킬 파일 생김, 다음 키도 처리)
#
# `claude` 는 PATH 가짜 실행파일(MOCK_VERDICT 줄을 붙여 출력, 받은 프롬프트는 $T/prompt.txt).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/scripts"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > "$MOCK_PROMPT_FILE"
printf '# %s\n<!-- hermes:auto-generated version:1 created:2026-11-19 -->\n\n## 규칙\n- [ ] 규칙\n' "${MOCK_TITLE:-enforce-test}"
[[ -n "${MOCK_VERDICT:-}" ]] && printf '\n%s\n' "$MOCK_VERDICT"
exit 0
MOCK
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH" MOCK_PROMPT_FILE="$T/prompt.txt"

new_proj() { # new_proj <dir> — 실제 초기화 도구 + 차단 게이트 두 개짜리 pre-commit (git 저장소 아님 → .git/hooks 폴백)
  local d="$1"; mkdir -p "$d/.git/hooks"
  HOME="$T/home" python3 "$S/hermes-init.py" --project "$d" >/dev/null 2>&1
  printf '#!/usr/bin/env bash\n#   차단 2 — R-size R-secret\n#   경고 1 — R-cov\n' > "$d/.git/hooks/pre-commit"
}
run() { # run <proj> <key> <verdict> [title] [extra args...]
  local p="$1" k="$2" v="$3" title="${4:-$2}"; shift 4 2>/dev/null || shift $#
  MOCK_TITLE="$title" MOCK_VERDICT="$v" python3 "$S/hermes-crystallize.py" \
    --db "$p/.hermes/state.db" --crystallize "$k" --project-dir "$p" "$@" 2>&1
}
nfiles() { ls "$1" 2>/dev/null | grep -c '\.md$' | tr -d ' '; }
cryst() { python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('SELECT crystallized FROM pattern_count WHERE pattern_key=?',(sys.argv[2],)).fetchone()[0])" "$1/.hermes/state.db" "$2"; }
ledger() { # ledger <proj> <key> <field> — 그 키의 마지막 장부 줄 값
  python3 - "$1/.hermes/enforce-verdicts.jsonl" "$2" "$3" <<'PY'
import json, sys
path, key, field = sys.argv[1:4]
rows = []
try:
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
except FileNotFoundError:
    pass
rows = [r for r in rows if r.get("key") == key]
print(rows[-1].get(field, "") if rows else "<없음>")
PY
}

P="$T/p"; new_proj "$P"; SK="$P/.hermes/skills"

echo "[a] checkable:hook"
OUT=$(run "$P" "커밋-전-확인" "ENFORCE: checkable:hook" "commit-check")
assert "스킬 파일 1" "1" "$(nfiles "$SK")"
assert "본문에 ENFORCE 줄 없음" "0" "$(cat "$SK/commit-check.md" 2>/dev/null | grep -c ENFORCE)"
assert "crystallized 1" "1" "$(cryst "$P" "커밋-전-확인")"
assert "장부 verdict" "checkable" "$(ledger "$P" "커밋-전-확인" verdict)"
assert "장부 kind" "hook" "$(ledger "$P" "커밋-전-확인" kind)"
assert "장부 skill_file" "commit-check.md" "$(basename "$(ledger "$P" "커밋-전-확인" skill_file)")"

echo "[b] covered:R-size"
OUT=$(run "$P" "파일-분리" "ENFORCE: covered:R-size" "split-file")
assert "스킬 파일 늘지 않음" "1" "$(nfiles "$SK")"
assert "crystallized -1" "-1" "$(cryst "$P" "파일-분리")"
assert "장부 verdict" "covered" "$(ledger "$P" "파일-분리" verdict)"
assert "장부 gate" "R-size" "$(ledger "$P" "파일-분리" gate)"
assert "COVERED 출력" "1" "$(grep -c 'COVERED:파일-분리' <<<"$OUT")"

echo "[c] covered:R-없는이름 → prose 강등"
OUT=$(run "$P" "없는-게이트" "ENFORCE: covered:R-nowhere" "no-gate")
assert "스킬 파일 생김" "2" "$(nfiles "$SK")"
assert "장부 verdict" "prose" "$(ledger "$P" "없는-게이트" verdict)"
assert "장부 note" "unknown-gate" "$(ledger "$P" "없는-게이트" note)"

echo "[d] 판정 줄 없음 → prose"
OUT=$(run "$P" "판정-없음" "" "no-verdict")
assert "스킬 파일 생김" "3" "$(nfiles "$SK")"
assert "장부 verdict" "prose" "$(ledger "$P" "판정-없음" verdict)"
assert "장부 note" "missing" "$(ledger "$P" "판정-없음" note)"

echo "[e] 프롬프트에 게이트 목록"
assert "R-size 가 프롬프트에" "1" "$(grep -c 'R-size' "$T/prompt.txt" | awk '{print ($1>0)}')"
assert "R-secret 이 프롬프트에" "1" "$(grep -c 'R-secret' "$T/prompt.txt" | awk '{print ($1>0)}')"
assert "ENFORCE 지시가 프롬프트에" "1" "$(grep -c 'ENFORCE:' "$T/prompt.txt" | awk '{print ($1>0)}')"

echo "[f] 실제 pre-commit 원본의 차단 게이트"
GATES=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import hermes_enforce_verdict as v; print(' '.join(v.gate_names(sys.argv[2])))" \
  "$S" "$ROOT/assets/hooks/pre-commit.sh" 2>&1)
for g in R-size R-secret R-cx R-privacy; do
  assert "$g 찾음" "1" "$(tr ' ' '\n' <<<"$GATES" | grep -cx "$g")"
done
for g in R-out R-cov; do
  assert "$g 없음(차단 아님)" "0" "$(tr ' ' '\n' <<<"$GATES" | grep -cx "$g")"
done

echo "[g] list — checkable 만, 스킬 파일을 다시 써도 같다"
run "$P" "시험-먼저" "ENFORCE: checkable:test" "test-first" >/dev/null
LIST=$(python3 "$S/hermes_enforce_ledger.py" list --hermes-dir "$P/.hermes" 2>&1)
assert "후보 2줄" "2" "$(grep -c 'checkable' <<<"$LIST")"
printf '# commit-check\n\n## 규칙\n- [ ] 진화로 다시 씀\n' > "$SK/commit-check.md"
LIST2=$(python3 "$S/hermes_enforce_ledger.py" list --hermes-dir "$P/.hermes" 2>&1)
assert "다시 써도 같은 목록" "$LIST" "$LIST2"

echo "[h] 개인 층 covered"
OUT=$(run "$P" "agent:a1:파일-분리" "ENFORCE: covered:R-size" "agent-split" --agent a1)
assert "개인 skills 0" "0" "$(nfiles "$P/.hermes/agents/a1/skills")"
assert "장부 verdict" "covered" "$(ledger "$P" "agent:a1:파일-분리" verdict)"

echo "[i] split_verdict 경계"
while IFS= read -r line; do
  case "$line" in OK::*) assert "${line#OK::}" "ok" "ok" ;; FAIL::*) assert "${line#FAIL::}" "ok" "fail" ;; esac
done < <(python3 - "$S" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import hermes_enforce_verdict as v
G = ["R-size", "R-secret"]
def check(name, cond): print(("OK::" if cond else "FAIL::") + name)
r = v.split_verdict("```markdown\n# t\n- [ ] a\n```\nENFORCE: prose", G)
check("펜스 뒤 판정 → 닫는 펜스 안 남음", r[0] == "prose" and not r[3].rstrip().endswith("```"))
r = v.split_verdict("# t\n\nENFORCE: covered:R-Size", G)
check("대소문자 무시 → 정본 이름", r[:2] == ("covered", "R-size"))
r = v.split_verdict("# t\n\n`ENFORCE: covered:`R-secret``", G)
check("백틱 감싼 판정", r[:2] == ("covered", "R-secret"))
r = v.split_verdict("# t\n예:\nENFORCE: checkable:hook\n- [ ] b\nENFORCE: prose", G)
check("본문 중간 예시 줄 보존", r[0] == "prose" and "ENFORCE: checkable:hook" in r[3])
r = v.split_verdict("ENFORCE: checkable:test\n# t\n- [ ] a", G)
check("첫 줄 판정도 인식·제거", r[0] == "checkable" and r[3].startswith("# t"))
PY
)

echo "[j] 장부 쓰기 실패 → 결정화 계속"
Q="$T/q"; new_proj "$Q"; mkdir -p "$Q/.hermes/enforce-verdicts.jsonl"   # 파일 자리에 폴더 → 열기 실패
OUT=$(MOCK_VERDICT="ENFORCE: prose" python3 "$S/hermes-crystallize.py" --db "$Q/.hermes/state.db" \
  --crystallize "첫째-키,둘째-키" --project-dir "$Q" 2>&1)
assert "DONE 2건" "2" "$(grep -c 'DONE:' <<<"$OUT")"
assert "실패를 남김" "1" "$(grep -c '장부 쓰기 실패' <<<"$OUT" | awk '{print ($1>0)}')"

echo "  통과 $PASS / 실패 $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
