#!/usr/bin/env bash
# UserPromptSubmit hook — `@hag` 약속어. 보낸 글에서 명부 에이전트 고르기를 알아보고 지시를 문맥에 넣는다.
# (계획 2026-09-28-hermes-chat 목표 6 — 입력 목록은 scripts/hermes_file_suggest.py 가 fileSuggestion 으로 띄운다)
#
# 세 모양:
#   [hag:call] `@"<이름> · … · hag:<slug>"`·`@hag:<slug>` — 목록에서 고른 줄. 그 slug 의 에이전트로 넘기게 한다(파일 첨부가 아니다).
#   [hag:list] `@hag` 만 — 명부 표를 그대로 보이게 한다.
#   `@hag` + 말(고른 항목 없음)은 아무것도 넣지 않는다 — 설계 논의 중 `@hag` 를 말한 것을 "맡기기" 로 두 번 오인했다(2026-09-28).
# 무시: 백틱 안(말하는 것 — 2026-09-28 `@hagent` 실측에서 잡은 오인) · 메일 주소(me@hag.com) · 붙은 말(@hagfile) ·
#       은퇴자·명부 밖 slug · hermes 프로젝트 아님. 항상 exit 0.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
[[ -f "$PROJECT/.hermes/agents.json" ]] || exit 0

# 명령(@hag-on/off/add/rm)이면 처리하고 프롬프트를 막는다 — 모델 답 없음(계획 2026-09-28-hag-rooms-ui, Step 1 실측).
# 안내 한 줄은 stderr 로(Claude Code 가 "blocked by hook" 아래에 보인다). 명령이 아니면 아래 고르기·명부로 넘어간다.
_msg="$(printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$PROJECT" python3 "$PROJECT/scripts/hermes_hag_commands.py" 2>/dev/null)"
if [[ $? -eq 2 && -n "$_msg" ]]; then
  printf '%s\n' "$_msg" >&2
  exit 2
fi
printf '%s' "$INPUT" | HAG_PROJECT="$PROJECT" PYTHONPATH="$PROJECT/scripts" python3 -c '
import json, os, re, subprocess, sys
from hermes_roster_pick import pickable
try:
    prompt = str(json.load(sys.stdin).get("prompt") or "")
except Exception:
    sys.exit(0)
prompt = re.sub(r"`[^`]*`", " ", prompt)
project = os.environ["HAG_PROJECT"]
people = {a["slug"]: a for a in pickable(project)}
picked = [people[s] for s in dict.fromkeys(re.findall(r"(?:@\"[^\"]*|(?<![\w.])@)hag:([a-z][a-z0-9-]{1,39})", prompt)) if s in people]
if picked:
    for name, slug in ((a["name"], a["slug"]) for a in picked):
        print(f"[hag:call] 사용자가 `@hag` 목록에서 명부 에이전트 {name}(을)를 골랐다. `@\"hag:…\"` 표기는 파일 첨부가 아니다.")
        print(f"- \"{name}에게 넘깁니다\" 한 줄을 쓰고, 표기를 뺀 나머지 말을 Agent 도구 subagent_type={slug} 로 넘긴다.")
    sys.exit(0)
bare = re.compile(r"(?<![\w@.])@hag(?![\w:-])", re.I)
if not bare.search(prompt):
    sys.exit(0)
if " ".join(bare.sub(" ", prompt).split()):
    sys.exit(0)                      # 말이 붙어 있으면 "@hag 이야기" 다 — 고른 항목만 넘긴다
res = subprocess.run([sys.executable, os.path.join(project, "scripts", "hermes-agent.py"), "--project", project, "roster"],
                     capture_output=True, text=True, timeout=10)
table = res.stdout.strip() if res.returncode == 0 else ""
if not table:
    print(f"[hag] 명부를 읽지 못했다: {res.stderr.strip() or res.returncode} — 이 줄을 사용자에게 그대로 보인다.")
    sys.exit(0)
print("[hag:list] 사용자가 `@hag` 로 명부를 보려 한다. 아래 표를 고치지 말고 코드 블록으로 보이고, 한 줄만 덧붙인다:")
print("부르는 법 — 입력창에 `@hag` 를 치고 화살표로 고른 뒤 엔터, 할 일을 이어 쓴다.")
print("```")
print(table)
print("```")
' 2>/dev/null || true
exit 0
