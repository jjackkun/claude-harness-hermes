#!/usr/bin/env python3
"""Bash 명령 한 줄에서 **모양**만 뽑는다 — 값·인자는 읽어도 돌려주지 않는다. 순수 함수, 파일·네트워크 없음.

R-out 의 `cmd:<머리>` 는 `cd X &&` 를 걷어낸 첫 단어라, 한 호출에 여러 명령을 묶으면 바이트를 낸 명령이 가려진다
(tool-output-budget §7-6 정정). 모양을 남기면 "묶음이 큰 출력을 내는가" 를 상시 볼 수 있다.

  seg    최상위 명령 수 — 따옴표·괄호·heredoc 본문 밖의 `; && || &` 와 줄바꿈으로 가른 덩어리.
         맨 앞의 `cd X` 접두와 `VAR=값` 만 있는 덩어리는 세지 않는다.
  pipe   따옴표·괄호 밖의 `|` 수(`||` 제외)
  hd     heredoc(`<<TAG`)이 있으면 1 — 본문 줄은 명령이 아니고, 끝 표시 줄 뒤의 명령은 센다
  heads  각 명령(파이프 단계 포함)의 머리, 최대 6개. 머리는 첫 단어의 basename(인터프리터면 둘째 단어까지).
         **`[A-Za-z0-9_.+-]` 밖의 글자가 든 머리는 `?`** — 따옴표·치환·괄호가 머리 자리에 와도 값이 새지 않는다.

계획: docs/exec-plans/completed/2026-10-01-out-shape-agent-fields.md 목표 1 · 2 · 3

공개: shape_of · fields_text · second_word(R-out `cmd:<머리>` 도 같은 규칙으로 — 백로그 r-out-path-head-second-word)
"""

import re
import shlex

MAX_HEADS = 6        # detail 길이를 묶는다 — 6개 × 48자 + 고정 글자로 약 400자 이내
MAX_WORD = 48
MAX_INPUT = 16384    # 이보다 긴 명령은 앞부분만 본다 — detail 상한(약 400자)에 필요한 머리는 앞에 있고, 수십만 자 한 줄이 훅을 늦추지 않게
# 둘째 단어(부명령·스크립트)는 **알려진 것만** 붙인다. 아무 단어나 붙이면 `python3 <토큰모양>` 처럼 인자가 새고,
# 훅 head_of 의 path 머리에는 같은 노출이 남아 있다(이 모듈이 더 엄격하다 — 백로그 참고).
_SCRIPT_RUNNERS = ("python3", "python", "bash", "sh", "node")
_SCRIPT_EXT = (".py", ".sh", ".js", ".mjs", ".ts")
_SUBCOMMANDS = {
    "git": ("status", "diff", "log", "show", "add", "commit", "push", "pull", "checkout", "branch", "merge", "rebase",
            "fetch", "clone", "stash", "reset", "tag", "remote", "rev-parse", "ls-files", "ls-remote", "update-ref",
            "fsck", "worktree", "config", "apply", "cherry-pick", "restore", "switch", "grep", "mv", "rm", "init",
            "check-ignore", "reflog"),
    "npm": ("run", "test", "install", "ci", "build", "start", "exec", "lint"),
    "pnpm": ("run", "test", "install", "build", "start", "exec", "dlx", "add", "lint", "dev"),
    "yarn": ("run", "test", "install", "build", "start", "add", "lint", "dev"),
    "make": ("test", "build", "clean", "install", "all", "lint", "check"),
    "cargo": ("build", "test", "run", "check", "fmt", "clippy", "bench"),
    "go": ("build", "test", "run", "mod", "vet", "fmt"),
    "docker": ("ps", "run", "exec", "build", "logs", "compose", "images", "pull", "stop", "rm"),
    "uv": ("run", "pip", "sync", "add", "venv"),
    "poetry": ("run", "install", "add"),
}
_WORD_OK = re.compile(r"^[A-Za-z0-9_.+-]+$")
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_SEP = re.compile(r"&&|\|\||;|(?<![<>&])&(?![>&])")
_PIPE = re.compile(r"(?<!\|)\|(?!\|)")
# 따옴표·$( ) 안의 `<<` 도 연산자로 본다(보수적) — 놓치면 본문 줄의 첫 단어가 머리로 샌다(리뷰 Block).
# 잘못 잡아 본문으로 오인하면 명령 일부를 못 세지만 값은 새지 않는다. `<<<` 는 here-string 이라 제외.
_HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
_CLOSERS = re.compile(r"[)}\"'`\s]*")     # `)"` 처럼 닫는 글자뿐인 덩어리는 명령이 아니다


def _mask_quotes(text: str) -> str:
    """따옴표·백틱 안쪽을 'x' 로 가린 같은 길이의 글자(구분자 판정용). 백슬래시 다음 글자도 가린다."""
    out, quote, esc = [], None, False
    for ch in text:
        if esc:
            out.append("x")
            esc = False
        elif ch == "\\":
            out.append("x")
            esc = True
        elif quote:
            out.append(ch if ch == quote else "x")
            quote = None if ch == quote else quote
        elif ch in "\"'`":
            out.append(ch)
            quote = ch
        else:
            out.append(ch)
    return "".join(out)


