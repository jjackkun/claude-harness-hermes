#!/usr/bin/env python3
"""`organization.yaml` 이 쓰는 YAML **부분집합**의 파서·직렬화만 담당한다.

표준 모듈에 YAML 이 없고 헤르메스는 pip 의존을 두지 않는다(계획 §6). 그래서 조직 파일이 쓰는
모양만 읽고 쓴다. 앵커·다중 문서·여러 줄 문자열은 지원하지 않는다(필요 없음).

지원하는 모양:
  key: 스칼라                      # 문자열·정수·true/false/null
  key: [a, b, c]                  # 흐름 목록
  key:                            # 블록 목록
    - a
    - b
  key:                            # 2단 맵 — 값은 흐름 맵 또는 스칼라
    name: {unit_id: x, code: [src/**]}
    other: 값
  # 주석은 줄 어디서나

공개 함수 3개: parse · dump · YamlSubsetError
"""

import re


class YamlSubsetError(ValueError):
    """이 부분집합이 읽지 못하는 모양 — 어느 줄인지 함께 알린다."""


def _scalar(text: str):
    text = text.strip()
    if text == "" or text in ("null", "~"):
        return None
    if text in ("true", "True"):
        return True
    if text in ("false", "False"):
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def _split_flow(body: str) -> list:
    """`a, b, {c: d}, [e, f]` 를 최상위 쉼표로만 나눈다."""
    parts, depth, cur, quote = [], 0, "", None
    for ch in body:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def _flow(text: str, line_no: int):
    text = text.strip()
    if text.startswith("[") and text.endswith("]"):
        return [_flow(p, line_no) for p in _split_flow(text[1:-1])]
    if text[:1] in "[{" and text[-1:] not in "]}":
        raise YamlSubsetError(f"{line_no}행: 닫히지 않은 흐름 목록/맵: {text[:30]}")
    if text.startswith("{") and text.endswith("}"):
        out = {}
        for item in _split_flow(text[1:-1]):
            if ":" not in item:
                raise YamlSubsetError(f"{line_no}행: 흐름 맵 항목에 ':' 가 없다: {item}")
            k, v = item.split(":", 1)
            out[k.strip()] = _flow(v, line_no)
        return out
    return _scalar(text)


def _strip_comment(line: str) -> str:
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


def parse(text: str) -> dict:
    """문자열 → dict. 지원 밖 모양이면 YamlSubsetError."""
    state = {"root": {}, "key": None, "mode": None}   # mode: None | pending | list | map
    for n, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            _top_line(state, line.strip(), n)
        else:
            _child_line(state, line.strip(), n)
    return state["root"]


def _top_line(state: dict, body: str, n: int) -> None:
    if ":" not in body:
        raise YamlSubsetError(f"{n}행: 최상위 줄에 ':' 가 없다")
    key, rest = body.split(":", 1)
    state["key"], rest = key.strip(), rest.strip()
    if rest:
        state["root"][state["key"]] = _flow(rest, n)
        state["mode"] = None
    else:
        state["root"][state["key"]] = None
        state["mode"] = "pending"


def _child_line(state: dict, body: str, n: int) -> None:
    key, mode, root = state["key"], state["mode"], state["root"]
    if key is None:
        raise YamlSubsetError(f"{n}행: 키 없이 들여쓴 줄")
    want = "list" if body.startswith("- ") else "map"
    if mode not in ("pending", want):
        raise YamlSubsetError(f"{n}행: {'목록' if want == 'list' else '맵'} 항목이 올 자리가 아니다")
    if mode == "pending":
        root[key], state["mode"] = ([] if want == "list" else {}), want
    if want == "list":
        root[key].append(_flow(body[2:], n))
        return
    if ":" not in body:
        raise YamlSubsetError(f"{n}행: 맵 항목에 ':' 가 없다")
    k, v = body.split(":", 1)
    root[key][k.strip()] = _flow(v, n)


def _flow_dump(value) -> str:
    if isinstance(value, dict):
        return "{" + ", ".join(f"{k}: {_flow_dump(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ", ".join(_flow_dump(v) for v in value) + "]"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def dump(data: dict, comments: dict = None) -> str:
    """dict → 문자열. 2단 맵은 블록으로, 목록은 흐름으로 쓴다. comments 는 {키: 줄 끝 주석}."""
    comments = comments or {}
    lines = []
    for key, value in data.items():
        tail = f"   # {comments[key]}" if key in comments else ""
        if isinstance(value, dict):
            lines.append(f"{key}:{tail}")
            for k, v in value.items():
                lines.append(f"  {k}: {_flow_dump(v)}")
        else:
            lines.append(f"{key}: {_flow_dump(value)}{tail}")
    return "\n".join(lines) + "\n"
