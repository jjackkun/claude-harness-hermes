#!/usr/bin/env bash
# LLM 전송 경계 마스킹 회귀 테스트 — 사람이 친 원문이 claude -p 프롬프트로 그대로 나가지 않는다.
#
# 배경: summarize·persona 는 LLM 에 보내기 전 redact() 를 거치지만, 검색 질의·evolve 피드백·
#   summon 과제·cron 메시지·loop 목표(goal.md 직접 편집분)·mesh gate 본문은 원문 그대로 나갔다
#   (계획 2026-10-16-redact-llm-input-gaps). 가짜 claude 가 받은 stdin 을 대조한다.
#   프롬프트 전체가 아니라 입력 필드만 가려야 한다 — redact 가 OS 사용자명을 가려 경로가 깨진다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/skills/demo"
CAPTURE="$TMP/prompt.txt"
cat > "$TMP/bin/claude" <<SH
#!/usr/bin/env bash
cat > "$CAPTURE"
echo "SPECIFIC"
SH
chmod +x "$TMP/bin/claude"
printf -- '---\nname: demo\ndescription: 데모 스킬\n---\n본문\n' > "$TMP/skills/demo/SKILL.md"

# 각 경계를 부르고, 가짜 claude 가 받은 프롬프트(또는 조립된 프롬프트)를 판정한다.
probe() {
  rm -f "$CAPTURE"
  PATH="$TMP/bin:$PATH" HERMES_CLAUDE_BIN="$TMP/bin/claude" CAPTURE="$CAPTURE" SKILLS="$TMP/skills" \
  PYTHONPATH="$SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" env -u HERMES_DISABLED python3 - "$1" "$SCRIPTS" <<'PY'
import getpass, importlib.util, os, sys
case, scripts = sys.argv[1], sys.argv[2]
TOK = "ghp_" + "Z" * 36                      # 런타임 조립 — 이 파일이 R-secret 에 걸리지 않게
MAIL = "leak.check" + "@" + "example.com"
SECRET = f"토큰 {TOK} 메일 {MAIL}"
PATH_KEEP = f"/home/{getpass.getuser()}/proj"

def load(fname, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(scripts, fname))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def captured():
    p = os.environ["CAPTURE"]
    return open(p, encoding="utf-8").read() if os.path.exists(p) else ""

if case == "search":
    load("hermes_search_fallback.py", "sf").haiku_fallback(SECRET, [os.environ["SKILLS"]], 3)
    out = captured()
elif case == "evolve":
    load("hermes-evolve-skill.py", "ev").generate_evolved_content("x/SKILL.md", "본문", SECRET, 1, 2)
    out = captured()
elif case == "summon":
    home_path = os.path.expanduser("~") + "/PROJECT/x/app.py"      # 과제에 흔히 쓰는 절대경로 — 사용자명이 든다
    out = load("hermes-summon.py", "su").build_task_prompt({"name": "QA", "agent_id": "qa"}, f"{home_path} 고쳐라 {SECRET}")
    if home_path not in out:
        print("PATH-BROKEN"); sys.exit()
elif case == "cron":
    out = load("hermes-manager.py", "mg").format_unread([(1, "loop", SECRET, "2026-10-16 10:00:00")])
elif case == "loop":
    out = load("hermes_loop_prompt.py", "lp").build_iteration_prompt(
        PATH_KEEP, PATH_KEEP + "/goal.md", f"{os.path.expanduser('~')}/PROJECT/goal-target {SECRET}",
        [(False, SECRET)], [SECRET], "none", 1, 3, "main")
    if PATH_KEEP not in out or f"{os.path.expanduser('~')}/PROJECT/goal-target" not in out:
        print("PATH-BROKEN"); sys.exit()
elif case == "mesh":
    load("hermes_mesh_gate.py", "mesh").stage2_is_general(SECRET)
    out = captured()
if not out:
    print("NO-PROMPT")
elif TOK in out or MAIL in out:
    print("LEAK")
else:
    print("CLEAN")
PY
}

check() {
  local got; got="$(probe "$1" 2>"$TMP/err.$1" | tail -1)"
  if [[ "$got" == "CLEAN" ]]; then ok "$2"
  else nope "$2 → $got $(tail -1 "$TMP/err.$1" 2>/dev/null)"; fi
}

check search "T1 검색 fallback 질의를 가려서 보낸다"
check evolve "T2 evolve --feedback 을 가려서 보낸다"
check summon "T3 summon --task 를 가려서 프롬프트에 싣는다"
check cron   "T4 cron 매니저 프롬프트의 미확인 메시지를 가린다"
check loop   "T5 loop 프롬프트의 목표·조건·로그를 가리고 경로는 보존한다"
check mesh   "T6 mesh gate 2단계 판정 본문을 가려서 보낸다"

echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
