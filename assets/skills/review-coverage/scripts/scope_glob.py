"""경로 패턴 맞추기 — `**` · `*` · `?` · `{a,b}` 를 지원하는 gitignore 비슷한 glob."""
import re
from functools import lru_cache

_PREFIX_TOKENS = (("**/", "(?:.*/)?"), ("**", ".*"))
_CHAR_TOKENS = {"*": "[^/]*", "?": "[^/]"}


def _brace_ok(pattern):
    depth = 0
    for ch in pattern:
        depth += {"{": 1, "}": -1}.get(ch, 0)
        if depth < 0:
            return False
    return depth == 0


def _token(pattern, i, depth, braces):
    """(정규식 조각, 다음 위치, 중괄호 깊이 변화). braces 가 False 면 중괄호는 글자다."""
    for src, dst in _PREFIX_TOKENS:
        if pattern.startswith(src, i):
            return dst, i + len(src), 0
    ch = pattern[i]
    if ch in _CHAR_TOKENS:
        return _CHAR_TOKENS[ch], i + 1, 0
    brace_map = {"{": ("(?:", 1), "}": (")", -1), ",": ("|", 0)} if braces else {}
    if ch in brace_map and (ch == "{" or depth > 0):
        piece, delta = brace_map[ch]
        return piece, i + 1, delta
    return re.escape(ch), i + 1, 0


@lru_cache(maxsize=512)
def _compile(pattern):
    braces = _brace_ok(pattern)  # 짝이 안 맞으면 중괄호를 글자로 다룬다
    out, i, depth = [], 0, 0
    while i < len(pattern):
        piece, i, delta = _token(pattern, i, depth, braces)
        out.append(piece)
        depth += delta
    return re.compile("".join(out) + r"\Z")


def glob_match(pattern, path):
    """pattern 이 path 와 맞으면 True. '/' 없는 패턴은 아무 깊이의 이름·폴더와, '/' 로 끝나면 그 폴더 아래 전부와 맞춘다."""
    pattern = pattern.strip()
    if not pattern:
        return False
    body = pattern.rstrip("/")
    if "/" not in body:
        return bool(_compile("**/" + body).match(path) or _compile("**/" + body + "/**").match(path))
    body = body.lstrip("/")
    if pattern.endswith("/"):
        return bool(_compile(body + "/**").match(path))
    return bool(_compile(body).match(path))


def split_patterns(values):
    """['a,b', '*.{py,md}'] → ['a', 'b', '*.{py,md}'] — 중괄호 안 쉼표는 나누지 않는다."""
    out = []
    for value in values or ():
        depth, cur = 0, ""
        for ch in value:
            depth += {"{": 1, "}": -1}.get(ch, 0)
            if ch == "," and depth <= 0:
                out.append(cur)
                cur = ""
            else:
                cur += ch
        out.append(cur)
    return [p.strip() for p in out if p.strip()]
