#!/usr/bin/env python3
"""`@` 입력 목록 제안(Claude Code fileSuggestion) — `@hag…` 이면 명부 에이전트, 그 밖은 파일 경로.

왜(2026-09-28): 새 트리거 문자는 없고 `@` 뒤 기호는 목록이 안 뜬다(실측). fileSuggestion 은 `@` 파일 목록을
이 스크립트 출력으로 **교체**하므로(settings-reference "fileSuggestion"), 약속어 `hag` 로 시작하면 명부를 내고
나머지는 기본 목록을 대신할 만큼 파일을 찾아 준다.
입력: stdin {"query": "...", "cwd": "..."} · 출력: 한 줄에 하나, 최대 15줄 · 어떤 오류에도 exit 0(목록이 비는 것뿐).
명부 줄 `<이름> · <분야/직급/조직> · hag:<slug>` — 고르면 `@"…"` 로 들어가고 보낸 뒤 훅이 hag:<slug> 를 읽는다.
계획: docs/exec-plans/completed/2026-09-28-hermes-chat.md 목표 6
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_roster_pick import find_project, match, org_label, pickable  # noqa: E402
from hermes_hag_rooms import RoomsError, list_rooms  # noqa: E402

HAG_PREFIX = "hag"
MAX_LINES = 15                    # 문서의 상한(settings-reference fileSuggestion)
_SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build"}
_WALK_CAP = 20000                 # git 이 아닌 폴더에서 훑는 파일 수 상한 — 5초 타임아웃 안에 끝나게


# 명령 줄 — 첫 글자가 서로 달라야 Tab 이 한 줄을 통째로 넣는다(2026-09-28 실측). 계획 hag-rooms-ui 목표 1.
COMMAND_LINES = ("켜기 · 상태줄에 방 줄 · hag-on", "끄기 · 방 줄 숨기기 · hag-off",
                 "초대 · 에이전트 방 열기 · hag-add", "닫기 · 방 닫기(대화는 남음) · hag-rm")
_STATUS = {"idle": "대기", "busy": "일하는 중"}


def _rooms(project: str) -> list:
    try:
        return list_rooms(project)
    except RoomsError:
        return []                     # 목록을 못 읽으면 방 없음으로 — 초대 명령이 실제로 열 때 다시 확인한다


def _add_lines(project: str) -> list:
    taken = {r["slug"] for r in _rooms(project)}
    return [f"{a['name']} · {org_label(a)} · hag-add:{a['slug']}" for a in pickable(project) if a["slug"] not in taken]


def _rm_lines(project: str) -> list:
    return [f"{r['agent']}방 · {_STATUS.get(r['status'], r['status'] or '?')} · hag-rm:{r['id']}" for r in _rooms(project)]


def hag_lines(project: str, query: str) -> list:
    """`@hag…` 목록: hag-add → 방 없는 사람 · hag-rm → 열린 방 · hag- → 명령 · hag 만 → 명령 + 명부 · hag<이름> → 명부만."""
    if query.startswith("hag-add"):
        return _add_lines(project)
    if query.startswith("hag-rm"):
        return _rm_lines(project)
    if query.startswith("hag-"):
        return [c for c in COMMAND_LINES if c.rsplit(" · ", 1)[1].startswith(query)]
    rest = query[len(HAG_PREFIX):]
    return roster_lines(project, rest) if rest else list(COMMAND_LINES) + roster_lines(project, rest)


def roster_lines(project: str, rest: str) -> list:
    people = pickable(project)
    rest = rest.lstrip(":").strip()
    chosen = (match(people, rest) or people) if rest else people
    # 이름이 앞 — 줄마다 첫 글자가 같으면 Tab 이 "공통 앞부분 완성" 으로 `hag:` 만 넣는다(2026-09-28 실측)
    return [f"{a['name']} · {org_label(a)} · {HAG_PREFIX}:{a['slug']}" for a in chosen]


def _git_files(root: str) -> list:
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard"],
                             capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return []
    return out.stdout.splitlines() if out.returncode == 0 else []


def _walk_files(root: str) -> list:
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS]
        found += [os.path.relpath(os.path.join(base, f), root) for f in files]
        if len(found) >= _WALK_CAP:
            break
    return found


def _score(q: str, path: str):
    """큰 값이 앞. 맞지 않으면 None — 이름 포함 > 경로 포함 > 흩어진 글자."""
    p, name = path.lower(), os.path.basename(path).lower()
    if q in name:
        return 3000 + (500 if name.startswith(q) else 0) - len(path)
    if q in p:
        return 2000 - len(path)
    pos, gaps = -1, 0
    for ch in q:
        nxt = p.find(ch, pos + 1)
        if nxt < 0:
            return None
        gaps += nxt - pos - 1
        pos = nxt
    return 1000 - gaps - len(path)


def file_lines(cwd: str, query: str) -> list:
    root = cwd if os.path.isdir(cwd) else os.getcwd()
    paths = _git_files(root) or _walk_files(root)
    q = query.lower()
    if not q:
        return sorted(paths, key=lambda x: (x.count("/"), x))[:MAX_LINES]
    scored = [(s, x) for x in paths for s in [_score(q, x)] if s is not None]
    return [x for _, x in sorted(scored, key=lambda t: (-t[0], t[1]))[:MAX_LINES]]


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    query, cwd = str(data.get("query") or ""), str(data.get("cwd") or os.getcwd())
    project = find_project(cwd)
    if project and query.lower().startswith(HAG_PREFIX):
        lines = hag_lines(project, query.lower())
    else:
        lines = file_lines(cwd, query)
    print("\n".join(lines[:MAX_LINES]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
