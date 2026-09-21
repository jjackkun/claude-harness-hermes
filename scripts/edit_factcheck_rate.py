#!/usr/bin/env python3
"""세션 트랜스크립트에서 **편집 전 사실 확인** 준수율을 센다. 훅이 아니라 계측기다 — 아무것도 막지 않는다.

`assets/rules/harness/rules.md` 는 "수정 전 import 그래프 1회 확인, 파일명 추론 금지" 를 요구한다.
그 요구가 실제로 지켜지는지 재는 자리. ECC 의 `gateguard-fact-force` 를 도입할지 판단하려고 2026-09-21 에 만들었고,
그때 전수 측정이 준수율 95.7% 를 내놓아 **훅을 만들지 않기로** 했다(docs/audits/2026-09-21-gateguard-fact-force-measurement.md).
다시 묻는 사람이 생기면 이 스크립트를 돌려 다시 재면 된다.

세는 규칙:
  - 대상은 **기존 파일 수정**(Edit·MultiEdit·NotebookEdit)뿐. 같은 세션에서 `Write` 로 방금 만든 파일은 뺀다 — 조사할 대상이 아니다.
  - "내용을 봤다" = `Read` 로 읽었거나, Bash 명령·검색 패턴에 그 경로·파일명이 등장했다.
    Bash 를 세는 것이 중요하다. `cat`·`sed -n` 으로 읽는 경우가 많아 `Read` 만 세면 준수율이 18.4% 로 과소 집계된다(같은 날 실측).
  - "importer 를 찾았다" = grep·rg·ack·ag 계열 명령/패턴에 그 파일명(또는 확장자 뗀 이름)이 있었다.

한계: 컨텍스트 압축·세션 재개로 앞선 조사가 다른 트랜스크립트에 있으면 "안 봤다" 로 읽힌다. `blind` 는 상한값이다.

사용:
  edit_factcheck_rate.py                     사람이 읽는 표
  edit_factcheck_rate.py --json              기계용
  edit_factcheck_rate.py --root DIR          트랜스크립트 디렉터리 지정(기본 ~/.claude/projects)
"""
import glob
import json
import os
import re
import sys

EDIT_TOOLS = ("Edit", "MultiEdit", "NotebookEdit")
SEARCH_CMD_RE = re.compile(r"\b(grep|rg|ack|ag)\b")
DEFAULT_ROOT = "~/.claude/projects"


def _line_tool_uses(line):
    """트랜스크립트 한 줄에서 (도구 이름, 입력) 들을 꺼낸다. 깨진 줄은 조용히 건너뛴다."""
    if '"tool_use"' not in line:
        return
    try:
        rec = json.loads(line)
    except ValueError:
        return
    content = (rec.get("message") or {}).get("content")
    for blk in content if isinstance(content, list) else []:
        if isinstance(blk, dict) and blk.get("type") == "tool_use" and isinstance(blk.get("input"), dict):
            yield blk.get("name", ""), blk["input"]


def _tool_uses(path):
    """트랜스크립트 한 건의 도구 호출을 순서대로 내놓는다."""
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        for line in fh:
            for use in _line_tool_uses(line):
                yield use


def _saw(file_path, seen, blobs):
    base = os.path.basename(file_path)
    return file_path in seen or any(file_path in b or base in b for b in blobs)


def _searched(file_path, blobs):
    base = os.path.basename(file_path)
    stem = base.rsplit(".", 1)[0]
    return any(SEARCH_CMD_RE.search(b) and (base in b or (len(stem) > 3 and stem in b)) for b in blobs)


def _note_edit(file_path, tally, seen, blobs, made):
    """편집 한 건을 집계에 반영한다. 같은 세션에서 만든 파일은 분모에서 뺀다."""
    if file_path in made:
        tally["self_made"] += 1
        return
    saw = _saw(file_path, seen, blobs)
    tally["edits"] += 1
    tally["saw_content"] += saw
    tally["saw_importer"] += _searched(file_path, blobs)
    tally["blind"] += not saw


def _note_investigation(name, inp, file_path, seen, blobs, made):
    """조사 흔적을 쌓는다 — 읽은 경로(seen)와 검색·명령 문자열(blobs)."""
    if name == "Write" and file_path:
        made.add(file_path)
        seen.add(file_path)
    elif name == "Read" and file_path:
        seen.add(file_path)
    elif name in ("Grep", "Glob"):
        for key in ("pattern", "path", "glob"):
            if inp.get(key):
                blobs.append("grep " + str(inp[key]))
    elif name == "Bash" and inp.get("command"):
        blobs.append(str(inp["command"]))


def _scan_session(path, tally):
    seen, blobs, made = set(), [], set()
    for name, inp in _tool_uses(path):
        file_path = str(inp.get("file_path") or inp.get("notebook_path") or "")
        if name in EDIT_TOOLS:
            if file_path:
                _note_edit(file_path, tally, seen, blobs, made)
        else:
            _note_investigation(name, inp, file_path, seen, blobs, made)


def measure(root=DEFAULT_ROOT):
    """{transcripts, edits, self_made, saw_content, saw_importer, blind, rates} — 읽기 전용."""
    paths = sorted(glob.glob(os.path.join(os.path.expanduser(root), "*", "*.jsonl")))
    tally = {"edits": 0, "self_made": 0, "saw_content": 0, "saw_importer": 0, "blind": 0}
    for path in paths:
        _scan_session(path, tally)
    total = tally["edits"] or 1
    tally["transcripts"] = len(paths)
    tally["rates"] = {k: round(100.0 * tally[k] / total, 1) for k in ("saw_content", "saw_importer", "blind")}
    return tally


def _render(data):
    return "\n".join([
        "트랜스크립트 %d개 · 기존 파일 수정 %d건 (같은 세션에서 만든 파일 수정 %d건 제외)"
        % (data["transcripts"], data["edits"], data["self_made"]),
        "  내용을 본 뒤 고쳤다        %6d  %5.1f%%" % (data["saw_content"], data["rates"]["saw_content"]),
        "  importer 를 찾아봤다       %6d  %5.1f%%" % (data["saw_importer"], data["rates"]["saw_importer"]),
        "  맨눈 편집(상한값)          %6d  %5.1f%%" % (data["blind"], data["rates"]["blind"]),
        "※ 압축·재개로 앞선 조사가 다른 트랜스크립트에 있으면 맨눈으로 읽힌다 — 맨눈은 상한이다.",
    ])


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else DEFAULT_ROOT
    data = measure(root)
    print(json.dumps(data, ensure_ascii=False, indent=2) if "--json" in argv else _render(data))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 판정 불가는 2
        print("edit_factcheck_rate: %s" % exc, file=sys.stderr)
        sys.exit(2)