def _mask_groups(text: str) -> str:
    """바깥 괄호 `( … )` 안쪽을 'x' 로 가린다. `$( … )` 도 같은 괄호라 함께 가려진다."""
    out, depth = [], 0
    for ch in text:
        if ch == ")" and depth:
            depth -= 1
        out.append("x" if depth else ch)
        if ch == "(":
            depth += 1
    return "".join(out)


def _mask(text: str) -> str:
    return _mask_groups(_mask_quotes(text))


def _split_on(pattern, text: str) -> list:
    """가린 글자에서 pattern 위치를 찾아 원문을 가른다."""
    masked, pieces, start = _mask(text), [], 0
    for m in pattern.finditer(masked):
        pieces.append(text[start:m.start()])
        start = m.end()
    pieces.append(text[start:])
    return pieces


def _word(token: str) -> str:
    base = token.rsplit("/", 1)[-1]
    return base[:MAX_WORD] if _WORD_OK.match(base) else "?"


def _tokens(stage: str) -> list:
    try:
        return shlex.split(stage)
    except ValueError:                       # 따옴표가 안 닫힘 — 그냥 공백으로
        return stage.split()


def second_word(head: str, token: str) -> str:
    """둘째 단어 — 알려진 부명령이거나 스크립트 파일 이름일 때만. 그 밖에는 빈 글자(붙이지 않는다)."""
    if head in _SUBCOMMANDS:
        return token if token in _SUBCOMMANDS[head] else ""
    base = token.rsplit("/", 1)[-1]
    ok = head in _SCRIPT_RUNNERS and base.endswith(_SCRIPT_EXT) and _WORD_OK.match(base)
    return base[:MAX_WORD] if ok else ""


def _head(stage: str):
    """파이프 한 단계의 머리. 명령이 없으면 None."""
    toks = _tokens(stage)
    while toks and _ASSIGN.match(toks[0]):
        toks.pop(0)
    if not toks:
        return None
    head = _word(toks[0])
    second = second_word(head, toks[1]) if len(toks) > 1 else ""
    return head + (" " + second if second else "")


def _unit_heads(unit: str) -> list:
    """덩어리(파이프 포함)의 단계 머리들. 머리가 없는 단계는 뺀다. 닫는 글자뿐인 덩어리는 명령이 아니다."""
    if _CLOSERS.fullmatch(unit):
        return []
    return [h for h in (_head(stage) for stage in _split_on(_PIPE, unit)) if h]


def _heredoc_tags(line: str) -> list:
    """이 줄이 여는 heredoc 끝 표시들(한 줄에 여럿 가능, 순서대로 닫힌다)."""
    return [m.group(2) for m in _HEREDOC.finditer(line)]


def _continues(line: str) -> bool:
    """줄이 홀수 개의 `\` 로 끝나면 다음 줄로 이어진다(짝수 개는 `\\` 이스케이프)."""
    return (len(line) - len(line.rstrip("\\"))) % 2 == 1


def _scan(cmd: str):
    """(덩어리별 머리 목록, 파이프 수, heredoc 여부)."""
    units, pipes, hd, tags, pending = [], 0, 0, [], ""
    for raw in str(cmd or "").split("\n"):
        if tags:                                 # heredoc 본문 — 명령이 아니다(끝 표시 줄까지)
            tags = tags[1:] if raw.strip() == tags[0] else tags
            continue
        line = pending + raw
        if _continues(line):                     # 줄 끝 `\` — 셸은 다음 줄을 같은 명령으로 읽는다(안 잇으면 인자가 머리로 샌다)
            pending = line[:-1] + " "
            continue
        pending = ""
        tags = _heredoc_tags(line)
        hd = hd or int(bool(tags))
        pipes += len(_PIPE.findall(_mask(line)))
        units += [heads for heads in map(_unit_heads, _split_on(_SEP, line)) if heads]
    return units, pipes, hd


def shape_of(cmd) -> dict:
    """{"seg": 명령 수, "pipe": 파이프 수, "hd": 0|1, "heads": [머리…≤6]}. 명령이 문자열이 아니면 빈 모양."""
    if not isinstance(cmd, str):
        return {"seg": 0, "pipe": 0, "hd": 0, "heads": []}
    units, pipes, hd = _scan(cmd[:MAX_INPUT])
    while units and units[0] == ["cd"]:          # `cd X &&` 접두는 명령이 아니다 — head_of 와 같은 규칙
        units.pop(0)
    heads = [h for unit in units for h in unit][:MAX_HEADS]
    return {"seg": len(units), "pipe": pipes, "hd": hd, "heads": heads}


def _clean_agent(agent) -> str:
    return re.sub(r"[^A-Za-z0-9_.:-]", "", str(agent or ""))[:MAX_WORD] or "-"


def fields_text(shape: dict, agent="", sub: bool = False) -> str:
    """detail 뒤에 덧붙일 `key=value` 글자. **`heads=` 가 맨 끝**이고 줄 끝까지다(머리에 공백이 들 수 있다)."""
    heads = ",".join(shape.get("heads") or []) or "-"
    return (f"seg={shape.get('seg', 0)} pipe={shape.get('pipe', 0)} hd={shape.get('hd', 0)} "
            f"sub={int(bool(sub))} agent={_clean_agent(agent)} heads={heads}")
